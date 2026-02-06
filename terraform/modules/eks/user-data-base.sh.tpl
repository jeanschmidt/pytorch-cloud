MIME-Version: 1.0
Content-Type: multipart/mixed; boundary="==MYBOUNDARY=="

--==MYBOUNDARY==
Content-Type: text/x-shellscript; charset="us-ascii"

#!/bin/bash
# EKS Base Infrastructure Node User Data Template
# This template calls the EKS bootstrap script, then runs post-bootstrap configuration

set -o xtrace

# Call EKS bootstrap script with base node configuration (REQUIRED)
/etc/eks/bootstrap.sh ${cluster_name} \
  --kubelet-extra-args '--max-pods=110 --register-with-taints=CriticalAddonsOnly=true:NoSchedule'

# Run post-bootstrap configuration script
${post_bootstrap_script}

--==MYBOUNDARY==--
