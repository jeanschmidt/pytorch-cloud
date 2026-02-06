# Helm "Linting" Explanation

## Why No Helm Chart Linting?

The `helm/` directory structure in this project is **not standard Helm charts**. Here's why:

## What We Have

```
helm/
├── arc/
│   ├── values.yaml           # Base values
│   ├── values-staging.yaml   # Staging overrides
│   └── values-production.yaml # Production overrides
├── arc-runners/
│   └── values*.yaml
└── arc-gpu-runners/
    └── values*.yaml
```

**These are values files for EXTERNAL OCI charts**, not self-contained charts.

## Standard Helm Chart Structure (We Don't Have This)

A standard Helm chart would look like:

```
my-chart/
├── Chart.yaml       # ❌ We don't have this
├── values.yaml
├── templates/       # ❌ We don't have this
│   ├── deployment.yaml
│   └── service.yaml
└── charts/          # ❌ We don't have this
```

## What We're Actually Doing

We're using **GitHub's official OCI charts** and providing custom values:

```bash
# We install from GitHub's OCI registry
helm install arc \
  oci://ghcr.io/actions/actions-runner-controller-charts/gha-runner-scale-set-controller \
  --values helm/arc/values.yaml \
  --values helm/arc/values-staging.yaml

# NOT from local charts
helm install ./helm/arc/  # ❌ This won't work - no Chart.yaml
```

## Why This Approach?

1. **Use Official Charts**: GitHub maintains the ARC charts, we just customize values
2. **No Template Duplication**: We don't copy/maintain chart templates
3. **Easy Updates**: `helm upgrade` pulls latest chart from OCI registry
4. **Values Only**: We only maintain configuration, not chart logic

## Linting Strategy

Since we only have values files:

1. **YAML Syntax**: Validated by `yamllint` (in `just lint-yaml`)
2. **Helm Compatibility**: Validated when you actually run `helm install`
3. **No Chart.yaml**: Expected - these aren't standalone charts

## The `lint-helm` Command

```bash
just lint-helm
```

Output:
```
→ Checking Helm values files...
  Note: helm/ contains values files for external OCI charts (not full charts)
  YAML syntax is validated by 'just lint-yaml'
  ✓ helm installed - values files can be used with: helm install --values
```

This command:
- ✅ Checks if helm is installed (for deployment)
- ✅ Explains the structure
- ✅ Points to yamllint for YAML validation
- ❌ Does NOT try to `helm lint` (would fail - no Chart.yaml)

## Validation Happens at Deploy Time

The real validation happens when you deploy:

```bash
# Staging deployment
just helm-install-arc staging

# This runs:
helm install arc \
  oci://ghcr.io/actions/.../gha-runner-scale-set-controller \
  --values helm/arc/values.yaml \
  --values helm/arc/values-staging.yaml
```

If the values are incompatible with the chart schema, `helm install` will fail with a clear error.

## Summary

| What | Where | How Validated |
|------|-------|---------------|
| YAML syntax | `helm/*/values*.yaml` | `yamllint` (in `just lint-yaml`) |
| Chart templates | OCI registry (GitHub) | Maintained by GitHub |
| Values compatibility | Deploy time | `helm install` validates against chart schema |

**This is a best practice for using external charts** - you don't maintain the chart templates, just the values customization.

## Alternative: If You Want Full Chart Linting

If you later create custom charts (not recommended for ARC), structure them like:

```
helm/
├── my-custom-chart/         # New custom chart
│   ├── Chart.yaml           # Required
│   ├── values.yaml
│   └── templates/           # Required
│       └── deployment.yaml
└── arc/                     # Keep existing values-only dirs
    └── values.yaml
```

Then you could lint the custom chart:
```bash
helm lint helm/my-custom-chart/
```

But for ARC, using GitHub's official OCI charts is the right approach.
