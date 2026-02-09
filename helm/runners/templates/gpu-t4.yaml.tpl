githubConfigUrl: "{{GITHUB_CONFIG_URL}}"
githubConfigSecret: "{{GITHUB_CONFIG_SECRET}}"
runnerScaleSetName: "{{RUNNER_NAME_PREFIX}}pytorch-gpu-t4"

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

    # Runner pod should be lightweight and NOT request GPU
    # The GPU will be allocated to job pods via the hook template
    # However, we still schedule runner on GPU nodes so job pods can run locally
    nodeSelector:
      nvidia.com/gpu: "true"
      nvidia.com/gpu.product: "T4"

    tolerations:
      - key: nvidia.com/gpu
        value: "t4"
        effect: NoSchedule
      - key: cpu-type
        value: "intel-xeon"
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
          # LIGHTWEIGHT runner pod - NO GPU requested here
          # Job pods get the GPU via hook template
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
                  storage: 200Gi
              storageClassName: gp3
      - name: hook-extensions
        configMap:
          name: arc-runner-hook-gpu-t4
          items:
            - key: job-pod.yaml
              path: job-pod.yaml
