#!/bin/bash

JSON_FILE=""
DIRECTORY="./../../final-csv/sonar"

# Parse command-line options using getopt
OPTS=$(getopt -o "" --long json-file: -- "$@")

if [ $? -ne 0 ]; then
    echo "Error parsing options."
    exit 1
fi

eval set -- "$OPTS"

while true; do
    case "$1" in
        --json-file) JSON_FILE="$2"; shift 2 ;;
        --) shift; break ;;
        *) echo "Unexpected option: $1"; exit 1 ;;
    esac
done

# Check input file
if [[ -z "$JSON_FILE" || ! -f "$JSON_FILE" ]]; then
  echo "❌ Error: Provide a valid JSON file."
  echo "Usage: --json-file <json_file_path>"
  exit 1
fi

# Ensure output directory exists
mkdir -p "$DIRECTORY"

# 1. General summary
echo "metric,value" > "$DIRECTORY/summary.csv"
grep -E '"(lines_of_code|technical_debt_min)"' "$JSON_FILE" | \
sed -E 's/[[:space:]]*"([^"]+)":[[:space:]]*"?([^",}]+)"?,?/\1,\2/' >> "$DIRECTORY/summary.csv"

# 2. Issues by severity
echo "severity,count" > "$DIRECTORY/issues_by_severity.csv"
awk '
  /"by_severity"/ { in_section=1; next }
  in_section && /]/ { in_section=0; next }
  in_section {
    if (/"severity"/) {
      gsub(/[",]/, "", $0)
      split($0, a, ":")
      severity = a[2]
    }
    if (/"count"/) {
      gsub(/[",]/, "", $0)
      split($0, b, ":")
      count = b[2]
      print severity "," count
    }
  }
' "$JSON_FILE" >> "$DIRECTORY/issues_by_severity.csv"

# 3. Issues by type
echo "type,count" > "$DIRECTORY/issues_by_type.csv"
awk '
  /"by_type"/ { in_section=1; next }
  in_section && /]/ { in_section=0; next }
  in_section {
    if (/"type"/) {
      gsub(/[",]/, "", $0)
      split($0, a, ":")
      type = a[2]
    }
    if (/"count"/) {
      gsub(/[",]/, "", $0)
      split($0, b, ":")
      count = b[2]
      print type "," count
    }
  }
' "$JSON_FILE" >> "$DIRECTORY/issues_by_type.csv"

# 4. Security hotspots
echo "severity,total,category_name,category_number" > "$DIRECTORY/security_hotspots.csv"
awk '
  /"security_hotspots"/ { in_hotspots=1; next }
  in_hotspots && /^\s*\]/ { in_hotspots=0; next }

  in_hotspots {
    if (/"severity"/) {
      gsub(/[",]/, "", $0)
      split($0, a, ":")
      severity = a[2]
    }
    if (/"total"/) {
      gsub(/[",]/, "", $0)
      split($0, b, ":")
      total = b[2]
    }
    if (/"name"/) {
      gsub(/[",]/, "", $0)
      split($0, c, ":")
      name = c[2]
    }
    if (/"number"/) {
      gsub(/[",]/, "", $0)
      split($0, d, ":")
      number = d[2]
      print severity "," total "," name "," number
    }
  }
' "$JSON_FILE" >> "$DIRECTORY/security_hotspots.csv"

echo "✅ CSV files generated in '$DIRECTORY':
- summary.csv
- issues_by_severity.csv
- issues_by_type.csv
- security_hotspots.csv"
