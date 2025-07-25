#!/bin/bash

# Input JSON file
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
echo "metric,value" > $DIRECTORY/summary.csv
grep -E '"lines_of_code"\s*:\s*[0-9]+' "$JSON_FILE" | sed -E 's/.*"lines_of_code"\s*:\s*([0-9]+).*/lines_of_code,\1/' >> $DIRECTORY/summary.csv
grep -E '"technical_debt_min"\s*:\s*[0-9]+' "$JSON_FILE" | sed -E 's/.*"technical_debt_min"\s*:\s*([0-9]+).*/technical_debt_min,\1/' >> $DIRECTORY/summary.csv

# 2. Issues by severity
echo "severity,count" > "$DIRECTORY/issues_by_severity.csv"

awk -v out_file="$DIRECTORY/issues_by_severity.csv" '
    /"by_severity"/ { in_section=1; next }
    in_section && /\]/ { in_section=0 }
    in_section && /"severity"/ {
        gsub(/[",]/, "", $0)
        split($0, a, ": ")
        severity=a[2]
        getline
        gsub(/[",]/, "", $0)
        split($0, b, ": ")
        count=b[2]
        print severity "," count >> out_file
    }
' "$JSON_FILE"


# 3. Issues by type
echo "type,count" > $DIRECTORY/issues_by_type.csv
awk -v out_file="$DIRECTORY/issues_by_type.csv" '
    /"by_type"/ { in_section=1; next }
    in_section && /\]/ { in_section=0 }
    in_section && /"type"/ {
        gsub(/[",]/, "", $0)
        split($0, a, ": ")
        type=a[2]
        getline
        gsub(/[",]/, "", $0)
        split($0, b, ": ")
        count=b[2]
        print type "," count >> out_file
    }
' "$JSON_FILE"

# 4. Security hotspots
echo "severity,total,category_name,category_number" > $DIRECTORY/security_hotspots.csv
awk -v out_file="$DIRECTORY/security_hotspots.csv" '
    /"security_hotspots"/ { in_hotspots=1; next }
    in_hotspots && /\]/ { in_hotspots=0 }

    in_hotspots && /"severity"/ {
        gsub(/[",]/, "", $0)
        split($0, a, ": ")
        severity=a[2]
        getline
        gsub(/[",]/, "", $0)
        split($0, b, ": ")
        total=b[2]
        # Look ahead for categories
        while ((getline line) > 0) {
            if (line ~ /"name"/) {
                gsub(/[",]/, "", line)
                split(line, c, ": ")
                cat_name=c[2]
                getline
                gsub(/[",]/, "", $0)
                split($0, d, ": ")
                cat_num=d[2]
                print severity "," total "," cat_name "," cat_num >> out_file
            }
            if (line ~ /\]/) break
        }
    }
' "$JSON_FILE"

echo "✅ CSV files generated in $DIRECTORY:
- summary.csv
- issues_by_severity.csv
- issues_by_type.csv
- security_hotspots.csv"
