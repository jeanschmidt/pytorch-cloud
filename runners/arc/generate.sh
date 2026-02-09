#!/usr/bin/env bash
# Generate environment-specific runner YAML files from templates
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATES_DIR="${SCRIPT_DIR}/templates"
OUTPUT_DIR="${SCRIPT_DIR}/generated"

# Map runner type to maxRunners key
get_max_runners_key() {
    case "$1" in
        cpu-small) echo "cpuSmall" ;;
        cpu-medium) echo "cpuMedium" ;;
        cpu-large) echo "cpuLarge" ;;
        gpu-t4) echo "gpuT4" ;;
        *) echo "unknown" ;;
    esac
}

# Parse nested max runners values
parse_max_runners() {
    local env=$1
    local runner_key=$2
    
    awk -v env="$env" -v key="$runner_key" '
        /^[a-z]+:/ { current_env = $1; gsub(/:/, "", current_env) }
        current_env == env && /maxRunners:/ { in_max_runners = 1; next }
        current_env == env && in_max_runners && /^[a-z]+:/ { in_max_runners = 0 }
        in_max_runners && $1 ~ key":" { print $2; exit }
    ' "${SCRIPT_DIR}/env-values.yaml"
}

# Generate runner config for a specific environment and type
generate_runner() {
    local env=$1
    local runner_type=$2
    local runner_key
    runner_key=$(get_max_runners_key "$runner_type")
    
    local template_file="${TEMPLATES_DIR}/${runner_type}.yaml.tpl"
    local output_file="${OUTPUT_DIR}/${runner_type}.yaml"
    
    if [[ ! -f "$template_file" ]]; then
        echo "❌ Template not found: $template_file"
        return 1
    fi
    
    # Parse values from env-values.yaml
    local github_url github_secret runner_prefix max_runners
    
    github_url=$(awk -v env="$env" '
        /^[a-z]+:/ { current_env = $1; gsub(/:/, "", current_env) }
        current_env == env && /githubConfigUrl:/ { 
            sub(/.*githubConfigUrl: *"?/, ""); sub(/".*/, ""); print; exit 
        }
    ' "${SCRIPT_DIR}/env-values.yaml")
    
    github_secret=$(awk -v env="$env" '
        /^[a-z]+:/ { current_env = $1; gsub(/:/, "", current_env) }
        current_env == env && /githubConfigSecret:/ { 
            sub(/.*githubConfigSecret: *"?/, ""); sub(/".*/, ""); print; exit 
        }
    ' "${SCRIPT_DIR}/env-values.yaml")
    
    runner_prefix=$(awk -v env="$env" '
        /^[a-z]+:/ { current_env = $1; gsub(/:/, "", current_env) }
        current_env == env && /runnerNamePrefix:/ { 
            sub(/.*runnerNamePrefix: *"?/, ""); sub(/".*/, ""); print; exit 
        }
    ' "${SCRIPT_DIR}/env-values.yaml")
    
    max_runners=$(parse_max_runners "$env" "$runner_key")
    
    # Generate file from template
    sed -e "s|{{GITHUB_CONFIG_URL}}|${github_url}|g" \
        -e "s|{{GITHUB_CONFIG_SECRET}}|${github_secret}|g" \
        -e "s|{{RUNNER_NAME_PREFIX}}|${runner_prefix}|g" \
        -e "s|{{MAX_RUNNERS}}|${max_runners}|g" \
        "$template_file" > "$output_file"
    
    echo "  ✓ Generated: $output_file"
}

# Main
main() {
    local env="${1:-}"
    
    if [[ -z "$env" ]]; then
        echo "Usage: $0 <environment>"
        echo ""
        echo "Available environments: staging, production"
        echo ""
        echo "Example: $0 staging"
        exit 1
    fi
    
    if [[ "$env" != "staging" && "$env" != "production" ]]; then
        echo "❌ Invalid environment: $env"
        echo "Must be 'staging' or 'production'"
        exit 1
    fi
    
    # Create output directory if it doesn't exist
    mkdir -p "$OUTPUT_DIR"
    
    echo "→ Generating runner configs for: $env"
    echo ""
    
    # Generate configs for all runner types
    for runner_type in cpu-small cpu-medium cpu-large gpu-t4; do
        generate_runner "$env" "$runner_type"
    done
    
    echo ""
    echo "✓ All runner configs generated for $env in $OUTPUT_DIR"
}

main "$@"
