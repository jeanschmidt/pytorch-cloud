# pytorch-cloud

PyTorch CI infrastructure for GitHub Actions self-hosted runners on AWS using Kubernetes.

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
- **Docker**: Custom runner images with PyTorch toolchain and GPU support
- **Kubernetes**: Runner deployments and GPU device plugins (NVIDIA)
- **Helm**: External dependencies (ARC controller)
- **Scripts**: Bootstrap and configuration scripts for nodes
- **AMI**: Custom EC2 images for EKS nodes

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
│   ├── runner-base/  # Base runner image
│   └── runner-gpu/   # GPU-enabled runner image
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

```bash
# Install project-local dependencies
just setup

# You'll need to install system tools manually:
brew install hadolint  # Dockerfile linter
mise install  # shellcheck, shfmt from mise.toml

# Deploy infrastructure (staging)
just tf-init staging
just tf-plan staging
just tf-apply staging

# Install ARC controller
just helm-install-arc staging

# Deploy runners
just k8s-apply staging

# Build and push custom images
just docker-build runner-gpu
just docker-push <ecr-registry>/runner-gpu:latest
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
