#!/bin/bash
set -euo pipefail

# === Configuration / Environment Variables ===

REQUIRED_ENV_VARS=("PROJECT_ROOT" "PROJECT_KEY" "SONAR_URL" "TOKEN")
temp_files=()

for var in "${REQUIRED_ENV_VARS[@]}"; do
  if [[ -z "${!var:-}" ]]; then
    echo "Error: Environment variable '$var' is not set."
    exit 1
  fi
done

prepare_pom() {
cd "$PROJECT_ROOT" || exit 1

plugin_file=$(mktemp)
temp_files+=("$plugin_file")
cat << 'EOF' > "$plugin_file"
            <plugin>
              <groupId>org.jacoco</groupId>
              <artifactId>jacoco-maven-plugin</artifactId>
              <version>0.8.10</version>
              <executions>
                <execution>
                  <goals>
                    <goal>prepare-agent</goal>
                  </goals>
                </execution>
                <execution>
                  <id>report</id>
                  <phase>prepare-package</phase>
                  <goals>
                    <goal>report</goal>
                  </goals>
                </execution>
              </executions>
            </plugin>
EOF

# create backup of pom.xml
cp pom.xml pom.xml.bak || {
    echo "Fehler beim Erstellen eines Backups der pom.xml"
    return
}

# create new temp pom.xml
temp_file=$(mktemp)
temp_files+=("$temp_file")

# search for <plugins> and add plugin
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
        return
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
        return
    }
fi

# check if temp file is not empty
if [ ! -s "$temp_file" ]; then
    echo "Fehler: Temporäre pom.xml ist leer"
    return
fi

# replace original with modified pom
mv "$temp_file" pom.xml || {
    echo "Fehler beim Aktualisieren der pom.xml"
    return
}
temp_files=("${temp_files[@]/$temp_file}")
}

run_sonar_analysis() {
  echo "🧪 Running SonarQube analysis..."
  echo "📍 Changing to project directory: $PROJECT_ROOT"

  cd "$PROJECT_ROOT" || exit 1

  mvn clean verify sonar:sonar \
    -Dsonar.projectKey="$PROJECT_KEY" \
    -Dsonar.host.url="$SONAR_URL" \
    -Dsonar.token="$TOKEN"

  echo "✅ SonarQube analysis complete."
}

cleanup_pom() {
# restore original pom.xml
if [ -f "pom.xml.bak" ]; then
  mv pom.xml.bak pom.xml || {
      echo "Warnung: Konnte pom.xml nicht wiederherstellen"
  }
else
  echo "Warnung: pom.xml.bak nicht gefunden, kann nicht wiederhergestellt werden"
fi

for file in "${temp_files[@]}"; do
    [ -f "$file" ] && rm -f "$file"
done
rm -f "$plugin_file"
}

# === Main Execution ===
prepare_pom
run_sonar_analysis
cleanup_pom