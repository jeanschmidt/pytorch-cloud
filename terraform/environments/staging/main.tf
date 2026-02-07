terraform {
  required_version = ">= 1.7"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {
    bucket         = "pytorch-cloud-terraform-state-staging"
    key            = "staging/terraform.tfstate"
    region         = "us-west-2" # S3 bucket location (independent of infrastructure)
    dynamodb_table = "pytorch-cloud-terraform-locks"
    encrypt        = true
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Environment = "staging"
      Project     = "pytorch-cloud"
      ManagedBy   = "terraform"
    }
  }
}

data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  cluster_name = "pytorch-arc-staging"
  # Use min(3, available AZs) to handle regions with fewer than 3 AZs
  azs = slice(data.aws_availability_zones.available.names, 0, min(length(data.aws_availability_zones.available.names), 3))

  tags = {
    Environment = "staging"
    Project     = "pytorch-cloud"
  }
}

# VPC Module
module "vpc" {
  source = "../../modules/vpc"

  name = "${local.cluster_name}-vpc"
  cidr = "10.0.0.0/16" # 65,536 IPs total
  azs  = local.azs
  # Private subnets: Dynamic sizing based on AZ count
  # For 2 AZs: Use /18 (16k IPs each) to leave room for public subnets
  # For 3 AZs: Use /18 (16k IPs each)
  private_subnets = length(local.azs) == 2 ? ["10.0.0.0/18", "10.0.64.0/18"] : ["10.0.0.0/18", "10.0.64.0/18", "10.0.128.0/18"]
  # Public subnets: /24 = 256 IPs each, placed at end of address space
  public_subnets     = length(local.azs) == 2 ? ["10.0.192.0/24", "10.0.193.0/24"] : ["10.0.192.0/24", "10.0.193.0/24", "10.0.194.0/24"]
  enable_nat_gateway = true
  single_nat_gateway = true # Cost optimization for staging

  tags = merge(local.tags, {
    "kubernetes.io/cluster/${local.cluster_name}" = "shared"
  })
}

# EKS Module
module "eks" {
  source = "../../modules/eks"

  cluster_name    = local.cluster_name
  cluster_version = "1.35"
  vpc_id          = module.vpc.vpc_id
  subnet_ids      = module.vpc.private_subnet_ids
  enable_irsa     = true

  cluster_endpoint_private_access = true
  cluster_endpoint_public_access  = true

  # Base infrastructure nodes (fixed size, tainted)
  base_node_count         = var.base_node_count
  base_node_instance_type = var.base_node_instance_type

  tags = local.tags
}

# Karpenter Module
module "karpenter" {
  source = "../../modules/karpenter"

  cluster_name            = local.cluster_name
  aws_region              = var.aws_region
  oidc_provider_arn       = module.eks.oidc_provider_arn
  oidc_provider           = module.eks.oidc_provider
  node_instance_role_arn  = module.eks.node_instance_role_arn

  tags = local.tags
}

# Tag subnets for Karpenter discovery
resource "aws_ec2_tag" "private_subnets_karpenter" {
  count = length(module.vpc.private_subnet_ids)

  resource_id = module.vpc.private_subnet_ids[count.index]
  key         = "karpenter.sh/discovery"
  value       = local.cluster_name
}

# Tag cluster security group for Karpenter
resource "aws_ec2_tag" "cluster_sg_karpenter" {
  resource_id = module.eks.cluster_security_group_id
  key         = "karpenter.sh/discovery"
  value       = local.cluster_name
}
