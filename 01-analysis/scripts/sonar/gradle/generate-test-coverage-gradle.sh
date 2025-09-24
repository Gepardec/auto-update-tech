#!/bin/bash
set -euo pipefail

# === Required Environment Variables ===
REQUIRED_ENV_VARS=("PROJECT_ROOT" "PROJECT_KEY" "SONAR_USER" "SONAR_PASSWORD" "SONAR_URL")

check_env_vars() {
  for var in "${REQUIRED_ENV_VARS[@]}"; do
    if [[ -z "${!var:-}" ]]; then
      echo "❌ Error: Environment variable '$var' is not set."
      exit 1
    fi
  done
}

# === Find All Valid Gradle Modules ===
find_modules() {
  # Look for build.gradle or build.gradle.kts excluding build directories
  find "$PROJECT_ROOT" -type f \( -name "build.gradle" -o -name "build.gradle.kts" \) \
    | grep -v "/build/" \
    | while read -r build_file; do
        dir=$(dirname "$build_file")
        rel_path="${dir#"$PROJECT_ROOT"}"
        module="${rel_path#/}"

        # Skip root project itself
        if [[ -z "$rel_path" || "$rel_path" == "." ]]; then
          continue
        fi

        echo "$module"
      done | sort -u
}

# === Process Each Module ===
process_module() {
  local module="$1"
  local build_file="$PROJECT_ROOT/$module/build.gradle"

  # Check both build.gradle and build.gradle.kts
  if [[ ! -f "$build_file" ]]; then
    build_file="$PROJECT_ROOT/$module/build.gradle.kts"
  fi

  if [[ ! -f "$build_file" ]]; then
    echo "⚠️ build file not found in $module" >&2
    return
  fi

  if [[ ! -s "$build_file" ]]; then
    echo "⚠️ build file is empty in $module" >&2
    return
  fi

  response=$(curl -u "$SONAR_USER:$SONAR_PASSWORD" -s \
    "$SONAR_URL/api/measures/component?component=$PROJECT_KEY:$module&metricKeys=coverage,line_coverage,branch_coverage")

  if ! echo "$response" | jq .component &>/dev/null; then
    echo "⚠️ Failed to get valid response for $module. Skipping." >&2
    return
  fi

  echo "$response" | jq '{
    name: .component.name,
    measures: (
      .component.measures
      | map({key: .metric, value: .value})
      | from_entries
    )
  }'
}

# === Main ===
main() {
  check_env_vars

  modules=$(find_modules)

  results=""

  for module in $modules; do
    echo "Processing module $module ..."
    result=$(process_module "$module")
    results+="$result"
  done

  moduleList=$(echo "$results" | jq -s .)

  REPORT=$(curl -u "$SONAR_USER:$SONAR_PASSWORD" -s "$SONAR_URL/api/measures/component?component=$PROJECT_KEY&metricKeys=coverage,line_coverage,branch_coverage" | jq "{
    name: .component.name,
    measures: (
      .component.measures
      | map({key: .metric, value: .value})
      | from_entries
    ),
    modules: $moduleList
  }")

  echo "$REPORT" | jq
  echo "$REPORT" | jq > test-coverage-report.json
  echo "Report saved to test-coverage-report.json ✅"
}

main
