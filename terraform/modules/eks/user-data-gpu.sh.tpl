# shellcheck shell=bash disable=SC2148,SC2034,SC2215,SC2154
# This is a MIME multipart cloud-init template for EKS user-data (GPU nodes)
# Template variables are provided by Terraform and should not be checked by shellcheck
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
      # CRITICAL for benchmark consistency - prevents noisy neighbor on CPU
      cpuManagerPolicy: static
      cpuManagerReconcilePeriod: 10s
      # Reserve CPUs 0-3 for system daemons on GPU nodes (more overhead than CPU nodes)
      # GPU nodes typically have more CPUs, so reserve more for system tasks
      systemReserved:
        cpu: "4000m"
        memory: "4Gi"
        ephemeral-storage: "20Gi"
      kubeReserved:
        cpu: "2000m"
        memory: "2Gi"
      # Memory Manager: Static policy for NUMA-aware memory allocation
      # Pins memory to NUMA nodes for better performance
      # CRITICAL for benchmark consistency - prevents memory access penalties
      memoryManagerPolicy: Static
      # Topology Manager: single-numa-node policy
      # Ensures CPU, memory, and GPU are allocated from the same NUMA node
      # CRITICAL for GPU workloads - minimizes PCIe latency
      topologyManagerPolicy: single-numa-node
      topologyManagerScope: pod
    flags:
      - --node-labels=nvidia.com/gpu=true

--==BOUNDARY==
Content-Type: text/x-shellscript; charset="us-ascii"

${post_bootstrap_script}

--==BOUNDARY==--
