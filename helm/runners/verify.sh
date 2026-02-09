#!/usr/bin/env bash
# Verify that generated runner configs match templates
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

# Generate configs to temp location
TEMP_DIR=$(mktemp -d)
trap "rm -rf ${TEMP_DIR}" EXIT

echo "Generating configs to temp location..."
bash "${SCRIPT_DIR}/generate.sh" staging > /dev/null 2>&1
bash "${SCRIPT_DIR}/generate.sh" production > /dev/null 2>&1

# Move generated files to temp for comparison
for env in staging production; do
    for runner in cpu-small cpu-medium cpu-large gpu-t4; do
        if [[ -f "${SCRIPT_DIR}/${runner}-${env}.yaml" ]]; then
            cp "${SCRIPT_DIR}/${runner}-${env}.yaml" "${TEMP_DIR}/${runner}-${env}.yaml"
        fi
    done
done

# Regenerate in place
echo "Regenerating configs..."
bash "${SCRIPT_DIR}/generate.sh" staging > /dev/null 2>&1
bash "${SCRIPT_DIR}/generate.sh" production > /dev/null 2>&1

# Compare
echo ""
echo "Comparing generated vs existing..."
DIFFERENCES=0
for env in staging production; do
    for runner in cpu-small cpu-medium cpu-large gpu-t4; do
        current="${SCRIPT_DIR}/${runner}-${env}.yaml"
        temp="${TEMP_DIR}/${runner}-${env}.yaml"
        
        if [[ -f "$temp" ]] && [[ -f "$current" ]]; then
            if ! diff -q "$current" "$temp" > /dev/null 2>&1; then
                echo "  ❌ ${runner}-${env}.yaml differs"
                DIFFERENCES=$((DIFFERENCES + 1))
            else
                echo "  ✓ ${runner}-${env}.yaml matches"
            fi
        fi
    done
done

echo ""
if [[ $DIFFERENCES -eq 0 ]]; then
    echo "✅ All runner configs are consistent with templates"
    exit 0
else
    echo "❌ Found $DIFFERENCES inconsistent file(s)"
    echo ""
    echo "To fix: run './generate.sh staging production'"
    exit 1
fi
