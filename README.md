# pytorch-cloud

PyTorch CI infrastructure for GitHub Actions self-hosted runners on AWS using Kubernetes.

---

## ⚠️ AWS Region Check
**Before any AWS CLI commands**: Check region in `terraform/environments/{env}/variables.tf` (aws_region variable), NOT your local AWS CLI config. Your CLI region may differ from infrastructure.

## 💥 Staging Environment: Break Things Freely
**Staging/canary**: No need to drain nodes, wait for pods, or avoid disruption. This environment is for testing infrastructure changes. Kill nodes, break workflows, experiment freely - no production workloads here.

---

## ⚠️ CRITICAL: THIS PROJECT USES OPENTOFU (tofu), NOT TERRAFORM

**NEVER run `terraform` commands! Always use `tofu` or `just` commands.**

Running `terraform` instead of `tofu` will **corrupt the state file** and break deployments.

✅ Use: `tofu plan` or `just tf-plan staging`  
❌ Never: `terraform plan`

See [CRITICAL-USE-TOFU.md](CRITICAL-USE-TOFU.md) for details.

---

## Overview

This project deploys and manages GitHub Actions Runner Controller (ARC) on AWS EKS to provide self-hosted GPU and CPU runners for PyTorch CI/CD workflows.

### Key Components

- **Terraform**: Infrastructure as Code for AWS resources (EKS, VPC, IAM, etc.)
- **Docker**: Lightweight runner image (workflows specify their own containers)
- **Kubernetes**: Runner deployments, GPU device plugins (NVIDIA), and job containers
- **Helm**: External dependencies (ARC controller)
- **Scripts**: Bootstrap and configuration scripts for nodes
- **AMI**: Custom EC2 images for EKS nodes

### Runner Architecture

pytorch-cloud uses **Kubernetes mode** for ARC runners. This means:

- **Lightweight runner pods**: Contain only the GitHub Actions runner binary and basic tools (~500MB)
- **Workflow containers**: All builds must use the `container:` tag to specify their build environment
- **Dynamic GPU allocation**: GPU resources are allocated to workflow containers, not runner pods
- **Better isolation**: Each job runs in its own pod with proper resource limits
- **Flexibility**: Users choose exact CUDA version, PyTorch version, dependencies, etc.

#### Workflow Requirements

All workflows using these runners **MUST** specify a `container:` in their job definition:

```yaml
jobs:
  build:
    runs-on: pytorch-cpu-small
    container:
      image: python:3.11
    steps:
      - uses: actions/checkout@v4
      - run: python setup.py build
```

For GPU workflows:

```yaml
jobs:
  gpu-test:
    runs-on: pytorch-gpu-t4
    container:
      image: pytorch/pytorch:2.5.0-cuda12.4-cudnn9-devel
      options: --gpus all
    steps:
      - run: nvidia-smi
      - run: python test_gpu.py
```

## Architecture

```
pytorch-cloud/
├── terraform/          # Cloud-specific: AWS infrastructure
│   ├── modules/       # Reusable Terraform modules
│   └── environments/  # Per-environment configs (staging, production)
├── kubernetes/        # Cloud-agnostic: K8s manifests
│   ├── base/         # Base manifests (kustomize)
│   └── overlays/     # Environment-specific overlays
├── docker/           # Cloud-agnostic: Container images
│   └── runner-base/  # Lightweight runner image (CPU and GPU)
├── helm/             # Cloud-agnostic: Helm values for external charts
│   ├── arc/          # ARC controller values
│   └── arc-runners/  # ARC runner values
├── scripts/          # Cloud-specific: Bash scripts for nodes
│   ├── bootstrap/    # Node initialization scripts
│   └── hooks/        # Runner lifecycle hooks
├── ami/              # Cloud-specific: Packer templates
│   ├── eks-base/     # Base EKS node AMI
│   └── eks-gpu/      # GPU-enabled EKS node AMI
└── python/           # (Future) Cloud-agnostic: Python utilities
```

## Prerequisites

- [mise](https://mise.jdx.dev/) - Tool version manager (for project-local tools)
- [just](https://just.systems/) - Command runner
- [uv](https://docs.astral.sh/uv/) - Python package manager (for project-local Python tools)
- **[OpenTofu](https://opentofu.org/)** - Infrastructure as Code (NOT Terraform!)
- AWS credentials configured
- Docker installed

**System Tools** (install yourself via brew/package manager):
- `hadolint` - Dockerfile linter (cannot be project-local)

**⚠️ CRITICAL**: 
- This project uses **OpenTofu (tofu)**, not Terraform. Using `terraform` commands will corrupt the state file.
- All tools are installed **project-locally** to avoid conflicts with other projects you work on.
- `mise` installs tools in `.mise/` and Python packages go in `.venv/`

## Quick Start

### Option 1: Full Automated Deployment (Recommended)

```bash
# Clone the project
git clone <repository-url>
cd pytorch-cloud

# Configure AWS credentials
export AWS_PROFILE=your-profile  # or use aws configure

# Deploy everything to staging with one command!
just deploy staging

# The deploy command will:
# ✅ Auto-install all dependencies (mise, tofu, kubectl, helm, etc.)
# ✅ Initialize and apply Terraform (VPC, EKS, node groups)
# ✅ Configure kubectl to access the cluster
# ✅ Deploy Kubernetes resources (namespaces, NVIDIA plugin)
# ✅ Install Helm charts (ARC controller, runner sets)
# ✅ Optionally build and push Docker images

# With Docker registry (builds and pushes images):
just deploy staging 123456789.dkr.ecr.us-west-2.amazonaws.com/pytorch-cloud

# Deploy to production:
just deploy production

# Destroy an environment:
just destroy staging
```

### Option 2: Manual Step-by-Step Deployment

```bash
# Clone the project
git clone <repository-url>
cd pytorch-cloud

# That's it! Just run any command and dependencies will auto-install:
just validate  # Runs all validation checks (automatically sets up dependencies)
just lint      # Runs all linters (automatically sets up dependencies)

# Deploy infrastructure step by step:
just tf-init staging
just tf-plan staging
just tf-apply staging

# Update kubeconfig
aws eks update-kubeconfig --name pytorch-arc-staging --region us-west-2

# Deploy Kubernetes resources
just k8s-apply staging

# Install Helm charts
just helm-install-arc staging
just helm-install-runners staging
just helm-install-gpu-runners staging

# Build and push lightweight runner image (optional - uses default if not specified)
# Single image used for both CPU and GPU runners
# Workflows specify their own GPU-enabled containers
```

### Automatic Dependency Setup

**All `just` commands automatically handle dependencies!**

You don't need to run `just setup` manually - any command you run will:
1. Check if dependencies are installed
2. Install missing dependencies automatically (first run only)
3. Subsequent runs are instant (< 1 second)

This means you can clone the project and immediately run:
- `just validate` - Validates all code
- `just lint` - Lints everything  
- `just lint-shell` - Lint shell scripts only
- `just tf-plan staging` - Plan Terraform changes

**One-time manual installs** (cannot be project-local):
```bash
brew install hadolint  # Dockerfile linter
```

**Optional tools** (for full linting):
```bash
mise install  # Installs shellcheck + shfmt from mise.toml
```

## Common Commands

### Deployment
```bash
just deploy staging                    # Full deployment to staging
just deploy production <registry>      # Deploy to production with Docker images
just deploy-noninteractive staging     # Deploy without prompts (for CI/CD)
just destroy staging                   # Destroy entire staging environment
```

### Infrastructure (Terraform/OpenTofu)
```bash
just tf-init staging                   # Initialize Terraform
just tf-plan staging                   # Plan infrastructure changes
just tf-apply staging                  # Apply infrastructure changes
just tf-destroy staging                # Destroy infrastructure
just tf-validate                       # Validate Terraform configuration
```

### Kubernetes
```bash
just k8s-apply staging                 # Apply Kubernetes manifests
just k8s-delete staging                # Delete Kubernetes resources
just k8s-diff staging                  # Show diff of changes
just k8s-validate                      # Validate all manifests (dry-run)
```

### Helm
```bash
just helm-install-arc staging          # Install ARC controller
just helm-install-runners staging      # Install CPU runner scale set
just helm-install-gpu-runners staging  # Install GPU runner scale set
```

### Docker
```bash
# Lightweight runner image (single image for CPU and GPU)
# Workflows specify their own containers with required dependencies
just docker-build runner-base         # Build lightweight runner image
# Note: No separate GPU image needed - workflows use GPU containers
```

### Validation & Linting
```bash
just validate                          # Run all validation (lint + tf + ami + k8s)
just lint                              # Run all linters
just lint-fix                          # Auto-fix linting issues
just lint-shell                        # Lint shell scripts
just lint-yaml                         # Lint YAML files
just lint-docker                       # Lint Dockerfiles
```

### AMI Building
```bash
just ami-build eks-base                # Build base EKS AMI
just ami-build eks-gpu                 # Build GPU EKS AMI
just ami-validate                      # Validate Packer templates
```

### Utilities
```bash
just setup                             # Manually run setup (auto-runs when needed)
just clean                             # Clean generated files and caches
just                                   # Show all available commands
```

## GPU Support

This project includes NVIDIA GPU support for PyTorch workloads:

- **NVIDIA Device Plugin**: DaemonSet for GPU discovery
- **GPU Operator**: (Optional) For advanced GPU management
- **Custom AMIs**: Pre-configured with NVIDIA drivers
- **Docker GPU Runtime**: nvidia-docker2 integration

## Environments

- **staging**: Development and testing environment
- **production**: Production environment for PyTorch CI

## Project Structure Principles

### Separation of Concerns

1. **Cloud-agnostic** components (Docker, Kubernetes, Helm) are separated from **cloud-specific** (Terraform, scripts, AMIs)
2. Each component type has its own directory (no mixing of YAML, scripts, Python, Terraform)
3. Terraform modules are reusable across environments
4. Kubernetes uses kustomize overlays for environment-specific configs

### Component Organization

| Component | Location | Cloud-specific? |
|-----------|----------|-----------------|
| Infrastructure | `terraform/` | ✅ AWS |
| Container images | `docker/` | ❌ Agnostic |
| K8s manifests | `kubernetes/` | ❌ Agnostic |
| External charts | `helm/` | ❌ Agnostic |
| Bootstrap scripts | `scripts/` | ✅ AWS |
| Custom AMIs | `ami/` | ✅ AWS |
| Python utilities | `python/` | ❌ Agnostic |

### CRITICAL: Do NOT Mix Code Types

**❌ NEVER DO THIS:**
- Embed bash scripts inside Terraform files (use `templatefile()` to reference external scripts)
- Put Python code in bash scripts
- Mix Kubernetes YAML with shell scripts in the same file
- Inline long scripts in Dockerfile RUN commands (use COPY and separate script files)

**✅ ALWAYS DO THIS:**
- Keep bash scripts in `scripts/` directory
- Keep Terraform in `terraform/` directory
- Keep Kubernetes YAML in `kubernetes/` directory
- Reference scripts from Terraform using `templatefile()` or `file()` functions
- Use proper project organization - one file type per directory

**Example (CORRECT):**
```hcl
# In terraform/modules/eks/main.tf
user_data = base64encode(templatefile("${path.module}/user-data.sh.tpl", {
  post_bootstrap_script = file("${path.module}/../../scripts/bootstrap/node-setup.sh")
}))
```

**Example (WRONG - DO NOT DO THIS):**
```hcl
# DO NOT embed scripts directly in Terraform!
user_data = base64encode(<<-EOT
  #!/bin/bash
  yum install -y ...
  cat > /etc/config.json <<EOF
  ...
  EOF
EOT
)
```

## Common Tasks

| Task | Command |
|------|---------|
| Deploy infrastructure | `just tf-apply <env>` |
| Install ARC | `just helm-install-arc <env>` |
| Deploy runners | `just k8s-apply <env>` |
| Build Docker image | `just docker-build <image>` |
| Build AMI | `just ami-build <name>` |
| Run all linting | `just lint` |
| Auto-fix linting | `just lint-fix` |
| Run all checks | `just ci-check` |

## Development

### Linting

This project uses comprehensive linting for code quality:

```bash
# Run all linters
just lint

# Auto-fix issues
just lint-fix

# Run specific linters
just lint-tofu      # OpenTofu/Terraform
just lint-shell     # Bash scripts
just lint-yaml      # Kubernetes/Helm YAML
just lint-docker    # Dockerfiles
just lint-helm      # Helm charts
just lint-python    # Python code
```

See [docs/LINTING.md](docs/LINTING.md) for detailed linting documentation.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for development guidelines.

## License

See [LICENSE](LICENSE) for details.
