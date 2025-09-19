#!/bin/bash
set -euo pipefail

# === Configuration Defaults ===
export SONAR_URL="https://gepardec-sonarqube.apps.cloudscale-lpg-2.appuio.cloud"
export SONAR_USER="admin"
export SONAR_PASSWORD=""
export TOKEN_NAME="java-token"

PROJECT_ROOT=""
PROJECT_KEY=""
PROJECT_NAME=""
TOKEN=""

# === Functions ===

print_usage() {
  echo "Usage: $0 --project-root <path-to-project-root> --sonar-qube-admin-password <password>"
  exit 1
}

parse_args() {
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
        echo "❌ Unexpected option: $1"
        print_usage
        ;;
    esac
  done

  if [[ -z "$PROJECT_ROOT" || -z "$SONAR_PASSWORD" ]]; then
    echo "❌ Error: Missing required arguments."
    print_usage
  fi

  export PROJECT_ROOT
}

extract_project_metadata() {
  echo "📦 Extracting project metadata from Gradle files..."

  # Try to read from settings.gradle(.kts) first
  if [[ -f "$PROJECT_ROOT/settings.gradle" ]]; then
    PROJECT_KEY=$(grep -E "rootProject\.name\s*=" "$PROJECT_ROOT/settings.gradle" | sed -E 's/.*=\s*"([^"]+)".*/\1/' | head -n 1)
  elif [[ -f "$PROJECT_ROOT/settings.gradle.kts" ]]; then
    PROJECT_KEY=$(grep -E "rootProject\.name\s*=" "$PROJECT_ROOT/settings.gradle.kts" | sed -E 's/.*=\s*"([^"]+)".*/\1/' | head -n 1)
  fi

  # Fallback: try to read from build.gradle(.kts)
  if [[ -z "$PROJECT_KEY" ]]; then
    if [[ -f "$PROJECT_ROOT/build.gradle" ]]; then
      PROJECT_KEY=$(grep -E "^rootProject\.name\s*=" "$PROJECT_ROOT/build.gradle" | sed -E 's/.*=\s*"([^"]+)".*/\1/' | head -n 1)
      [[ -z "$PROJECT_KEY" ]] && PROJECT_KEY=$(grep -E "^name\s*=" "$PROJECT_ROOT/build.gradle" | sed -E 's/.*=\s*"([^"]+)".*/\1/' | head -n 1)
    elif [[ -f "$PROJECT_ROOT/build.gradle.kts" ]]; then
      PROJECT_KEY=$(grep -E "^rootProject\.name\s*=" "$PROJECT_ROOT/build.gradle.kts" | sed -E 's/.*=\s*"([^"]+)".*/\1/' | head -n 1)
      [[ -z "$PROJECT_KEY" ]] && PROJECT_KEY=$(grep -E "^name\s*=" "$PROJECT_ROOT/build.gradle.kts" | sed -E 's/.*=\s*"([^"]+)".*/\1/' | head -n 1)
    fi
  fi

  # Final fallback: use directory name
  if [[ -z "$PROJECT_KEY" ]]; then
    PROJECT_KEY=$(basename "$PROJECT_ROOT")
  fi

  PROJECT_NAME="$PROJECT_KEY"

  echo "🔑 PROJECT_KEY = $PROJECT_KEY"
  echo "📛 PROJECT_NAME = $PROJECT_NAME"

  export PROJECT_KEY PROJECT_NAME
}

create_user_token() {
  TOKEN=$(curl -u "$SONAR_USER:$SONAR_PASSWORD" -s "$SONAR_URL/api/user_tokens/generate" \
    -d name="$TOKEN_NAME" | jq -r ".token")

  if [[ -z "$TOKEN" ]]; then
    echo "❌ Failed to generate token."
    echo "$TOKEN"
    exit 1
  fi

  export TOKEN
  echo "✅ Token created."
}

create_project() {
  echo "📁 Creating project '$PROJECT_KEY'..."
  curl -s -u "$TOKEN:" "$SONAR_URL/api/projects/create" \
    -d name="$PROJECT_NAME" -d project="$PROJECT_KEY"
}

associate_quality_profile() {
  echo "📎 Associating 'Sonar way' quality profile..."
  curl -s -u "$TOKEN:" "$SONAR_URL/api/qualityprofiles/add_project" \
    -d language=java -d project="$PROJECT_KEY" -d qualityProfile="Sonar way"
}

initialize_project_analysis() {
  echo "🚀 Running project analysis initialization..."
  cd "$WORKSPACE"
  source ./gradle/initialize-project-gradle.sh
}

sleep_seconds_for_results() {
  counter=$1
  echo "💤 Sleep for $counter seconds to wait on result at sonar-qube..."
  while [ $counter -gt 0 ]; do
    echo -n "$counter..."
    counter=$(( counter - 1 ))
    sleep 1
  done
  echo "$counter"
}

generate_report() {
  echo "📊 Generating Sonar report..."
  cd "$WORKSPACE"
  source ./generate-sonar-report.sh
}

generate_test_coverage() {
  echo "📊 Generating Test Coverage..."
  cd "$WORKSPACE"
  source ./gradle/generate-test-coverage-gradle.sh
}

delete_project() {
  echo "🗑️  Deleting project '$PROJECT_KEY'..."
  curl -s -u "$TOKEN:" "$SONAR_URL/api/projects/delete" \
    -d project="$PROJECT_KEY"
}

revoke_token() {
  echo "🔐 Revoking user token..."
  curl -s -u "$SONAR_USER:$SONAR_PASSWORD" "$SONAR_URL/api/user_tokens/revoke" \
    -d name="$TOKEN_NAME" > /dev/null
  echo "✅ Token revoked."
}

main() {
  WORKSPACE=$(pwd)
  parse_args "$@"
  extract_project_metadata
  create_user_token
  create_project
  associate_quality_profile
  initialize_project_analysis
  sleep_seconds_for_results 20
  generate_report
  generate_test_coverage
  delete_project
  revoke_token
}

# === Entry Point ===
main "$@"
