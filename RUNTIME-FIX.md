# Runtime Issue Fix - Pod Crashing

## 💥 Staging Environment: Break Things Freely
**Staging/canary**: No need to drain nodes, wait for pods, or avoid disruption. This environment is for testing infrastructure changes. Kill nodes, break workflows, experiment freely - no production workloads here.

## 🔴 Issue Found During Deployment

**Error:**
```
exec: "/home/runner/run.sh": stat /home/runner/run.sh: no such file or directory
```

## Root Cause

**Two problems:**

1. **Wrong image used:** Justfile was overriding image with `--set template.spec.containers[0].image="${ECR_IMAGE}"` forcing use of custom ECR image instead of ghcr.io official image

2. **Wrong command:** Runner configs had `command: ["/home/runner/run.sh"]` which:
   - Overrides the image's ENTRYPOINT
   - Path doesn't exist in the image
   - Causes container to crash immediately

## What Happened

1. Previous deployment ran `just deploy staging` which included `deploy-images`
2. This built and pushed custom runner-base:staging to ECR  
3. Deployment scripts forced this image via `--set`
4. Custom image has different entrypoint (`/home/runner/actions-runner/bin/Runner.Listener run`)
5. Config tried to execute `/home/runner/run.sh` which doesn't exist
6. Container crashed immediately

## Fixes Applied

### Fix #1: Removed Image Overrides from Justfile

**Changed in 4 commands:**
- `_deploy-runner-cpu-small`
- `_deploy-runner-cpu-medium`
- `_deploy-runner-cpu-large`
- `_deploy-runner-gpu-t4`

**Before:**
```bash
ECR_IMAGE="${AWS_ACCOUNT}.dkr.ecr.${AWS_REGION}.amazonaws.com/pytorch-cloud/runner-base:{{env}}"
--set template.spec.containers[0].image="${ECR_IMAGE}"  # ❌ Force ECR image
```

**After:**
```bash
# Removed ECR_IMAGE variable
# Removed --set for image
# Uses image from values file: ghcr.io/actions/actions-runner:latest ✅
```

### Fix #2: Removed Command Overrides from All Configs

**Changed in 11 files:**
- helm/runners/*.yaml (8 files)
- helm/arc-runners/values.yaml
- helm/arc-gpu-runners/*.yaml (2 files)

**Before:**
```yaml
containers:
  - name: runner
    image: ghcr.io/actions/actions-runner:latest
    command: ["/home/runner/run.sh"]  # ❌ Wrong path
```

**After:**
```yaml
containers:
  - name: runner
    image: ghcr.io/actions/actions-runner:latest
    # No command override - uses image's ENTRYPOINT ✅
```

## How to Apply Fix

```bash
# Redeploy the runners with fixed configs
just deploy-runners staging

# Or deploy individually
just _deploy-runner-cpu-small staging
just _deploy-runner-cpu-medium staging
just _deploy-runner-cpu-large staging
just _deploy-runner-gpu-t4 staging
```

## Verification

After redeployment:

```bash
# Watch for pods to come up
kubectl get pods -n arc-runners -w

# Check they stay running
kubectl get pods -n arc-runners

# Verify they're using correct image
kubectl get pod <pod-name> -n arc-runners -o jsonpath='{.spec.containers[0].image}'
# Should show: ghcr.io/actions/actions-runner:latest

# Check events (should be clean)
kubectl get events -n arc-runners --sort-by='.lastTimestamp' | tail -10
```

## Expected Result

- ✅ Runner pods start successfully
- ✅ Stay running (don't crash)
- ✅ Show "Listening for Jobs" in logs
- ✅ Appear in GitHub as available runners

## Why This Happened

This was a **configuration mismatch** between:
- Values files (specified ghcr.io image)
- Justfile deploy scripts (forced ECR image)
- Command override (incompatible with both images)

**Lesson:** Don't override images in deployment scripts - trust the values files.

## Files Changed

- justfile (4 _deploy-runner-* commands)
- helm/runners/*.yaml (8 files - removed command)
- helm/arc-runners/values.yaml (1 file - removed command)
- helm/arc-gpu-runners/*.yaml (2 files - removed command)

**Total:** 15 files fixed
