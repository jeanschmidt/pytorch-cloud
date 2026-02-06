# AGENTS.md - AI Assistant Guidelines for pytorch-cloud

This document provides guidelines for AI assistants working on this codebase.

## Project Overview

This is a CI infrastructure project that provides GitHub Actions self-hosted runners on AWS using Kubernetes (EKS). The project manages:

- **Terraform**: Infrastructure as code for AWS resources (EKS, VPC, IAM, etc.)
- **Kubernetes**: GPU device plugins and runner deployments
- **Docker**: Custom runner images with GPU support
- **Helm**: Values for ARC (Actions Runner Controller) installation
- **Bash Scripts**: Node bootstrap and runner lifecycle hooks
- **AMI Building**: Packer templates for custom EKS node images

## Directory Structure

The project follows strict separation of concerns:

```
pytorch-cloud/
├── terraform/          # Cloud-specific: AWS infrastructure
│   ├── modules/       # Reusable modules (VPC, EKS)
│   └── environments/  # Environment configs (staging, production)
├── kubernetes/        # Cloud-agnostic: K8s manifests
│   ├── base/         # Base manifests (kustomize)
│   └── overlays/     # Environment overlays
├── docker/           # Cloud-agnostic: Container images
│   ├── runner-base/  # Base runner image
│   └── runner-gpu/   # GPU-enabled runner
├── helm/             # Cloud-agnostic: Helm values
│   ├── arc/          # ARC controller values
│   └── arc-runners/  # ARC runner values
├── scripts/          # Cloud-specific: Bash scripts
│   ├── bootstrap/    # Node initialization
│   └── hooks/        # Runner lifecycle hooks
├── ami/              # Cloud-specific: Packer templates
│   ├── eks-base/     # Base EKS node AMI
│   └── eks-gpu/      # GPU EKS node AMI
└── python/           # (Future) Cloud-agnostic: Python utilities
```

## Build System

This project uses **just** + **mise** for build coordination:

- `mise.toml`: Defines tool versions (Python, **OpenTofu**, kubectl, etc.)
- `justfile`: Defines all build/test/deploy commands

**⚠️ CRITICAL: This project uses OpenTofu (tofu), NOT Terraform**

**ALWAYS use `just` commands** rather than running tools directly:

```bash
just setup            # Install dependencies (includes tofu)
just tf-plan staging  # Plan changes (uses tofu internally)
just docker-build runner-gpu  # Build Docker images
just k8s-apply staging        # Apply Kubernetes manifests
```

**NEVER run `terraform` commands!** Use `tofu` or `just` commands only.

See [CRITICAL-USE-TOFU.md](CRITICAL-USE-TOFU.md) for important details.

## Key Guidelines

### 0. ⚠️ CRITICAL: NEVER USE TERRAFORM - USE TOFU ONLY

**THIS IS THE MOST IMPORTANT RULE!**

This project uses **OpenTofu (tofu)**, NOT Terraform.

**❌ NEVER EVER DO THIS:**
```bash
terraform init
terraform plan
terraform apply
terraform destroy
terraform <anything>
```

**✅ ALWAYS DO THIS:**
```bash
tofu init
tofu plan
tofu apply

# OR use just commands (recommended):
just tf-init staging
just tf-plan staging
just tf-apply staging
```

**WHY THIS IS CRITICAL:**
- Running `terraform` will **corrupt the state file**
- State file corruption can destroy infrastructure
- Mixing terraform and tofu commands causes deployment failures
- Recovery from state corruption is difficult/impossible

**If you accidentally run terraform:**
1. STOP immediately
2. Do NOT commit state file changes
3. Restore state from backup
4. Use tofu from now on

**For AI Assistants:**
- NEVER suggest or run `terraform` commands
- ALWAYS use `tofu` or `just` commands
- ALWAYS warn users if they mention terraform
- This rule overrides all other rules

See [CRITICAL-USE-TOFU.md](../CRITICAL-USE-TOFU.md) for full details.

### 1. No Direct Tool Invocation

❌ Don't: `terraform plan` (NEVER USE TERRAFORM!)
✅ Do: `tofu plan` or `just tf-plan staging`

❌ Don't: `docker build`
✅ Do: `just docker-build runner-gpu`

**Note**: Commands that start with `tf-` in justfile use `tofu` internally, not terraform.

### 2. Environment-Specific Operations

All operations require an environment (`staging` or `production`):

```bash
just tf-plan staging
just k8s-apply production
just helm-install-arc staging
```

### 3. Separation of Concerns

- **Never mix** YAML, scripts, Python, and Terraform in the same directory
- Keep cloud-specific code (Terraform, scripts, AMI) separate from cloud-agnostic (Docker, K8s, Helm)
- Terraform modules must be reusable across environments

### 4. CRITICAL: Do NOT Embed Scripts in Terraform

**❌ NEVER DO THIS:**
```hcl
# DO NOT embed bash scripts directly in Terraform!
resource "aws_launch_template" "example" {
  user_data = base64encode(<<-EOT
    #!/bin/bash
    yum install -y ...
    cat > /etc/config <<EOF
    ...
    EOF
  EOT
  )
}
```

**✅ ALWAYS DO THIS:**
```hcl
# Reference external scripts from their proper location
resource "aws_launch_template" "example" {
  user_data = base64encode(templatefile("${path.module}/user-data.sh.tpl", {
    post_bootstrap_script = file("${path.module}/../../scripts/bootstrap/setup.sh")
  }))
}
```

**Why?**
- Bash scripts belong in `scripts/` directory
- Terraform files belong in `terraform/` directory
- Mixing them makes code hard to maintain, test, and reuse
- Violates separation of concerns principle
- Makes shellcheck and linting impossible

**File Organization Rules:**
- All bash scripts → `scripts/` directory
- All Terraform code → `terraform/` directory  
- All Kubernetes YAML → `kubernetes/` directory
- All Dockerfile → `docker/` directory
- All Helm values → `helm/` directory
- Use `templatefile()` and `file()` to reference between them

### 5. No Unnecessary Complexity

This project includes NVIDIA GPU support:
- NVIDIA Device Plugin DaemonSet (`kubernetes/base/nvidia-device-plugin.yaml`)
- GPU node groups with taints and labels
- Custom GPU AMIs with NVIDIA drivers
- Docker nvidia-runtime configuration

### 5. No Unnecessary Complexity

- Don't add features beyond what's requested
- Keep changes minimal and focused
- Follow existing patterns in the codebase

### 7. Testing Requirements

- **Terraform**: Validate with `just tf-validate` before committing
- **Kubernetes**: Validate with `just k8s-validate` before applying
- **Docker**: Test builds locally before pushing
- **Scripts**: Use shellcheck for bash scripts

## Common Tasks

| Task | Command |
|------|---------|
| First-time setup | `just setup` |
| Deploy infrastructure | `just tf-apply <env>` |
| Build Docker image | `just docker-build <image>` |
| Apply K8s manifests | `just k8s-apply <env>` |
| Install ARC | `just helm-install-arc <env>` |
| Build AMI | `just ami-build <name>` |
| Run all checks | `just ci-check` |

## Secrets Management

- **Never** commit secrets, tokens, or credentials
- Use AWS Secrets Manager or Kubernetes secrets
- Reference secrets via environment variables
- GitHub tokens must be provided via Helm values or `--set`

## Making Changes

**Standard workflow for all changes:**

1. Run `just setup` if dependencies changed
2. Make your changes (keeping code organized by type)
3. **Run `just lint`** to check all code (OpenTofu, shell, YAML, Docker, etc.)
4. **Run `just lint-fix`** to auto-fix formatting issues
5. Run `just tf-validate` if OpenTofu was modified
6. Test in staging before production

**Linting is mandatory** - all PRs must pass `just lint` before merging.

See [docs/LINTING.md](docs/LINTING.md) for detailed linting information.

## Notes

- This is the **only** AGENTS.md file
- Do NOT run `setup.py` or install packages (no network access)
- Do NOT create summary files unless explicitly asked
- Do NOT mix component types in the same directory
