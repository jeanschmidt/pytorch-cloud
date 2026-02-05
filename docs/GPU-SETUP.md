# GPU Support Guide

This guide covers GPU-specific configuration and troubleshooting for pytorch-cloud.

## Overview

pytorch-cloud provides NVIDIA GPU support for PyTorch CI/CD workloads through:

1. **EKS GPU Node Groups** - EC2 instances with NVIDIA GPUs (g4dn, p3, p4 families)
2. **NVIDIA Device Plugin** - Kubernetes DaemonSet for GPU discovery
3. **Custom GPU AMIs** - Pre-configured with NVIDIA drivers
4. **GPU-enabled Runner Images** - Docker images with CUDA and PyTorch dependencies
5. **Docker GPU Runtime** - nvidia-docker2 for container GPU access

## Architecture

```
┌─────────────────────────────────────────────┐
│ GitHub Actions Workflow                     │
│ runs-on: [self-hosted, gpu]                 │
└─────────────────┬───────────────────────────┘
                  │
                  v
┌─────────────────────────────────────────────┐
│ ARC Controller                               │
│ Manages runner lifecycle                    │
└─────────────────┬───────────────────────────┘
                  │
                  v
┌─────────────────────────────────────────────┐
│ Runner Pod (GPU)                             │
│ - Requests: nvidia.com/gpu=1                 │
│ - Tolerates: nvidia.com/gpu=true             │
│ - Has CUDA toolkit, PyTorch deps             │
└─────────────────┬───────────────────────────┘
                  │
                  v
┌─────────────────────────────────────────────┐
│ EKS GPU Node                                 │
│ - NVIDIA drivers installed                   │
│ - nvidia-docker2 configured                  │
│ - Device plugin exposes GPUs                 │
└─────────────────┬───────────────────────────┘
                  │
                  v
┌─────────────────────────────────────────────┐
│ NVIDIA GPU (Physical)                        │
│ Tesla T4, V100, A10G, etc.                   │
└─────────────────────────────────────────────┘
```

## Components

### 1. NVIDIA Device Plugin

The NVIDIA device plugin DaemonSet runs on all GPU nodes and:
- Discovers NVIDIA GPUs on the node
- Exposes them as `nvidia.com/gpu` resources
- Enables scheduling of GPU workloads

**Location:** `kubernetes/base/nvidia-device-plugin.yaml`

**Key features:**
- Only runs on nodes with `nvidia.com/gpu=true` label
- Tolerates GPU node taints
- Uses `nvcr.io/nvidia/k8s-device-plugin:v0.14.5` image

### 2. GPU Node Groups

GPU nodes are configured with:
- **Taints:** `nvidia.com/gpu=true:NoSchedule` (prevents non-GPU pods)
- **Labels:** `nvidia.com/gpu=true`, `role=gpu`
- **Instance types:** g4dn.xlarge (default), customizable
- **Scaling:** 0-5 nodes (configurable)

**Location:** `terraform/modules/eks/main.tf`

### 3. GPU-enabled Runner Image

The `runner-gpu` Docker image includes:
- Ubuntu 22.04 base
- NVIDIA CUDA 12.1 toolkit
- cuDNN libraries
- PyTorch build dependencies (cmake, ninja, ccache)
- GitHub Actions runner
- Common Python packages (numpy, pyyaml, etc.)

**Location:** `docker/runner-gpu/Dockerfile`

### 4. Custom GPU AMIs

GPU AMIs are pre-configured with:
- Amazon EKS GPU-optimized base AMI
- NVIDIA drivers (535.x series)
- nvidia-docker2 runtime
- Docker configured with NVIDIA as default runtime
- GPU monitoring tools (nvtop)
- Persistence mode enabled

**Location:** `ami/eks-gpu/packer.pkr.hcl`

## Deployment

### Step 1: Deploy EKS with GPU Nodes

```bash
# Deploy infrastructure
just tf-init staging
just tf-plan staging
just tf-apply staging

# Verify GPU nodes
kubectl get nodes -L nvidia.com/gpu
```

### Step 2: Deploy NVIDIA Device Plugin

```bash
# Apply Kubernetes manifests
just k8s-apply staging

# Verify device plugin is running
kubectl get daemonset -n kube-system nvidia-device-plugin-daemonset
kubectl get pods -n kube-system -l name=nvidia-device-plugin-ds

# Check logs
kubectl logs -n kube-system -l name=nvidia-device-plugin-ds
```

### Step 3: Build and Deploy GPU Runner Images

```bash
# Build GPU runner image
just docker-build runner-gpu

# Tag for ECR
docker tag runner-gpu:latest <account>.dkr.ecr.us-west-2.amazonaws.com/pytorch-cloud/runner-gpu:latest

# Push to ECR
aws ecr get-login-password --region us-west-2 | docker login --username AWS --password-stdin <account>.dkr.ecr.us-west-2.amazonaws.com
docker push <account>.dkr.ecr.us-west-2.amazonaws.com/pytorch-cloud/runner-gpu:latest
```

### Step 4: Configure ARC for GPU Runners

Update `helm/arc-runners/values-staging.yaml`:

```yaml
runnerLabels:
  - self-hosted
  - linux
  - x64
  - gpu
  - cuda

# Request GPU resources
runnerResources:
  limits:
    nvidia.com/gpu: 1
    cpu: 8
    memory: 32Gi
  requests:
    nvidia.com/gpu: 1
    cpu: 4
    memory: 16Gi

# Tolerate GPU node taints
tolerations:
  - key: nvidia.com/gpu
    operator: Equal
    value: "true"
    effect: NoSchedule

# Use custom GPU image
image:
  repository: <account>.dkr.ecr.us-west-2.amazonaws.com/pytorch-cloud/runner-gpu
  tag: latest
```

Then deploy:

```bash
just helm-install-runners staging
```

## Testing GPU Support

### Test 1: Check GPU Availability on Nodes

```bash
# List GPU nodes
kubectl get nodes -l nvidia.com/gpu=true

# Check GPU capacity
kubectl describe nodes -l nvidia.com/gpu=true | grep -A 10 "Capacity:"
```

### Test 2: Run GPU Test Pod

```bash
# Run nvidia-smi in a test pod
kubectl run gpu-test --rm -it --restart=Never \
  --image=nvidia/cuda:12.1.0-base-ubuntu22.04 \
  --overrides='{"spec":{"tolerations":[{"key":"nvidia.com/gpu","operator":"Equal","value":"true","effect":"NoSchedule"}],"nodeSelector":{"nvidia.com/gpu":"true"}}}' \
  --limits=nvidia.com/gpu=1 \
  -- nvidia-smi

# Expected output: nvidia-smi showing GPU details
```

### Test 3: Run PyTorch GPU Test

```bash
kubectl run pytorch-gpu-test --rm -it --restart=Never \
  --image=pytorch/pytorch:2.1.0-cuda12.1-cudnn8-runtime \
  --overrides='{"spec":{"tolerations":[{"key":"nvidia.com/gpu","operator":"Equal","value":"true","effect":"NoSchedule"}],"nodeSelector":{"nvidia.com/gpu":"true"}}}' \
  --limits=nvidia.com/gpu=1 \
  -- python3 -c "import torch; print(f'CUDA available: {torch.cuda.is_available()}'); print(f'Device count: {torch.cuda.device_count()}'); print(f'Device name: {torch.cuda.get_device_name(0) if torch.cuda.is_available() else \"N/A\"}')"
```

### Test 4: GitHub Actions Workflow

Create `.github/workflows/test-gpu.yml`:

```yaml
name: Test GPU

on: [push]

jobs:
  test-gpu:
    runs-on: [self-hosted, linux, x64, gpu]
    steps:
      - uses: actions/checkout@v4
      
      - name: Check NVIDIA Driver
        run: nvidia-smi
      
      - name: Check CUDA
        run: nvcc --version
      
      - name: Test PyTorch GPU
        run: |
          python3 -c "
          import torch
          print(f'PyTorch version: {torch.__version__}')
          print(f'CUDA available: {torch.cuda.is_available()}')
          print(f'CUDA version: {torch.version.cuda}')
          if torch.cuda.is_available():
              print(f'Device count: {torch.cuda.device_count()}')
              print(f'Device name: {torch.cuda.get_device_name(0)}')
              print(f'Device capability: {torch.cuda.get_device_capability(0)}')
              # Test GPU operations
              x = torch.randn(1000, 1000).cuda()
              y = torch.matmul(x, x)
              print(f'GPU computation successful!')
          "
```

## Troubleshooting

### Issue: Device plugin not running

**Symptoms:**
- DaemonSet shows 0/X pods ready
- GPU resources not available

**Debug:**
```bash
kubectl describe daemonset -n kube-system nvidia-device-plugin-daemonset
kubectl get events -n kube-system --sort-by='.lastTimestamp'
```

**Common causes:**
- No GPU nodes available (check node count)
- Nodes missing `nvidia.com/gpu=true` label
- Device plugin can't access `/var/lib/kubelet/device-plugins`

**Fix:**
```bash
# Check GPU nodes exist
kubectl get nodes -l nvidia.com/gpu=true

# Manually label node if needed
kubectl label node <node-name> nvidia.com/gpu=true

# Restart device plugin
kubectl delete pods -n kube-system -l name=nvidia-device-plugin-ds
```

### Issue: Runners can't access GPU

**Symptoms:**
- `nvidia-smi: command not found` in runner
- `RuntimeError: No CUDA GPUs are available`

**Debug:**
```bash
# Check runner pod has GPU resource
kubectl describe pod -n arc-runners <runner-pod> | grep -A 5 "Limits:"

# Check runner pod is on GPU node
kubectl get pod -n arc-runners <runner-pod> -o wide

# Check runner pod toleration
kubectl get pod -n arc-runners <runner-pod> -o yaml | grep -A 5 "tolerations:"
```

**Fix:**
- Ensure runner spec requests `nvidia.com/gpu` resource
- Ensure runner has toleration for `nvidia.com/gpu=true:NoSchedule`
- Verify node has GPU capacity available

### Issue: CUDA version mismatch

**Symptoms:**
- `CUDA driver version is insufficient`
- PyTorch can't find CUDA libraries

**Debug:**
```bash
# Check CUDA version in container
kubectl exec -n arc-runners <runner-pod> -- nvcc --version

# Check CUDA driver version on node
# SSH to node:
nvidia-smi
```

**Fix:**
- Update CUDA version in `docker/runner-gpu/Dockerfile`
- Rebuild and push runner image
- Ensure AMI has compatible driver version

### Issue: Out of GPU memory

**Symptoms:**
- `RuntimeError: CUDA out of memory`
- Jobs failing with OOM errors

**Debug:**
```bash
# Check GPU memory usage
kubectl exec -n arc-runners <runner-pod> -- nvidia-smi
```

**Fix:**
- Reduce batch size in tests
- Add memory cleanup in runner hooks (`scripts/hooks/post-job.sh`)
- Scale up to larger GPU instances (e.g., g4dn.2xlarge)

## Performance Optimization

### 1. GPU Persistence Mode

Enable persistence mode to reduce CUDA initialization time:

```bash
# In bootstrap script or AMI
nvidia-smi -pm 1
```

Already configured in `scripts/bootstrap/eks-gpu-bootstrap.sh`.

### 2. Build Caching

Use ccache to speed up builds:

```yaml
# In GitHub Actions workflow
- name: Setup ccache
  run: |
    ccache -z
    ccache --max-size=10G

- name: Build
  run: python setup.py build
  env:
    CC: ccache gcc
    CXX: ccache g++

- name: ccache stats
  run: ccache -s
```

### 3. Docker Layer Caching

Build runner images with multi-stage builds and caching:

```dockerfile
# Cache CUDA toolkit installation
FROM nvidia/cuda:12.1.0-devel-ubuntu22.04 as cuda-base
RUN apt-get update && apt-get install -y ...

# Final stage
FROM cuda-base
COPY --from=builder ...
```

### 4. Runner Scaling

Configure auto-scaling based on workload:

```yaml
# In helm/arc-runners/values.yaml
minRunners: 0
maxRunners: 10
runnerScaleDownDelaySecondsAfterScaleOut: 300
```

## Monitoring

### GPU Metrics

View GPU metrics on nodes:

```bash
# Install metrics server if not already installed
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml

# View GPU usage
kubectl exec -n kube-system <nvidia-device-plugin-pod> -- nvidia-smi dmon -s u -c 1
```

### Runner Logs

Check runner logs for GPU initialization:

```bash
kubectl logs -n arc-runners <runner-pod> | grep -i cuda
kubectl logs -n arc-runners <runner-pod> | grep -i nvidia
```

### CloudWatch Metrics

Configure GPU metrics to CloudWatch:

```bash
# Install NVIDIA DCGM exporter
kubectl apply -f https://raw.githubusercontent.com/NVIDIA/dcgm-exporter/main/dcgm-exporter.yaml

# Or use Prometheus + Grafana for GPU metrics
```

## Cost Optimization

### 1. Use Spot Instances

For non-critical workloads, use spot instances:

```hcl
# In terraform/modules/eks/main.tf
resource "aws_eks_node_group" "gpu" {
  capacity_type = "SPOT"
  instance_types = ["g4dn.xlarge", "g4dn.2xlarge"]
  # ...
}
```

### 2. Auto-scaling to Zero

Scale GPU runners to 0 when not in use:

```yaml
minRunners: 0
maxRunners: 10
runnerScaleDownDelaySecondsAfterScaleOut: 60
```

### 3. Right-size Instances

Choose appropriate instance types:

| Instance Type | GPU | vCPU | Memory | Use Case |
|---------------|-----|------|--------|----------|
| g4dn.xlarge   | 1x T4 | 4 | 16 GB | Small builds, testing |
| g4dn.2xlarge  | 1x T4 | 8 | 32 GB | Medium builds |
| p3.2xlarge    | 1x V100 | 8 | 61 GB | Training, large builds |
| p4d.24xlarge  | 8x A100 | 96 | 1152 GB | Large-scale training |

## Best Practices

1. **Pre-build AMIs:** Include NVIDIA drivers in AMIs to reduce boot time
2. **Use Device Plugin:** Always deploy NVIDIA device plugin for GPU discovery
3. **Set Resource Limits:** Always specify GPU requests/limits in pod specs
4. **Enable Persistence Mode:** Reduces CUDA initialization overhead
5. **Monitor GPU Usage:** Track utilization to optimize costs
6. **Clean Up After Jobs:** Use post-job hooks to free GPU memory
7. **Use Spot Instances:** For non-critical workloads to save costs
8. **Test Locally:** Build and test GPU images locally before deploying

## Additional Resources

- [NVIDIA Device Plugin Documentation](https://github.com/NVIDIA/k8s-device-plugin)
- [EKS GPU AMIs](https://docs.aws.amazon.com/eks/latest/userguide/gpu-ami.html)
- [CUDA Compatibility](https://docs.nvidia.com/deploy/cuda-compatibility/)
- [PyTorch CUDA Support](https://pytorch.org/get-started/locally/)
- [AWS EC2 GPU Instances](https://aws.amazon.com/ec2/instance-types/#Accelerated_Computing)
