#!/usr/bin/env bash
# Post-job hook - runs after each job completes on the runner

set -euo pipefail

echo "Running post-job hook at $(date)"

# Display ccache stats if available
if command -v ccache &> /dev/null; then
    echo "ccache statistics:"
    ccache -s || true
fi

# Display disk usage
echo "Disk usage:"
df -h

# Display memory usage
echo "Memory usage:"
free -h

# Clean up large temporary files
echo "Cleaning up temporary files..."
find /tmp -type f -size +100M -mtime +1 -delete 2>/dev/null || true

# Docker cleanup
if command -v docker &> /dev/null; then
    echo "Docker disk usage:"
    docker system df || true
    
    # Remove dangling images and stopped containers
    docker container prune -f || true
    docker image prune -f || true
fi

echo "Post-job hook completed at $(date)"
