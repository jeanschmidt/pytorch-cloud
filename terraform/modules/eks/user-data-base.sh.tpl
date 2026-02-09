MIME-Version: 1.0
Content-Type: multipart/mixed; boundary="==BOUNDARY=="

--==BOUNDARY==
Content-Type: application/node.eks.aws

---
apiVersion: node.eks.aws/v1alpha1
kind: NodeConfig
spec:
  cluster:
    name: ${cluster_name}
    apiServerEndpoint: ${cluster_endpoint}
    certificateAuthority: ${cluster_ca_data}
    cidr: ${service_cidr}
  kubelet:
    config:
      maxPods: 110
      # CPU Manager: Static policy for CPU pinning
      # Provides dedicated CPU cores to Guaranteed QoS pods
      cpuManagerPolicy: static
      cpuManagerReconcilePeriod: 10s
      # Reserve CPUs 0-1 for system daemons (kubelet, containerd, etc.)
      # This prevents workload pods from using these cores
      systemReserved:
        cpu: "2000m"
        memory: "2Gi"
        ephemeral-storage: "10Gi"
      kubeReserved:
        cpu: "1000m"
        memory: "1Gi"
      # Memory Manager: Static policy for NUMA-aware memory allocation
      # Pins memory to NUMA nodes for better performance
      memoryManagerPolicy: Static
      # Topology Manager: single-numa-node policy
      # Ensures CPU and memory are allocated from the same NUMA node
      # Critical for performance consistency on multi-socket systems
      topologyManagerPolicy: single-numa-node
      topologyManagerScope: pod
    flags:
      - --register-with-taints=CriticalAddonsOnly=true:NoSchedule

--==BOUNDARY==
Content-Type: text/x-shellscript; charset="us-ascii"

${post_bootstrap_script}

--==BOUNDARY==--
