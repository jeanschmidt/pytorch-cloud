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
        resources:
          limits:
            cpu: "8"
            memory: "32Gi"
          requests:
            cpu: "8"
            memory: "32Gi"
        volumeMounts:
          - name: work
            mountPath: /home/runner/_work

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
