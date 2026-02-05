#!/bin/bash
# EKS GPU Node User Data Template
# This template calls the EKS bootstrap script, then runs post-bootstrap GPU configuration

set -o xtrace

# Call EKS bootstrap script with GPU node labels (REQUIRED)
/etc/eks/bootstrap.sh ${cluster_name} \
  --kubelet-extra-args '--max-pods=110 --node-labels=nvidia.com/gpu=true'

# Run post-bootstrap GPU configuration script
# Script is passed as a template variable from Terraform
${post_bootstrap_script}
