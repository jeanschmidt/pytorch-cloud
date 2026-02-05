#!/usr/bin/env bash
# Quick start script for pytorch-cloud
# This script helps you get started with the project

set -euo pipefail

echo "==================================="
echo "pytorch-cloud Quick Start"
echo "==================================="
echo ""

# Check if required tools are installed
check_tool() {
    if ! command -v "$1" &> /dev/null; then
        echo "❌ $1 is not installed"
        echo "   Install from: $2"
        return 1
    else
        echo "✅ $1 is installed"
        return 0
    fi
}

echo "Checking prerequisites..."
echo ""

MISSING=0

check_tool "mise" "https://mise.jdx.dev" || MISSING=1
check_tool "just" "https://just.systems" || MISSING=1
check_tool "docker" "https://docs.docker.com/get-docker/" || MISSING=1
check_tool "aws" "https://aws.amazon.com/cli/" || MISSING=1

# Check for tofu (OpenTofu) - critical!
echo ""
echo "⚠️  Checking for OpenTofu (tofu)..."
if command -v tofu &> /dev/null; then
    echo "✅ tofu is installed"
    tofu version
else
    echo "❌ tofu (OpenTofu) is not installed!"
    echo "   This project uses OpenTofu, NOT Terraform"
    echo "   Install from: https://opentofu.org/docs/intro/install/"
    echo ""
    echo "   After 'mise install', if 'tofu' is not available:"
    echo "   - Visit https://opentofu.org/docs/intro/install/"
    echo "   - Or: brew install opentofu (macOS)"
    echo "   - Or: Install manually and ensure 'tofu' is in PATH"
    MISSING=1
fi

echo ""

if [ $MISSING -eq 1 ]; then
    echo "❌ Some prerequisites are missing. Please install them first."
    exit 1
fi

echo "✅ All prerequisites are installed!"
echo ""

# Check AWS credentials
echo "Checking AWS credentials..."
if aws sts get-caller-identity &> /dev/null; then
    echo "✅ AWS credentials are configured"
    ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    echo "   Account ID: $ACCOUNT_ID"
else
    echo "❌ AWS credentials are not configured"
    echo "   Run: aws configure"
    exit 1
fi

echo ""
echo "Setting up the project..."
echo ""

# Run setup
if just setup; then
    echo ""
    echo "✅ Setup complete!"
else
    echo ""
    echo "❌ Setup failed"
    exit 1
fi

echo ""
echo "==================================="
echo "Next Steps"
echo "==================================="
echo ""
echo "⚠️  IMPORTANT: This project uses OpenTofu (tofu), NOT Terraform!"
echo "   NEVER run 'terraform' commands - always use 'tofu' or 'just' commands"
echo ""
echo "1. Create S3 backend for OpenTofu state:"
echo "   aws s3 mb s3://pytorch-cloud-terraform-state-staging --region us-west-2"
echo "   aws s3 mb s3://pytorch-cloud-terraform-state-production --region us-west-2"
echo ""
echo "2. Create DynamoDB table for state locking:"
echo "   aws dynamodb create-table --table-name pytorch-cloud-terraform-locks \\"
echo "     --attribute-definitions AttributeName=LockID,AttributeType=S \\"
echo "     --key-schema AttributeName=LockID,KeyType=HASH \\"
echo "     --billing-mode PAY_PER_REQUEST --region us-west-2"
echo ""
echo "3. Create ECR repositories:"
echo "   aws ecr create-repository --repository-name pytorch-cloud/runner-base --region us-west-2"
echo "   aws ecr create-repository --repository-name pytorch-cloud/runner-gpu --region us-west-2"
echo ""
echo "4. Deploy staging infrastructure (using OpenTofu):"
echo "   just tf-init staging"
echo "   just tf-plan staging"
echo "   just tf-apply staging"
echo ""
echo "5. Read the documentation:"
echo "   - CRITICAL-USE-TOFU.md - MUST READ: Why we use tofu not terraform"
echo "   - docs/QUICKSTART.md - Step-by-step guide"
echo "   - docs/SETUP-CHECKLIST.md - Complete deployment checklist"
echo "   - docs/GPU-SETUP.md - GPU configuration guide"
echo ""
echo "For help, run: just --list"
echo ""
