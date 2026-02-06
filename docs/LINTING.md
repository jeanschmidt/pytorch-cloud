# Linting Guide

This project uses comprehensive linting for all code types to maintain quality and consistency.

## Quick Start

```bash
# Run all linters
just lint

# Auto-fix all fixable issues
just lint-fix

# Run specific linter
just lint-tofu
just lint-shell
just lint-yaml
just lint-docker
just lint-helm
just lint-python
```

## Linting Tools by File Type

### OpenTofu/Terraform (`.tf` files)

**Tool**: `tofu fmt`
**Config**: Built-in formatter
**Command**: `just lint-tofu` or `just lint-fix-tofu`

Checks:
- ✅ Indentation (2 spaces)
- ✅ Alignment of `=` in blocks
- ✅ Consistent formatting

### Shell Scripts (`.sh` files)

**Tool**: `shellcheck` + `shfmt`
**Config**: `.shellcheckrc`
**Command**: `just lint-shell` or `just lint-fix-shell`

Checks:
- ✅ Common shell scripting errors
- ✅ Quoting issues
- ✅ Unused variables
- ✅ Consistent formatting (2 spaces, bash style)

Files checked:
- `scripts/**/*.sh`
- `terraform/modules/*/user-data-*.sh.tpl`

### YAML Files (Kubernetes, Helm, Workflows)

**Tool**: `yamllint`
**Config**: `.yamllint`
**Command**: `just lint-yaml`

Checks:
- ✅ Syntax validity
- ✅ Indentation (2 spaces)
- ✅ Line length (120 chars max, warning)
- ✅ Trailing spaces
- ✅ Document structure

Files checked:
- `kubernetes/**/*.yaml`
- `helm/**/*.yaml`
- `.github/**/*.yaml`

### Dockerfiles

**Tool**: `hadolint`
**Config**: `.hadolint.yaml`
**Command**: `just lint-docker`

Checks:
- ✅ Best practices (layer caching, image size)
- ✅ Security issues
- ✅ Deprecated instructions
- ✅ Order of instructions

Files checked:
- `docker/*/Dockerfile`

### Helm Charts

**Tool**: `helm lint`
**Config**: Built-in validation
**Command**: `just lint-helm`

Checks:
- ✅ Chart.yaml validity
- ✅ Template syntax
- ✅ Values schema
- ✅ Required fields

Charts checked:
- `helm/arc/`
- `helm/arc-runners/`
- `helm/arc-gpu-runners/`

### Python Code

**Tool**: `ruff` (linter + formatter) + `mypy` (type checker)
**Config**: `pyproject.toml`
**Command**: `just lint-python` or `just lint-fix-python`

Checks:
- ✅ PEP 8 style (100 char line length)
- ✅ Import sorting (isort)
- ✅ Common bugs (flake8-bugbear)
- ✅ Type hints (mypy)
- ✅ Code modernization (pyupgrade)

Files checked:
- `python/**/*.py` (when created)

### Packer Templates (`.pkr.hcl` files)

**Tool**: `packer validate`
**Config**: Built-in validation
**Command**: `just lint-packer`

Checks:
- ✅ HCL syntax
- ✅ Required fields
- ✅ Plugin availability

Files checked:
- `ami/**/*.pkr.hcl`

## Configuration Files

| File | Purpose |
|------|---------|
| `.yamllint` | YAML linting rules |
| `.hadolint.yaml` | Dockerfile linting rules |
| `.shellcheckrc` | Shell script linting rules |
| `pyproject.toml` | Python linting rules (ruff, mypy) |

## CI Integration

All linting runs automatically in CI:

```yaml
# .github/workflows/ci.yaml
- name: Run CI checks
  run: just ci-check  # Runs all linters
```

Pull requests must pass all linting checks before merging.

## Pre-commit Hooks (Optional)

You can set up pre-commit hooks to run linters before committing:

```bash
# Create .git/hooks/pre-commit
cat > .git/hooks/pre-commit << 'EOF'
#!/bin/bash
set -e
just lint
EOF

chmod +x .git/hooks/pre-commit
```

## Disabling Specific Rules

### Shell Scripts

Add inline comments:

```bash
# shellcheck disable=SC2086
echo $UNQUOTED_VAR
```

### YAML

Add inline comments:

```yaml
# yamllint disable-line rule:line-length
very_long_line: "..."
```

### Dockerfiles

Add inline comments:

```dockerfile
# hadolint ignore=DL3008
RUN apt-get install -y some-package
```

### Python

Add inline comments:

```python
import something  # noqa: F401
```

## Auto-fix Capabilities

| Tool | Auto-fix | Command |
|------|----------|---------|
| tofu fmt | ✅ Yes | `just lint-fix-tofu` |
| shfmt | ✅ Yes | `just lint-fix-shell` |
| yamllint | ❌ No | Manual fix required |
| hadolint | ❌ No | Manual fix required |
| helm lint | ❌ No | Manual fix required |
| ruff | ✅ Yes | `just lint-fix-python` |
| mypy | ❌ No | Manual fix required |
| packer | ❌ No | Manual fix required |

## Common Issues

### Line Length

Most linters enforce line length limits:
- **Python**: 100 chars
- **YAML**: 120 chars (warning)
- **Shell**: No limit (but use good judgment)

### Indentation

All files use **2 spaces** (except Python which uses 4):
- YAML: 2 spaces
- Shell: 2 spaces
- Terraform: 2 spaces
- Helm: 2 spaces
- Python: 4 spaces (ruff default)

### Trailing Whitespace

All linters complain about trailing whitespace. Use your editor's auto-trim feature.

### YAML Quotes

yamllint prefers consistent quoting. Use quotes when:
- String contains special characters
- String looks like a number/boolean but should be a string
- Otherwise, quotes are optional

## IDE Integration

### VS Code

Install extensions:
- **Terraform**: HashiCorp Terraform
- **YAML**: Red Hat YAML
- **Shell**: shellcheck
- **Docker**: Microsoft Docker
- **Python**: Ruff, Mypy

### JetBrains (PyCharm, IntelliJ)

Enable external tools:
- Settings → Tools → External Tools
- Add commands for `just lint-*`

### Neovim/Vim

Use ALE or null-ls with configured linters.

## Skipping Linting (Emergency Only)

If you absolutely must skip linting (not recommended):

```bash
# Skip specific linter
just lint-tofu lint-shell lint-yaml  # Skip others

# Push without CI (requires permissions)
git push --no-verify  # NEVER DO THIS
```

## Getting Help

If linting errors are unclear:

1. Read the error message carefully (most are self-explanatory)
2. Check the tool's documentation:
   - shellcheck: https://www.shellcheck.net/
   - yamllint: https://yamllint.readthedocs.io/
   - hadolint: https://github.com/hadolint/hadolint
   - ruff: https://docs.astral.sh/ruff/
3. Run the specific linter for detailed output:
   ```bash
   shellcheck scripts/bootstrap/eks-base-bootstrap.sh
   yamllint kubernetes/base/nvidia-device-plugin.yaml
   ```

## Summary

✅ **Run `just lint` before committing**
✅ **Run `just lint-fix` to auto-fix when possible**
✅ **All PRs must pass linting**
✅ **Don't disable rules without good reason**
✅ **Keep code clean and consistent**
