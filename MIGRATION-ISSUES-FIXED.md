# Migration Issues Found & Fixed - DinD to Kubernetes Mode

This document lists all issues, gotchas, and problems discovered during verification and how they were resolved.

## 🔴 CRITICAL ISSUES FOUND & FIXED

### Issue #1: helm/arc-gpu-runners/ NOT Updated ⚠️ **BLOCKER**

**Problem:**
- The `helm/arc-gpu-runners/` directory had 3 files that were NOT updated
- Still configured for dind mode
- Still requesting GPU resources in runner pod (not workflow container)
- Missing `serviceAccountName`
- Using gp2 instead of gp3

**Files affected:**
- `helm/arc-gpu-runners/values.yaml`
- `helm/arc-gpu-runners/values-staging.yaml`
- `helm/arc-gpu-runners/values-production.yaml`

**Impact:** These runners would FAIL to work in Kubernetes mode or waste GPU by allocating to runner pod.

**Fixed:**
- ✅ Changed `containerMode` to kubernetes
- ✅ Added `serviceAccountName: arc-runner`
- ✅ Removed `nvidia.com/gpu` from runner resources
- ✅ Removed NVIDIA environment variables
- ✅ Changed storageClassName to gp3
- ✅ Used `ghcr.io/actions/actions-runner:latest` image

### Issue #2: CI/CD Workflow References Deleted File ⚠️ **BUILD FAILURE**

**Problem:**
- `.github/workflows/docker-publish.yaml` still includes `runner-gpu` in build matrix
- File `docker/runner-gpu/Dockerfile` was deleted
- Workflow would fail when triggered

**Impact:** CI/CD pipeline would break on any docker/ changes.

**Fixed:**
- ✅ Removed `runner-gpu` from workflow matrix
- ✅ Updated workflow to only build `runner-base`
- ✅ Updated input description to clarify only runner-base exists

### Issue #3: RBAC Permissions Too Broad 🔒 **SECURITY RISK**

**Problem:**
- ServiceAccount had `update` and `patch` verbs on pods
- Had `delete`, `update`, `patch` on secrets (risky - can delete other secrets)
- Had `delete`, `update`, `patch` on configmaps
- Had `update`, `patch` on serviceaccounts (unnecessary)

**Security Risk:**
Runners could delete/modify arbitrary secrets and configmaps in the namespace, not just ones they create.

**Fixed:**
- ✅ Removed `update` and `patch` from pods (only need create, delete, get, list, watch)
- ✅ Removed `delete`, `update`, `patch` from secrets (only need create, get, list)
- ✅ Removed `delete`, `update`, `patch` from configmaps (only need create, get, list)
- ✅ Removed serviceaccounts write permissions entirely
- ✅ Added missing `pods/status` and `pods/attach` (actually needed)

**Result:** Tightened permissions to principle of least privilege.

### Issue #4: Inconsistent StorageClass 📦 **POTENTIAL FAILURE**

**Problem:**
- Some configs used `storageClassName: gp2` (old)
- Others used `storageClassName: gp3` (new)
- gp2 is deprecated, slower, and more expensive
- Inconsistency across environments

**Files affected:**
- `helm/arc-runners/values.yaml`
- `helm/arc-runners/values-staging.yaml`  
- `helm/arc-runners/values-production.yaml`
- `helm/arc-gpu-runners/values.yaml`

**Impact:** Mixed performance, costs, and potential failures if gp2 not available.

**Fixed:**
- ✅ Changed all to `storageClassName: gp3`
- ✅ Updated comment to reference kubernetes/base/storageclass-gp3.yaml

## 🟡 USELESS RESOURCES / WASTE

### Waste #1: Custom Docker Image Built But Never Used 💸

**Problem:**
- `justfile` has `deploy-images` command that builds custom runner-base
- Pushes to ECR (costs money for storage)
- All runner configs use `ghcr.io/actions/actions-runner:latest` instead
- `deploy` command calls `deploy-images` unnecessarily

**Impact:**
- Wastes build time (~2-5 minutes per deployment)
- Wastes ECR storage costs
- Creates confusion about which image is used

**Fixed:**
- ✅ Removed `deploy-images` call from `deploy` command
- ✅ Added note explaining official image is used
- ✅ Kept `deploy-images` available for manual use if needed

### Waste #2: Empty runner-gpu Directory 🗑️

**Problem:**
- `docker/runner-gpu/` directory still exists
- Only contains `.dockerignore` file
- `docker-build-all` would attempt to build it (would fail - no Dockerfile)

**Impact:** Confusion and potential build failures.

**Fixed:**
- ✅ Deleted `docker/runner-gpu/` directory entirely

### Waste #3: Confusing Commented-Out Image References 📝

**Problem:**
- Many helm values files had commented lines like:
  ```yaml
  # image: <account>.dkr.ecr.us-west-2.amazonaws.com/pytorch-cloud/runner-gpu:latest
  ```
- References non-existent runner-gpu image
- Suggests custom images should be used when they shouldn't

**Fixed:**
- ✅ Removed confusing comments from arc-gpu-runners values
- ✅ Clarified that ghcr.io image is used

## 🟢 DOCUMENTATION INCONSISTENCIES

### Doc Issue #1: SETUP-CHECKLIST.md Out of Date

**Problem:**
- Instructions to create ECR repo for runner-gpu
- Instructions to build and push runner-gpu
- Makes setup seem more complex than it is

**Fixed:**
- ✅ Made ECR creation optional
- ✅ Clarified official image is used by default
- ✅ Removed runner-gpu references

### Doc Issue #2: PROJECT-STRUCTURE.md Shows Old Architecture

**Problem:**
- Listed runner-gpu in directory structure
- Described "GPU-enabled runner with CUDA"
- Suggested docker-build and docker-push workflow

**Fixed:**
- ✅ Removed runner-gpu from structure
- ✅ Explained Kubernetes mode architecture
- ✅ Clarified custom image is optional

### Doc Issue #3: CLAUDE.md Had Old Commands

**Problem:**
- Referenced `just docker-build runner-gpu`

**Fixed:**
- ✅ Changed to `just docker-build runner-base` with note it's optional

## ⚠️ GOTCHAS THAT COULD CAUSE FAILURES

### Gotcha #1: Workflow Container Registry Authentication

**Issue:** If workflows use private container registries, they need credentials.

**Solution Required:**
1. For public images (docker hub, ghcr.io): No action needed
2. For private registries: Configure imagePullSecrets

**Example:**
```yaml
# Option A: In workflow
container:
  image: private.registry/image:tag
  credentials:
    username: ${{ secrets.USER }}
    password: ${{ secrets.PASS }}

# Option B: In runner config
template:
  spec:
    imagePullSecrets:
      - name: registry-secret
```

**Status:** ⚠️ Users must configure if using private registries

### Gotcha #2: GPU Toleration Not Inherited by Job Containers

**Issue:** GPU runner pod has tolerations for nvidia.com/gpu, but job container pods are separate.

**Potential Problem:** Job containers requesting GPU might not tolerate GPU node taints.

**How ARC Handles This:**
ARC in Kubernetes mode should propagate tolerations/nodeSelector to job containers automatically.

**Verification Needed:**
Test GPU workflow to ensure container actually schedules on GPU node and gets GPU.

**Test Command:**
```bash
# After deploying, run test workflow with nvidia-smi
# Check: kubectl get pod -n arc-runners -o wide
# Verify job container is on GPU node
```

**Status:** ⚠️ Needs runtime verification

### Gotcha #3: Workspace Volume Sharing Between Runner and Job Container

**Issue:** In dind mode, runner and job container share filesystem.
In Kubernetes mode, they are separate pods.

**Potential Problem:** 
- Checkout might work differently
- Artifacts might not be available
- Cache might not work

**How GitHub Actions Handles This:**
GitHub Actions runner in Kubernetes mode uses:
- Kubernetes volumes for workspace sharing
- Pod affinity to co-locate if needed
- Built-in artifact upload/download still works

**Status:** ⚠️ Should work but needs testing with actions/checkout and artifacts

### Gotcha #4: Service Account Token Auto-Mounting

**Issue:** Some GitHub Actions might need service account tokens (e.g., to interact with K8s API).

**Current Config:**
ServiceAccount exists but no explicit `automountServiceAccountToken` setting.

**Default Behavior:**
Kubernetes auto-mounts tokens by default, should work fine.

**If Issues Occur:**
Add to runner template:
```yaml
spec:
  automountServiceAccountToken: true
```

**Status:** ⚠️ Should work by default

### Gotcha #5: Resource Limits for Job Containers

**Issue:** Runner pod has resource limits, but what about job containers?

**Current Behavior:**
Job containers inherit NO resource limits unless specified in workflow:

```yaml
container:
  image: python:3.11
  options: --memory=4g --cpus=2
```

**Potential Problem:**
Job containers could consume all node resources.

**Mitigation:**
1. Karpenter will provision appropriately sized nodes
2. Set LimitRange in arc-runners namespace (optional)
3. Users should specify resource limits in workflows

**Status:** ⚠️ Consider adding LimitRange (optional)

### Gotcha #6: Double Pod Count

**Issue:** Each workflow job now creates TWO pods:
1. Runner pod
2. Job container pod

**Impact:**
- 2x pod count vs dind mode
- Could hit pod quotas faster
- More Kubernetes API load

**Mitigation:**
- Ensure adequate pod quota in namespace
- Monitor pod count
- Scale Kubernetes control plane if needed

**Status:** ⚠️ Monitor pod quotas

### Gotcha #7: Ephemeral Storage per Pod

**Issue:** Each runner pod has 50-200GB ephemeral storage.
Job containers are separate pods - do they also need storage?

**Current Behavior:**
Job containers use container filesystem (ephemeral).
For larger builds, might need persistent volumes.

**If Issues Occur:**
Users can mount volumes in workflow:
```yaml
container:
  image: python:3.11
  volumes:
    - cache:/tmp/cache
```

**Status:** ⚠️ Monitor for storage issues

## 📊 SUMMARY OF FIXES

### Files Created (1):
- `MIGRATION-ISSUES-FIXED.md` (this file)

### Files Modified (9):
- ✅ `kubernetes/base/runner-serviceaccount.yaml` - Fixed RBAC permissions
- ✅ `helm/arc-gpu-runners/values.yaml` - Updated to kubernetes mode
- ✅ `helm/arc-gpu-runners/values-staging.yaml` - Updated to kubernetes mode
- ✅ `helm/arc-gpu-runners/values-production.yaml` - Updated to kubernetes mode
- ✅ `.github/workflows/docker-publish.yaml` - Removed runner-gpu
- ✅ `justfile` - Removed deploy-images from deploy command
- ✅ `docs/SETUP-CHECKLIST.md` - Updated image build instructions
- ✅ `docs/PROJECT-STRUCTURE.md` - Removed runner-gpu references
- ✅ `CLAUDE.md` - Updated docker-build command

### Files Deleted (1):
- ✅ `docker/runner-gpu/` directory (was empty except .dockerignore)

### Storage Class Standardization (4 files):
- ✅ All configs now use `gp3` consistently

## ✅ VERIFICATION CHECKLIST

Before deploying to staging:

- [x] All runner configs use `containerMode: kubernetes`
- [x] All runner configs reference `serviceAccountName: arc-runner`
- [x] ServiceAccount and RBAC created with minimum necessary permissions
- [x] No configs request GPU for runner pod (GPU allocated to workflow containers)
- [x] All storage uses gp3
- [x] CI/CD workflows don't reference deleted files
- [x] Documentation consistent (no runner-gpu references except in migration guide)
- [x] Justfile doesn't build unused images by default
- [x] Kustomization includes runner-serviceaccount.yaml

Runtime verification needed:

- [ ] Verify ARC controller version >= 0.8.0
- [ ] Test workflow with container: tag
- [ ] Verify GPU allocation to job containers
- [ ] Check workspace volume sharing
- [ ] Monitor pod count and quotas
- [ ] Verify private registry access (if needed)

## 🎯 MIGRATION READY

All critical issues have been fixed. The migration is ready for deployment with the following caveats:

1. **Use official image**: All runners use `ghcr.io/actions/actions-runner:latest`
2. **Workflows need containers**: All workflows MUST specify `container:` tag
3. **Test thoroughly**: Run validation workflow in staging first
4. **Monitor resources**: Watch pod count and resource usage
5. **User education**: Share migration guide with workflow authors

## 🚀 NEXT STEPS

1. **Deploy RBAC first:**
   ```bash
   just k8s-apply staging
   kubectl get serviceaccount arc-runner -n arc-runners
   ```

2. **Deploy one runner to test:**
   ```bash
   just _deploy-runner-cpu-small staging
   kubectl get pods -n arc-runners -w
   ```

3. **Run test workflow:**
   ```bash
   # Trigger .github/workflows/test-kubernetes-mode.yml
   # Verify all jobs pass
   ```

4. **Deploy all runners:**
   ```bash
   just deploy-runners staging
   ```

5. **Monitor for 24 hours, then deploy to production**
