# Contributing to pytorch-cloud

Thank you for your interest in contributing to pytorch-cloud!

## Development Setup

1. **Install prerequisites:**
   - [mise](https://mise.jdx.dev/) - Tool version manager
   - [just](https://just.systems/) - Command runner
   - Docker
   - AWS credentials configured

2. **Set up the development environment:**
   ```bash
   just setup
   ```

3. **Verify your setup:**
   ```bash
   just ci-check
   ```

## Project Structure

This project follows strict separation of concerns:

- **terraform/** - Cloud-specific AWS infrastructure
- **kubernetes/** - Cloud-agnostic K8s manifests (kustomize)
- **docker/** - Cloud-agnostic container images
- **helm/** - Cloud-agnostic Helm values
- **scripts/** - Cloud-specific bash scripts
- **ami/** - Cloud-specific Packer templates

**Rule**: Never mix YAML, scripts, Python, and Terraform in the same directory.

## Making Changes

### OpenTofu Changes

1. Make your changes to modules or environments
2. Format: `just lint-fix`
3. Validate: `just tf-validate`
4. Test in staging:
   ```bash
   just tf-plan staging
   just tf-apply staging
   ```

### Docker Changes

1. Update Dockerfile in `docker/<image>/`
2. Build: `just docker-build <image>`
3. Test the image locally
4. Push to registry: `just docker-push <registry>/<image>:<tag>`

### Kubernetes Changes

1. Update manifests in `kubernetes/base/` or overlays
2. Validate: `just k8s-validate`
3. Test in staging: `just k8s-apply staging`
4. Verify with `kubectl get all -n arc-runners`

### Script Changes

1. Update scripts in `scripts/bootstrap/` or `scripts/hooks/`
2. Run shellcheck: `just lint`
3. Test the script in a dev environment

### AMI Changes

1. Update Packer template in `ami/<name>/`
2. Validate: `just ami-validate`
3. Build: `just ami-build <name>`

## Testing

### Local Testing

- **Terraform**: `just tf-plan staging`
- **Docker**: Build and run locally
- **Kubernetes**: Use `kubectl apply --dry-run=client`
- **Scripts**: Run shellcheck

### Staging Environment

Always test in staging before deploying to production:

```bash
# Deploy infrastructure
just tf-apply staging

# Apply K8s manifests
just k8s-apply staging

# Install ARC
just helm-install-arc staging
```

## Code Style

### OpenTofu
- Use `tofu fmt` (via `just lint-fix`)
- Follow module patterns in `terraform/modules/`
- Always include outputs and variables files

### Docker
- Use multi-stage builds when appropriate
- Minimize layer count
- Include `.dockerignore` files

### Kubernetes
- Use kustomize for environment variations
- Follow manifest organization in `base/`
- Include resource limits and requests

### Bash
- Start with `set -euo pipefail`
- Use shellcheck
- Include logging and error handling

## Commit Guidelines

- Write clear, descriptive commit messages
- Keep commits focused on a single change
- Reference issues when applicable

## Pull Request Process

1. Create a feature branch
2. Make your changes
3. Run `just ci-check` to verify
4. Test in staging environment
5. Submit PR with clear description
6. Address review feedback

## Secrets and Credentials

- **Never** commit secrets or credentials
- Use AWS Secrets Manager for sensitive data
- Use environment variables for configuration
- GitHub tokens should be provided via Helm `--set` flags

## Getting Help

- Check the [README.md](README.md) for overview
- See [AGENTS.md](AGENTS.md) for AI assistant guidelines
- Review existing code for patterns
- Open an issue for questions

## License

By contributing, you agree that your contributions will be licensed under the same license as the project.
