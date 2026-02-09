#!/usr/bin/env bash
# Validate runner configurations for Guaranteed QoS
# Checks that all JOB CONTAINER specs in ConfigMaps have requests == limits with integer values
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

ERRORS=0
WARNINGS=0

# Validate a ConfigMap file (job pod hook template)
validate_configmap() {
	local file=$1
	local filename=$(basename "$file")
	local errors_in_file=0

	echo "→ Validating: $filename"

	# Extract the job pod spec from the ConfigMap's data.job-pod.yaml field
	# The spec is indented under "job-pod.yaml: |"
	local job_spec=$(awk '/job-pod\.yaml: \|/,0' "$file" | tail -n +2)

	if [[ -z "$job_spec" ]]; then
		echo -e "  ${RED}✗${NC} No job-pod.yaml found in ConfigMap"
		errors_in_file=$((errors_in_file + 1))
		ERRORS=$((ERRORS + errors_in_file))
		echo ""
		return
	fi

	# Extract resources from the $job container spec
	# Looking for: containers: - name: "$job" resources: ...
	local cpu_limit=$(echo "$job_spec" | awk '/- name: "\$job"/,/^[[:space:]]*$/' | grep -A 10 "limits:" | grep "cpu:" | head -1 | awk '{print $2}' | tr -d '"' | xargs || echo "")
	local cpu_request=$(echo "$job_spec" | awk '/- name: "\$job"/,/^[[:space:]]*$/' | grep -A 10 "requests:" | grep "cpu:" | head -1 | awk '{print $2}' | tr -d '"' | xargs || echo "")
	local mem_limit=$(echo "$job_spec" | awk '/- name: "\$job"/,/^[[:space:]]*$/' | grep -A 10 "limits:" | grep "memory:" | head -1 | awk '{print $2}' | tr -d '"' | xargs || echo "")
	local mem_request=$(echo "$job_spec" | awk '/- name: "\$job"/,/^[[:space:]]*$/' | grep -A 10 "requests:" | grep "memory:" | head -1 | awk '{print $2}' | tr -d '"' | xargs || echo "")

	# Check for GPU resources (optional)
	local gpu_limit=$(echo "$job_spec" | awk '/- name: "\$job"/,/^[[:space:]]*$/' | grep -A 10 "limits:" | grep "nvidia.com/gpu:" | head -1 | awk '{print $2}' | tr -d '"' | xargs || echo "")
	local gpu_request=$(echo "$job_spec" | awk '/- name: "\$job"/,/^[[:space:]]*$/' | grep -A 10 "requests:" | grep "nvidia.com/gpu:" | head -1 | awk '{print $2}' | tr -d '"' | xargs || echo "")

	# Validate CPU
	if [[ -z "$cpu_limit" ]] || [[ -z "$cpu_request" ]]; then
		echo -e "  ${RED}✗${NC} Missing CPU limits or requests"
		errors_in_file=$((errors_in_file + 1))
	elif [[ "$cpu_limit" != "$cpu_request" ]]; then
		echo -e "  ${RED}✗${NC} CPU mismatch: limits=$cpu_limit, requests=$cpu_request (must be equal for Guaranteed QoS)"
		errors_in_file=$((errors_in_file + 1))
	elif ! echo "$cpu_limit" | grep -qE '^[0-9]+$'; then
		echo -e "  ${RED}✗${NC} CPU value must be integer: $cpu_limit (e.g., \"4\" not \"4.5\" or \"4000m\")"
		errors_in_file=$((errors_in_file + 1))
	else
		echo -e "  ${GREEN}✓${NC} CPU: $cpu_limit (Guaranteed QoS)"
	fi

	# Validate Memory
	if [[ -z "$mem_limit" ]] || [[ -z "$mem_request" ]]; then
		echo -e "  ${RED}✗${NC} Missing memory limits or requests"
		errors_in_file=$((errors_in_file + 1))
	elif [[ "$mem_limit" != "$mem_request" ]]; then
		echo -e "  ${RED}✗${NC} Memory mismatch: limits=$mem_limit, requests=$mem_request (must be equal for Guaranteed QoS)"
		errors_in_file=$((errors_in_file + 1))
	else
		echo -e "  ${GREEN}✓${NC} Memory: $mem_limit (Guaranteed QoS)"
	fi

	# Validate GPU if present
	if [[ -n "$gpu_limit" ]] || [[ -n "$gpu_request" ]]; then
		if [[ "$gpu_limit" != "$gpu_request" ]]; then
			echo -e "  ${RED}✗${NC} GPU mismatch: limits=$gpu_limit, requests=$gpu_request (must be equal)"
			errors_in_file=$((errors_in_file + 1))
		else
			echo -e "  ${GREEN}✓${NC} GPU: $gpu_limit"
		fi
	fi

	# Additional check: CPU should be integer (warn about millicpu)
	if [[ -n "$cpu_limit" ]] && echo "$cpu_limit" | grep -q "m$"; then
		echo -e "  ${YELLOW}⚠${NC}  CPU uses millicpu notation ($cpu_limit). Integer values recommended for clarity."
		WARNINGS=$((WARNINGS + 1))
	fi

	if [[ $errors_in_file -gt 0 ]]; then
		echo -e "  ${RED}Failed with $errors_in_file error(s)${NC}"
		ERRORS=$((ERRORS + errors_in_file))
	fi

	echo ""
}

# Main
main() {
	echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
	echo "Runner QoS Configuration Validator"
	echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
	echo ""
	echo "Checking that all JOB CONTAINERS have Guaranteed QoS:"
	echo "  • Job pods defined in ConfigMaps (hook templates)"
	echo "  • resources.requests == resources.limits"
	echo "  • CPU values are integers (not millicpu)"
	echo ""

	# Find all runner hook ConfigMaps
	local files=()

	for configmap in "${PROJECT_ROOT}"/runners/arc/hooks/*.yaml; do
		if [[ -f "$configmap" ]]; then
			files+=("$configmap")
		fi
	done

	if [[ ${#files[@]} -eq 0 ]]; then
		echo -e "${RED}No runner hook ConfigMaps found!${NC}"
		echo "Expected files in: runners/arc/hooks/*.yaml"
		exit 1
	fi

	# Validate each ConfigMap
	for file in "${files[@]}"; do
		validate_configmap "$file"
	done

	# Summary
	echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
	echo "Summary"
	echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
	echo ""
	echo "ConfigMaps checked: ${#files[@]}"

	if [[ $ERRORS -gt 0 ]]; then
		echo -e "${RED}Errors: $ERRORS${NC}"
	else
		echo -e "${GREEN}Errors: 0${NC}"
	fi

	if [[ $WARNINGS -gt 0 ]]; then
		echo -e "${YELLOW}Warnings: $WARNINGS${NC}"
	fi

	echo ""

	if [[ $ERRORS -gt 0 ]]; then
		echo -e "${RED}❌ Validation FAILED${NC}"
		echo ""
		echo "All job containers must have Guaranteed QoS:"
		echo "  1. Set resources.requests == resources.limits"
		echo "  2. Use integer CPU values (e.g., \"4\" not \"4000m\")"
		echo ""
		echo "Example (in ConfigMap):"
		echo "  containers:"
		echo "    - name: \"\$job\""
		echo "      resources:"
		echo "        limits:"
		echo "          cpu: \"8\""
		echo "          memory: \"32Gi\""
		echo "        requests:"
		echo "          cpu: \"8\"        # Same as limits"
		echo "          memory: \"32Gi\"  # Same as limits"
		echo ""
		exit 1
	else
		echo -e "${GREEN}✅ All job containers have Guaranteed QoS configuration!${NC}"
		echo ""
		exit 0
	fi
}

main "$@"
