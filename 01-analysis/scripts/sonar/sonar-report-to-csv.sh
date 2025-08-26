#!/bin/bash

# Input JSON file
JSON_FILE=""
DIRECTORY="./../../final-csv/sonar"

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

# Check input file
echo $JSON_FILE
if [[ -z "$JSON_FILE" || ! -f "$JSON_FILE" ]]; then
  echo "❌ Error: Provide a valid JSON file."
  echo "Usage: --json-file <json_file_path>"
  exit 1
fi

# 1. General summary
echo "metric,value" > $DIRECTORY/summary.csv
jq -r '. | to_entries[] | "\(.key),\(.value)"' $JSON_FILE | \
grep -E "lines_of_code|technical_debt_min" >> $DIRECTORY/summary.csv

# 2. Issues by severity
echo "severity,count" > $DIRECTORY/issues_by_severity.csv
jq -r '.issues.by_severity[] | "\(.severity),\(.count)"' $JSON_FILE >> $DIRECTORY/issues_by_severity.csv

# 3. Issues by type
echo "type,count" > $DIRECTORY/issues_by_type.csv
jq -r '.issues.by_type[] | "\(.type),\(.count)"' $JSON_FILE >> $DIRECTORY/issues_by_type.csv

# 4. Security hotspots
echo "severity,total,category_name,category_number" > $DIRECTORY/security_hotspots.csv
jq -r '.security_hotspots[] |
  . as $parent |
  .categories[] |
  "\($parent.severity),\($parent.total),\(.name),\(.number)"' $JSON_FILE >> $DIRECTORY/security_hotspots.csv

echo "✅ CSV files generated:
- summary.csv
- issues_by_severity.csv
- issues_by_type.csv
- security_hotspots.csv"