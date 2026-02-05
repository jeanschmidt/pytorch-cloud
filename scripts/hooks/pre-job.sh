#!/usr/bin/env bash
# Pre-job hook - runs before each job starts on the runner

set -euo pipefail

echo "Running pre-job hook at $(date)"

# Clean up workspace
if [ -d "${GITHUB_WORKSPACE}" ]; then
    echo "Cleaning workspace: ${GITHUB_WORKSPACE}"
    rm -rf "${GITHUB_WORKSPACE:?}"/*
fi

# Clean Docker resources
if command -v docker &> /dev/null; then
    echo "Cleaning Docker resources..."
    docker system prune -f --volumes || true
fi

# Reset ccache stats if available
if command -v ccache &> /dev/null; then
    echo "Resetting ccache stats..."
    ccache -z || true
fi

# Display GPU status if available
if command -v nvidia-smi &> /dev/null; then
    echo "GPU Status:"
    nvidia-smi
fi

echo "Pre-job hook completed at $(date)"
