# CLAUDE.md - Instructions for Claude AI

## 💥 Staging Environment: Break Things Freely
**Staging/canary**: No need to drain nodes, wait for pods, or avoid disruption. This environment is for testing infrastructure changes. Kill nodes, break workflows, experiment freely - no production workloads here.

## ⚠️ Version Management
**CRITICAL**: (1) Latest K8s ≥1.35, Amazon Linux 2 is deprecated (use AL2023). Before proposing version changes/migrations or blaming version issues, research actual latest versions. If you can't verify, STOP and ask user. (2) NEVER update ANY version without asking user first. (3) **STOP IMMEDIATELY before changing ANY version** (packages, dependencies, EKS, K8s, AWS services, Python, Node, build tools, containers, AMIs, etc.) - NO updates/upgrades/downgrades/changes without explicit user approval.

## ⚠️ CRITICAL RULE #1: NEVER USE TERRAFORM

**THIS PROJECT USES OPENTOFU (tofu), NOT TERRAFORM!**

### What You MUST Do:

1. **NEVER run or suggest `terraform` commands**
2. **NEVER configure tools to install `terraform`**
3. **ALWAYS use `opentofu` in configuration files**
4. **ALWAYS use `tofu` commands** or `just` commands
5. **ALWAYS warn users** if they mention terraform
6. **NEVER use terraform** even if explicitly asked

### Examples - Commands:

**❌ NEVER DO THIS:**
```bash
terraform init
terraform plan
terraform apply
```

**✅ ALWAYS DO THIS:**
```bash
tofu init
tofu plan
tofu apply

# OR use just commands (preferred):
just tf-init staging
just tf-plan staging
just tf-apply staging
```

### Examples - Configuration Files:

**❌ WRONG - mise.toml:**
```toml
[tools]
terraform = "1.7"  # Installs terraform, NOT tofu!
```

**✅ CORRECT - mise.toml:**
```toml
[tools]
opentofu = "1.7"  # Installs tofu binary
```

**Configuration files to check:**
- `mise.toml` → Use `opentofu`, NOT `terraform`
- `requirements.txt` → Use `opentofu`, NOT `terraform`
- `package.json` → Use `opentofu` packages, NOT `terraform`
- `.github/workflows/*.yaml` → Install `opentofu`, NOT `terraform`
- `Dockerfile` → Install `tofu`, NOT `terraform`

### Why This Matters:

- **State File Corruption**: Mixing terraform and tofu will corrupt the infrastructure state
- **Wrong Tool Available**: Installing terraform makes the wrong command available
- **Data Loss Risk**: Corrupted state can lead to infrastructure destruction
- **No Recovery**: State corruption is very difficult to fix

### What is OpenTofu?

OpenTofu is the open-source fork of Terraform:
- 100% syntax compatible
- Drop-in replacement for Terraform
- Community-driven, Linux Foundation project
- Uses same .tf files but different state format

### If User Mentions Terraform:

**Response Template:**
```
⚠️ IMPORTANT: This project uses OpenTofu (tofu), not Terraform.

Please use:
- `tofu <command>` instead of `terraform <command>`
- OR `just tf-<command>` which uses tofu internally

Running terraform commands will corrupt the state file.
See CRITICAL-USE-TOFU.md for details.
```

## Other Important Guidelines

### Code Separation

- NEVER embed bash scripts in Terraform/OpenTofu files
- ALWAYS keep scripts in `scripts/` directory
- Use `templatefile()` to reference external files
- See AGENTS.md section 4 for details

### Project Structure

This project strictly separates:
- **terraform/** - OpenTofu/Terraform HCL files ONLY
- **scripts/** - Bash scripts ONLY
- **kubernetes/** - YAML manifests ONLY
- **docker/** - Dockerfiles ONLY
- **helm/** - Helm values ONLY

Do NOT mix file types!

### Build System

- ALWAYS use `just` commands, not direct tool invocation
- Tool versions managed by `mise`
- See justfile for available commands

### GitHub ARC

- Uses NEW GitHub ARC (v0.8.0+), not old Summerwind ARC
- OCI chart: `oci://ghcr.io/actions/actions-runner-controller-charts/`
- See FIXES-APPLIED.md for API details

## Quick Reference

### Common Commands:

```bash
# Setup
just setup

# OpenTofu (NOT terraform!)
just tf-init staging
just tf-plan staging
just tf-apply staging

# Kubernetes
just k8s-apply staging

# Docker (optional - using official ghcr.io image by default)
just docker-build runner-base

# Helm (GitHub ARC)
just helm-install-arc staging
just helm-install-runners staging
just helm-install-gpu-runners staging
```

### Documentation:

- `CRITICAL-USE-TOFU.md` - OpenTofu vs Terraform
- `AGENTS.md` - Complete AI assistant guidelines
- `FIXES-APPLIED.md` - Recent fixes and changes
- `FINAL-REVIEW.md` - Integration verification
- `docs/QUICKSTART.md` - Deployment guide

## Remember:

1. 🚫 **NEVER use terraform**
2. ✅ **ALWAYS use tofu** or just commands
3. 📁 **NEVER mix code types** in same directory
4. 🔧 **ALWAYS use just commands** over direct tool calls
5. 📖 **READ documentation** before making changes

---

**Most Important**: This project uses OpenTofu. Using terraform will break things!

## Verification Checklist for AI Assistants

Before making changes or suggesting commands, verify:

- [ ] **Commands**: Am I suggesting `tofu` or `just tf-*`, NOT `terraform`?
- [ ] **Configuration**: If editing mise.toml, am I using `opentofu`, NOT `terraform`?
- [ ] **CI/CD**: If editing workflows, am I installing `opentofu`, NOT `terraform`?
- [ ] **Dependencies**: If editing package files, am I using `opentofu` packages?
- [ ] **Code**: Are all shell commands using `tofu`, NOT `terraform`?

**Red flags that should trigger re-checking:**
- User mentions "terraform" anywhere
- Editing `mise.toml` or other dependency files
- Creating CI/CD workflows
- Installing tools or dependencies
- Error messages mentioning "command not found: tofu"
