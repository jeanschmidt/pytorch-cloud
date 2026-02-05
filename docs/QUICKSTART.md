# pytorch-cloud Quick Start Guide

This guide helps you get started with deploying ARC (Actions Runner Controller) on AWS.

## Prerequisites

1. **Install required tools:**
   ```bash
   # Install mise (tool version manager)
   curl https://mise.run | sh
   
   # Install just (command runner)
   curl --proto '=https' --tlsv1.2 -sSf https://just.systems/install.sh | bash -s -- --to ~/.local/bin
   ```

2. **Configure AWS credentials:**
   ```bash
   aws configure
   # OR use AWS SSO
   aws sso login --profile pytorch
   ```

3. **Clone the repository:**
   ```bash
   git clone <repository-url>
   cd pytorch-cloud
   ```

## Initial Setup

```bash
# Install all dependencies
just setup

# Verify setup
just ci-check
```

## Deployment Steps

### 1. Deploy Infrastructure (Staging)

```bash
# Initialize OpenTofu (not terraform!)
just tf-init staging

# Plan infrastructure changes
just tf-plan staging

# Apply infrastructure
just tf-apply staging

# Get cluster name and configure kubectl
cd terraform/environments/staging
tofu output configure_kubectl
# Run the output command, e.g.:
# aws eks update-kubeconfig --region us-west-2 --name pytorch-arc-staging
```

### 2. Deploy Kubernetes Components

```bash
# Apply NVIDIA device plugin and namespaces
just k8s-apply staging

# Verify deployment
kubectl get daemonset -n kube-system nvidia-device-plugin-daemonset
kubectl get nodes -L nvidia.com/gpu
```

### 3. Create GitHub Secret

Create a Kubernetes secret with your GitHub credentials:

```bash
# Option 1: Using Personal Access Token (PAT)
# Token needs: repo, admin:org, manage_runners:org scopes
kubectl create secret generic github-secret \
  --namespace=arc-runners \
  --from-literal=github_token=ghp_xxxxxxxxxxxxx

# Option 2: Using GitHub App (recommended for production)
kubectl create secret generic github-secret \
  --namespace=arc-runners \
  --from-literal=github_app_id=123456 \
  --from-literal=github_app_installation_id=789012 \
  --from-literal=github_app_private_key="$(cat private-key.pem)"
```

### 4. Install ARC Controller

```bash
# Install ARC controller
just helm-install-arc staging

# Verify ARC is running
kubectl get pods -n arc-systems
kubectl logs -n arc-systems -l app.kubernetes.io/name=gha-runner-scale-set-controller
```

### 5. Deploy Runner Scale Sets

```bash
# Update githubConfigUrl in helm values files first:
# - helm/arc-runners/values-staging.yaml
# - helm/arc-gpu-runners/values-staging.yaml

# Install CPU runners
just helm-install-runners staging

# Install GPU runners (if you have GPU nodes)
just helm-install-gpu-runners staging

# Verify runners
kubectl get pods -n arc-runners
kubectl get runnersets -n arc-runners
```

## Building Custom Images

```bash
# Build runner images
just docker-build runner-base
just docker-build runner-gpu

# Tag and push to ECR
aws ecr get-login-password --region us-west-2 | docker login --username AWS --password-stdin <account-id>.dkr.ecr.us-west-2.amazonaws.com

docker tag runner-gpu:latest <account-id>.dkr.ecr.us-west-2.amazonaws.com/pytorch-cloud/runner-gpu:latest
docker push <account-id>.dkr.ecr.us-west-2.amazonaws.com/pytorch-cloud/runner-gpu:latest
```

## Building Custom AMIs

```bash
# Validate Packer templates
just ami-validate

# Build base AMI
just ami-build eks-base

# Build GPU AMI
just ami-build eks-gpu

# Update terraform/modules/eks/main.tf with new AMI IDs
```

## Testing

### Verify GPU Support

```bash
# Check GPU nodes
kubectl get nodes -L nvidia.com/gpu

# Check NVIDIA device plugin
kubectl get daemonset -n kube-system nvidia-device-plugin-daemonset

# Test GPU in a pod
kubectl run gpu-test --rm -it --restart=Never \
  --image=nvidia/cuda:12.1.0-base-ubuntu22.04 \
  --limits=nvidia.com/gpu=1 \
  -- nvidia-smi
```

### Verify Runners

```bash
# Check runner pods
kubectl get pods -n arc-runners

# Check runner logs
kubectl logs -n arc-runners <runner-pod-name>

# Check runner resources
kubectl describe runners -n arc-runners
```

## Using Runners in GitHub Actions

In your workflow file:

```yaml
name: CI with GPU

on: [push]

jobs:
  test-gpu:
    runs-on: [self-hosted, linux, x64, staging, gpu]
    steps:
      - uses: actions/checkout@v4
      - name: Check GPU
        run: nvidia-smi
      - name: Test PyTorch
        run: |
          python3 -c "import torch; print(torch.cuda.is_available())"
```

## Common Commands

```bash
# Check status
kubectl get all -n arc-systems
kubectl get all -n arc-runners

# View logs
kubectl logs -n arc-systems deployment/arc-controller-manager
kubectl logs -n arc-runners <runner-pod>

# Scale runners
kubectl scale runner <runner-name> --replicas=5 -n arc-runners

# Delete resources
just k8s-delete staging
just tf-destroy staging
```

## Troubleshooting

### Runners not starting

```bash
# Check controller logs
kubectl logs -n arc-systems deployment/arc-controller-manager

# Check runner pod events
kubectl describe pod -n arc-runners <runner-pod>

# Verify GitHub token
kubectl get secret -n arc-systems arc-controller-manager -o yaml
```

### GPU not available

```bash
# Check device plugin
kubectl logs -n kube-system daemonset/nvidia-device-plugin-daemonset

# Check node labels
kubectl get nodes --show-labels | grep nvidia

# SSH to GPU node and check
nvidia-smi
docker run --rm --gpus all nvidia/cuda:12.1.0-base-ubuntu22.04 nvidia-smi
```

### OpenTofu errors

```bash
# Reinitialize
just tf-init staging

# Check state
cd terraform/environments/staging
tofu state list

# Validate configuration
just tf-validate
```

## Production Deployment

Once staging is working:

```bash
# Deploy to production
just tf-init production
just tf-plan production
just tf-apply production

# Configure kubectl for production
cd terraform/environments/production
tofu output configure_kubectl

# Deploy K8s and ARC
just k8s-apply production
just helm-install-arc production
just helm-install-runners production
```

## Next Steps

- Set up monitoring (Prometheus, Grafana)
- Configure auto-scaling policies
- Set up log aggregation (CloudWatch, ELK)
- Implement backup/disaster recovery
- Create custom runner images for specific workloads
- Configure runner lifecycle hooks
- Set up cost monitoring and optimization

## Additional Resources

- [ARC Documentation](https://github.com/actions-runner-controller/actions-runner-controller)
- [EKS Best Practices](https://aws.github.io/aws-eks-best-practices/)
- [NVIDIA Device Plugin](https://github.com/NVIDIA/k8s-device-plugin)
- [OpenTofu Documentation](https://opentofu.org/docs/)
