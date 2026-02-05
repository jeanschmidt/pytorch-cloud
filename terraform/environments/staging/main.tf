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

  name               = "${local.cluster_name}-vpc"
  cidr               = "10.0.0.0/16"
  azs                = local.azs
  private_subnets    = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  public_subnets     = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]
  enable_nat_gateway = true
  single_nat_gateway = true  # Cost optimization for staging

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

  tags = local.tags
}
