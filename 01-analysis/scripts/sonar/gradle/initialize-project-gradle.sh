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

# === Detect Gradle file ===
detect_gradle_file() {
  if [[ -f "$PROJECT_ROOT/build.gradle.kts" ]]; then
    echo "$PROJECT_ROOT/build.gradle.kts"
  elif [[ -f "$PROJECT_ROOT/build.gradle" ]]; then
    echo "$PROJECT_ROOT/build.gradle"
  else
    echo "❌ No build.gradle or build.gradle.kts found in $PROJECT_ROOT" >&2
    exit 1
  fi
}

# === Prepare Gradle for Sonar ===
prepare_gradle() {
  local gradle_file
  gradle_file=$(detect_gradle_file)

  echo "📄 Using Gradle file: $gradle_file"
  cd "$PROJECT_ROOT" || exit 1

  # Determine syntax style for plugins
  local jacoco_line sonar_line
  if [[ "$gradle_file" == *".kts" ]]; then
    jacoco_line='id("jacoco")'
    sonar_line='id("org.sonarqube") version "5.1.0.4882"'
  else
    jacoco_line="id 'jacoco'"
    sonar_line="id 'org.sonarqube' version '5.1.0.4882'"
  fi

  # === Add JaCoCo plugin to root if missing ===
  if ! grep -Eq 'id\s*\(?["'\'']jacoco["'\'']\)?' "$gradle_file"; then
    echo "ℹ️ Adding JaCoCo plugin to root..."
    cp "$gradle_file" "$gradle_file.bak" || exit 1
    temp_file=$(mktemp)
    temp_files+=("$temp_file")

    awk -v jacoco="$jacoco_line" '
      BEGIN { inserted=0 }
      /^plugins\s*[{]/ {
        print
        print "    " jacoco
        inserted=1
        next
      }
      { print }
      END {
        if (inserted == 0) {
          print "plugins {"
          print "    " jacoco
          print "}"
        }
      }
    ' "$gradle_file" > "$temp_file"

    mv "$temp_file" "$gradle_file"
  fi

  # === Add SonarQube plugin if missing ===
  if ! grep -Eq 'id\s*\(?["'\'']org\.sonarqube["'\'']\)?' "$gradle_file"; then
    echo "ℹ️ Adding SonarQube plugin..."
    temp_file=$(mktemp)
    temp_files+=("$temp_file")

    awk -v sonar="$sonar_line" '
      BEGIN { inserted=0 }
      /^plugins\s*[{]/ {
        print
        print "    " sonar
        inserted=1
        next
      }
      { print }
      END {
        if (inserted == 0) {
          print "plugins {"
          print "    " sonar
          print "}"
        }
      }
    ' "$gradle_file" > "$temp_file"

    mv "$temp_file" "$gradle_file"
  fi

  # === Add subprojects JaCoCo plugin safely ===
  if ! grep -q 'subprojects {.*jacoco' "$gradle_file"; then
    echo "ℹ️ Applying JaCoCo plugin to subprojects..."
    if [[ "$gradle_file" == *".kts" ]]; then
      cat << 'EOF' >> "$gradle_file"

subprojects {
    apply(plugin = "jacoco")
}
EOF
    else
      cat << 'EOF' >> "$gradle_file"

subprojects {
    apply plugin: 'jacoco'
}
EOF
    fi
  fi

  # === Add updated root aggregated Jacoco report ===
  echo "ℹ️ Adding root aggregated Jacoco report..."
  if [[ "$gradle_file" == *".kts" ]]; then
    cat << 'EOF' >> "$gradle_file"

tasks.register<JacocoReport>("jacocoRootReport") {
    // Include both root project and subprojects
    val allProjects = listOf(project) + subprojects

    // Make sure all test tasks run before generating the report
    dependsOn(allProjects.map { it.tasks.named("test") })

    reports {
        xml.required.set(true)
        html.required.set(true)
    }

    // Collect sources and execution data
    val classDirs = files()
    val execData = files()

    allProjects.forEach { proj ->
        val sourceSets = proj.extensions.getByName("sourceSets") as SourceSetContainer
        classDirs.from(sourceSets["main"].output)
        execData.from(fileTree(proj.buildDir).include("jacoco/test.exec"))
    }

    classDirectories.setFrom(classDirs)
    executionData.setFrom(execData)
}
EOF
  else
    cat << 'EOF' >> "$gradle_file"

task jacocoRootReport(type: JacocoReport) {
    def allProjects = [project] + subprojects
    dependsOn allProjects.collect { it.tasks.test }

    reports {
        xml.required = true
        html.required = true
    }

    def classDirs = files()
    def execData = files()

    allProjects.each { proj ->
        classDirs.from(proj.sourceSets.main.output)
        execData.from(fileTree(proj.buildDir).include('jacoco/test.exec'))
    }

    classDirectories.setFrom(classDirs)
    executionData.setFrom(execData)
}
EOF
  fi
}

# === Run SonarQube Analysis ===
run_sonar_analysis() {
  echo "🧪 Running SonarQube analysis..."
  cd "$PROJECT_ROOT" || exit 1

  JACOCO_XML="$PROJECT_ROOT/build/reports/jacoco/jacocoRootReport/jacocoRootReport.xml"

  echo "📊 Running tests and generating Jacoco coverage report..."
  gradle clean test jacocoRootReport

  if [[ ! -f "$JACOCO_XML" ]]; then
    echo "❌ Error: Jacoco XML report not found at $JACOCO_XML"
    exit 1
  fi
  echo "✅ Jacoco XML report generated at: $JACOCO_XML"

  echo "🔍 Running SonarQube analysis using generated Jacoco report..."
  gradle clean test jacocoRootReport sonar \
    -Dsonar.projectKey="$PROJECT_KEY" \
    -Dsonar.host.url="$SONAR_URL" \
    -Dsonar.token="$TOKEN" \
    -Dsonar.coverage.jacoco.xmlReportPaths="$JACOCO_XML"

  echo "✅ SonarQube analysis complete."
}

# === Cleanup Gradle changes ===
cleanup_gradle() {
  echo "🧹 Cleaning up..."
  local gradle_file
  gradle_file=$(detect_gradle_file)

  if [[ -f "$gradle_file.bak" ]]; then
    mv "$gradle_file.bak" "$gradle_file" || {
      echo "⚠️ Warning: Could not restore $gradle_file"
    }
  else
    echo "⚠️ Warning: No backup found for $gradle_file"
  fi

  for file in "${temp_files[@]}"; do
    [[ -f "$file" ]] && rm -f "$file"
  done

  echo "Cleanup finished."
}

# === Main Execution ===
prepare_gradle
run_sonar_analysis
cleanup_gradle
echo "Initialization of Gradle Sonar finished."
