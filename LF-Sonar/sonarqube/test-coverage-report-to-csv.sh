#!/bin/bash

JSON_FILE=""
OUTPUT_DIR="./final-csv"
OUTPUT_FILE="$OUTPUT_DIR/test_coverage.csv"

# Parse command-line options
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

if [[ -z "$JSON_FILE" || ! -f "$JSON_FILE" ]]; then
  echo "❌ Error: Provide a valid JSON file."
  echo "Usage: --json-file <json_file_path>"
  exit 1
fi

mkdir -p "$OUTPUT_DIR"

# Write CSV header
echo "module,coverage,branch_coverage,line_coverage" > "$OUTPUT_FILE"

# Extract root module (project-level measures)
root_cov=$(grep -A5 '"measures"' "$JSON_FILE" | grep '"coverage"' | head -1 | sed -E 's/.*"coverage"[[:space:]]*:[[:space:]]*"([^"]*)".*/\1/')
root_branch_cov=$(grep -A5 '"measures"' "$JSON_FILE" | grep '"branch_coverage"' | head -1 | sed -E 's/.*"branch_coverage"[[:space:]]*:[[:space:]]*"([^"]*)".*/\1/')
root_line_cov=$(grep -A5 '"measures"' "$JSON_FILE" | grep '"line_coverage"' | head -1 | sed -E 's/.*"line_coverage"[[:space:]]*:[[:space:]]*"([^"]*)".*/\1/')
project_name=$(grep '"name"' "$JSON_FILE" | head -1 | sed -E 's/.*"name"[[:space:]]*:[[:space:]]*"([^"]*)".*/\1/')
echo "$project_name,$root_cov,$root_branch_cov,$root_line_cov" >> "$OUTPUT_FILE"

# Extract modules
awk -v outfile="$OUTPUT_FILE" '
/"modules"/ { in_modules = 1; next }
/]/ && in_modules { in_modules = 0; next }

in_modules {
    if ($0 ~ /"name"/) {
        gsub(/[",]/, "", $0)
        split($0, a, ":")
        module = a[2]
        cov = ""; branch_cov = ""; line_cov = ""
    }

    if ($0 ~ /"coverage"/) {
        match($0, /"coverage"[[:space:]]*:[[:space:]]*"([^"]+)"/, m)
        cov = m[1]
    }

    if ($0 ~ /"branch_coverage"/) {
        match($0, /"branch_coverage"[[:space:]]*:[[:space:]]*"([^"]+)"/, m)
        branch_cov = m[1]
    }

    if ($0 ~ /"line_coverage"/) {
        match($0, /"line_coverage"[[:space:]]*:[[:space:]]*"([^"]+)"/, m)
        line_cov = m[1]
    }

    # Emit once we close the module object
    if ($0 ~ /},?$/ && module != "") {
        print module "," cov "," branch_cov "," line_cov >> outfile
        module = ""
    }
}
' "$JSON_FILE"

echo "✅ CSV generated at: $OUTPUT_FILE"
