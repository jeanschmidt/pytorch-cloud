terraform {
  required_version = ">= 1.7"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# EKS Cluster
resource "aws_eks_cluster" "this" {
  name     = var.cluster_name
  version  = var.cluster_version
  role_arn = aws_iam_role.cluster.arn

  vpc_config {
    subnet_ids              = var.subnet_ids
    endpoint_private_access = var.cluster_endpoint_private_access
    endpoint_public_access  = var.cluster_endpoint_public_access
    public_access_cidrs     = var.cluster_endpoint_public_access_cidrs
  }

  enabled_cluster_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]

  tags = merge(
    var.tags,
    {
      Name = var.cluster_name
    }
  )

  depends_on = [
    aws_iam_role_policy_attachment.cluster_policy,
    aws_iam_role_policy_attachment.vpc_resource_controller,
  ]
}

# EKS Cluster IAM Role
resource "aws_iam_role" "cluster" {
  name = "${var.cluster_name}-cluster-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "eks.amazonaws.com"
        }
      }
    ]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "cluster_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.cluster.name
}

resource "aws_iam_role_policy_attachment" "vpc_resource_controller" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSVPCResourceController"
  role       = aws_iam_role.cluster.name
}

# OIDC Provider for IRSA
data "tls_certificate" "cluster" {
  count = var.enable_irsa ? 1 : 0
  url   = aws_eks_cluster.this.identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "cluster" {
  count = var.enable_irsa ? 1 : 0

  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.cluster[0].certificates[0].sha1_fingerprint]
  url             = aws_eks_cluster.this.identity[0].oidc[0].issuer

  tags = var.tags
}

# EKS Addons
resource "aws_eks_addon" "vpc_cni" {
  cluster_name                = aws_eks_cluster.this.name
  addon_name                  = "vpc-cni"
  addon_version               = "v1.16.0-eksbuild.1"
  resolve_conflicts_on_update = "PRESERVE"

  tags = var.tags
}

resource "aws_eks_addon" "coredns" {
  cluster_name                = aws_eks_cluster.this.name
  addon_name                  = "coredns"
  addon_version               = "v1.11.1-eksbuild.4"
  resolve_conflicts_on_update = "PRESERVE"

  # CoreDNS must tolerate base node taints to run on infrastructure nodes
  configuration_values = jsonencode({
    tolerations = [
      {
        key      = "CriticalAddonsOnly"
        operator = "Equal"
        value    = "true"
        effect   = "NoSchedule"
      }
    ]
  })

  tags = var.tags

  depends_on = [aws_eks_node_group.base]
}

resource "aws_eks_addon" "kube_proxy" {
  cluster_name                = aws_eks_cluster.this.name
  addon_name                  = "kube-proxy"
  addon_version               = "v1.29.0-eksbuild.1"
  resolve_conflicts_on_update = "PRESERVE"

  tags = var.tags
}

# Base Infrastructure Node Group (Fixed Size)
# These nodes run critical cluster components only (ARC, Karpenter, CoreDNS, etc.)
# Tainted to prevent runner workloads from scheduling here
resource "aws_eks_node_group" "base" {
  cluster_name    = aws_eks_cluster.this.name
  node_group_name = "${var.cluster_name}-base-nodes"
  node_role_arn   = aws_iam_role.node.arn
  subnet_ids      = var.subnet_ids

  # Fixed size - no auto-scaling
  scaling_config {
    desired_size = var.base_node_count
    max_size     = var.base_node_count
    min_size     = var.base_node_count
  }

  instance_types = [var.base_node_instance_type]
  capacity_type  = "ON_DEMAND"

  labels = {
    role                           = "base-infrastructure"
    "node.kubernetes.io/lifecycle" = "on-demand"
  }

  # Taint to prevent runner workloads from landing here
  # Only system components with matching tolerations can schedule
  taint {
    key    = "CriticalAddonsOnly"
    value  = "true"
    effect = "NO_SCHEDULE"
  }

  # Use launch template for bootstrap script
  launch_template {
    id      = aws_launch_template.base.id
    version = "$Latest"
  }

  tags = merge(
    var.tags,
    {
      Name = "${var.cluster_name}-base-nodes"
      Type = "base-infrastructure"
    }
  )

  depends_on = [
    aws_iam_role_policy_attachment.node_policy,
    aws_iam_role_policy_attachment.cni_policy,
    aws_iam_role_policy_attachment.ecr_policy,
  ]
}

# Launch template for base infrastructure nodes
resource "aws_launch_template" "base" {
  name_prefix   = "${var.cluster_name}-base-"
  image_id      = "" # Empty = use EKS-optimized AMI
  instance_type = var.base_node_instance_type

  # User data calls EKS bootstrap, then runs our post-bootstrap script
  user_data = base64encode(templatefile("${path.module}/user-data-base.sh.tpl", {
    cluster_name          = aws_eks_cluster.this.name
    post_bootstrap_script = file("${path.module}/../../scripts/bootstrap/eks-base-bootstrap.sh")
  }))

  block_device_mappings {
    device_name = "/dev/xvda"

    ebs {
      volume_size           = 100
      volume_type           = "gp3"
      iops                  = 3000
      throughput            = 125
      delete_on_termination = true
      encrypted             = true
    }
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  tag_specifications {
    resource_type = "instance"
    tags = merge(
      var.tags,
      {
        Name = "${var.cluster_name}-base-node"
        Type = "base-infrastructure"
      }
    )
  }

  tags = var.tags
}

# GPU Node Group
resource "aws_eks_node_group" "gpu" {
  cluster_name    = aws_eks_cluster.this.name
  node_group_name = "${var.cluster_name}-gpu-nodes"
  node_role_arn   = aws_iam_role.node.arn
  subnet_ids      = var.subnet_ids

  scaling_config {
    desired_size = 0
    max_size     = 5
    min_size     = 0
  }

  instance_types = ["g4dn.xlarge"]
  capacity_type  = "ON_DEMAND"

  labels = {
    role             = "gpu"
    "nvidia.com/gpu" = "true"
  }

  taints {
    key    = "nvidia.com/gpu"
    value  = "true"
    effect = "NO_SCHEDULE"
  }

  # Use launch template for GPU bootstrap script
  launch_template {
    id      = aws_launch_template.gpu.id
    version = "$Latest"
  }

  tags = merge(
    var.tags,
    {
      Name = "${var.cluster_name}-gpu-nodes"
    }
  )

  depends_on = [
    aws_iam_role_policy_attachment.node_policy,
    aws_iam_role_policy_attachment.cni_policy,
    aws_iam_role_policy_attachment.ecr_policy,
  ]
}

# Launch template for GPU nodes
resource "aws_launch_template" "gpu" {
  name_prefix   = "${var.cluster_name}-gpu-"
  image_id      = "" # Empty = use EKS GPU-optimized AMI
  instance_type = "g4dn.xlarge"

  # User data calls EKS bootstrap, then runs our post-bootstrap script
  user_data = base64encode(templatefile("${path.module}/user-data-gpu.sh.tpl", {
    cluster_name          = aws_eks_cluster.this.name
    post_bootstrap_script = file("${path.module}/../../scripts/bootstrap/eks-gpu-bootstrap.sh")
  }))

  block_device_mappings {
    device_name = "/dev/xvda"

    ebs {
      volume_size           = 200
      volume_type           = "gp3"
      iops                  = 3000
      throughput            = 125
      delete_on_termination = true
      encrypted             = true
    }
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  tag_specifications {
    resource_type = "instance"
    tags = merge(
      var.tags,
      {
        Name = "${var.cluster_name}-gpu-node"
      }
    )
  }

  tags = var.tags
}

# EKS Node IAM Role
resource "aws_iam_role" "node" {
  name = "${var.cluster_name}-node-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "node_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.node.name
}

resource "aws_iam_role_policy_attachment" "cni_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.node.name
}

resource "aws_iam_role_policy_attachment" "ecr_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.node.name
}
