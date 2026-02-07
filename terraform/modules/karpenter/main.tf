terraform {
  required_version = ">= 1.7"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# Karpenter Controller IAM Role (IRSA)
resource "aws_iam_role" "karpenter_controller" {
  name = "${var.cluster_name}-karpenter-controller"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRoleWithWebIdentity"
      Effect = "Allow"
      Principal = {
        Federated = var.oidc_provider_arn
      }
      Condition = {
        StringEquals = {
          "${var.oidc_provider}:sub" = "system:serviceaccount:karpenter:karpenter"
          "${var.oidc_provider}:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })

  tags = var.tags
}

# Karpenter Controller Policy
resource "aws_iam_policy" "karpenter_controller" {
  name        = "${var.cluster_name}-karpenter-controller"
  description = "Karpenter controller policy for ${var.cluster_name}"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowScopedEC2InstanceAccessActions"
        Effect = "Allow"
        Action = [
          "ec2:RunInstances",
          "ec2:CreateFleet"
        ]
        Resource = [
          "arn:aws:ec2:${var.aws_region}:*:launch-template/*",
          "arn:aws:ec2:${var.aws_region}:*:security-group/*",
          "arn:aws:ec2:${var.aws_region}::image/*",
          "arn:aws:ec2:${var.aws_region}::snapshot/*",
          "arn:aws:ec2:${var.aws_region}:*:subnet/*"
        ]
      },
      {
        Sid    = "AllowScopedEC2LaunchTemplateAccessActions"
        Effect = "Allow"
        Action = [
          "ec2:RunInstances",
          "ec2:CreateFleet"
        ]
        Resource = "arn:aws:ec2:${var.aws_region}:*:launch-template/*"
        Condition = {
          StringEquals = {
            "aws:ResourceTag/kubernetes.io/cluster/${var.cluster_name}" = "owned"
          }
        }
      },
      {
        Sid    = "AllowScopedEC2InstanceActionsWithTags"
        Effect = "Allow"
        Action = [
          "ec2:RunInstances",
          "ec2:CreateFleet",
          "ec2:CreateLaunchTemplate"
        ]
        Resource = [
          "arn:aws:ec2:${var.aws_region}:*:fleet/*",
          "arn:aws:ec2:${var.aws_region}:*:instance/*",
          "arn:aws:ec2:${var.aws_region}:*:volume/*",
          "arn:aws:ec2:${var.aws_region}:*:network-interface/*",
          "arn:aws:ec2:${var.aws_region}:*:launch-template/*"
        ]
        Condition = {
          StringEquals = {
            "aws:RequestTag/kubernetes.io/cluster/${var.cluster_name}" = "owned"
          }
        }
      },
      {
        Sid      = "AllowScopedResourceCreationTagging"
        Effect   = "Allow"
        Action   = "ec2:CreateTags"
        Resource = [
          "arn:aws:ec2:${var.aws_region}:*:fleet/*",
          "arn:aws:ec2:${var.aws_region}:*:instance/*",
          "arn:aws:ec2:${var.aws_region}:*:volume/*",
          "arn:aws:ec2:${var.aws_region}:*:network-interface/*",
          "arn:aws:ec2:${var.aws_region}:*:launch-template/*"
        ]
        Condition = {
          StringEquals = {
            "aws:RequestTag/kubernetes.io/cluster/${var.cluster_name}" = "owned"
            "ec2:CreateAction" = [
              "RunInstances",
              "CreateFleet",
              "CreateLaunchTemplate"
            ]
          }
        }
      },
      {
        Sid    = "AllowScopedResourceTagging"
        Effect = "Allow"
        Action = "ec2:CreateTags"
        Resource = "arn:aws:ec2:${var.aws_region}:*:instance/*"
        Condition = {
          StringEquals = {
            "aws:ResourceTag/kubernetes.io/cluster/${var.cluster_name}" = "owned"
          }
          StringLike = {
            "aws:RequestTag/karpenter.sh/nodepool" = "*"
          }
        }
      },
      {
        Sid      = "AllowScopedDeletion"
        Effect   = "Allow"
        Action   = [
          "ec2:TerminateInstances",
          "ec2:DeleteLaunchTemplate"
        ]
        Resource = [
          "arn:aws:ec2:${var.aws_region}:*:instance/*",
          "arn:aws:ec2:${var.aws_region}:*:launch-template/*"
        ]
        Condition = {
          StringEquals = {
            "aws:ResourceTag/kubernetes.io/cluster/${var.cluster_name}" = "owned"
          }
        }
      },
      {
        Sid    = "AllowRegionalReadActions"
        Effect = "Allow"
        Action = [
          "ec2:DescribeAvailabilityZones",
          "ec2:DescribeImages",
          "ec2:DescribeInstances",
          "ec2:DescribeInstanceTypeOfferings",
          "ec2:DescribeInstanceTypes",
          "ec2:DescribeLaunchTemplates",
          "ec2:DescribeSecurityGroups",
          "ec2:DescribeSpotPriceHistory",
          "ec2:DescribeSubnets"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "aws:RequestedRegion" = var.aws_region
          }
        }
      },
      {
        Sid    = "AllowSSMReadActions"
        Effect = "Allow"
        Action = "ssm:GetParameter"
        Resource = "arn:aws:ssm:${var.aws_region}::parameter/aws/service/*"
      },
      {
        Sid      = "AllowPricingReadActions"
        Effect   = "Allow"
        Action   = "pricing:GetProducts"
        Resource = "*"
      },
      {
        Sid    = "AllowInterruptionQueueActions"
        Effect = "Allow"
        Action = [
          "sqs:DeleteMessage",
          "sqs:GetQueueAttributes",
          "sqs:GetQueueUrl",
          "sqs:ReceiveMessage"
        ]
        Resource = aws_sqs_queue.karpenter.arn
      },
      {
        Sid    = "AllowPassingInstanceRole"
        Effect = "Allow"
        Action = "iam:PassRole"
        Resource = var.node_instance_role_arn
        Condition = {
          StringEquals = {
            "iam:PassedToService" = "ec2.amazonaws.com"
          }
        }
      },
      {
        Sid    = "AllowScopedInstanceProfileCreationActions"
        Effect = "Allow"
        Action = [
          "iam:CreateInstanceProfile"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "aws:RequestTag/kubernetes.io/cluster/${var.cluster_name}" = "owned"
            "aws:RequestTag/topology.kubernetes.io/region"             = var.aws_region
          }
          StringLike = {
            "aws:RequestTag/karpenter.k8s.aws/ec2nodeclass" = "*"
          }
        }
      },
      {
        Sid    = "AllowScopedInstanceProfileTagActions"
        Effect = "Allow"
        Action = [
          "iam:TagInstanceProfile"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "aws:ResourceTag/kubernetes.io/cluster/${var.cluster_name}" = "owned"
            "aws:ResourceTag/topology.kubernetes.io/region"             = var.aws_region
            "aws:RequestTag/kubernetes.io/cluster/${var.cluster_name}"  = "owned"
            "aws:RequestTag/topology.kubernetes.io/region"              = var.aws_region
          }
          StringLike = {
            "aws:ResourceTag/karpenter.k8s.aws/ec2nodeclass" = "*"
            "aws:RequestTag/karpenter.k8s.aws/ec2nodeclass"  = "*"
          }
        }
      },
      {
        Sid    = "AllowScopedInstanceProfileActions"
        Effect = "Allow"
        Action = [
          "iam:AddRoleToInstanceProfile",
          "iam:RemoveRoleFromInstanceProfile",
          "iam:DeleteInstanceProfile"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "aws:ResourceTag/kubernetes.io/cluster/${var.cluster_name}" = "owned"
            "aws:ResourceTag/topology.kubernetes.io/region"             = var.aws_region
          }
          StringLike = {
            "aws:ResourceTag/karpenter.k8s.aws/ec2nodeclass" = "*"
          }
        }
      },
      {
        Sid      = "AllowInstanceProfileReadActions"
        Effect   = "Allow"
        Action   = ["iam:GetInstanceProfile", "iam:ListInstanceProfiles"]
        Resource = "*"
      },
      {
        Sid    = "AllowAPIServerEndpointDiscovery"
        Effect = "Allow"
        Action = "eks:DescribeCluster"
        Resource = "arn:aws:eks:${var.aws_region}:*:cluster/${var.cluster_name}"
      }
    ]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "karpenter_controller" {
  role       = aws_iam_role.karpenter_controller.name
  policy_arn = aws_iam_policy.karpenter_controller.arn
}

# SQS Queue for Spot Interruption Handling
resource "aws_sqs_queue" "karpenter" {
  name                      = "${var.cluster_name}-karpenter"
  message_retention_seconds = 300
  sqs_managed_sse_enabled   = true

  tags = var.tags
}

resource "aws_sqs_queue_policy" "karpenter" {
  queue_url = aws_sqs_queue.karpenter.url

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = [
            "events.amazonaws.com",
            "sqs.amazonaws.com"
          ]
        }
        Action   = "sqs:SendMessage"
        Resource = aws_sqs_queue.karpenter.arn
      }
    ]
  })
}

# EventBridge Rules for Spot Interruptions
resource "aws_cloudwatch_event_rule" "spot_interruption" {
  name        = "${var.cluster_name}-karpenter-spot-interruption"
  description = "Karpenter spot interruption warning"

  event_pattern = jsonencode({
    source      = ["aws.ec2"]
    detail-type = ["EC2 Spot Instance Interruption Warning"]
  })

  tags = var.tags
}

resource "aws_cloudwatch_event_target" "spot_interruption" {
  rule      = aws_cloudwatch_event_rule.spot_interruption.name
  target_id = "KarpenterSpotInterruption"
  arn       = aws_sqs_queue.karpenter.arn
}

resource "aws_cloudwatch_event_rule" "rebalance" {
  name        = "${var.cluster_name}-karpenter-rebalance"
  description = "Karpenter rebalance recommendation"

  event_pattern = jsonencode({
    source      = ["aws.ec2"]
    detail-type = ["EC2 Instance Rebalance Recommendation"]
  })

  tags = var.tags
}

resource "aws_cloudwatch_event_target" "rebalance" {
  rule      = aws_cloudwatch_event_rule.rebalance.name
  target_id = "KarpenterRebalance"
  arn       = aws_sqs_queue.karpenter.arn
}

resource "aws_cloudwatch_event_rule" "instance_state_change" {
  name        = "${var.cluster_name}-karpenter-instance-state-change"
  description = "Karpenter instance state change"

  event_pattern = jsonencode({
    source      = ["aws.ec2"]
    detail-type = ["EC2 Instance State-change Notification"]
  })

  tags = var.tags
}

resource "aws_cloudwatch_event_target" "instance_state_change" {
  rule      = aws_cloudwatch_event_rule.instance_state_change.name
  target_id = "KarpenterInstanceStateChange"
  arn       = aws_sqs_queue.karpenter.arn
}

resource "aws_cloudwatch_event_rule" "scheduled_change" {
  name        = "${var.cluster_name}-karpenter-scheduled-change"
  description = "Karpenter scheduled change"

  event_pattern = jsonencode({
    source      = ["aws.health"]
    detail-type = ["AWS Health Event"]
  })

  tags = var.tags
}

resource "aws_cloudwatch_event_target" "scheduled_change" {
  rule      = aws_cloudwatch_event_rule.scheduled_change.name
  target_id = "KarpenterScheduledChange"
  arn       = aws_sqs_queue.karpenter.arn
}
