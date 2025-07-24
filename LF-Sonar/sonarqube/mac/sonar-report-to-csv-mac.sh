#!/bin/bash

# Input JSON file
JSON_FILE=""
DIRECTORY="./../final-csv"

# Parse command-line options using getopt
#OPTS=$(getopt -o "" --long json-file: -- "$@")
#
#if [ $? -ne 0 ]; then
#    echo "Error parsing options."
#    exit 1
#fi
#
#eval set -- "$OPTS"

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

shift

# Check input file
echo $JSON_FILE
if [[ -z "$JSON_FILE" || ! -f "$JSON_FILE" ]]; then
  echo "❌ Error: Provide a valid JSON file."
  echo "Usage: --json-file <json_file_path>"
  exit 1
fi

# 1. General summary
echo "metric,value" > summary.csv
jq -r '. | to_entries[] | "\(.key),\(.value)"' $INPUT_JSON | \
grep -E "lines_of_code|technical_debt_min" >> summary.csv

# 2. Issues by severity
echo "severity,count" > issues_by_severity.csv
jq -r '.issues.by_severity[] | "\(.severity),\(.count)"' $INPUT_JSON >> issues_by_severity.csv

# 3. Issues by type
echo "type,count" > issues_by_type.csv
jq -r '.issues.by_type[] | "\(.type),\(.count)"' $INPUT_JSON >> issues_by_type.csv

# 4. Security hotspots
echo "severity,total,category_name,category_number" > security_hotspots.csv
jq -r '.security_hotspots[] |
  . as $parent |
  .categories[] |
  "\($parent.severity),\($parent.total),\(.name),\(.number)"' $INPUT_JSON >> security_hotspots.csv

echo "✅ CSV files generated:
- summary.csv
- issues_by_severity.csv
- issues_by_type.csv
- security_hotspots.csv"