# justfile - Command runner for pytorch-cloud
# https://just.systems/

# ⚠️ CRITICAL: This project uses OpenTofu (tofu), NOT Terraform!
# All "tf-*" commands below use "tofu" internally, not "terraform".
# NEVER run "terraform" commands directly - use these just commands or "tofu" directly.

set dotenv-load := true
set shell := ["bash", "-euo", "pipefail", "-c"]

# Default recipe: show help
default:
    @just --list --unsorted

# ============================================================================
# SETUP
# ============================================================================

# Install all tools and dependencies
setup: _ensure-mise
    mise install
    just _setup-terraform
    @echo "✓ Setup complete"

# Clean all generated files and caches
clean:
    rm -rf .venv/
    rm -rf .terraform.d/
    find . -type d -name ".terraform" -exec rm -rf {} + 2>/dev/null || true
    find . -type d -name "__pycache__" -exec rm -rf {} + 2>/dev/null || true
    find . -type d -name "*.egg-info" -exec rm -rf {} + 2>/dev/null || true
    find . -type f -name "*.tfplan" -delete 2>/dev/null || true
    @echo "✓ Cleaned"

# ============================================================================
# DEVELOPMENT
# ============================================================================

# Run linting on all code
lint: _ensure-mise
    tofu fmt -check -recursive terraform/
    shellcheck scripts/*.sh || true
    yamllint kubernetes/ || true

# Auto-fix linting issues
lint-fix: _ensure-mise
    tofu fmt -recursive terraform/

# ============================================================================
# TERRAFORM / OPENTOFU
# ⚠️ CRITICAL: These commands use "tofu" (OpenTofu), NOT "terraform"!
# NEVER run "terraform" commands on this project - it will corrupt the state!
# ============================================================================

# Initialize tofu for an environment
tf-init env: _ensure-mise
    cd terraform/environments/{{env}} && tofu init

# Plan tofu changes
tf-plan env: _ensure-mise
    cd terraform/environments/{{env}} && tofu plan -out=tfplan

# Apply tofu changes
tf-apply env: _ensure-mise
    cd terraform/environments/{{env}} && tofu apply tfplan

# Destroy tofu resources (use with caution!)
tf-destroy env: _ensure-mise
    cd terraform/environments/{{env}} && tofu destroy

# Validate tofu configuration
tf-validate: _ensure-mise
    tofu fmt -check -recursive terraform/
    @for dir in terraform/environments/*/; do \
        echo "Validating $$dir..."; \
        (cd "$$dir" && tofu init -backend=false && tofu validate); \
    done

# ============================================================================
# DOCKER
# ============================================================================

# Build a docker image
docker-build image tag="latest":
    docker build -t {{image}}:{{tag}} -f docker/{{image}}/Dockerfile docker/{{image}}/

# Build all docker images
docker-build-all:
    @for dir in docker/*/; do \
        name=$$(basename "$$dir"); \
        echo "Building $$name..."; \
        just docker-build "$$name"; \
    done

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
    @for dir in kubernetes/overlays/*/; do \
        env=$$(basename "$$dir"); \
        echo "Validating $$env..."; \
        kubectl apply --dry-run=server -k "$$dir"; \
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
    @for dir in ami/*/; do \
        echo "Validating $$dir..."; \
        (cd "$$dir" && packer validate .); \
    done

# ============================================================================
# CI HELPERS
# ============================================================================

# Run all checks (for CI)
ci-check: lint tf-validate
    @echo "✓ All CI checks passed"

# ============================================================================
# PRIVATE RECIPES (not shown in --list)
# ============================================================================

_ensure-mise:
    @command -v mise > /dev/null || { echo "❌ mise not found. Install: https://mise.jdx.dev"; exit 1; }
    @mise install --quiet

_setup-terraform:
    mkdir -p .terraform.d/plugin-cache
    @echo "✓ OpenTofu/Terraform cache ready"
    @echo "⚠️  REMINDER: Use 'tofu' commands, not 'terraform'"
