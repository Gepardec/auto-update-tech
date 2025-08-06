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
    | jq -r '.component.measures[0].value'
}

get_issues() {
  curl -u "$SONAR_USER:$SONAR_PASSWORD" -s "$SONAR_URL/api/issues/search?componentKeys=$PROJECT_KEY&facets=severities,types" \
    | jq -r '.facets'
}

get_security_hotspots() {
  curl -u "$SONAR_USER:$SONAR_PASSWORD" -s "$SONAR_URL/api/hotspots/search?component=$PROJECT_KEY&project=$PROJECT_KEY" | \
    jq '  .hotspots
        | group_by(.vulnerabilityProbability)
        | map({
            (.[0].vulnerabilityProbability): {
              total: length,
              categories: (
                group_by(.securityCategory)
                | map({
                    name: .[0].securityCategory,
                    number: length
                  })
              )
            }
          })
        | add'
}

get_technical_debt() {
  curl -u "$TOKEN:" -s "$SONAR_URL/api/measures/component?component=$PROJECT_KEY&metricKeys=sqale_index" \
    | jq -r '.component.measures[0].value'
}

sleep_seconds_for_results() {
  counter=$1
  echo "💤 Sleep for $counter seconds to wait on result at sonar-qube..."
  while [ $counter -gt 0 ]
  do
    echo -n "$counter..."
    counter=$(( counter - 1 ))
    sleep 1
  done
  echo "$counter"
}

# === Main Execution ===
echo "Requesting lines of code (ncloc)..."
LINES_OF_CODE=$(get_lines_of_code)
result=$((($LINES_OF_CODE / 1000)-10))
if [ "$LINES_OF_CODE" -gt 10000 ]; then
  sleep_seconds_for_results "$result"
fi

echo "Requesting issues data..."
ISSUES=$(get_issues)
echo "Requesting security hotspots..."
SECURITY_HOTSPOTS=$(get_security_hotspots)
echo "Requesting technical debt (minutes)..."
TECH_DEBT_MIN=$(get_technical_debt)

# === Report Generation ===

echo "Generating final report..."

REPORT=$(jq -n \
  --arg loc "$LINES_OF_CODE" \
  --argjson issues "$ISSUES" \
  --argjson sec "$SECURITY_HOTSPOTS" \
  --arg td "$TECH_DEBT_MIN" '
{
  lines_of_code: ($loc | tonumber),
  technical_debt_min: ($td | tonumber),
  issues: {
    by_severity: ($issues[] | select(.property=="severities") | .values | map({severity: .val, count: .count})),
    by_type: ($issues[] | select(.property=="types") | .values | map({type: .val, count: .count}))
  },
  security_hotspots: (
    $sec | to_entries | map({
      severity: .key,
      total: .value.total,
      categories: .value.categories
    })
  )
}
')

echo "$REPORT" | jq
echo "$REPORT" | jq > sonar-report.json

echo "Report saved to sonar-report.json ✅"
