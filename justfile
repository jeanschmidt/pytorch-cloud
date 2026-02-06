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
    just _setup-linters
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

# Run all linting checks
lint: lint-tofu lint-shell lint-yaml lint-docker lint-helm lint-python
    @echo "✓ All linting passed"

# Auto-fix all linting issues where possible
lint-fix: lint-fix-tofu lint-fix-shell lint-fix-yaml lint-fix-python
    @echo "✓ All auto-fixes applied"

# Lint OpenTofu/Terraform files
lint-tofu: _ensure-mise
    @echo "→ Linting Terraform/OpenTofu..."
    tofu fmt -check -recursive terraform/

# Auto-fix OpenTofu/Terraform formatting
lint-fix-tofu: _ensure-mise
    @echo "→ Formatting Terraform/OpenTofu..."
    tofu fmt -recursive terraform/

# Lint shell scripts
lint-shell: _ensure-mise
    @echo "→ Linting shell scripts..."
    find scripts/ -type f -name "*.sh" -exec shellcheck {} +
    find terraform/modules/*/user-data-*.sh.tpl -type f -exec shellcheck -x {} + || true

# Auto-fix shell script formatting
lint-fix-shell: _ensure-mise
    @echo "→ Formatting shell scripts..."
    find scripts/ -type f -name "*.sh" -exec shfmt -w {} +

# Lint YAML files (Kubernetes, Helm, workflows)
lint-yaml: _ensure-mise
    @echo "→ Linting YAML files..."
    yamllint kubernetes/ helm/ .github/

# Auto-fix YAML formatting (limited - yamllint doesn't auto-fix much)
lint-fix-yaml: _ensure-mise
    @echo "→ Checking YAML files..."
    yamllint kubernetes/ helm/ .github/ || true

# Lint Dockerfiles
lint-docker: _ensure-mise
    @echo "→ Linting Dockerfiles..."
    find docker/ -name "Dockerfile" -exec hadolint {} +

# Lint Helm charts
lint-helm: _ensure-mise
    @echo "→ Linting Helm charts..."
    helm lint helm/arc/
    helm lint helm/arc-runners/
    helm lint helm/arc-gpu-runners/

# Lint Python code (when python code exists)
lint-python: _ensure-mise
    @echo "→ Linting Python code..."
    @if [ -d "python/" ]; then \
        cd python/ && ruff check .; \
        cd python/ && ruff format --check .; \
        cd python/ && mypy . || true; \
    else \
        echo "  (no Python code yet)"; \
    fi

# Auto-fix Python formatting
lint-fix-python: _ensure-mise
    @echo "→ Formatting Python code..."
    @if [ -d "python/" ]; then \
        cd python/ && ruff check --fix .; \
        cd python/ && ruff format .; \
    else \
        echo "  (no Python code yet)"; \
    fi

# Lint Packer templates
lint-packer: _ensure-mise
    @echo "→ Validating Packer templates..."
    find ami/ -name "*.pkr.hcl" -exec packer validate {} \; || true

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

_setup-linters:
    @echo "→ Installing linting tools..."
    @command -v yamllint > /dev/null || pip3 install --user yamllint
    @command -v hadolint > /dev/null || { \
        echo "  Installing hadolint..."; \
        if [[ "$$OSTYPE" == "darwin"* ]]; then \
            brew install hadolint 2>/dev/null || curl -sL https://github.com/hadolint/hadolint/releases/latest/download/hadolint-Darwin-x86_64 -o /usr/local/bin/hadolint && chmod +x /usr/local/bin/hadolint; \
        else \
            curl -sL https://github.com/hadolint/hadolint/releases/latest/download/hadolint-Linux-x86_64 -o /usr/local/bin/hadolint && chmod +x /usr/local/bin/hadolint; \
        fi \
    }
    @command -v ruff > /dev/null || pip3 install --user ruff
    @command -v mypy > /dev/null || pip3 install --user mypy
    @echo "✓ Linting tools ready"
