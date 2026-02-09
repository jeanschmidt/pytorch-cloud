#!/usr/bin/env bash
# Validate runner configurations for Guaranteed QoS
# Checks that all runner containers have requests == limits with integer values
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

# Validate a single YAML file
validate_file() {
	local file=$1
	local filename=$(basename "$file")
	local errors_in_file=0

	echo "→ Validating: $filename"

	# Use yq if available, otherwise use grep-based parsing
	if command -v yq &>/dev/null; then
		# Extract CPU and memory values using yq
		local cpu_limit=$(yq eval '.template.spec.containers[] | select(.name == "runner") | .resources.limits.cpu' "$file" 2>/dev/null | grep -v "null" | head -1 || echo "")
		local cpu_request=$(yq eval '.template.spec.containers[] | select(.name == "runner") | .resources.requests.cpu' "$file" 2>/dev/null | grep -v "null" | head -1 || echo "")
		local mem_limit=$(yq eval '.template.spec.containers[] | select(.name == "runner") | .resources.limits.memory' "$file" 2>/dev/null | grep -v "null" | head -1 || echo "")
		local mem_request=$(yq eval '.template.spec.containers[] | select(.name == "runner") | .resources.requests.memory' "$file" 2>/dev/null | grep -v "null" | head -1 || echo "")
	else
		# Fallback to grep-based parsing
		# Extract values between runner container and volumeMounts
		local runner_section=$(awk '/- name: runner/,/volumeMounts:/' "$file")

		cpu_limit=$(echo "$runner_section" | awk '/limits:/,/requests:/' | grep "cpu:" | head -1 | awk '{print $2}' | tr -d '"' | xargs || echo "")
		cpu_request=$(echo "$runner_section" | awk '/requests:/,/volumeMounts:/' | grep "cpu:" | head -1 | awk '{print $2}' | tr -d '"' | xargs || echo "")
		mem_limit=$(echo "$runner_section" | awk '/limits:/,/requests:/' | grep "memory:" | head -1 | awk '{print $2}' | tr -d '"' | xargs || echo "")
		mem_request=$(echo "$runner_section" | awk '/requests:/,/volumeMounts:/' | grep "memory:" | head -1 | awk '{print $2}' | tr -d '"' | xargs || echo "")
	fi

	# Strip quotes and whitespace (redundant but safe)
	cpu_limit=$(echo "$cpu_limit" | tr -d '"' | xargs)
	cpu_request=$(echo "$cpu_request" | tr -d '"' | xargs)
	mem_limit=$(echo "$mem_limit" | tr -d '"' | xargs)
	mem_request=$(echo "$mem_request" | tr -d '"' | xargs)

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
	echo "Checking that all runners have Guaranteed QoS:"
	echo "  • resources.requests == resources.limits"
	echo "  • CPU values are integers (not millicpu)"
	echo ""

	# Find all runner configuration files
	local files=()

	# Check base values
	if [[ -f "${PROJECT_ROOT}/helm/arc-runners/values.yaml" ]]; then
		files+=("${PROJECT_ROOT}/helm/arc-runners/values.yaml")
	fi
	if [[ -f "${PROJECT_ROOT}/helm/arc-runners/values-staging.yaml" ]]; then
		files+=("${PROJECT_ROOT}/helm/arc-runners/values-staging.yaml")
	fi
	if [[ -f "${PROJECT_ROOT}/helm/arc-runners/values-production.yaml" ]]; then
		files+=("${PROJECT_ROOT}/helm/arc-runners/values-production.yaml")
	fi

	# Check GPU runners
	if [[ -f "${PROJECT_ROOT}/helm/arc-gpu-runners/values.yaml" ]]; then
		files+=("${PROJECT_ROOT}/helm/arc-gpu-runners/values.yaml")
	fi
	if [[ -f "${PROJECT_ROOT}/helm/arc-gpu-runners/values-staging.yaml" ]]; then
		files+=("${PROJECT_ROOT}/helm/arc-gpu-runners/values-staging.yaml")
	fi
	if [[ -f "${PROJECT_ROOT}/helm/arc-gpu-runners/values-production.yaml" ]]; then
		files+=("${PROJECT_ROOT}/helm/arc-gpu-runners/values-production.yaml")
	fi

	# Check templates
	for template in "${PROJECT_ROOT}"/helm/runners/templates/*.yaml.tpl; do
		if [[ -f "$template" ]]; then
			files+=("$template")
		fi
	done

	# Check generated files if they exist
	for generated in "${PROJECT_ROOT}"/helm/runners/generated/*.yaml; do
		if [[ -f "$generated" ]]; then
			files+=("$generated")
		fi
	done

	if [[ ${#files[@]} -eq 0 ]]; then
		echo -e "${RED}No runner configuration files found!${NC}"
		exit 1
	fi

	# Validate each file
	for file in "${files[@]}"; do
		validate_file "$file"
	done

	# Summary
	echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
	echo "Summary"
	echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
	echo ""
	echo "Files checked: ${#files[@]}"

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
		echo "All runner containers must have Guaranteed QoS:"
		echo "  1. Set resources.requests == resources.limits"
		echo "  2. Use integer CPU values (e.g., \"4\" not \"4000m\")"
		echo ""
		echo "Example:"
		echo "  resources:"
		echo "    limits:"
		echo "      cpu: \"8\""
		echo "      memory: \"32Gi\""
		echo "    requests:"
		echo "      cpu: \"8\"        # Same as limits"
		echo "      memory: \"32Gi\"  # Same as limits"
		echo ""
		exit 1
	else
		echo -e "${GREEN}✅ All runners have Guaranteed QoS configuration!${NC}"
		echo ""
		exit 0
	fi
}

main "$@"
