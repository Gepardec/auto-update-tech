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
    rel_path="${dir#"$PROJECT_ROOT"}"
    module="${rel_path#/}"

    if [[ -z "$rel_path" || "$rel_path" == "." ]]; then
      continue
    fi

    echo "$module"
  done | sort -u
}

# === Parse JSON response manually ===
parse_measures() {
  local json="$1"
  local name
  name=$(echo "$json" | grep -o '"name":"[^"]*"' | cut -d':' -f2 | tr -d '"')
  echo "    {"
  echo "      \"name\": \"$name\","
  echo "      \"measures\": {"
  echo "$json" | grep -o '"metric":"[^"]*","value":"[^"]*"' | \
    sed -E 's/"metric":"([^"]*)","value":"([^"]*)"/        "\1": "\2",/' | sed '$ s/,$//'
  echo "      }"
  echo "    }"
}

# === Process Each Module ===
process_module() {
  local module="$1"
  local module_path="$PROJECT_ROOT/$module"

  if [[ ! -f "$module_path/pom.xml" ]]; then
    echo "⚠️ pom.xml not found in $module" >&2
    return
  fi

  if [[ ! -s "$module_path/pom.xml" ]]; then
    echo "⚠️ pom.xml is empty in $module" >&2
    return
  fi

  local json
  json=$(curl -u "$SONAR_USER:$SONAR_PASSWORD" -s "$SONAR_URL/api/measures/component?component=$PROJECT_KEY:$module&metricKeys=coverage,line_coverage,branch_coverage")

  parse_measures "$json"
}

# === Main ===
main() {
  check_env_vars

  modules=$(find_modules)

  if [[ -z "$modules" ]]; then
    echo "❌ No modules with pom.xml found."
    exit 1
  fi

  echo "Generating report..."

  # Top-level project metrics
  top_json=$(curl -u "$SONAR_USER:$SONAR_PASSWORD" -s "$SONAR_URL/api/measures/component?component=$PROJECT_KEY&metricKeys=coverage,line_coverage,branch_coverage")
  top_name=$(echo "$top_json" | grep -o '"name":"[^"]*"' | cut -d':' -f2 | tr -d '"')

  echo "{" > test-coverage-report.json
  echo "  \"name\": \"$top_name\"," >> test-coverage-report.json
  echo "  \"measures\": {" >> test-coverage-report.json
  echo "$top_json" | grep -o '"metric":"[^"]*","value":"[^"]*"' | \
    sed -E 's/"metric":"([^"]*)","value":"([^"]*)"/    "\1": "\2",/' | sed '$ s/,$//' >> test-coverage-report.json
  echo "  }," >> test-coverage-report.json

  echo "  \"modules\": [" >> test-coverage-report.json

  first_module=true
  for module in $modules; do
    echo "Processing module $module ..." >&2
    module_json=$(process_module "$module")

    if [[ -n "$module_json" ]]; then
      if [[ "$first_module" = true ]]; then
        first_module=false
      else
        echo "," >> test-coverage-report.json
      fi
      echo "$module_json" >> test-coverage-report.json
    fi
  done

  echo "  ]" >> test-coverage-report.json
  echo "}" >> test-coverage-report.json

  cat test-coverage-report.json
  echo "Report saved to test-coverage-report.json ✅"
}

main
