#!/bin/bash

# ================================
# Script: generate_all_csvs.sh
# Purpose: Convert a given JSON file into multiple CSVs
# Dependencies: python3
# Usage:
#   ./generate_all_csvs.sh <json_file> [function]
# ================================

JSON_FILE=""
DIRECTORY="./../final-csv"

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

# Check for python3
if ! command -v python3 &> /dev/null; then
  echo "❌ Error: 'python3' is required but not installed."
  exit 1
fi

mkdir -p "$DIRECTORY"

# ================================
# Function: main_artifacts
# ================================
main_artifacts() {
python3 - <<EOF
import json, csv
with open("$JSON_FILE") as f:
    data = json.load(f)
with open("$DIRECTORY/main_artifacts.csv", "w", newline='') as out:
    writer = csv.writer(out)
    writer.writerow(["groupId", "artifactId", "version", "scope", "lastUpdatedDate"])
    for item in data:
        writer.writerow([
            item.get("groupId", ""),
            item.get("artifactId", ""),
            item.get("version", ""),
            item.get("scope", ""),
            item.get("lastUpdatedDate", "")
        ])
EOF
echo "✓ main_artifacts.csv"
}

# ================================
# Function: relocations
# ================================
relocations() {
python3 - <<EOF
import json, csv
with open("$JSON_FILE") as f:
    data = json.load(f)
with open("$DIRECTORY/relocations.csv", "w", newline='') as out:
    writer = csv.writer(out)
    writer.writerow([
        "groupId", "artifactId", "lastUpdatedDate",
        "relocationGroupId", "relocationArtifactId", "relocationLastUpdatedDate"
    ])
    for item in data:
        for r in item.get("relocations", []):
            writer.writerow([
                item.get("groupId", ""),
                item.get("artifactId", ""),
                item.get("lastUpdatedDate", ""),
                r.get("groupId", ""),
                r.get("artifactId", ""),
                r.get("lastUpdatedDate", "")
            ])
EOF
echo "✓ relocations.csv"
}

# ================================
# Function: vulnerabilities
# ================================
vulnerabilities() {
python3 - <<EOF
import json, csv

with open("$JSON_FILE") as f:
    data = json.load(f)

with open("$DIRECTORY/vulnerabilities.csv", "w", newline='') as out:
    writer = csv.writer(out)
    writer.writerow(["groupId", "artifactId", "vulnId", "severity", "epssScore", "description"])
    for item in data:
        for vuln in item.get("vulnerabilities", []):
            writer.writerow([
                item.get("groupId", ""),
                item.get("artifactId", ""),
                vuln.get("vulnId", ""),
                vuln.get("severity", ""),
                str(vuln.get("epssScore", "")),
                vuln.get("description", "").replace('\n', ' ')
            ])

with open("$DIRECTORY/vulnerability_summary.csv", "w", newline='') as out:
    writer = csv.writer(out)
    writer.writerow([
        "groupId", "artifactId",
        "numberOfCritical", "numberOfHigh", "numberOfMedium",
        "numberOfLow", "numberOfUnassigned"
    ])
    for item in data:
        vulns = item.get("vulnerabilities", [])
        sev_count = {
            "CRITICAL": 0,
            "HIGH": 0,
            "MEDIUM": 0,
            "LOW": 0,
            "UNASSIGNED": 0
        }
        for v in vulns:
            sev = v.get("severity", "UNASSIGNED").upper()
            sev_count[sev] = sev_count.get(sev, 0) + 1
        writer.writerow([
            item.get("groupId", ""),
            item.get("artifactId", ""),
            sev_count["CRITICAL"],
            sev_count["HIGH"],
            sev_count["MEDIUM"],
            sev_count["LOW"],
            sev_count["UNASSIGNED"]
        ])
EOF
echo "✓ vulnerabilities.csv"
echo "✓ vulnerability_summary.csv"
}

# ================================
# Function: new_versions
# ================================
new_versions() {
python3 - <<EOF
import json, csv

with open("$JSON_FILE") as f:
    data = json.load(f)

with open("$DIRECTORY/new_versions.csv", "w", newline='') as out:
    writer = csv.writer(out)
    writer.writerow(["groupId", "artifactId", "version", "updateType", "major", "nonMajor"])
    for item in data:
        for new in item.get("newVersions", []):
            writer.writerow([
                item.get("groupId", ""),
                item.get("artifactId", ""),
                item.get("version", ""),
                new.get("updateType", ""),
                new.get("major", ""),
                new.get("non-major", "")
            ])
EOF
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
  new_versions
  echo "🎉 All CSVs generated successfully."
}

# ================================
# Entry Point
# ================================
if [[ $# -eq 0 ]]; then
  createAll
else
  "$@"
fi
