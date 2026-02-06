terraform {
  required_version = ">= 1.7"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {
    # Configure via backend config file or CLI:
    # tofu init -backend-config="bucket=pytorch-cloud-terraform-state-staging"
    # bucket         = "pytorch-cloud-terraform-state-staging"
    # key            = "staging/terraform.tfstate"
    # region         = "us-west-2"
    # dynamodb_table = "pytorch-cloud-terraform-locks"
    # encrypt        = true
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
  azs          = slice(data.aws_availability_zones.available.names, 0, 3)

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
  # Private subnets: /18 = 16,384 IPs each (48k total for nodes/pods)
  private_subnets = ["10.0.0.0/18", "10.0.64.0/18", "10.0.128.0/18"]
  # Public subnets: /24 = 256 IPs each (sufficient for load balancers)
  public_subnets     = ["10.0.192.0/24", "10.0.193.0/24", "10.0.194.0/24"]
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
  cluster_version = "1.29"
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
