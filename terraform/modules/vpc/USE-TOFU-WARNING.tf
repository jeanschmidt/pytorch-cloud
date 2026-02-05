# ⚠️ CRITICAL: USE OPENTOFU (tofu), NOT TERRAFORM

# This module uses OpenTofu, not Terraform.
# NEVER run "terraform" commands on this module!
#
# Mixing terraform and tofu will corrupt the state file.
#
# Use:
#   tofu init
#   tofu plan
#   tofu apply
#
# Or use just commands from project root:
#   just tf-init staging
#   just tf-plan staging
#   just tf-apply staging
#
# See /CRITICAL-USE-TOFU.md for full details.

terraform {
  required_version = ">= 1.7"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}
