#!/bin/bash
set -euo pipefail

# === Configuration / Environment Variables ===
REQUIRED_ENV_VARS=("PROJECT_ROOT" "PROJECT_KEY" "SONAR_URL" "TOKEN")
temp_files=()

for var in "${REQUIRED_ENV_VARS[@]}"; do
  if [[ -z "${!var:-}" ]]; then
    echo "❌ Error: Environment variable '$var' is not set."
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

  echo "📦 Backing up original pom.xml..."
  cp pom.xml pom.xml.bak || {
    echo "❌ Error backing up pom.xml"
    return 1
  }

  temp_file=$(mktemp)
  temp_files+=("$temp_file")

  if grep -q "<plugins>" pom.xml; then
    echo "🔧 Inserting JaCoCo plugin into existing <plugins>..."
    awk -v plugin_file="$plugin_file" '
      /<\/plugins>/ {
        while ((getline line < plugin_file) > 0) print line
        close(plugin_file)
        print
        next
      }
      { print }
    ' pom.xml > "$temp_file"
  else
    echo "🔧 Adding new <build> and <plugins> section with JaCoCo plugin..."
    awk -v plugin_file="$plugin_file" '
      /<\/project>/ {
        print "  <build>"
        print "    <plugins>"
        while ((getline line < plugin_file) > 0) print line
        close(plugin_file)
        print "    </plugins>"
        print "  </build>"
      }
      { print }
    ' pom.xml > "$temp_file"
  fi

  if [ ! -s "$temp_file" ]; then
    echo "❌ Error: Modified pom.xml is empty!"
    return 1
  fi

  mv "$temp_file" pom.xml || {
    echo "❌ Error replacing original pom.xml"
    return 1
  }

  # Remove used temp_file from list
  temp_files=("${temp_files[@]/$temp_file}")
}

run_sonar_analysis() {
  echo "🧪 Running SonarQube analysis..."
#  cd "$PROJECT_ROOT" || exit 1

  mvn clean verify sonar:sonar \
    -Dsonar.projectKey="$PROJECT_KEY" \
    -Dsonar.host.url="$SONAR_URL" \
    -Dsonar.token="$TOKEN"

  echo "✅ SonarQube analysis complete."
}

cleanup_pom() {
  echo "♻️ Cleaning up..."

  if [ -f "pom.xml.bak" ]; then
    mv pom.xml.bak pom.xml || {
      echo "⚠️ Warning: Could not restore original pom.xml"
    }
  else
    echo "⚠️ Warning: Backup pom.xml.bak not found"
  fi

  for file in "${temp_files[@]}"; do
    [ -f "$file" ] && rm -f "$file"
  done

  [ -f "$plugin_file" ] && rm -f "$plugin_file"

  echo "🧼 Cleanup complete."
}

# === Main Execution ===
prepare_pom
run_sonar_analysis
cleanup_pom
