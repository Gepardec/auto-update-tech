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

# Check if all required arguments are provided
if [ -z "$PROJECT_ROOT" ] ; then
    echo "Error: All arguments must be provided."
    echo "Usage: --project-root <path-to-project-root>"
    exit 1
fi

# CleanUp Temp Files later
temp_files=()

# find all folders with pom.xml, exclude target/, und save them sorted
modules=$(find $PROJECT_ROOT -type f -name "pom.xml" | grep -v "/target/" | while read -r pom; do
    # extract file path; if pom.xml is in root dir return .
    dir=$(dirname "$pom")
    echo "${dir#./}"
done | sort -u)

# check if modules were found
if [ -z "$modules" ]; then
    echo "Keine Module mit pom.xml gefunden."
    exit 1
fi

# create tempFile for plugin xml
plugin_file=$(mktemp)
temp_files+=("$plugin_file")
cat << 'EOF' > "$plugin_file"
            <plugin>
                <groupId>org.codehaus.mojo</groupId>
                <artifactId>exec-maven-plugin</artifactId>
                <version>3.1.0</version>
                <executions>
                    <execution>
                        <phase>process-resources</phase>
                        <goals>
                            <goal>exec</goal>
                        </goals>
                    </execution>
                </executions>
                <configuration>
                    <executable>python3</executable>
                    <arguments>
                        <argument>${project.basedir}/convert_xdoc.py</argument>
                        <argument>${project.build.directory}/reports/dependency-analysis.xdoc</argument>
                        <argument>${project.basedir}/gepardec-reports/dependency-analysis.json</argument>
                    </arguments>
                </configuration>
            </plugin>
EOF

# iterate through found folders
for module in $modules; do
    echo "Verarbeite Modul: $module"

    # cd to module-folder
    if [ "$module" != "." ]; then
        cd "$module" || {
            echo "Fehler beim Wechseln in $module"
            continue
        }
    fi

    # check if pom.xml is present and readable
    if [ ! -f "pom.xml" ]; then
        echo "Fehler: pom.xml nicht gefunden in $module"
        if [ "$module" != "." ]; then
            cd - > /dev/null
        fi
        continue
    fi
    if [ ! -s "pom.xml" ]; then
        echo "Fehler: pom.xml ist leer in $module"
        if [ "$module" != "." ]; then
            cd - > /dev/null
        fi
        continue
    fi

    # check if type is packaging pom
    if grep -q "<packaging>pom</packaging>" pom.xml; then
        echo "Überspringe Aggregator-Modul (packaging=pom): $module"
        if [ "$module" != "." ]; then
            cd - > /dev/null
        fi
        continue
    fi

    # create convert_xdoc.py in current dir, if not present already
    if [ ! -f "convert_xdoc.py" ]; then
        echo "Erstelle convert_xdoc.py im Modulverzeichnis $module..."
        cat << 'INNER_EOF' > "convert_xdoc.py"
import sys
import xml.etree.ElementTree as ET
import json
import re
import os

def parse_table(table, namespaces):
    if table is None:
        return []

    # extract table headers
    headers = [th.text.strip() if th.text else "" for th in table.findall(".//ns:tr/ns:th", namespaces)]
    rows = []
    for tr in table.findall(".//ns:tr", namespaces)[1:]:
        # extract rows
        row = {headers[i]: td.text.strip() if td.text else "-" for i, td in enumerate(tr.findall("ns:td", namespaces))}
        rows.append(row)

    return rows

input_file = sys.argv[1]
output_file = sys.argv[2]

# ensure reports directory exists
output_dir = os.path.dirname(output_file)
if not os.path.exists(output_dir):
    os.makedirs(output_dir)

# read and clean up file
with open(input_file, "r", encoding="utf-8") as f:
    content = f.read()
    # replace <a>-tags with their text
    content = re.sub(r'<a[^>]*>(.*?)</a>', r'\1', content)
    # rm invisible elements
    content = re.sub(r'[\x00-\x08\x0B\x0C\x0E-\x1F]', '', content)

# define namespace
namespaces = {'ns': 'http://maven.apache.org/XDOC/2.0'}

# parse
try:
    root = ET.fromstring(content)
except ET.ParseError as e:
    print(f"Parse-Fehler: {e}")
    print(f"Problem bei: {content[:100]}")
    sys.exit(1)

# prepare json structure
title_elem = root.find(".//ns:properties/ns:title", namespaces)
result = {
    "title": title_elem.text if title_elem is not None else "Dependency Analysis (Default)",
    "sections": []
}

for section in root.findall(".//ns:section", namespaces):
    section_name = section.get("name")
    section_data = {
        "name": section_name,
        "subsections": []
    }

    for subsection in section.findall(".//ns:subsection", namespaces):
        subsection_name = subsection.get("name")
        # debug
        table = subsection.find("ns:table", namespaces)

        # extract dependencies from table
        dependencies = parse_table(table, namespaces)

        subsection_data = {
            "name": subsection_name,
            "dependencies": dependencies
        }
        section_data["subsections"].append(subsection_data)

    result["sections"].append(section_data)

# write json
with open(output_file, "w", encoding="utf-8") as f:
    json.dump(result, f, indent=2)

print(f"Konvertierung abgeschlossen: {output_file}")
INNER_EOF
    else
        echo "convert_xdoc.py existiert bereits in $module, überspringe Erstellung."
    fi

    # execute analyze-report
    echo "Erstelle Dependency Analysis Report für $module..."
    if ! mvn org.apache.maven.plugins:maven-dependency-plugin:3.8.1:analyze-report -s ~/.m2/settings_normal.xml -Doutput.format=xdoc; then
        echo "Fehler beim Ausführen von mvn analyze-report in $module"
        if [ "$module" != "." ]; then
            cd - > /dev/null
        fi
        continue
    fi

    # check if dependency-analysis.xdoc was created
    if [ ! -f "target/reports/dependency-analysis.xdoc" ]; then
        echo "Fehler: dependency-analysis.xdoc wurde nicht erstellt in $module"
        if [ "$module" != "." ]; then
            cd - > /dev/null
        fi
        continue
    fi

    # check if exec-maven-plugin with exactly the same execution and configuration is present already
    if grep -A 10 "org.codehaus.mojo:exec-maven-plugin" pom.xml | grep -q "<phase>process-resources</phase>" && \
       grep -A 15 "org.codehaus.mojo:exec-maven-plugin" pom.xml | grep -q "<executable>python3</executable>" && \
       grep -A 20 "org.codehaus.mojo:exec-maven-plugin" pom.xml | grep -q "<argument>\${project.basedir}/convert_xdoc.py</argument>"; then
        echo "exec-maven-plugin mit gleicher execution und configuration bereits in pom.xml vorhanden, überspringe Änderung in $module"
    else
        echo "Füge exec-maven-plugin zu pom.xml in $module hinzu..."

        # create backup of pom.xml
        cp pom.xml pom.xml.bak || {
            echo "Fehler beim Erstellen eines Backups der pom.xml in $module"
            if [ "$module" != "." ]; then
                cd - > /dev/null
            fi
            continue
        }

        # create new temp pom.xml
        temp_file=$(mktemp)
        temp_files+=("$temp_file")

        # search for <plugins> and add plugin
        if grep -q "<plugins>" pom.xml; then
            awk -v plugin_file="$plugin_file" '
                /<\/plugins>/ {
                    while ((getline line < plugin_file) > 0) {
                        print line
                    }
                    close(plugin_file)
                    print
                    next
                }
                { print }
            ' pom.xml > "$temp_file" || {
                echo "Fehler beim Bearbeiten der pom.xml mit awk in $module"
                if [ "$module" != "." ]; then
                    cd - > /dev/null
                fi
                continue
            }
        else
            awk -v plugin_file="$plugin_file" '
                /<\/project>/ {
                    print "    <build>"
                    print "        <plugins>"
                    while ((getline line < plugin_file) > 0) {
                        print line
                    }
                    close(plugin_file)
                    print "        </plugins>"
                    print "    </build>"
                }
                { print }
            ' pom.xml > "$temp_file" || {
                echo "Fehler beim Bearbeiten der pom.xml mit awk in $module"
                if [ "$module" != "." ]; then
                    cd - > /dev/null
                fi
                continue
            }
        fi

        # check if temp file is not empty
        if [ ! -s "$temp_file" ]; then
            echo "Fehler: Temporäre pom.xml ist leer in $module"
            if [ "$module" != "." ]; then
                cd - > /dev/null
            fi
            continue
        fi

        # replace original with modified pom
        mv "$temp_file" pom.xml || {
            echo "Fehler beim Aktualisieren der pom.xml in $module"
            if [ "$module" != "." ]; then
                cd - > /dev/null
            fi
            continue
        }
        temp_files=("${temp_files[@]/$temp_file}")
    fi

    # execute process-resources
    echo "Erstelle Dependency Analysis JSON für $module..."
    if ! mvn process-resources -s ~/.m2/settings_normal.xml; then
        echo "Fehler beim Ausführen von mvn process-resources in $module"
        # restore original pom.xml in case of error
        if [ -f "pom.xml.bak" ]; then
            mv pom.xml.bak pom.xml || {
                echo "Warnung: Konnte pom.xml in $module nicht wiederherstellen"
            }
        fi
        if [ "$module" != "." ]; then
            cd - > /dev/null
        fi
        continue
    fi

    # check if dependency-analysis.json was created
    if [ ! -f "gepardec-reports/dependency-analysis.json" ]; then
        echo "Fehler: dependency-analysis.json wurde nicht erstellt in $module"
        # restore original pom.xml
        if [ -f "pom.xml.bak" ]; then
            mv pom.xml.bak pom.xml || {
                echo "Warnung: Konnte pom.xml in $module nicht wiederherstellen"
            }
        fi
        if [ "$module" != "." ]; then
            cd - > /dev/null
        fi
        continue
    fi

    # restore original pom.xml
    if [ -f "pom.xml.bak" ]; then
        mv pom.xml.bak pom.xml || {
            echo "Warnung: Konnte pom.xml in $module nicht wiederherstellen"
        }
    else
        echo "Warnung: pom.xml.bak nicht gefunden in $module, kann nicht wiederhergestellt werden"
    fi

    # delete convert_xdoc.py if it was created
    if [ -f "convert_xdoc.py" ]; then
        rm -f convert_xdoc.py || {
            echo "Warnung: Konnte convert_xdoc.py in $module nicht löschen"
        }
    fi

    # move back to dir
    if [ "$module" != "." ]; then
        cd - > /dev/null
    fi

    echo "Modul $module abgeschlossen"
    echo "------------------------"
done

# delete all temp files
for file in "${temp_files[@]}"; do
    [ -f "$file" ] && rm -f "$file"
done
rm -f "$plugin_file"

echo "Alle Module wurden verarbeitet."