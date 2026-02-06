terraform {
  required_version = ">= 1.7"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {
    bucket         = "pytorch-cloud-terraform-state-production"
    key            = "production/terraform.tfstate"
    region         = "us-west-2" # S3 bucket location (independent of infrastructure)
    dynamodb_table = "pytorch-cloud-terraform-locks"
    encrypt        = true
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Environment = "production"
      Project     = "pytorch-cloud"
      ManagedBy   = "terraform"
    }
  }
}

data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  cluster_name = "pytorch-arc-production"
  # Use min(3, available AZs) to handle regions with fewer than 3 AZs
  azs = slice(data.aws_availability_zones.available.names, 0, min(length(data.aws_availability_zones.available.names), 3))

  tags = {
    Environment = "production"
    Project     = "pytorch-cloud"
  }
}

# VPC Module
module "vpc" {
  source = "../../modules/vpc"

  name = "${local.cluster_name}-vpc"
  cidr = "10.1.0.0/16" # 65,536 IPs total
  azs  = local.azs
  # Private subnets: Dynamic sizing based on AZ count (32k IPs each for 2 AZs)
  private_subnets = length(local.azs) == 2 ? ["10.1.0.0/17", "10.1.128.0/17"] : ["10.1.0.0/18", "10.1.64.0/18", "10.1.128.0/18"]
  # Public subnets: /24 = 256 IPs each
  public_subnets     = length(local.azs) == 2 ? ["10.1.192.0/24", "10.1.193.0/24"] : ["10.1.192.0/24", "10.1.193.0/24", "10.1.194.0/24"]
  enable_nat_gateway = true
  single_nat_gateway = false # High availability for production

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
