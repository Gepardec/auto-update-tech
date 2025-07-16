#!/bin/bash

set -e

# --- Parse args ---
while [[ "$#" -gt 0 ]]; do
  case $1 in
    --project-root) PROJECT_ROOT="$2"; shift ;;
    --sonar-qube-admin-password) ADMIN_PWD="$2"; shift ;;
    *) echo "Unknown parameter passed: $1"; exit 1 ;;
  esac
  shift
done

if [[ -z "$PROJECT_ROOT" || -z "$ADMIN_PWD" ]]; then
  echo "Usage: $0 --project-root <path> --sonar-qube-admin-password <password>"
  exit 1
fi

# --- Variables ---
SONAR_URL="https://gepardec-sonarqube.apps.cloudscale-lpg-2.appuio.cloud"
ADMIN_USER="admin"
SONAR_PROJECT_KEY=""
SONAR_PROJECT_NAME=""
SONAR_ORG="default"
SONAR_PROFILE="Sonar way"

cd "$PROJECT_ROOT"

SONAR_PROJECT_KEY=$(mvn help:evaluate -f ./pom.xml -Dexpression=project.artifactId -q -DforceStdout)
SONAR_PROJECT_NAME=$(mvn help:evaluate -f ./pom.xml -Dexpression=project.artifactId -q -DforceStdout)

echo "↳ Adding sonar‑maven‑plugin to pom.xml …"

echo "🔐 Generating user token …"
TOKEN_NAME="ci-token-$(date +%s)"
SONAR_TOKEN=$(curl -s -u "$ADMIN_USER:$ADMIN_PWD" \
  -X POST "$SONAR_URL/api/user_tokens/generate" \
  -d "name=$TOKEN_NAME" | sed -n 's/.*"token":"\([^"]*\)".*/\1/p')

if [[ -z "$SONAR_TOKEN" ]]; then
  echo "❌ Failed to generate token. Check credentials."
  exit 1
fi

echo "📁 Creating project (if not exists) …"
curl -s -u "$ADMIN_USER:$ADMIN_PWD" -X POST "$SONAR_URL/api/projects/create" \
  -d "project=$SONAR_PROJECT_KEY" \
  -d "name=$SONAR_PROJECT_NAME" \
  -d "organization=$SONAR_ORG" \
  > /dev/null || true

echo "📎 Applying '$SONAR_PROFILE' profile …"
curl -s -u "$ADMIN_USER:$ADMIN_PWD" \
  "$SONAR_URL/api/qualityprofiles/add_project" \
  -d "language=java" \
  -d "project=$SONAR_PROJECT_KEY" \
  -d "qualityProfile=$SONAR_PROFILE" \
  > /dev/null

echo "🧪 Running analysis …"
mvn clean verify sonar:sonar \
  -Dsonar.host.url="$SONAR_URL" \
  -Dsonar.login="$SONAR_TOKEN" \
  -Dsonar.projectKey="$SONAR_PROJECT_KEY" \
  -Dsonar.projectName="$SONAR_PROJECT_NAME"

# --- Report Collection Section ---
echo "📊 Collecting report metrics..."

sleep 5

# 1. Lines of Code (ncloc)
echo "➡️  Fetching ncloc..."
LINES_OF_CODE=$(curl -s -u "$SONAR_TOKEN:" "$SONAR_URL/api/measures/component?component=$SONAR_PROJECT_KEY&metricKeys=ncloc" \
  | grep -o '"value":"[0-9]*"' | grep -o '[0-9]*')

# 2. Issues by severity/type
echo "➡️  Fetching issues..."
ISSUES_RAW=$(curl -s -u "$ADMIN_USER:$ADMIN_PWD" "$SONAR_URL/api/issues/search?component=$SONAR_PROJECT_KEY&facets=severities,types")

SEVERITIES=$(echo "$ISSUES_RAW" | grep -oE '"property":"severities".*?\[(.*?)\]' | grep -oE '"val":"[^"]+","count":[0-9]+' | sed 's/"val":"\([^"]\+\)","count":\([0-9]\+\)/{"severity":"\1","count":\2}/g' | paste -sd "," -)
TYPES=$(echo "$ISSUES_RAW" | grep -oE '"property":"types".*?\[(.*?)\]' | grep -oE '"val":"[^"]+","count":[0-9]+' | sed 's/"val":"\([^"]\+\)","count":\([0-9]\+\)/{"type":"\1","count":\2}/g' | paste -sd "," -)

# 3. Security Hotspots
echo "➡️  Fetching security hotspots..."
HOTSPOTS_RAW=$(curl -s -u "$ADMIN_USER:$ADMIN_PWD" "$SONAR_URL/api/hotspots/search?component=$SONAR_PROJECT_KEY&project=$SONAR_PROJECT_KEY")

SECURITY_HOTSPOTS=$(echo "$HOTSPOTS_RAW" | grep -oE '"vulnerabilityProbability":"[^"]+"' | cut -d'"' -f4 | sort | uniq -c | awk '{printf("{\"severity\":\"%s\",\"total\":%s},", $2, $1)}' | sed 's/,$//')

# 4. Technical Debt (min)
echo "➡️  Fetching technical debt..."
TECH_DEBT=$(curl -s -u "$SONAR_TOKEN:" "$SONAR_URL/api/measures/component?component=$SONAR_PROJECT_KEY&metricKeys=sqale_index" | grep -o '"value":"[0-9]*"' | grep -o '[0-9]*')

# --- Combine JSON ---
echo "📝 Building report..."
REPORT=$(cat <<EOF
{
  "lines_of_code": $LINES_OF_CODE,
  "technical_debt_min": $TECH_DEBT,
  "issues": {
    "by_severity": [ $SEVERITIES ],
    "by_type": [ $TYPES ]
  },
  "security_hotspots": [ $SECURITY_HOTSPOTS ]
}
EOF
)

echo "$REPORT" | tee sonar-report.json

echo "❌ Delete project (if exists)..."
curl -s -u "$ADMIN_USER:$ADMIN_PWD" -X POST "$SONAR_URL/api/projects/delete" \
  -d "project=$SONAR_PROJECT_KEY" \
  > /dev/null || true


# --- Revoke Token ---
echo "🔐 Revoking user token..."
curl -s -u "$ADMIN_USER:$ADMIN_PWD" -X POST "$SONAR_URL/api/user_tokens/revoke" -d name="$TOKEN_NAME" > /dev/null

echo "✅ Report completed. Saved as sonar-report.json"
