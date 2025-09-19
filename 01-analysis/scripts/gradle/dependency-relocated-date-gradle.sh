#!/bin/bash

PROJECT_ROOT=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --project-root)
            PROJECT_ROOT="$2"
            shift 2
            ;;
        *)
            echo "Unexpected option: $1"
            exit 1
            ;;
    esac
done

# Check if project root is provided
if [ -z "$PROJECT_ROOT" ]; then
    echo "Error: --project-root is required"
    exit 1
fi

# Ensure python3 is available
if ! command -v python3 &> /dev/null; then
    echo "Error: python3 is not installed"
    exit 1
fi

cd "$PROJECT_ROOT" || exit 1

########################################
# CREATE PYTHON SCRIPTS IF MISSING
########################################

echo "Ensuring Python helper scripts are present..."

# convert.py
if [ ! -f "$PROJECT_ROOT/convert.py" ]; then
    cat << 'EOF' > "$PROJECT_ROOT/convert.py"
import json
import sys
import re
from pathlib import Path

def parse_dependency_line(line):
    tree_symbols_pattern = r'^[\s|\\+\-]+'
    if not re.match(tree_symbols_pattern, line):
        return None
    clean_line = re.sub(tree_symbols_pattern, '', line).strip()
    if not clean_line or ':' not in clean_line:
        return None
    parts = clean_line.split("->")
    if len(parts) == 2:
        left, version = parts
        left = left.strip()
        version = version.strip()
    else:
        left = clean_line
        version = None
    coords = left.split(":")
    if len(coords) < 2:
        return None
    group_id = coords[0].strip()
    artifact_id = coords[1].strip()
    if version is None and len(coords) >= 3:
        version = coords[2].strip()
    return {"groupId": group_id, "artifactId": artifact_id, "version": version or ""}

def main():
    if len(sys.argv) != 3:
        print("Usage: python convert.py <input_file.txt> <output_file.json>")
        sys.exit(1)
    input_file = Path(sys.argv[1])
    output_file = Path(sys.argv[2])
    if not input_file.exists():
        print(f"Error: input file {input_file} does not exist.")
        sys.exit(1)
    dependencies = []
    seen = set()
    with input_file.open("r", encoding="utf-8") as f:
        for line in f:
            dep = parse_dependency_line(line)
            if dep:
                key = (dep["groupId"], dep["artifactId"], dep["version"])
                if key not in seen:
                    seen.add(key)
                    dependencies.append(dep)
    flat_json = {"dependencies": dependencies}
    with output_file.open("w", encoding="utf-8") as f:
        json.dump(flat_json, f, indent=2)
    print(f"Extracted {len(dependencies)} dependencies into {output_file}")

if __name__ == "__main__":
    main()
EOF
    echo "Created convert.py"
else
    echo "Found existing convert.py"
fi

# dated.py
if [ ! -f "$PROJECT_ROOT/dated.py" ]; then
    cat << 'EOF' > "$PROJECT_ROOT/dated.py"
import json
import sys
import urllib.request
import xml.etree.ElementTree as ET
from datetime import datetime

def get_last_updated_date(group_id, artifact_id):
    try:
        group_path = group_id.replace('.', '/')
        metadata_url = f"https://repo1.maven.org/maven2/{group_path}/{artifact_id}/maven-metadata.xml"
        with urllib.request.urlopen(metadata_url) as response:
            xml_content = response.read()
        root = ET.fromstring(xml_content)
        last_updated_elem = root.find(".//lastUpdated")
        if last_updated_elem is not None:
            raw_date = last_updated_elem.text.strip()
            return datetime.strptime(raw_date, "%Y%m%d%H%M%S").strftime("%Y-%m-%d %H:%M:%S")
        else:
            return "Unknown"
    except Exception as e:
        print(f"Could not fetch metadata for {group_id}:{artifact_id} — {e}")
        return "Unknown"

def update_dependencies_with_dates(json_file, output_file):
    with open(json_file, 'r') as f:
        data = json.load(f)
    for dependency in data.get("dependencies", []):
        dependency["lastUpdatedDate"] = get_last_updated_date(
            dependency.get("groupId", ""),
            dependency.get("artifactId", "")
        )
    with open(output_file, 'w') as f:
        json.dump(data, f, indent=4)
    print(f"Updated JSON written to {output_file}")

if __name__ == "__main__":
    if len(sys.argv) != 3:
        print("Usage: python dated.py <input_file> <output_file>")
        sys.exit(1)
    update_dependencies_with_dates(sys.argv[1], sys.argv[2])
EOF
    echo "Created dated.py"
else
    echo "Found existing dated.py"
fi

# relocated.py
if [ ! -f "$PROJECT_ROOT/relocated.py" ]; then
    cat << 'EOF' > "$PROJECT_ROOT/relocated.py"
import json
import sys

def update_dependencies_with_relocations(json_file, output_file, old_group_id, old_artifact_id, new_group_id, new_artifact_id):
    with open(json_file, 'r') as f:
        data = json.load(f)
    for dependency in data.get("dependencies", []):
        if dependency.get("groupId") == old_group_id and (old_artifact_id == "*" or dependency.get("artifactId") == old_artifact_id):
            if "relocations" not in dependency:
                dependency["relocations"] = []
            dependency["relocations"].append({"groupId": new_group_id, "artifactId": new_artifact_id})
    with open(output_file, 'w') as f:
        json.dump(data, f, indent=4)
    print(f"Updated JSON written to {output_file}")

if __name__ == "__main__":
    if len(sys.argv) != 7:
        print("Usage: python relocated.py <input_file> <output_file> <old_group_id> <old_artifact_id> <new_group_id> <new_artifact_id>")
        sys.exit(1)
    update_dependencies_with_relocations(sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4], sys.argv[5], sys.argv[6])
EOF
    echo "Created relocated.py"
else
    echo "Found existing relocated.py"
fi

########################################
# FIND GRADLE MODULES
########################################

modules=$(find . -name "build.gradle" -o -name "build.gradle.kts" | sed 's|/build.gradle.*||' | sort -u)

if [ -z "$modules" ]; then
    echo "No Gradle modules found"
    exit 1
fi

########################################
# PROCESS EACH MODULE
########################################
for module in $modules; do
    echo "Processing module: $module"

    mkdir -p "$PROJECT_ROOT/$module/build/reports"

    ########################################
    # GENERATE DEPENDENCY TREE
    ########################################
    echo "Generating dependency tree for $module..."
    if [ "$module" = "." ]; then
        "$PROJECT_ROOT/gradlew" dependencies --configuration runtimeClasspath > "$PROJECT_ROOT/$module/build/reports/dependency-tree.txt"
    else
        gradle_module="${module#./}"
        gradle_module="${gradle_module//\//\:}"
        "$PROJECT_ROOT/gradlew" ":$gradle_module:dependencies" --configuration runtimeClasspath > "$PROJECT_ROOT/$module/build/reports/dependency-tree.txt"
    fi

    if [ $? -ne 0 ]; then
        echo "Error generating dependency tree for $module"
        continue
    fi

    python3 "$PROJECT_ROOT/convert.py" "$PROJECT_ROOT/$module/build/reports/dependency-tree.txt" "$PROJECT_ROOT/$module/build/reports/dependency-tree.json"

    ########################################
    # ENSURE OGA PLUGIN IS PRESENT (WITH BACKUP)
    ########################################
    build_file=""
    if [ -f "$PROJECT_ROOT/$module/build.gradle.kts" ]; then
        build_file="$PROJECT_ROOT/$module/build.gradle.kts"
    elif [ -f "$PROJECT_ROOT/$module/build.gradle" ]; then
        build_file="$PROJECT_ROOT/$module/build.gradle"
    else
        echo "❌ No build.gradle or build.gradle.kts found for $module"
        continue
    fi

    backup_file="${build_file}.bak"
    cp "$build_file" "$backup_file"
    echo "Backup created: $backup_file"

    if [[ "$build_file" == *".kts" ]]; then
        if ! grep -q 'id("biz.lermitage.oga")' "$build_file"; then
            sed -i '/plugins[[:space:]]*{/a \    id("biz.lermitage.oga") version("1.1.1")' "$build_file"
        fi
    else
        if ! grep -q "id 'biz.lermitage.oga'" "$build_file"; then
            sed -i "/plugins[[:space:]]*{/a \    id 'biz.lermitage.oga' version '1.1.1'" "$build_file"
        fi
    fi

    ########################################
    # RUN OGA GRADLE PLUGIN
    ########################################
    echo "Running OGA Gradle plugin check..."
    if [ "$module" = "." ]; then
        "$PROJECT_ROOT/gradlew" --refresh-dependencies biz-lermitage-oga-gradle-check > "$PROJECT_ROOT/$module/build/reports/oga-output.txt" 2>&1
    else
        "$PROJECT_ROOT/gradlew" --refresh-dependencies ":$gradle_module:biz-lermitage-oga-gradle-check" > "$PROJECT_ROOT/$module/build/reports/oga-output.txt" 2>&1
    fi

    if [ ! -s "$PROJECT_ROOT/$module/build/reports/oga-output.txt" ]; then
        echo "⚠ OGA plugin did not produce any output for $module, skipping relocations"
        mv "$backup_file" "$build_file"
        continue
    fi

    ########################################
    # GENERATE RELOCATIONS JSON
    ########################################
    > "$PROJECT_ROOT/$module/build/reports/relocations.json"
    while IFS= read -r line; do
        if [[ $line =~ \'([^\']+):([^\']+)\'[[:space:]]should[[:space:]]be[[:space:]]replaced[[:space:]]by[[:space:]]\'([^\']+)\' ]]; then
            old_group="${BASH_REMATCH[1]}"
            old_artifact="${BASH_REMATCH[2]}"
            new_candidate="${BASH_REMATCH[3]}"
            first_replacement=$(echo "$new_candidate" | awk -F' or ' '{print $1}')
            if [[ "$first_replacement" == *:* ]]; then
                new_group=$(echo "$first_replacement" | cut -d':' -f1)
                new_artifact=$(echo "$first_replacement" | cut -d':' -f2)
            else
                new_group="$first_replacement"
                new_artifact="$first_replacement"
            fi
            echo "$old_group:$old_artifact:$new_group:$new_artifact" >> "$PROJECT_ROOT/$module/build/reports/relocations.json"
        fi
    done < "$PROJECT_ROOT/$module/build/reports/oga-output.txt"

    if [ -f "$PROJECT_ROOT/$module/build/reports/relocations.json" ]; then
        while IFS= read -r mapping; do
            old_group=$(echo "$mapping" | cut -d':' -f1)
            old_artifact=$(echo "$mapping" | cut -d':' -f2)
            new_group=$(echo "$mapping" | cut -d':' -f3)
            new_artifact=$(echo "$mapping" | cut -d':' -f4)

            python3 "$PROJECT_ROOT/relocated.py" \
                "$PROJECT_ROOT/$module/build/reports/dependency-tree.json" \
                "$PROJECT_ROOT/$module/build/reports/dependency-tree.json" \
                "$old_group" "$old_artifact" "$new_group" "$new_artifact"
        done < "$PROJECT_ROOT/$module/build/reports/relocations.json"
    fi

    ########################################
    # ADD LAST UPDATED DATES
    ########################################
    python3 "$PROJECT_ROOT/dated.py" \
        "$PROJECT_ROOT/$module/build/reports/dependency-tree.json" \
        "$PROJECT_ROOT/$module/build/reports/dependency-relocated-date.json"

    ########################################
    # MOVE JSON TO gepardec-reports
    ########################################
    gepardec_dir="$PROJECT_ROOT/$module/gepardec-reports"
    mkdir -p "$gepardec_dir"
    if [ -s "$PROJECT_ROOT/$module/build/reports/dependency-relocated-date.json" ]; then
        mv "$PROJECT_ROOT/$module/build/reports/dependency-relocated-date.json" "$gepardec_dir/"
        echo "✅ dependency-relocated-date.json moved to $gepardec_dir"
    else
        echo "⚠ Missing or empty: $PROJECT_ROOT/$module/build/reports/dependency-relocated-date.json"
    fi

    ########################################
    # RESTORE ORIGINAL BUILD FILE
    ########################################
    if [ -f "$backup_file" ]; then
        mv "$backup_file" "$build_file"
        echo "Restored original build file: $build_file"
    fi

    echo "✅ Finished processing $module"
    echo "----------------------------------------------------------"
done

########################################
# DELETE PYTHON HELPER SCRIPTS
########################################
rm -f "$PROJECT_ROOT/convert.py" "$PROJECT_ROOT/relocated.py" "$PROJECT_ROOT/dated.py"

echo "Gradle dependency processing completed successfully."
