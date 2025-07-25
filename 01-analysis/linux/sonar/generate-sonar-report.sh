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

# === API calls and saving raw responses to files ===

echo "Requesting lines of code (ncloc)..."
curl -u "$TOKEN:" -s "$SONAR_URL/api/measures/component?component=$PROJECT_KEY&metricKeys=ncloc" > ncloc.json

echo "Requesting issues data..."
curl -u "$SONAR_USER:$SONAR_PASSWORD" -s "$SONAR_URL/api/issues/search?componentKeys=$PROJECT_KEY&facets=severities,types" > issues.json

echo "Requesting security hotspots..."
curl -u "$SONAR_USER:$SONAR_PASSWORD" -s "$SONAR_URL/api/hotspots/search?component=$PROJECT_KEY&project=$PROJECT_KEY" > hotspots.json

echo "Requesting technical debt (minutes)..."
curl -u "$TOKEN:" -s "$SONAR_URL/api/measures/component?component=$PROJECT_KEY&metricKeys=sqale_index" > techdebt.json


# === Processing with Python (no jq required) ===

python3 <<EOF
import json

with open("ncloc.json") as f:
    ncloc_json = json.load(f)

with open("techdebt.json") as f:
    techdebt_json = json.load(f)

with open("issues.json") as f:
    issues_json = json.load(f)

with open("hotspots.json") as f:
    hotspots_json = json.load(f)

# Parse basic values
lines_of_code = int(ncloc_json.get("component", {}).get("measures", [{}])[0].get("value", 0))
tech_debt_min = int(techdebt_json.get("component", {}).get("measures", [{}])[0].get("value", 0))

# Parse issues
issues = {"by_severity": [], "by_type": []}
for facet in issues_json.get("facets", []):
    key = facet.get("property")
    if key == "severities":
        issues["by_severity"] = [
            {"severity": v["val"], "count": v["count"]}
            for v in facet.get("values", [])
        ]
    elif key == "types":
        issues["by_type"] = [
            {"type": v["val"], "count": v["count"]}
            for v in facet.get("values", [])
        ]

# Parse security hotspots
hotspots_by_severity = {}
for h in hotspots_json.get("hotspots", []):
    severity = h.get("vulnerabilityProbability")
    category = h.get("securityCategory")
    if severity not in hotspots_by_severity:
        hotspots_by_severity[severity] = {"total": 0, "categories": {}}
    hotspots_by_severity[severity]["total"] += 1
    if category not in hotspots_by_severity[severity]["categories"]:
        hotspots_by_severity[severity]["categories"][category] = 0
    hotspots_by_severity[severity]["categories"][category] += 1

security_hotspots = []
for severity, data in hotspots_by_severity.items():
    security_hotspots.append({
        "severity": severity,
        "total": data["total"],
        "categories": [
            {"name": cat, "number": count}
            for cat, count in data["categories"].items()
        ]
    })

# Final report
report = {
    "lines_of_code": lines_of_code,
    "technical_debt_min": tech_debt_min,
    "issues": issues,
    "security_hotspots": security_hotspots
}

with open("sonar-report.json", "w") as f:
    json.dump(report, f, indent=2)

print(json.dumps(report, indent=2))
EOF

rm ncloc.json issues.json hotspots.json techdebt.json


echo "Report saved to sonar-report.json ✅"
