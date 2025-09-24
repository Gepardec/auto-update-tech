#!/bin/bash

# ================================
# Script: generate_all_csvs.sh
# Purpose: Convert a given JSON file into multiple CSVs
# Compatible with: macOS (uses awk for headers)
# Dependencies: jq
# Usage:
#   ./generate_all_csvs.sh <json_file> [function]
#   Example:
#     ./generate_all_csvs.sh plain.json         # runs createAll
#     ./generate_all_csvs.sh plain.json vulnerabilities
# ================================

# Input JSON file
JSON_FILE=""
DIRECTORY="./../final-csv"

mkdir -p "$DIRECTORY"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --json-file)
            JSON_FILE="$2"
            shift 2
            ;;
        *)
            echo "Unexpected option: $1"
            exit 1
            ;;
    esac
done

#shift

# Check input file
echo $JSON_FILE
if [[ -z "$JSON_FILE" || ! -f "$JSON_FILE" ]]; then
  echo "❌ Error: Provide a valid JSON file."
  echo "Usage: --json-file <json_file_path>"
  exit 1
fi

# Check for jq
if ! command -v jq &> /dev/null; then
  echo "❌ Error: 'jq' is required but not installed. Install it with 'brew install jq'."
  exit 1
fi

# ================================
# Function: main_artifacts
# ================================
main_artifacts() {
  jq -r '.[] | [.groupId, .artifactId, .version, .scope, .lastUpdatedDate] | @csv' "$JSON_FILE" \
  | awk 'BEGIN { print "\"groupId\",\"artifactId\",\"version\",\"scope\",\"lastUpdatedDate\"" } { print }' \
  > $DIRECTORY/main_artifacts.csv
  echo "✓ main_artifacts.csv"
}

# ================================
# Function: relocations
# ================================
relocations() {
  jq -r '.[] | select(.relocations != null) |
    . as $parent |
    .relocations[] |
    [$parent.groupId, $parent.artifactId, $parent.lastUpdatedDate, .groupId, .artifactId, .lastUpdatedDate] | @csv' "$JSON_FILE" \
  | awk 'BEGIN { print "\"groupId\",\"artifactId\",\"lastUpdatedDate\",\"relocationGroupId\",\"relocationArtifactId\",\"relocationLastUpdatedDate\"" } { print }' \
  > $DIRECTORY/relocations.csv
  echo "✓ relocations.csv"
}

# ================================
# Function: vulnerabilities
# ================================
vulnerabilities() {
  jq -r '.[] | select(.vulnerabilities != null) |
      . as $parent |
      .vulnerabilities[] |
      [$parent.groupId, $parent.artifactId, .vulnId, .severity, (.epssScore|tostring), (.description|gsub("\n";" "))] | @csv' "$JSON_FILE" \
    | awk 'BEGIN { print "\"groupId\",\"artifactId\",\"vulnId\",\"severity\",\"epssScore\",\"description\"" } { print }' \
    > $DIRECTORY/vulnerabilities.csv
    echo "✓ vulnerabilities.csv"

  jq -r '
    .[] |
    {groupId, artifactId, vulnerabilities} |
    .vulnerabilities as $vulns |
    {
      groupId,
      artifactId,
      numberOfCritical:   ($vulns | map(select(.severity == "CRITICAL"))   | length),
      numberOfHigh:       ($vulns | map(select(.severity == "HIGH"))       | length),
      numberOfMedium:     ($vulns | map(select(.severity == "MEDIUM"))     | length),
      numberOfLow:        ($vulns | map(select(.severity == "LOW"))        | length),
      numberOfUnassigned: ($vulns | map(select(.severity == "UNASSIGNED")) | length)
    } |
    [.groupId, .artifactId, (.numberOfCritical|tostring), (.numberOfHigh|tostring), (.numberOfMedium|tostring), (.numberOfLow|tostring), (.numberOfUnassigned|tostring)] |
    @csv
  ' "$JSON_FILE" |
  awk 'BEGIN {
    print "\"groupId\",\"artifactId\",\"numberOfCritical\",\"numberOfHigh\",\"numberOfMedium\",\"numberOfLow\",\"numberOfUnassigned\""
  } { print }' > $DIRECTORY/vulnerability_summary.csv

  echo "✓ vulnerability_summary.csv"
}

# ================================
# Function: policy_violations
# ================================
policy_violations() {
  jq -r '.[]
    | select(.policyViolations != null and (.policyViolations | length > 0))
    | . as $parent
    | .policyViolations[]
    | [.violationState, .type, .policyName, $parent.groupId, $parent.artifactId]
    | @csv' "$JSON_FILE" \
  | awk 'BEGIN { print "\"violationState\",\"type\",\"policyName\",\"groupId\",\"artifactId\"" } { print }' \
  > $DIRECTORY/policyViolations.csv

  echo "✓ policyViolations.csv"
}


# ================================
# Function: new_versions
# ================================
new_versions() {
  jq -r '.[] | select(.newVersions != null) |
    . as $parent |
    .newVersions[] |
    [$parent.groupId, $parent.artifactId, $parent.version, .updateType, .major, ."non-major"] | @csv' "$JSON_FILE" \
  | awk 'BEGIN { print "\"groupId\",\"artifactId\",\"version\",\"updateType\",\"major\",\"nonMajor\"" } { print }' \
  > $DIRECTORY/new_versions.csv
  echo "✓ new_versions.csv"
}

# ================================
# Function: createAll
# ================================
createAll() {
  echo "Generating CSVs from $JSON_FILE..."
  main_artifacts
  relocations
  vulnerabilities
  policy_violations
  new_versions
  echo "🎉 All CSVs generated successfully."
}

# ================================
# Entry point
# ================================
if [[ $# -eq 0 ]]; then
  createAll
else
  "$@"
fi
