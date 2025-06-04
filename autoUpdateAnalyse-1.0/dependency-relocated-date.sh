#!/bin/bash

PROJECT_ROOT=""

# Parse command-line options using getopt
OPTS=$(getopt -o "" --long project-root: -- "$@")

if [ $? -ne 0 ]; then
    echo "Error parsing options."
    exit 1
fi

eval set -- "$OPTS"

while true; do
    case "$1" in
        --project-root) PROJECT_ROOT="$2"; shift 2 ;;
        --) shift; break ;;
        *) echo "Unexpected option: $1"; exit 1 ;;
    esac
done

# Check if all required arguments are provided
if [ -z "$PROJECT_ROOT" ] ; then
    echo "Error: All arguments must be provided."
    echo "Usage: --project-root <path-to-project-root>"
    exit 1
fi

# Check for python3
if ! command -v python3 &> /dev/null; then
    echo "Error: python3 is not installed. Please install Python 3 to proceed."
    echo "Download from https://www.python.org/downloads/"
    exit 1
fi

# File 1: convert.py content
convert_file_name="convert.py"
convert_content=$(cat << 'EOF'
import json
import sys
from pathlib import Path

def collect_dependencies(node, seen, flat_list):
    for child in node.get("children", []):
        key = (child["groupId"], child["artifactId"], child["version"])
        if key in seen:
            continue
        seen.add(key)
        flat_list.append({
            "groupId": child["groupId"],
            "artifactId": child["artifactId"],
            "version": child["version"],
            "type": child.get("type", "jar"),
            "scope": child.get("scope", ""),
            "classifier": child.get("classifier", ""),
            "optional": child.get("optional", "false")
        })
        collect_dependencies(child, seen, flat_list)

def main():
    if len(sys.argv) != 3:
        print("Usage: python flatten_dependencies.py <input_file.json> <output_file.json>")
        sys.exit(1)

    input_file = Path(sys.argv[1])
    output_file = Path(sys.argv[2])

    if not input_file.exists():
        print(f"Error: input file {input_file} does not exist.")
        sys.exit(1)

    with input_file.open("r", encoding="utf-8") as f:
        root = json.load(f)

    flat_deps = []
    seen = set()

    collect_dependencies(root, seen, flat_deps)

    flattened_json = {
        "groupId": root["groupId"],
        "artifactId": root["artifactId"],
        "version": root["version"],
        "type": root.get("type", "jar"),
        "scope": root.get("scope", ""),
        "classifier": root.get("classifier", ""),
        "optional": root.get("optional", "false"),
        "dependencies": flat_deps
    }

    with output_file.open("w", encoding="utf-8") as f:
        json.dump(flattened_json, f, indent=2)

    print(f"Flattened {len(flat_deps)} dependencies into {output_file}")

if __name__ == "__main__":
    main()
EOF
)

# File 2: relocated.py content
test_file_name="relocated.py"
test_content=$(cat << 'EOF'
import json
import sys
import urllib.request
import xml.etree.ElementTree as ET
from datetime import datetime

def update_dependencies_with_relocations_and_dates(json_file, output_file, old_group_id, old_artifact_id, new_group_id, new_artifact_id):
    with open(json_file, 'r') as f:
        data = json.load(f)

    for dependency in data.get("dependencies", []):
        group_id = dependency.get("groupId")
        artifact_id = dependency.get("artifactId")

        # If the dependency matches the old group/artifact, add relocation
        if group_id == old_group_id and artifact_id == old_artifact_id:
            if "relocations" not in dependency:
                dependency["relocations"] = []
            dependency["relocations"].append({
                "groupId": new_group_id,
                "artifactId": new_artifact_id
            })
        elif group_id == old_group_id and old_artifact_id == "*":
            if "relocations" not in dependency:
                dependency["relocations"] = []
            dependency["relocations"].append({
                "groupId": new_group_id,
                "artifactId": new_artifact_id
            })

    with open(output_file, 'w') as f:
        json.dump(data, f, indent=4)

    print(f"Updated JSON written to {output_file}")

if __name__ == "__main__":
    # Check if arguments are passed
    if len(sys.argv) != 7:
        print("Usage: python script.py <input_file> <output_file> <old_group_id> <old_artifact_id> <new_group_id> <new_artifact_id>")
        sys.exit(1)

    # Get file paths from command-line arguments
    json_file = sys.argv[1]
    output_file = sys.argv[2]

    # Example relocation information
    old_group_id = sys.argv[3]
    old_artifact_id = sys.argv[4]
    new_group_id = sys.argv[5]
    new_artifact_id = sys.argv[6]

    update_dependencies_with_relocations_and_dates(json_file, output_file, old_group_id, old_artifact_id, new_group_id, new_artifact_id)
EOF
)

# File 3: dated.py content
dated_file_name="dated.py"
dated_content=$(cat << 'EOF'
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
            # Convert yyyyMMddHHmmss → YYYY-MM-DD HH:MM:SS
            formatted_date = datetime.strptime(raw_date, "%Y%m%d%H%M%S").strftime("%Y-%m-%d %H:%M:%S")
            return formatted_date
        else:
            return "Unknown"

    except Exception as e:
        print(f"Could not fetch metadata for {group_id}:{artifact_id} — {e}")
        return "Unknown"

def update_dependencies_with_dates(json_file, output_file):
    with open(json_file, 'r') as f:
        data = json.load(f)

    for dependency in data.get("dependencies", []):
        group_id = dependency.get("groupId")
        artifact_id = dependency.get("artifactId")

        # Add lastUpdatedDate to the main dependency
        dependency["lastUpdatedDate"] = get_last_updated_date(group_id, artifact_id)

        for relocation in dependency.get("relocations", []):
            re_group_id = relocation.get("groupId")
            re_artifact_id = relocation.get("artifactId")
            relocation["lastUpdatedDate"] = get_last_updated_date(re_group_id, re_artifact_id)

    with open(output_file, 'w') as f:
        json.dump(data, f, indent=4)

    print(f"Updated JSON written to {output_file}")

if __name__ == "__main__":
    # Check if arguments are passed
    if len(sys.argv) != 3:
        print("Usage: python script.py <input_file> <output_file>")
        sys.exit(1)

    # Get file paths from command-line arguments
    json_file = sys.argv[1]
    output_file = sys.argv[2]

    update_dependencies_with_dates(json_file, output_file)
EOF
)

# Array to store temporary files
temp_files=()

# Save original location
original_dir=$PROJECT_ROOT

cd $PROJECT_ROOT

# Find all folders with pom.xml, exclude target/, and save them sorted
modules=$(find . -name "pom.xml" -not -path "*/target/*" -exec dirname {} \; | sed "s|^\./||" | sort -u)

# Check if modules were found
if [ -z "$modules" ]; then
    echo "No modules with pom.xml found."
    exit 1
fi

# Process each module
for module in $modules; do
    if [ "$module" = "." ]; then
        path="$PWD"
    else
        path="$PWD/$module"
    fi
    cd "$path" || exit

    # Check if type is packaging pom
    if grep -q "<packaging>pom</packaging>" "pom.xml"; then
        echo "Skip module with packaging=pom: $module"
        if [ "$module" != "." ]; then
            cd "$original_dir" || exit
        fi
        continue
    fi

    # Execute analyze-report
    echo "Create Dependency Tree for $module..."
    mvn org.apache.maven.plugins:maven-dependency-plugin:3.8.1:tree -DoutputFile=target/dependency-tree.json -DoutputType=json
    if [ $? -ne 0 ]; then
        echo "Error while running mvn analyze-report in $module"
        if [ "$module" != "." ]; then
            cd "$original_dir" || exit
        fi
        continue
    fi

    # Check if dependency-tree.json was created
    if [ ! -f "target/dependency-tree.json" ]; then
        echo "Error: dependency-tree.json was not created in $module"
        if [ "$module" != "." ]; then
            cd "$original_dir" || exit
        fi
        continue
    fi

    # Write Python scripts if not already present
    convert_py_file="$path/convert.py"
    relocated_py_file="$path/relocated.py"
    dated_py_file="$path/dated.py"

    if [ ! -f "$convert_py_file" ]; then
        echo "$convert_content" > "$convert_py_file"
        echo "Created: $convert_py_file"
    else
        echo "Skipped (already exists): $convert_py_file"
    fi

    if [ ! -f "$relocated_py_file" ]; then
        echo "$test_content" > "$relocated_py_file"
        echo "Created: $relocated_py_file"
    else
        echo "Skipped (already exists): $relocated_py_file"
    fi

    if [ ! -f "$dated_py_file" ]; then
        echo "$dated_content" > "$dated_py_file"
        echo "Created: $dated_py_file"
    else
        echo "Skipped (already exists): $dated_py_file"
    fi

    # Backup pom.xml
    cp "pom.xml" "pom.xml.bak"
    echo "Created pom.xml.bak ..."

    # Run oga-maven-plugin check
    echo "Running 'mvn biz.lermitage.oga:oga-maven-plugin:check'..."
    mvn_output=$(mvn biz.lermitage.oga:oga-maven-plugin:check 2>&1)
    echo "$mvn_output"

    # Array to collect mappings
    dependency_mappings=()

    # Parse for deprecated dependency lines
    while IFS= read -r line; do
        if [[ $line =~ ^\[ERROR\]\ \(dependency\)\ \'([^:]+):([^[:space:]]+)\'\ should\ be\ replaced\ by\ \'([^:]+):([^[:space:]]+)\ or\ ([^:]+):([^[:space:]]+)\' ]]; then
            old_group_id="${BASH_REMATCH[1]}"
            old_artifact_id="${BASH_REMATCH[2]}"
            new_group_id1="${BASH_REMATCH[3]}"
            new_artifact_id1="${BASH_REMATCH[4]}"
            new_group_id2="${BASH_REMATCH[5]}"
            new_artifact_id2="${BASH_REMATCH[6]}"
            dependency_mappings+=("$old_group_id:$old_artifact_id:$new_group_id1:$new_artifact_id1")
            dependency_mappings+=("$old_group_id:$old_artifact_id:$new_group_id2:$new_artifact_id2")
        elif [[ $line =~ ^\[ERROR\]\ \(dependency\)\ \'([^[:space:]]+)\'\ groupId\ should\ be\ replaced\ by\ \'([^[:space:]]+)\' ]]; then
            old_group_id="${BASH_REMATCH[1]}"
            old_artifact_id="*"
            new_group_id="${BASH_REMATCH[2]}"
            new_artifact_id="*"
            dependency_mappings+=("$old_group_id:$old_artifact_id:$new_group_id:$new_artifact_id")
        elif [[ $line =~ ^\[ERROR\]\ \(dependency\)\ \'([^:]+):([^[:space:]]+)\'\ should\ be\ replaced\ by\ \'([^:]+):([^[:space:]]+)\' ]]; then
            old_group_id="${BASH_REMATCH[1]}"
            old_artifact_id="${BASH_REMATCH[2]}"
            new_group_id="${BASH_REMATCH[3]}"
            new_artifact_id="${BASH_REMATCH[4]}"
            dependency_mappings+=("$old_group_id:$old_artifact_id:$new_group_id:$new_artifact_id")
        fi
    done <<< "$mvn_output"

    # Update pom.xml without xmlstarlet
    pom_path="$path/pom.xml"
    if [ ! -f "$pom_path" ]; then
        echo "❌ No root pom.xml found at: $pom_path"
        if [ "$module" != "." ]; then
            cd "$original_dir" || exit
        fi
        continue
    fi

    # Check if <build> exists, add if not
    if ! grep -q "<build>" "$pom_path"; then
        sed -i "/<\/project>/i \ \ <build>\n\ \ </build>" "$pom_path"
    fi

    # Check if <plugins> exists, add if not
    if ! grep -q "<plugins>" "$pom_path"; then
        sed -i "/<build>/a \ \ \ \ <plugins>\n\ \ \ \ </plugins>" "$pom_path"
    fi

    # Remove any existing exec-maven-plugin to avoid duplicates
    sed -i "/<plugin>[[:space:]]*.*<groupId>org.codehaus.mojo<\/groupId>[[:space:]]*.*<artifactId>exec-maven-plugin<\/artifactId>.*<\/plugin>/d" "$pom_path"

    # Prepare exec-maven-plugin configuration in a temporary file
    tmp_plugin_config=$(mktemp)
    cat << EOF > "$tmp_plugin_config"
      <plugin>
        <groupId>org.codehaus.mojo</groupId>
        <artifactId>exec-maven-plugin</artifactId>
        <version>3.1.0</version>
        <executions>
          <execution>
            <id>run-tree</id>
            <phase>process-resources</phase>
            <goals>
              <goal>exec</goal>
            </goals>
            <configuration>
              <executable>python3</executable>
              <arguments>
                <argument>\${project.basedir}/convert.py</argument>
                <argument>\${project.build.directory}/dependency-tree.json</argument>
                <argument>\${project.build.directory}/dependency-tree-flattened.json</argument>
              </arguments>
            </configuration>
          </execution>
EOF

    # Add executions for dependency mappings
    if [ ${#dependency_mappings[@]} -gt 0 ]; then
        echo "Dependency Mappings Found:"
        printf '%s\n' "${dependency_mappings[@]}" | while IFS=':' read -r old_group old_artifact new_group new_artifact; do
            echo "Old: $old_group:$old_artifact -> New: $new_group:$new_artifact"
        done

        count=1
        for mapping in "${dependency_mappings[@]}"; do
            IFS=':' read -r old_group_id old_artifact_id new_group_id new_artifact_id <<< "$mapping"
            cat << EOF >> "$tmp_plugin_config"
          <execution>
            <id>run-script-$count</id>
            <phase>process-resources</phase>
            <goals>
              <goal>exec</goal>
            </goals>
            <configuration>
              <executable>python3</executable>
              <arguments>
                <argument>\${project.basedir}/relocated.py</argument>
                <argument>\${project.build.directory}/dependency-tree-flattened.json</argument>
                <argument>\${project.build.directory}/dependency-tree-flattened.json</argument>
                <argument>$old_group_id</argument>
                <argument>$old_artifact_id</argument>
                <argument>$new_group_id</argument>
                <argument>$new_artifact_id</argument>
              </arguments>
            </configuration>
          </execution>
EOF
            ((count++))
        done
    else
        echo "No deprecated dependencies found."
    fi

    # Add execution for dated.py
    cat << EOF >> "$tmp_plugin_config"
          <execution>
            <id>run-dated-script</id>
            <phase>process-resources</phase>
            <goals>
              <goal>exec</goal>
            </goals>
            <configuration>
              <executable>python3</executable>
              <arguments>
                <argument>\${project.basedir}/dated.py</argument>
                <argument>\${project.build.directory}/dependency-tree-flattened.json</argument>
                <argument>\${project.basedir}/gepardec-reports/dependency-relocated-date.json</argument>
              </arguments>
            </configuration>
          </execution>
        </executions>
      </plugin>
EOF

    # Append the plugin configuration to the <plugins> section
    sed -i "/<plugins>/r $tmp_plugin_config" "$pom_path"

    # Clean up temporary file
    rm -f "$tmp_plugin_config"

    echo "✅ Plugins added successfully to root pom.xml"

    mkdir -p "gepardec-reports"

    # Execute process-resources
    echo "Creating Dependency Tree Flattened JSON AND RELOCATION for $module..."
    mvn process-resources
    if [ $? -ne 0 ]; then
        echo "Error executing mvn process-resources in $module"
        if [ -f "pom.xml.bak" ]; then
            mv "pom.xml.bak" "pom.xml"
            if [ $? -ne 0 ]; then
                echo "Warning: Could not restore pom.xml in $module"
            fi
        fi
        if [ "$module" != "." ]; then
            cd "$original_dir" || exit
        fi
        echo "------------------------------------------------------------------------------------"
        continue
    fi

    # Restore original pom.xml
    if [ -f "pom.xml.bak" ]; then
        mv "pom.xml.bak" "pom.xml"
        if [ $? -ne 0 ]; then
            echo "Warning: Could not restore pom.xml in $module"
        fi
    else
        echo "Warning: pom.xml.bak not found in $module, cannot restore"
    fi

    # Delete Python scripts
    if [ -f "convert.py" ]; then
        rm "convert.py"
        if [ $? -ne 0 ]; then
            echo "Warning: Could not delete convert.py in $module"
        fi
    fi
    if [ -f "relocated.py" ]; then
        rm "relocated.py"
        if [ $? -ne 0 ]; then
            echo "Warning: Could not delete relocated.py in $module"
        fi
    fi
    if [ -f "dated.py" ]; then
        rm "dated.py"
        if [ $? -ne 0 ]; then
            echo "Warning: Could not delete dated.py in $module"
        fi
    fi

    echo "------------------------------------------------------------------------------------"

    if [ "$module" != "." ]; then
        cd "$original_dir" || exit
    fi
done

## Run Maven clean
#echo "Starting Maven clean: clean..."
#mvn clean
#if [ $? -eq 0 ]; then
#    echo -e "\n✅ Maven build completed successfully."
#else
#    echo -e "\n❌ Maven build failed with exit code $?"
#    exit $?
#fi