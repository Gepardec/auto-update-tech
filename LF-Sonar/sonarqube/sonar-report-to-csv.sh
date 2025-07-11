#!/bin/bash

# Input JSON file
INPUT_JSON="sonar-report.json"

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