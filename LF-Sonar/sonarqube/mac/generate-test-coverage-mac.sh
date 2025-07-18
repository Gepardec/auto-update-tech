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

# === Find All Valid Modules ===
find_modules() {
  find "$PROJECT_ROOT" -type f -name "pom.xml" | grep -v "/target/" | while read -r pom; do
    dir=$(dirname "$pom")
    rel_path="${dir#$PROJECT_ROOT}"
    module="${rel_path#/}"
      # Strip project root prefix

    # Skip root project itself (i.e., when rel_path is empty)
    if [[ -z "$rel_path" || "$rel_path" == "." ]]; then
      continue
    fi

    echo "$module"
  done | sort -u
}

# === Process Each Module ===
process_module() {
  local module="$1"

  if [[ ! -f "$PROJECT_ROOT/$module/pom.xml" ]]; then
    echo "⚠️ pom.xml not found in $module"
    return
  fi

  if [[ ! -s "$PROJECT_ROOT/$module/pom.xml" ]]; then
    echo "⚠️ pom.xml is empty in $module"
    return
  fi

  # ✅ Continue with SonarQube API calls (placeholder)
  curl -u "$SONAR_USER:$SONAR_PASSWORD" -s "$SONAR_URL/api/measures/component?component=$PROJECT_KEY:$module&metricKeys=coverage,line_coverage,branch_coverage" | jq '{
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

  echo "🔎 Searching for modules in: $PROJECT_ROOT"
  modules=$(find_modules)
  echo "MODULES: " $modules

  if [[ -z "$modules" ]]; then
    echo "❌ No modules with pom.xml found."
    exit 1
  fi

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
