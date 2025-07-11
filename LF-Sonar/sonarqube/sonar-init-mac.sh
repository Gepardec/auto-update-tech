#!/bin/bash

SONAR_URL="https://gepardec-sonarqube.apps.cloudscale-lpg-2.appuio.cloud"
SONAR_USER="admin"
SONAR_PASSWORD=""
PROJECT_KEY=""
PROJECT_NAME=""
TOKEN_NAME="java-token"
PROJECT_ROOT=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --project-root)
            PROJECT_ROOT="$2"
            shift 2
            ;;
        --sonar-qube-admin-password)
            SONAR_PASSWORD="$2"
            shift 2
            ;;
        *)
            echo "Unexpected option: $1"
            exit 1
            ;;
    esac
done

# Check if all required arguments are provided
if [ -z "$PROJECT_ROOT" ] || [ -z "$SONAR_PASSWORD"]; then
    echo "Error: All arguments must be provided."
    echo "Usage: --project-root <path-to-project-root> --sonar-qube-admin-password"
    exit 1
fi

temp_files=()
plugin_file=$(mktemp)

temp_files+=("$plugin_file")
cat << 'EOF' > "$plugin_file"
            <plugin>
                <groupId>org.sonarsource.scanner.maven</groupId>
                <artifactId>sonar-maven-plugin</artifactId>
                <version>5.1.0.4751</version>
            </plugin>
EOF

cd $PROJECT_ROOT

PROJECT_KEY=$(mvn help:evaluate -f ./pom.xml -Dexpression=project.artifactId -q -DforceStdout)
PROJECT_NAME=$(mvn help:evaluate -f ./pom.xml -Dexpression=project.artifactId -q -DforceStdout)

# Check if sonar-maven-plugin is already present in pom.xml
if grep -A 10 "org.sonarsource.scanner.maven:sonar-maven-plugin" pom.xml; then
    echo "sonar-maven-plugin mit der gleichen Konfiguration bereits in pom.xml vorhanden, überspringe Änderung"
else
    echo "Füge sonar-maven-plugin zu pom.xml hinzu..."

    # Create backup of pom.xml
    cp pom.xml pom.xml.bak || {
        echo "Fehler beim Erstellen eines Backups der pom.xml"
        cd - > /dev/null
        exit 1
    }

    # Create new temp pom.xml
    temp_file=$(mktemp)
    temp_files+=("$temp_file")

    # Search for <plugins> and add plugin
    if grep -q "<plugins>" pom.xml; then
        awk -v plugin_file="$plugin_file" '
            /<\/plugins>/ {
                while ((getline line < plugin_file) > 0) {
                    print line
                }
                close(plugin_file)
                print
                next
            }
            { print }
        ' pom.xml > "$temp_file" || {
            echo "Fehler beim Bearbeiten der pom.xml mit awk"
            cd - > /dev/null
            exit 1
        }
    else
        awk -v plugin_file="$plugin_file" '
            /<\/project>/ {
                print "    <build>"
                print "        <plugins>"
                while ((getline line < plugin_file) > 0) {
                    print line
                }
                close(plugin_file)
                print "        </plugins>"
                print "    </build>"
            }
            { print }
        ' pom.xml > "$temp_file" || {
            echo "Fehler beim Bearbeiten der pom.xml mit awk"
            cd - > /dev/null
            exit 1
        }
    fi

    # Check if temp file is not empty
    if [ ! -s "$temp_file" ]; then
        echo "Fehler: Temporäre pom.xml ist leer"
        cd - > /dev/null
        exit 1
    fi

    # Replace original with modified pom
    mv "$temp_file" pom.xml || {
        echo "Fehler beim Aktualisieren der pom.xml"
        cd - > /dev/null
        exit 1
    }
    temp_files=("${temp_files[@]/$temp_file}")
fi

echo "🔐 Creating user token..."
TOKEN=$(curl -u $SONAR_USER:"$SONAR_PASSWORD" -s "$SONAR_URL/api/user_tokens/generate" \
  -d name="$TOKEN_NAME" | jq -r ".token")
echo $TOKEN

echo "📁 Creating project..."
curl -s -u $TOKEN: "$SONAR_URL/api/projects/create" \
  -d name="$PROJECT_NAME" -d project="$PROJECT_KEY"

echo "📎 Associating 'Sonar way' to project..."
curl -s -u $TOKEN: "$SONAR_URL/api/qualityprofiles/add_project" \
  -d language=java -d project="$PROJECT_KEY" -d qualityProfile="Sonar way"


cd $PROJECT_ROOT

echo "🧪 Running SonarQube analysis..."
mvn clean verify sonar:sonar \
  -Dsonar.projectKey=$PROJECT_KEY \
  -Dsonar.host.url=$SONAR_URL \
  -Dsonar.token="$TOKEN"

# restore original pom.xml
if [ -f "pom.xml.bak" ]; then
    mv pom.xml.bak pom.xml || {
        echo "Warnung: Konnte pom.xml nicht wiederherstellen"
    }
else
    echo "Warnung: pom.xml.bak nicht gefunden, kann nicht wiederhergestellt werden"
fi

cd ..

echo "Making ncloc request"
LINES_OF_CODE=$(curl -u $TOKEN: -s "$SONAR_URL/api/measures/component?component=multi-module-issues&metricKeys=ncloc" | jq -r ".component.measures[0].value")

echo "Making issues request"
ISSUES=$(curl -u $SONAR_USER:$SONAR_PASSWORD -s "$SONAR_URL/api/issues/search?component=multi-module-issues&facets=severities,types" | jq -r ".facets")

echo "Security hotspots"
SECURITY_HOTSPOTS=$(curl -u $SONAR_USER:$SONAR_PASSWORD -s "$SONAR_URL/api/hotspots/search?component=multi-module-issues&project=$PROJECT_KEY" | jq '.hotspots
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
echo $REPORT | jq >> sonar-report.json

echo "🔐 Revoking user token..."
TOKEN=$(curl -u $SONAR_USER:"$SONAR_PASSWORD" -s "$SONAR_URL/api/user_tokens/revoke" \
  -d name="$TOKEN_NAME")
echo $TOKEN

# Clean up temporary plugin file
rm -f "$plugin_file"
temp_files=("${temp_files[@]/$plugin_file}")

#echo "📎 Associating '$NEW_PROFILE_NAME' to project..."
#curl -s -u $TOKEN: "$SONAR_URL/api/qualityprofiles/add_project" \
#  -d language=java -d project="$PROJECT_KEY" -d qualityProfile="$NEW_PROFILE_NAME"
#
#echo "✅ Done. Project '$PROJECT_KEY' now uses '$NEW_PROFILE_NAME' (Java)."
#echo "🔑 Token: $TOKEN"
#
#
#curl -s -u admin:AdminAdmin123! "http://localhost:9000/api/components/tree?component=multi-module-project&qualifiers=DIR" | jq -r '.components[].key' | grep -E '^multi-module-project:[^/]+$