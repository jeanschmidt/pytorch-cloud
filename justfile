# justfile - Command runner for pytorch-cloud
# https://just.systems/

# ⚠️ CRITICAL: This project uses OpenTofu (tofu), NOT Terraform!
# All "tf-*" commands below use "tofu" internally, not "terraform".
# NEVER run "terraform" commands directly - use these just commands or "tofu" directly.

set dotenv-load := true
# Use mise exec to ensure all commands run with mise tools available
set shell := ["mise", "exec", "--", "bash", "-euo", "pipefail", "-c"]

# Default recipe: show help
default:
    @just --list --unsorted

# ============================================================================
# SETUP
# ============================================================================

# Install all tools and dependencies
setup:
    @just _ensure-mise
    @just _setup-terraform
    @just _setup-linters
    @echo ""
    @echo "✓ Setup complete!"
    @echo ""
    @echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    @echo "NOTE: Additional tools for full linting support:"
    @echo ""
    @echo "  • shellcheck & shfmt - Shell script linting"
    @echo "    Install: mise install  (managed via mise.toml)"
    @echo ""
    @echo "  • hadolint - Dockerfile linter"
    @echo "    Install: brew install hadolint"
    @echo ""
    @echo "These are optional but recommended for complete linting."
    @echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    @echo ""

# Clean all generated files and caches
clean:
    rm -rf .venv/
    rm -rf .terraform.d/
    find . -type d -name ".terraform" -exec rm -rf {} + 2>/dev/null || true
    find . -type d -name "__pycache__" -exec rm -rf {} + 2>/dev/null || true
    find . -type d -name "*.egg-info" -exec rm -rf {} + 2>/dev/null || true
    find . -type f -name "*.tfplan" -delete 2>/dev/null || true
    @echo "Cleaning non-whitelisted markdown files..."
    @find . -type f -name "*.md" ! -path "./.git/*" | while IFS= read -r f; do if git check-ignore -q "$f" 2>/dev/null; then rm -f "$f"; fi; done
    @echo "✓ Cleaned"

# ============================================================================
# DEVELOPMENT
# ============================================================================

# Run all linting checks
lint: _auto-setup lint-tofu lint-shell lint-yaml lint-docker lint-helm lint-python
    @echo "✓ All linting passed"

# Auto-fix all linting issues where possible
lint-fix: _auto-setup lint-fix-tofu lint-fix-shell lint-fix-yaml lint-fix-python
    @echo "✓ All auto-fixes applied"

# Lint OpenTofu/Terraform files
lint-tofu: _auto-setup
    @echo "→ Linting Terraform/OpenTofu..."
    @mkdir -p .terraform.d/plugin-cache
    tofu fmt -check -recursive terraform/

# Auto-fix OpenTofu/Terraform formatting
lint-fix-tofu: _auto-setup
    @echo "→ Formatting Terraform/OpenTofu..."
    @mkdir -p .terraform.d/plugin-cache
    tofu fmt -recursive terraform/

# Lint shell scripts
lint-shell: _auto-setup
    @echo "→ Linting shell scripts..."
    @if command -v shellcheck >/dev/null 2>&1; then \
        shellcheck scripts/bootstrap/*.sh scripts/hooks/*.sh; \
        shellcheck -x terraform/modules/eks/user-data-*.sh.tpl terraform/modules/gpu/user-data-*.sh.tpl 2>/dev/null || true; \
    else \
        echo "  ❌ ERROR: shellcheck not found."; \
        echo "  Install via mise: mise install shellcheck"; \
        echo "  Or system: brew install shellcheck"; \
        exit 1; \
    fi

# Auto-fix shell script formatting
lint-fix-shell: _auto-setup
    @echo "→ Formatting shell scripts..."
    @if command -v shfmt >/dev/null 2>&1; then \
        shfmt -w scripts/bootstrap/*.sh scripts/hooks/*.sh 2>/dev/null || true; \
    else \
        echo "  ❌ ERROR: shfmt not found."; \
        echo "  Install via mise: mise install shfmt"; \
        echo "  Or system: brew install shfmt"; \
        exit 1; \
    fi

# Lint YAML files (Kubernetes, Helm, workflows)
lint-yaml: _auto-setup
    @echo "→ Linting YAML files..."
    @if [ -f ".venv/bin/yamllint" ]; then \
        .venv/bin/yamllint kubernetes/ helm/ .github/; \
    elif command -v yamllint >/dev/null 2>&1; then \
        yamllint kubernetes/ helm/ .github/; \
    else \
        echo "  ❌ ERROR: yamllint not found in project venv or system."; \
        echo "  Run: just setup"; \
        exit 1; \
    fi

# Auto-fix YAML formatting (limited - yamllint doesn't auto-fix much)
lint-fix-yaml: _auto-setup
    @echo "→ Checking YAML files..."
    @if [ -f ".venv/bin/yamllint" ]; then \
        .venv/bin/yamllint kubernetes/ helm/ .github/ || true; \
    elif command -v yamllint >/dev/null 2>&1; then \
        yamllint kubernetes/ helm/ .github/ || true; \
    else \
        echo "  (yamllint not installed, skipping)"; \
    fi

# Lint Dockerfiles
lint-docker: _auto-setup
    @echo "→ Linting Dockerfiles..."
    @if command -v hadolint >/dev/null 2>&1; then \
        for f in docker/*/Dockerfile; do [ -f "$$f" ] && hadolint "$$f" || true; done; \
    else \
        echo "  ❌ ERROR: hadolint not found."; \
        echo "  Install: brew install hadolint"; \
        echo "  Or: https://github.com/hadolint/hadolint#install"; \
        echo "  (hadolint cannot be installed project-locally)"; \
        exit 1; \
    fi

# Lint Helm charts
lint-helm: _auto-setup
    @echo "→ Checking Helm values files..."
    @echo "  Note: helm/ contains values files for external OCI charts (not full charts)"
    @echo "  YAML syntax is validated by 'just lint-yaml'"
    @if command -v helm >/dev/null 2>&1; then \
        echo "  ✓ helm installed - values files can be used with: helm install --values"; \
    else \
        echo "  ⚠️  helm not installed (optional for linting)"; \
    fi

# Lint Python code (when python code exists)
lint-python: _auto-setup
    @echo "→ Linting Python code..."
    @if [ -d "python/" ]; then \
        if [ -f ".venv/bin/ruff" ]; then \
            (cd python/ && ../.venv/bin/ruff check .); \
            (cd python/ && ../.venv/bin/ruff format --check .); \
            if [ -f "../.venv/bin/mypy" ]; then \
                (cd python/ && ../.venv/bin/mypy . || true); \
            fi; \
        elif command -v ruff >/dev/null 2>&1; then \
            (cd python/ && ruff check .); \
            (cd python/ && ruff format --check .); \
            if command -v mypy >/dev/null 2>&1; then \
                (cd python/ && mypy . || true); \
            fi; \
        else \
            echo "  ❌ ERROR: ruff not found in project venv or system."; \
            echo "  Run: just setup"; \
            exit 1; \
        fi; \
    else \
        echo "  (no Python code yet)"; \
    fi

# Auto-fix Python formatting
lint-fix-python: _auto-setup
    @echo "→ Formatting Python code..."
    @if [ -d "python/" ]; then \
        if [ -f ".venv/bin/ruff" ]; then \
            (cd python/ && ../.venv/bin/ruff check --fix .); \
            (cd python/ && ../.venv/bin/ruff format .); \
        elif command -v ruff >/dev/null 2>&1; then \
            (cd python/ && ruff check --fix .); \
            (cd python/ && ruff format .); \
        else \
            echo "  ❌ ERROR: ruff not found in project venv or system."; \
            echo "  Run: just setup"; \
            exit 1; \
        fi; \
    else \
        echo "  (no Python code yet)"; \
    fi

# Lint Packer templates
lint-packer:
    @echo "→ Validating Packer templates..."
    @if command -v packer >/dev/null 2>&1; then \
        find ami/ -name "*.pkr.hcl" -exec packer validate {} \; || true; \
    else \
        echo "  ⚠️  packer not installed. Skipping..."; \
    fi

# ============================================================================
# DEPLOYMENT
# ============================================================================

# Full deployment: infrastructure + kubernetes + helm + docker images
deploy env registry="": _auto-setup
    #!/usr/bin/env bash
    set -euo pipefail
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "🚀 FULL DEPLOYMENT - {{env}} environment"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "This will:"
    echo "  1. Initialize and deploy Terraform infrastructure"
    echo "  2. Configure kubectl access to the cluster"
    echo "  3. Deploy Kubernetes base resources (namespaces, NVIDIA plugin)"
    echo "  4. Install Helm charts (ARC controller and runner sets)"
    if [ -n "{{registry}}" ]; then echo "  5. Build and push Docker images to {{registry}}"; fi
    echo ""
    read -p "Continue? [y/N] " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "❌ Deployment cancelled"
        exit 1
    fi
    echo ""
    just _deploy-infrastructure {{env}}
    just _deploy-kubernetes {{env}}
    just _deploy-helm {{env}}
    if [ -n "{{registry}}" ]; then just _deploy-docker {{registry}}; fi
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "✅ DEPLOYMENT COMPLETE - {{env}}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "Cluster info:"
    kubectl cluster-info
    echo ""
    echo "Runner pods:"
    kubectl get pods -n arc-runners

# Deploy without confirmation prompt (for CI/CD)
deploy-noninteractive env registry="": _auto-setup
    @echo "🚀 Starting deployment to {{env}}..."
    @just _deploy-infrastructure {{env}}
    @just _deploy-kubernetes {{env}}
    @just _deploy-helm {{env}}
    @if [ -n "{{registry}}" ]; then just _deploy-docker {{registry}}; fi
    @echo "✅ Deployment complete"

# Destroy entire environment (with confirmation)
destroy env: _auto-setup
    #!/usr/bin/env bash
    set -euo pipefail
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "⚠️  DESTROY ENVIRONMENT - {{env}}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "This will PERMANENTLY DELETE:"
    echo "  - EKS Cluster: pytorch-arc-{{env}}"
    echo "  - VPC and all networking"
    echo "  - All node groups"
    echo "  - All Kubernetes resources"
    echo "  - All Helm releases"
    echo ""
    echo "Type the environment name to confirm: {{env}}"
    read -p "> " confirm
    if [ "$confirm" != "{{env}}" ]; then
        echo "❌ Confirmation failed"
        exit 1
    fi
    echo ""
    echo "Uninstalling Helm releases..."
    helm uninstall arc-gpu-runner-set -n arc-runners 2>/dev/null || true
    helm uninstall arc-runner-set -n arc-runners 2>/dev/null || true
    helm uninstall arc -n arc-systems 2>/dev/null || true
    echo ""
    echo "Deleting Kubernetes resources..."
    kubectl delete -k kubernetes/overlays/{{env}}/ || true
    echo ""
    echo "Destroying Terraform infrastructure..."
    cd terraform/environments/{{env}} && tofu destroy -auto-approve
    echo ""
    echo "✅ Environment {{env}} destroyed"

# ============================================================================
# TERRAFORM / OPENTOFU
# ⚠️ CRITICAL: These commands use "tofu" (OpenTofu), NOT "terraform"!
# NEVER run "terraform" commands on this project - it will corrupt the state!
# ============================================================================

# Initialize tofu for an environment
tf-init env: _auto-setup
    cd terraform/environments/{{env}} && tofu init

# Plan tofu changes
tf-plan env: _auto-setup
    cd terraform/environments/{{env}} && tofu plan -out=tfplan

# Apply tofu changes
tf-apply env: _auto-setup
    cd terraform/environments/{{env}} && tofu apply tfplan

# Destroy tofu resources (use with caution!)
tf-destroy env: _auto-setup
    cd terraform/environments/{{env}} && tofu destroy

# Validate tofu configuration
tf-validate: _auto-setup
    tofu fmt -check -recursive terraform/
    @for dir in terraform/environments/*/; do echo "Validating $dir..."; (cd "$dir" && tofu init -backend=false && tofu validate); done

# ============================================================================
# DOCKER
# ============================================================================

# Build a docker image
docker-build image tag="latest":
    docker build -t {{image}}:{{tag}} -f docker/{{image}}/Dockerfile docker/{{image}}/

# Build all docker images
docker-build-all:
    @for dir in docker/*/; do name=$$(basename "$dir"); echo "Building $name..."; just docker-build "$name"; done

# Push docker image to registry (provide full registry path)
docker-push image tag="latest":
    docker push {{image}}:{{tag}}

# ============================================================================
# KUBERNETES
# ============================================================================

# Apply kubernetes manifests for an environment
k8s-apply env:
    kubectl apply -k kubernetes/overlays/{{env}}/

# Delete kubernetes resources for an environment
k8s-delete env:
    kubectl delete -k kubernetes/overlays/{{env}}/

# Show diff of what would be applied
k8s-diff env:
    kubectl diff -k kubernetes/overlays/{{env}}/ || true

# Validate kubernetes manifests
k8s-validate:
    #!/usr/bin/env bash
    set -euo pipefail
    for dir in kubernetes/overlays/*/; do
        env=$(basename "$dir")
        echo "Validating $env..."
        kubectl apply --dry-run=server -k "$dir"
    done

# ============================================================================
# HELM
# ============================================================================

# Install/upgrade ARC controller
helm-install-arc env namespace="arc-systems":
    helm upgrade --install arc \
        --namespace {{namespace}} \
        --create-namespace \
        -f helm/arc/values.yaml \
        -f helm/arc/values-{{env}}.yaml \
        oci://ghcr.io/actions/actions-runner-controller-charts/gha-runner-scale-set-controller

# Install/upgrade CPU runner scale set
helm-install-runners env namespace="arc-runners":
    helm upgrade --install arc-runner-set \
        --namespace {{namespace}} \
        --create-namespace \
        -f helm/arc-runners/values.yaml \
        -f helm/arc-runners/values-{{env}}.yaml \
        oci://ghcr.io/actions/actions-runner-controller-charts/gha-runner-scale-set

# Install/upgrade GPU runner scale set
helm-install-gpu-runners env namespace="arc-runners":
    helm upgrade --install arc-gpu-runner-set \
        --namespace {{namespace}} \
        --create-namespace \
        -f helm/arc-gpu-runners/values.yaml \
        -f helm/arc-gpu-runners/values-{{env}}.yaml \
        oci://ghcr.io/actions/actions-runner-controller-charts/gha-runner-scale-set

# ============================================================================
# AMI
# ============================================================================

# Build an AMI using Packer
ami-build name:
    cd ami/{{name}} && packer build .

# Validate Packer templates
ami-validate:
    @command -v packer > /dev/null || { echo "❌ ERROR: packer not found. Install: mise install packer"; exit 1; }
    @for dir in ami/*/; do echo "Validating $dir..."; (cd "$dir" && packer init . > /dev/null && packer validate .); done

# ============================================================================
# CI HELPERS
# ============================================================================

# Run all static validation (linting + Terraform validation)
validate: lint tf-validate ami-validate k8s-validate
    @echo "✓ All validation passed"

# Run all checks (for CI) - alias for validate
ci-check: validate
    @echo "✓ All CI checks passed"

# ============================================================================
# PRIVATE RECIPES (not shown in --list)
# ============================================================================

# Automatically run setup if needed (idempotent, fast when already done)
_auto-setup:
    @just _ensure-mise
    @just _setup-terraform
    @just _setup-linters

_ensure-mise:
    @command -v mise > /dev/null || { echo "❌ mise not found. Install: https://mise.jdx.dev"; exit 1; }
    @mise install --quiet 2>/dev/null || true

_setup-terraform:
    @if [ ! -d .terraform.d/plugin-cache ]; then \
        mkdir -p .terraform.d/plugin-cache; \
        echo "✓ OpenTofu/Terraform cache created"; \
    fi

_setup-linters:
    @if [ ! -d .venv ] || [ ! -f .venv/bin/yamllint ]; then \
        echo "→ Setting up Python linters (first time only)..."; \
        command -v uv > /dev/null || { echo "❌ ERROR: 'uv' not found. Install: https://docs.astral.sh/uv/"; exit 1; }; \
        uv venv .venv --python 3.12 --quiet; \
        uv pip install --quiet yamllint ruff mypy; \
        echo "✓ Python linters installed in .venv/"; \
    fi

# Deploy infrastructure (Terraform)
_deploy-infrastructure env:
    @echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    @echo "📦 STEP 1: Infrastructure (Terraform/OpenTofu)"
    @echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    @echo "Initializing Terraform..."
    @cd terraform/environments/{{env}} && tofu init
    @echo ""
    @echo "Planning infrastructure changes..."
    @cd terraform/environments/{{env}} && tofu plan -out=tfplan
    @echo ""
    @echo "Applying infrastructure..."
    @cd terraform/environments/{{env}} && tofu apply tfplan
    @echo ""
    @echo "Updating kubeconfig..."
    @aws eks update-kubeconfig --name pytorch-arc-{{env}} --region $$(cd terraform/environments/{{env}} && tofu output -raw aws_region 2>/dev/null || echo "us-west-2")
    @echo "✅ Infrastructure deployed"

# Deploy Kubernetes resources
_deploy-kubernetes env:
    @echo ""
    @echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    @echo "☸️  STEP 2: Kubernetes Resources"
    @echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    @echo "Applying Kubernetes manifests for {{env}}..."
    @kubectl apply -k kubernetes/overlays/{{env}}/
    @echo ""
    @echo "Waiting for NVIDIA device plugin to be ready..."
    @kubectl rollout status daemonset/nvidia-device-plugin-daemonset -n kube-system --timeout=5m || true
    @echo "✅ Kubernetes resources deployed"

# Deploy Helm charts
_deploy-helm env:
    @echo ""
    @echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    @echo "⎈  STEP 3: Helm Charts"
    @echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    @echo "Installing ARC controller..."
    @helm upgrade --install arc \
        --namespace arc-systems \
        --create-namespace \
        -f helm/arc/values.yaml \
        -f helm/arc/values-{{env}}.yaml \
        oci://ghcr.io/actions/actions-runner-controller-charts/gha-runner-scale-set-controller \
        --wait
    @echo ""
    @echo "Installing CPU runner scale set..."
    @helm upgrade --install arc-runner-set \
        --namespace arc-runners \
        --create-namespace \
        -f helm/arc-runners/values.yaml \
        -f helm/arc-runners/values-{{env}}.yaml \
        oci://ghcr.io/actions/actions-runner-controller-charts/gha-runner-scale-set \
        --wait
    @echo ""
    @echo "Installing GPU runner scale set..."
    @helm upgrade --install arc-gpu-runner-set \
        --namespace arc-runners \
        --create-namespace \
        -f helm/arc-gpu-runners/values.yaml \
        -f helm/arc-gpu-runners/values-{{env}}.yaml \
        oci://ghcr.io/actions/actions-runner-controller-charts/gha-runner-scale-set \
        --wait
    @echo "✅ Helm charts deployed"

# Build and push Docker images
_deploy-docker registry:
    @echo ""
    @echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    @echo "🐳 STEP 4: Docker Images"
    @echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    @echo "Building and pushing Docker images to {{registry}}..."
    @for dir in docker/*/; do \
        name=$$(basename "$dir"); \
        echo ""; \
        echo "Building $name..."; \
        docker build -t {{registry}}/$name:latest -f "$dir/Dockerfile" "$dir"; \
        echo "Pushing $name..."; \
        docker push {{registry}}/$name:latest; \
    done
    @echo "✅ Docker images built and pushed"