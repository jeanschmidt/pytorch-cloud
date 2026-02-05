# Project Structure

This document describes the organization of the pytorch-cloud project.

## Directory Layout

```
pytorch-cloud/
├── .github/workflows/        # CI/CD pipelines
│   ├── ci.yaml              # Linting, validation, testing
│   ├── deploy.yaml          # Manual deployment workflow
│   └── docker-publish.yaml  # Docker image builds and pushes
│
├── terraform/               # Cloud-specific: AWS infrastructure
│   ├── modules/            # Reusable Terraform modules
│   │   ├── vpc/           # VPC, subnets, NAT gateways
│   │   └── eks/           # EKS cluster, node groups, IAM
│   └── environments/       # Per-environment configurations
│       ├── staging/       # Staging environment
│       └── production/    # Production environment
│
├── kubernetes/             # Cloud-agnostic: Kubernetes manifests
│   ├── base/              # Base resources (kustomize)
│   │   ├── namespace.yaml             # Namespaces
│   │   ├── nvidia-device-plugin.yaml  # GPU device plugin
│   │   └── kustomization.yaml
│   └── overlays/          # Environment-specific overlays
│       ├── staging/
│       └── production/
│
├── docker/                # Cloud-agnostic: Container images
│   ├── runner-base/       # Base runner image
│   │   ├── Dockerfile
│   │   └── .dockerignore
│   └── runner-gpu/        # GPU-enabled runner image
│       ├── Dockerfile
│       └── .dockerignore
│
├── helm/                  # Cloud-agnostic: Helm values
│   ├── arc/              # ARC controller configuration
│   │   ├── values.yaml
│   │   ├── values-staging.yaml
│   │   └── values-production.yaml
│   └── arc-runners/      # ARC runner configuration
│       ├── values.yaml
│       ├── values-staging.yaml
│       └── values-production.yaml
│
├── scripts/              # Cloud-specific: Bash scripts
│   ├── bootstrap/       # Node initialization scripts
│   │   ├── eks-cpu-bootstrap.sh
│   │   └── eks-gpu-bootstrap.sh
│   └── hooks/          # Runner lifecycle hooks
│       ├── pre-job.sh
│       └── post-job.sh
│
├── ami/                 # Cloud-specific: Packer templates
│   ├── eks-base/       # Base EKS node AMI
│   │   └── packer.pkr.hcl
│   └── eks-gpu/        # GPU-enabled EKS node AMI
│       └── packer.pkr.hcl
│
├── python/             # (Future) Cloud-agnostic: Python utilities
│   ├── src/
│   │   └── pytorch_cloud/
│   └── tests/
│
├── docs/               # Documentation
│   ├── QUICKSTART.md  # Getting started guide
│   └── GPU-SETUP.md   # GPU configuration guide
│
├── .gitignore         # Git ignore patterns
├── mise.toml          # Tool version management
├── justfile           # Command definitions
├── README.md          # Project overview
├── AGENTS.md          # AI assistant guidelines
├── CONTRIBUTING.md    # Contribution guidelines
└── LICENSE            # Project license
```

## Design Principles

### 1. Separation of Concerns

The project strictly separates components by type and cloud-specificity:

**Cloud-Agnostic Components:**
- `docker/` - Container images (portable across clouds)
- `kubernetes/` - K8s manifests (portable across clouds)
- `helm/` - Helm values for external charts
- `python/` - Python utilities (future)

**Cloud-Specific Components:**
- `terraform/` - AWS infrastructure (EKS, VPC, IAM)
- `scripts/` - Bash scripts for AWS EKS nodes
- `ami/` - Packer templates for AWS AMIs

### 2. No Mixing of File Types

Each directory contains only one type of file:
- Terraform files only in `terraform/`
- YAML manifests only in `kubernetes/`
- Bash scripts only in `scripts/`
- Docker images only in `docker/`
- Helm values only in `helm/`

This prevents confusion and makes the codebase easier to navigate.

### 3. Environment Separation

Environment-specific configuration is handled differently per component:

| Component | Method |
|-----------|--------|
| Terraform | Separate directories (`environments/staging/`, `environments/production/`) |
| Kubernetes | Kustomize overlays (`overlays/staging/`, `overlays/production/`) |
| Helm | Separate values files (`values-staging.yaml`, `values-production.yaml`) |

### 4. Reusable Modules

- **Terraform modules** (`terraform/modules/`) are reusable across environments
- **Kubernetes base** (`kubernetes/base/`) is shared, overlays customize
- **Helm base values** (`helm/*/values.yaml`) are shared, environment values override

### 5. Build System

All operations go through `just` commands:
- Provides consistent interface across components
- Ensures correct tool versions via `mise`
- Hides complexity of multi-step operations
- Documents available commands (`just --list`)

## Component Responsibilities

### Terraform (`terraform/`)

**Purpose:** Define and provision AWS infrastructure

**Components:**
- VPC with public/private subnets, NAT gateways
- EKS cluster with OIDC provider
- EKS node groups (CPU and GPU)
- IAM roles and policies
- Security groups

**Usage:**
```bash
just tf-init staging
just tf-plan staging
just tf-apply staging
```

### Kubernetes (`kubernetes/`)

**Purpose:** Define Kubernetes resources

**Components:**
- Namespaces (`arc-systems`, `arc-runners`)
- NVIDIA device plugin DaemonSet (for GPU support)
- Future: Additional cluster resources

**Usage:**
```bash
just k8s-apply staging
just k8s-validate
```

### Docker (`docker/`)

**Purpose:** Build custom runner images

**Components:**
- `runner-base`: Standard runner with dev tools
- `runner-gpu`: GPU-enabled runner with CUDA

**Usage:**
```bash
just docker-build runner-gpu
just docker-push <registry>/runner-gpu:latest
```

### Helm (`helm/`)

**Purpose:** Configure external Helm charts

**Components:**
- ARC controller values (manages runner lifecycle)
- ARC runner values (runner configuration)

**Usage:**
```bash
just helm-install-arc staging
just helm-install-runners staging
```

### Scripts (`scripts/`)

**Purpose:** Node and runner lifecycle automation

**Components:**
- Bootstrap scripts (run when nodes first boot)
- Runner hooks (pre-job, post-job)

**Usage:**
- Bootstrap scripts: Referenced by Terraform user data
- Hooks: Mounted into runner containers

### AMI (`ami/`)

**Purpose:** Build custom EKS node images

**Components:**
- Base AMI with dev tools, ccache
- GPU AMI with NVIDIA drivers, nvidia-docker

**Usage:**
```bash
just ami-validate
just ami-build eks-gpu
```

## Data Flow

### Deployment Flow

1. **Terraform** creates VPC, EKS cluster, and node groups
2. **Bootstrap scripts** configure nodes on first boot
3. **Kubernetes manifests** deploy NVIDIA device plugin
4. **Helm** installs ARC controller
5. **Docker images** provide runner environments
6. **Helm** configures ARC runners
7. **GitHub Actions** workflows use runners

### Job Execution Flow

1. GitHub Actions workflow starts
2. ARC controller receives webhook
3. Controller creates runner pod
4. Kubernetes schedules pod on appropriate node (CPU or GPU)
5. Pre-job hook runs (cleanup, setup)
6. Job executes in runner container
7. Post-job hook runs (cleanup, stats)
8. Runner pod terminates

## File Naming Conventions

- **Terraform:** `main.tf`, `variables.tf`, `outputs.tf`
- **Kubernetes:** Descriptive names like `nvidia-device-plugin.yaml`
- **Docker:** `Dockerfile`, `.dockerignore`
- **Helm:** `values.yaml`, `values-<env>.yaml`
- **Scripts:** Descriptive names with `.sh` extension
- **Packer:** `packer.pkr.hcl`

## Adding New Components

### Adding a New Terraform Module

1. Create `terraform/modules/<name>/`
2. Add `main.tf`, `variables.tf`, `outputs.tf`
3. Reference from environment configs

### Adding Kubernetes Resources

1. Add YAML to `kubernetes/base/`
2. Update `kubernetes/base/kustomization.yaml`
3. Add environment-specific patches to overlays if needed

### Adding Docker Images

1. Create `docker/<name>/`
2. Add `Dockerfile` and `.dockerignore`
3. Update `justfile` if special build args needed

### Adding Scripts

1. Add to `scripts/bootstrap/` or `scripts/hooks/`
2. Start with `#!/usr/bin/env bash` and `set -euo pipefail`
3. Run `shellcheck` to validate

### Adding AMI Templates

1. Create `ami/<name>/`
2. Add `packer.pkr.hcl`
3. Test with `just ami-validate`

## Future Enhancements

The structure is designed to accommodate:

- **Python utilities** in `python/src/pytorch_cloud/`
- **Additional Kubernetes resources** (monitoring, logging)
- **Multiple cloud providers** (separate `gcp/`, `azure/` directories)
- **Additional runner types** (macOS, Windows)
- **Custom Helm charts** (if needed beyond external charts)

## Maintenance

### Regular Tasks

- Update tool versions in `mise.toml`
- Update base AMIs in Packer templates
- Update CUDA versions in GPU Dockerfile
- Update EKS cluster version in Terraform
- Update ARC chart version in Helm commands

### Dependencies

Track dependency versions in:
- `mise.toml` - Tool versions (Terraform, kubectl, helm)
- `docker/*/Dockerfile` - OS packages, CUDA, Python packages
- `ami/*/packer.pkr.hcl` - Base AMI, NVIDIA drivers
- `terraform/modules/eks/main.tf` - EKS version, addon versions

## References

- [Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
- [EKS Documentation](https://docs.aws.amazon.com/eks/)
- [Actions Runner Controller](https://github.com/actions-runner-controller/actions-runner-controller)
- [NVIDIA Device Plugin](https://github.com/NVIDIA/k8s-device-plugin)
- [Kustomize](https://kustomize.io/)
