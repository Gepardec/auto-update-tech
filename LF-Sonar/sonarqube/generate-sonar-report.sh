#!/bin/bash
set -euo pipefail

# === Configuration / Environment Variables ===

REQUIRED_ENV_VARS=("SONAR_URL" "PROJECT_KEY" "TOKEN" "SONAR_USER" "SONAR_PASSWORD")

for var in "${REQUIRED_ENV_VARS[@]}"; do
  if [[ -z "${!var:-}" ]]; then
    echo "Error: Environment variable '$var' is not set."
    exit 1
  fi
done

# === Functions ===

get_lines_of_code() {
  curl -u "$TOKEN:" -s "$SONAR_URL/api/measures/component?component=$PROJECT_KEY&metricKeys=ncloc" \
    | grep -o '"value":"[0-9]\+"' | head -n1 | cut -d':' -f2 | tr -d '"'
}

get_issues() {
  curl -u "$SONAR_USER:$SONAR_PASSWORD" -s "$SONAR_URL/api/issues/search?componentKeys=$PROJECT_KEY&facets=severities,types"
}

parse_issues() {
  local json="$1"

  echo "  \"issues\": {"
  echo "    \"by_severity\": ["
  echo "$json" | grep -A100 '"property":"severities"' | grep -o '{"val":"[^"]*","count":[0-9]*}' | \
    sed 's/{/      {/' | sed 's/}/},/' | sed '$ s/},$/}/'
  echo "    ],"
  echo "    \"by_type\": ["
  echo "$json" | grep -A100 '"property":"types"' | grep -o '{"val":"[^"]*","count":[0-9]*}' | \
    sed 's/{/      {/' | sed 's/}/},/' | sed '$ s/},$/}/'
  echo "    ]"
  echo "  },"
}

get_security_hotspots() {
  curl -u "$SONAR_USER:$SONAR_PASSWORD" -s "$SONAR_URL/api/hotspots/search?component=$PROJECT_KEY&project=$PROJECT_KEY"
}

parse_security_hotspots() {
  local json="$1"

  echo "$json" | grep -oE '"vulnerabilityProbability":"[^"]+",.*?"securityCategory":"[^"]+"' | \
  sed -E 's/.*"vulnerabilityProbability":"([^"]+)".*"securityCategory":"([^"]+)".*/\1,\2/' | \
  awk -F',' '
  {
    vp=$1
    cat=$2
    total[vp]++
    key=vp "|" cat
    count[key]++
  }
  END {
    printf "  \"security_hotspots\": {\n"
    n = 0
    for (vp in total) {
      if (n++ > 0) printf ",\n"
      printf "    \"%s\": {\n", vp
      printf "      \"total\": %d,\n", total[vp]
      printf "      \"categories\": [\n"
      m = 0
      for (k in count) {
        split(k, parts, "|")
        if (parts[1] == vp) {
          if (m++ > 0) printf ",\n"
          printf "        { \"name\": \"%s\", \"number\": %d }", parts[2], count[k]
        }
      }
      printf "\n      ]\n    }"
    }
    printf "\n  }"
  }'
}


get_technical_debt() {
  curl -u "$TOKEN:" -s "$SONAR_URL/api/measures/component?component=$PROJECT_KEY&metricKeys=sqale_index" \
    | grep -o '"value":"[0-9]\+"' | head -n1 | cut -d':' -f2 | tr -d '"'
}

# === Main Execution ===
echo "Requesting lines of code (ncloc)..."
LINES_OF_CODE=$(get_lines_of_code)

echo "Requesting issues data..."
RAW_ISSUES_JSON=$(get_issues)

echo "Requesting security hotspots..."
RAW_HOTSPOTS_JSON=$(get_security_hotspots)

echo "Requesting technical debt (minutes)..."
TECH_DEBT_MIN=$(get_technical_debt)

# === Report Generation ===
echo "Generating final report..."

{
  echo "{"
  echo "  \"lines_of_code\": $LINES_OF_CODE,"
  echo "  \"technical_debt_min\": $TECH_DEBT_MIN,"
  parse_issues "$RAW_ISSUES_JSON"
  parse_security_hotspots "$RAW_HOTSPOTS_JSON"
  echo "}"
} > sonar-report.json

cat sonar-report.json

echo "Report saved to sonar-report.json ✅"
