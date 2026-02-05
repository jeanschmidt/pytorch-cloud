# Setup Checklist

Use this checklist to deploy pytorch-cloud from scratch.

## Prerequisites

- [ ] AWS account with admin access
- [ ] AWS CLI configured (`aws configure`)
- [ ] GitHub organization/repository for runners
- [ ] GitHub token or GitHub App credentials
- [ ] Domain for webhook endpoints (optional, for production)

## Installation

### 1. Install Tools

- [ ] Install [mise](https://mise.jdx.dev/): `curl https://mise.run | sh`
- [ ] Install [just](https://just.systems/): `curl --proto '=https' --tlsv1.2 -sSf https://just.systems/install.sh | bash`
- [ ] Install Docker: Follow [Docker installation guide](https://docs.docker.com/get-docker/)

### 2. Clone and Setup

```bash
# Clone repository
git clone <repository-url>
cd pytorch-cloud

# Install dependencies
just setup

# Verify installation
just ci-check
```

## AWS Setup

### 3. Create S3 Backend (One-time)

```bash
# Create S3 bucket for Terraform state
aws s3 mb s3://pytorch-cloud-terraform-state-staging --region us-west-2
aws s3 mb s3://pytorch-cloud-terraform-state-production --region us-west-2

# Enable versioning
aws s3api put-bucket-versioning \
  --bucket pytorch-cloud-terraform-state-staging \
  --versioning-configuration Status=Enabled

aws s3api put-bucket-versioning \
  --bucket pytorch-cloud-terraform-state-production \
  --versioning-configuration Status=Enabled

# Enable encryption
aws s3api put-bucket-encryption \
  --bucket pytorch-cloud-terraform-state-staging \
  --server-side-encryption-configuration '{
    "Rules": [{"ApplyServerSideEncryptionByDefault": {"SSEAlgorithm": "AES256"}}]
  }'

aws s3api put-bucket-encryption \
  --bucket pytorch-cloud-terraform-state-production \
  --server-side-encryption-configuration '{
    "Rules": [{"ApplyServerSideEncryptionByDefault": {"SSEAlgorithm": "AES256"}}]
  }'

# Create DynamoDB table for state locking
aws dynamodb create-table \
  --table-name pytorch-cloud-terraform-locks \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region us-west-2
```

### 4. Create ECR Repositories

```bash
# Create ECR repositories for runner images
aws ecr create-repository \
  --repository-name pytorch-cloud/runner-base \
  --region us-west-2

aws ecr create-repository \
  --repository-name pytorch-cloud/runner-gpu \
  --region us-west-2

# Get repository URLs
aws ecr describe-repositories \
  --repository-names pytorch-cloud/runner-base pytorch-cloud/runner-gpu \
  --region us-west-2 \
  --query 'repositories[*].repositoryUri' \
  --output table
```

## Staging Deployment

### 5. Deploy Infrastructure

```bash
# Initialize OpenTofu (not terraform!)
cd terraform/environments/staging
tofu init \
  -backend-config="bucket=pytorch-cloud-terraform-state-staging" \
  -backend-config="key=staging/terraform.tfstate" \
  -backend-config="region=us-west-2" \
  -backend-config="dynamodb_table=pytorch-cloud-terraform-locks" \
  -backend-config="encrypt=true"
cd ../../..

# OR use just command (you'll need to configure backend first)
just tf-init staging

# Plan changes
just tf-plan staging

# Review plan output
# - VPC with subnets
# - EKS cluster
# - CPU and GPU node groups

# Apply infrastructure
just tf-apply staging

# Configure kubectl
cd terraform/environments/staging
tofu output configure_kubectl
# Run the output command
```

### 6. Deploy Kubernetes Components

```bash
# Verify cluster access
kubectl get nodes

# Apply Kubernetes manifests (NVIDIA device plugin, namespaces)
just k8s-apply staging

# Verify NVIDIA device plugin
kubectl get daemonset -n kube-system nvidia-device-plugin-daemonset
kubectl logs -n kube-system -l name=nvidia-device-plugin-ds

# Verify namespaces
kubectl get namespaces arc-systems arc-runners
```

### 7. Build and Push Docker Images

```bash
# Login to ECR
aws ecr get-login-password --region us-west-2 | \
  docker login --username AWS --password-stdin \
  <account-id>.dkr.ecr.us-west-2.amazonaws.com

# Build images
just docker-build runner-base
just docker-build runner-gpu

# Tag images
docker tag runner-base:latest <account-id>.dkr.ecr.us-west-2.amazonaws.com/pytorch-cloud/runner-base:latest
docker tag runner-gpu:latest <account-id>.dkr.ecr.us-west-2.amazonaws.com/pytorch-cloud/runner-gpu:latest

# Push images
docker push <account-id>.dkr.ecr.us-west-2.amazonaws.com/pytorch-cloud/runner-base:latest
docker push <account-id>.dkr.ecr.us-west-2.amazonaws.com/pytorch-cloud/runner-gpu:latest
```

### 8. Install ARC Controller

```bash
# Add Helm repository
helm repo add actions-runner-controller https://actions-runner-controller.github.io/actions-runner-controller
helm repo update

# Install ARC with GitHub token
helm upgrade --install arc \
  --namespace arc-systems \
  --create-namespace \
  -f helm/arc/values.yaml \
  -f helm/arc/values-staging.yaml \
  --set authSecret.github_token="<your-github-token>" \
  actions-runner-controller/actions-runner-controller

# Verify ARC is running
kubectl get pods -n arc-systems
kubectl logs -n arc-systems deployment/arc-controller-manager
```

### 9. Deploy Runners

```bash
# Update helm/arc-runners/values-staging.yaml
# Set githubRepository to your repository

# Install runners
helm upgrade --install arc-runners \
  --namespace arc-runners \
  --create-namespace \
  -f helm/arc-runners/values.yaml \
  -f helm/arc-runners/values-staging.yaml \
  actions-runner-controller/actions-runner-controller-runners

# Verify runners
kubectl get pods -n arc-runners
kubectl get runners -n arc-runners
```

### 10. Test Runners

```bash
# Create test workflow in your repository
# .github/workflows/test-runner.yml

# Push workflow and verify it runs on self-hosted runner
```

## Production Deployment

### 11. Build Custom AMIs (Optional but Recommended)

```bash
# Validate Packer templates
just ami-validate

# Build AMIs
just ami-build eks-base
just ami-build eks-gpu

# Note AMI IDs from output
# Update terraform/modules/eks/main.tf with AMI IDs
```

### 12. Deploy Production

```bash
# Repeat steps 5-10 but use 'production' instead of 'staging'
just tf-init production
just tf-plan production
just tf-apply production

# Configure kubectl for production
cd terraform/environments/production
tofu output configure_kubectl

# Deploy production components
just k8s-apply production

# Install ARC for production
helm upgrade --install arc \
  --namespace arc-systems \
  --create-namespace \
  -f helm/arc/values.yaml \
  -f helm/arc/values-production.yaml \
  --set authSecret.github_token="<your-github-token>" \
  actions-runner-controller/actions-runner-controller

# Deploy production runners
helm upgrade --install arc-runners \
  --namespace arc-runners \
  --create-namespace \
  -f helm/arc-runners/values.yaml \
  -f helm/arc-runners/values-production.yaml \
  actions-runner-controller/actions-runner-controller-runners
```

## Post-Deployment

### 13. Set Up Monitoring

- [ ] Configure CloudWatch dashboards
- [ ] Set up log aggregation
- [ ] Configure alerts for node health
- [ ] Set up cost monitoring

### 14. Configure Auto-scaling

- [ ] Review runner scaling configuration
- [ ] Test scale-up and scale-down
- [ ] Configure webhook-based scaling (if needed)

### 15. Documentation

- [ ] Document custom configurations
- [ ] Create runbooks for common operations
- [ ] Document troubleshooting procedures

### 16. Security

- [ ] Review IAM roles and policies
- [ ] Enable CloudTrail logging
- [ ] Configure network policies
- [ ] Set up secret rotation (GitHub tokens)

## Verification

### Test GPU Support

```bash
# Run GPU test
kubectl run gpu-test --rm -it --restart=Never \
  --image=nvidia/cuda:12.1.0-base-ubuntu22.04 \
  --overrides='{"spec":{"tolerations":[{"key":"nvidia.com/gpu","operator":"Equal","value":"true","effect":"NoSchedule"}],"nodeSelector":{"nvidia.com/gpu":"true"}}}' \
  --limits=nvidia.com/gpu=1 \
  -- nvidia-smi

# Expected: nvidia-smi output showing GPU details
```

### Test PyTorch

```bash
kubectl run pytorch-test --rm -it --restart=Never \
  --image=pytorch/pytorch:2.1.0-cuda12.1-cudnn8-runtime \
  --overrides='{"spec":{"tolerations":[{"key":"nvidia.com/gpu","operator":"Equal","value":"true","effect":"NoSchedule"}],"nodeSelector":{"nvidia.com/gpu":"true"}}}' \
  --limits=nvidia.com/gpu=1 \
  -- python3 -c "import torch; print(torch.cuda.is_available())"

# Expected: True
```

### Test Runner

Create `.github/workflows/test.yml`:

```yaml
name: Test Self-hosted Runner

on: [workflow_dispatch]

jobs:
  test-cpu:
    runs-on: [self-hosted, linux, x64, staging]
    steps:
      - run: echo "CPU runner works!"
  
  test-gpu:
    runs-on: [self-hosted, linux, x64, staging, gpu]
    steps:
      - run: nvidia-smi
      - run: python3 -c "import torch; print(torch.cuda.is_available())"
```

## Troubleshooting

If something goes wrong:

1. Check controller logs: `kubectl logs -n arc-systems deployment/arc-controller-manager`
2. Check runner logs: `kubectl logs -n arc-runners <runner-pod>`
3. Check node events: `kubectl describe node <node-name>`
4. Check GPU plugin: `kubectl logs -n kube-system daemonset/nvidia-device-plugin-daemonset`
5. Review documentation: `docs/QUICKSTART.md`, `docs/GPU-SETUP.md`

## Cleanup

To tear down everything:

```bash
# Delete runners
helm uninstall arc-runners -n arc-runners

# Delete ARC
helm uninstall arc -n arc-systems

# Delete Kubernetes resources
just k8s-delete staging

# Destroy infrastructure (BE CAREFUL!)
just tf-destroy staging

# For production
just tf-destroy production
```

## Next Steps

- Review [docs/QUICKSTART.md](docs/QUICKSTART.md) for detailed usage
- Review [docs/GPU-SETUP.md](docs/GPU-SETUP.md) for GPU configuration
- Review [docs/PROJECT-STRUCTURE.md](docs/PROJECT-STRUCTURE.md) for architecture
- Set up CI/CD pipelines in `.github/workflows/`
- Configure monitoring and alerting
- Plan for disaster recovery
