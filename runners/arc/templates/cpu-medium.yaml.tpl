githubConfigUrl: "{{GITHUB_CONFIG_URL}}"
githubConfigSecret: "{{GITHUB_CONFIG_SECRET}}"
runnerScaleSetName: "{{RUNNER_NAME_PREFIX}}pytorch-cpu-medium"

minRunners: 0
maxRunners: {{MAX_RUNNERS}}

runnerGroup: "default"

containerMode:
  type: "kubernetes"

controllerServiceAccount:
  namespace: arc-systems
  name: arc-gha-rs-controller

listenerTemplate:
  spec:
    tolerations:
      - key: CriticalAddonsOnly
        operator: Equal
        value: "true"
        effect: NoSchedule
    containers:
      - name: listener
        resources:
          limits:
            cpu: "200m"
            memory: "256Mi"
          requests:
            cpu: "100m"
            memory: "128Mi"

template:
  spec:
    serviceAccountName: arc-runner

    # Schedule runner pods on CPU compute nodes
    nodeSelector:
      workload-type: github-runner

    # Tolerate CPU architecture taints
    tolerations:
      - key: cpu-type
        operator: Equal
        value: "compute-optimized"
        effect: NoSchedule

    containers:
      - name: runner
        image: ghcr.io/actions/actions-runner:latest
        command: ["/home/runner/run.sh"]
        env:
          - name: RUNNER_FEATURE_FLAG_EPHEMERAL
            value: "true"
          # Point to hook template for job pod customization
          - name: ACTIONS_RUNNER_CONTAINER_HOOK_TEMPLATE
            value: /home/runner/hook-extensions/job-pod.yaml
        resources:
          # LIGHTWEIGHT runner pod - job pods get the heavy resources
          # Runner is just an orchestrator, doesn't do the actual work
          limits:
            cpu: "200m"
            memory: "512Mi"
          requests:
            cpu: "200m"
            memory: "512Mi"
        volumeMounts:
          - name: work
            mountPath: /home/runner/_work
          - name: hook-extensions
            mountPath: /home/runner/hook-extensions

    volumes:
      - name: work
        ephemeral:
          volumeClaimTemplate:
            spec:
              accessModes: ["ReadWriteOnce"]
              resources:
                requests:
                  storage: 75Gi
              storageClassName: gp3
      - name: hook-extensions
        configMap:
          name: arc-runner-hook-cpu-medium
          items:
            - key: job-pod.yaml
              path: job-pod.yaml
---
# ConfigMap: Job Pod Hook Template for CPU Medium Runners
# Defines resource requests for workflow job containers in Kubernetes mode
# Runner pod is lightweight; job pods get the heavy resources

apiVersion: v1
kind: ConfigMap
metadata:
  name: arc-runner-hook-cpu-medium
  namespace: arc-runners
data:
  job-pod.yaml: |
    spec:
      # Job pods need service account to access cluster resources
      serviceAccountName: arc-runner

      # Schedule job pods on CPU compute nodes
      nodeSelector:
        workload-type: github-runner

      # Tolerate CPU architecture taints
      tolerations:
        - key: cpu-type
          operator: Equal
          value: "compute-optimized"
          effect: NoSchedule

      containers:
        - name: "$job"
          # Workflow container gets the actual compute resources
          resources:
            requests:
              cpu: "8"
              memory: "16Gi"
            limits:
              cpu: "8"
              memory: "16Gi"
