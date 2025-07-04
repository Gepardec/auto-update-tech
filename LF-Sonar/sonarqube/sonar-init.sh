#!/bin/bash

SONAR_URL="https://gepardec-sonarqube.apps.cloudscale-lpg-2.appuio.cloud"
ADMIN_USER="admin"
ADMIN_PASS="xxx"
PROJECT_KEY="multi-module-issues"
PROJECT_NAME="Multi Module Issues"
TOKEN_NAME="java-token"

echo "🔐 Creating user token..."
TOKEN=$(curl -u $ADMIN_USER:"$ADMIN_PASS" -s "$SONAR_URL/api/user_tokens/generate" \
  -d name="$TOKEN_NAME" | jq -r ".token")
echo $TOKEN

echo "📁 Creating project..."
curl -s -u $TOKEN: "$SONAR_URL/api/projects/create" \
  -d name="$PROJECT_NAME" -d project="$PROJECT_KEY"

echo "📎 Associating 'Sonar way' to project..."
curl -s -u $TOKEN: "$SONAR_URL/api/qualityprofiles/add_project" \
  -d language=java -d project="$PROJECT_KEY" -d qualityProfile="Sonar way"


cd multi-module-issues-project

echo "🧪 Running SonarQube analysis..."
mvn clean verify sonar:sonar \
  -Dsonar.projectKey=$PROJECT_KEY \
  -Dsonar.host.url=$SONAR_URL \
  -Dsonar.token="$TOKEN"

cd ..

echo "Making ncloc request"
LINES_OF_CODE=$(curl -u $TOKEN: -s "$SONAR_URL/api/measures/component?component=multi-module-issues&metricKeys=ncloc" | jq -r ".component.measures[0].value")

echo "Making issues request"
ISSUES=$(curl -u $ADMIN_USER:$ADMIN_PASS -s "$SONAR_URL/api/issues/search?component=multi-module-issues&facets=severities,types" | jq -r ".facets")

echo "Security hotspots"
SECURITY_HOTSPOTS=$(curl -u $ADMIN_USER:$ADMIN_PASS -s "$SONAR_URL/api/hotspots/search?component=multi-module-issues&project=$PROJECT_KEY" | jq '.hotspots
                                                                                                                              | group_by(.vulnerabilityProbability)                                                                                                                          | map({
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
                                                                                                                              | add
                                                                                                                            ')

echo "Making tech debt request"
TECH_DEBT_MIN=$(curl -u $TOKEN: -s "$SONAR_URL/api/measures/component?component=multi-module-issues&metricKeys=sqale_index" | jq -r '.component.measures[] | {technical_debt_min: .value}')

#echo $LINES_OF_CODE
#echo $ISSUES
#echo $SECURITY_HOTSPOTS
#echo $TECH_DEBT_MIN

REPORT=$(jq -n \
           --argjson loc "$LINES_OF_CODE" \
           --argjson issues "$ISSUES" \
           --argjson sec "$SECURITY_HOTSPOTS" \
           --argjson td "$TECH_DEBT_MIN" '
         {
           lines_of_code: $loc,
           technical_debt_min: ($td.technical_debt_min | tonumber),
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

echo $REPORT | jq

echo "🔐 Revoking user token..."
TOKEN=$(curl -u $ADMIN_USER:"$ADMIN_PASS" -s "$SONAR_URL/api/user_tokens/revoke" \
  -d name="$TOKEN_NAME")
echo $TOKEN


#echo "📎 Associating '$NEW_PROFILE_NAME' to project..."
#curl -s -u $TOKEN: "$SONAR_URL/api/qualityprofiles/add_project" \
#  -d language=java -d project="$PROJECT_KEY" -d qualityProfile="$NEW_PROFILE_NAME"
#
#echo "✅ Done. Project '$PROJECT_KEY' now uses '$NEW_PROFILE_NAME' (Java)."
#echo "🔑 Token: $TOKEN"
#
#
#curl -s -u admin:AdminAdmin123! "http://localhost:9000/api/components/tree?component=multi-module-project&qualifiers=DIR" | jq -r '.components[].key' | grep -E '^multi-module-project:[^/]+$