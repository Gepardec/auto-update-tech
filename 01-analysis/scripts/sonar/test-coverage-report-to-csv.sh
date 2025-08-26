#!/bin/bash

JSON_FILE=""
DIRECTORY="./../../final-csv/sonar"
OUTPUT_FILE="$DIRECTORY/test_coverage.csv"

# Parse options (macOS doesn't support long options with getopt)
while [ $# -gt 0 ]; do
  case "$1" in
    --json-file)
      JSON_FILE="$2"
      shift 2
      ;;
    *)
      echo "❌ Unknown option: $1"
      echo "Usage: --json-file <json_file_path>"
      exit 1
      ;;
  esac
done

# Validate input file
if [ -z "$JSON_FILE" ] || [ ! -f "$JSON_FILE" ]; then
  echo "❌ Error: Provide a valid JSON file."
  echo "Usage: --json-file <json_file_path>"
  exit 1
fi

# Ensure output directory exists
mkdir -p "$DIRECTORY"

# Write header
echo "module,coverage,branch_coverage,line_coverage" > "$OUTPUT_FILE"

# Extract project-level data
jq -r '
  [
    .name,
    (.measures.coverage // ""),
    (.measures.branch_coverage // ""),
    (.measures.line_coverage // "")
  ] | @csv
' "$JSON_FILE" >> "$OUTPUT_FILE"

# Extract module-level data
jq -r '
  .modules[] |
  [
    .name,
    (.measures.coverage // ""),
    (.measures.branch_coverage // ""),
    (.measures.line_coverage // "")
  ] | @csv
' "$JSON_FILE" >> "$OUTPUT_FILE"

echo "✅ CSV file generated at '$OUTPUT_FILE'"
