#!/usr/bin/env bash
# Verify that generated runner configs match templates
# Tests that regenerating configs produces identical output (idempotency)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "→ Verifying runner configuration consistency..."
echo ""

# Check that templates exist
echo "Checking templates..."
for template in cpu-small cpu-medium cpu-large gpu-t4; do
    if [[ ! -f "${SCRIPT_DIR}/templates/${template}.yaml.tpl" ]]; then
        echo "  ❌ Missing template: ${template}.yaml.tpl"
        exit 1
    fi
    echo "  ✓ ${template}.yaml.tpl exists"
done
echo ""

# This script tests that regenerating configs from templates is idempotent
# i.e., generating twice with same environment produces identical output

TEMP_DIR=$(mktemp -d)
trap "rm -rf ${TEMP_DIR}" EXIT

echo "Testing idempotency..."
DIFFERENCES=0

for env in staging production; do
    echo ""
    echo "→ Testing $env environment..."
    
    # Generate once
    bash "${SCRIPT_DIR}/generate.sh" "$env" > /dev/null 2>&1
    
    # Save generated files
    for runner in cpu-small cpu-medium cpu-large gpu-t4; do
        if [[ -f "${SCRIPT_DIR}/generated/${runner}.yaml" ]]; then
            cp "${SCRIPT_DIR}/generated/${runner}.yaml" "${TEMP_DIR}/${runner}-first-${env}.yaml"
        fi
    done
    
    # Generate again with same environment
    bash "${SCRIPT_DIR}/generate.sh" "$env" > /dev/null 2>&1
    
    # Compare for each runner
    for runner in cpu-small cpu-medium cpu-large gpu-t4; do
        current="${SCRIPT_DIR}/generated/${runner}.yaml"
        temp="${TEMP_DIR}/${runner}-first-${env}.yaml"
        
        if [[ -f "$temp" ]] && [[ -f "$current" ]]; then
            if ! diff -q "$current" "$temp" > /dev/null 2>&1; then
                echo "  ❌ ${runner}.yaml is not idempotent"
                DIFFERENCES=$((DIFFERENCES + 1))
            else
                echo "  ✓ ${runner}.yaml is consistent"
            fi
        fi
    done
done

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
if [[ $DIFFERENCES -eq 0 ]]; then
    echo "✅ All runner configs are idempotent and consistent"
    exit 0
else
    echo "❌ Found $DIFFERENCES inconsistent file(s)"
    echo ""
    echo "Generation is not idempotent - running generate.sh twice produces different output."
    echo "This should not happen and indicates a bug in generate.sh"
    exit 1
fi
