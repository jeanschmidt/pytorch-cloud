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
    @echo "Cleaning non-whitelisted markdown files..."
    @bash -c 'find . -type f -name "*.md" ! -path "./.git/*" | while IFS= read -r f; do \
        if git check-ignore -q "$f" 2>/dev/null; then \
            rm -f "$f"; \
        fi; \
    done'
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
lint-tofu:
    @echo "→ Linting Terraform/OpenTofu..."
    @mkdir -p .terraform.d/plugin-cache
    tofu fmt -check -recursive terraform/

# Auto-fix OpenTofu/Terraform formatting
lint-fix-tofu:
    @echo "→ Formatting Terraform/OpenTofu..."
    @mkdir -p .terraform.d/plugin-cache
    tofu fmt -recursive terraform/

# Lint shell scripts
lint-shell:
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
lint-fix-shell:
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
lint-yaml:
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
lint-fix-yaml:
    @echo "→ Checking YAML files..."
    @if [ -f ".venv/bin/yamllint" ]; then \
        .venv/bin/yamllint kubernetes/ helm/ .github/ || true; \
    elif command -v yamllint >/dev/null 2>&1; then \
        yamllint kubernetes/ helm/ .github/ || true; \
    else \
        echo "  (yamllint not installed, skipping)"; \
    fi

# Lint Dockerfiles
lint-docker:
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
lint-helm:
    @echo "→ Checking Helm values files..."
    @echo "  Note: helm/ contains values files for external OCI charts (not full charts)"
    @echo "  YAML syntax is validated by 'just lint-yaml'"
    @if command -v helm >/dev/null 2>&1; then \
        echo "  ✓ helm installed - values files can be used with: helm install --values"; \
    else \
        echo "  ⚠️  helm not installed (optional for linting)"; \
    fi

# Lint Python code (when python code exists)
lint-python:
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
lint-fix-python:
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
    @bash -c 'for dir in terraform/environments/*/; do \
        echo "Validating $dir..."; \
        (cd "$dir" && tofu init -backend=false && tofu validate); \
    done'

# ============================================================================
# DOCKER
# ============================================================================

# Build a docker image
docker-build image tag="latest":
    docker build -t {{image}}:{{tag}} -f docker/{{image}}/Dockerfile docker/{{image}}/

# Build all docker images
docker-build-all:
    @bash -c 'for dir in docker/*/; do \
        name=$$(basename "$dir"); \
        echo "Building $name..."; \
        just docker-build "$name"; \
    done'

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
    @bash -c 'for dir in kubernetes/overlays/*/; do \
        env=$$(basename "$dir"); \
        echo "Validating $env..."; \
        kubectl apply --dry-run=server -k "$dir"; \
    done'

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
    @bash -c 'for dir in ami/*/; do \
        echo "Validating $dir..."; \
        (cd "$dir" && packer validate .); \
    done'

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

_ensure-mise:
    @command -v mise > /dev/null || { echo "❌ mise not found. Install: https://mise.jdx.dev"; exit 1; }
    @mise install --quiet

_setup-terraform:
    mkdir -p .terraform.d/plugin-cache
    @echo "✓ OpenTofu/Terraform cache ready"
    @echo "⚠️  REMINDER: Use 'tofu' commands, not 'terraform'"

_setup-linters:
    @echo "→ Setting up project-local linting environment..."
    @echo ""
    @echo "Installing Python linters via uv (project-local)..."
    @command -v uv > /dev/null || { echo "❌ ERROR: 'uv' not found. Install: https://docs.astral.sh/uv/"; exit 1; }
    uv venv .venv --python 3.12
    uv pip install yamllint ruff mypy
    @echo ""
    @echo "✓ Python linters installed in .venv/"
    @echo ""
    @echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    @echo "NOTE: The following tools MUST be installed by you:"
    @echo ""
    @echo "  • shellcheck - Shell script linter"
    @echo "    Install: mise install shellcheck  (or: brew install shellcheck)"
    @echo ""
    @echo "  • shfmt - Shell script formatter"
    @echo "    Install: mise install shfmt  (or: brew install shfmt)"
    @echo ""
    @echo "  • hadolint - Dockerfile linter"
    @echo "    Install: brew install hadolint"
    @echo "    Or: https://github.com/hadolint/hadolint#install"
    @echo ""
    @echo "These tools cannot be installed project-locally."
    @echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    @echo ""
    @echo "Quick install (recommended):"
    @echo "  mise install  # Installs shellcheck + shfmt project-locally via mise"
    @echo "  brew install hadolint  # System install (no project-local option)"
    @echo ""