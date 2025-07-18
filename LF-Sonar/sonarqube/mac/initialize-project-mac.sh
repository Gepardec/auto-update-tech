#!/bin/bash
set -euo pipefail

# === Configuration / Environment Variables ===

REQUIRED_ENV_VARS=("PROJECT_ROOT" "PROJECT_KEY" "SONAR_URL" "TOKEN")

for var in "${REQUIRED_ENV_VARS[@]}"; do
  if [[ -z "${!var:-}" ]]; then
    echo "Error: Environment variable '$var' is not set."
    exit 1
  fi
done

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

# === Main Execution ===
run_sonar_analysis
