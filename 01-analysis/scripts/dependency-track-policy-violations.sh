#!/bin/sh

TMP_FILE="/tmp/policyViolationTmp.json"
FINAL_FILE="dependency-track-policy-violations.json"

API_URL="https://gepardec-dtrack.apps.cloudscale-lpg-2.appuio.cloud/api"
PROJECT_UUID=""
API_KEY=""


while [[ $# -gt 0 ]]; do
    case "$1" in
        --project-uuid)
            PROJECT_UUID="$2"
            shift 2
            ;;
        --dependency-track-api-key)
            API_KEY="$2"
            shift 2
            ;;
        *)
            echo "Unexpected option: $1"
            exit 1
            ;;
    esac
done

# Check if all required arguments are provided
if [ -z "$PROJECT_UUID" ] || [ -z "$API_KEY" ]; then
    echo "Error: All arguments must be provided."
    echo "Usage: --project-uuid <project-uuid-from-dependency-track> --dependency-track-api-key <api-key>"
    exit 1
fi

# Fetch the JSON data into a temporary file
curl --silent --location "$API_URL/v1/violation/project/$PROJECT_UUID?pageNumber=1&pageSize=300" \
  --header "X-API-Key: $API_KEY" > "$TMP_FILE"

# If jq is available, transform JSON into desired structure
if command -v jq >/dev/null 2>&1; then
  jq '[.[] | {
    violationState: .policyCondition.policy.violationState,
    type: .type,
    policyName: .policyCondition.policy.name,
    component: {
      group: .component.group,
      name: .component.name,
      version: .component.version,
      lastBomImport: .project.lastBomImport,
      uuid: .component.uuid
    }
  }]' "$TMP_FILE" > "$FINAL_FILE"

  echo "Filtered JSON written to $FINAL_FILE"
else
  echo "Error: jq is required for proper JSON transformation."
  exit 1
fi

# Clean up temp file
rm -f "$TMP_FILE"