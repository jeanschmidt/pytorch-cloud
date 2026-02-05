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
echo "1. Create S3 backend for Terraform state:"
echo "   aws s3 mb s3://pytorch-cloud-terraform-state-staging --region us-west-2"
echo ""
echo "2. Create ECR repositories:"
echo "   aws ecr create-repository --repository-name pytorch-cloud/runner-base --region us-west-2"
echo "   aws ecr create-repository --repository-name pytorch-cloud/runner-gpu --region us-west-2"
echo ""
echo "3. Deploy staging infrastructure:"
echo "   just tf-init staging"
echo "   just tf-plan staging"
echo "   just tf-apply staging"
echo ""
echo "4. Read the documentation:"
echo "   - docs/QUICKSTART.md - Step-by-step guide"
echo "   - docs/SETUP-CHECKLIST.md - Complete deployment checklist"
echo "   - docs/GPU-SETUP.md - GPU configuration guide"
echo ""
echo "For help, run: just --list"
echo ""
