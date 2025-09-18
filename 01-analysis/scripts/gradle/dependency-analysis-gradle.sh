#!/bin/bash
set -euo pipefail

PROJECT_ROOT=""

# Parse arguments
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

# Check required argument
if [ -z "$PROJECT_ROOT" ]; then
    echo "Error: --project-root <path> must be provided."
    exit 1
fi

PROJECT_ROOT=$(realpath "$PROJECT_ROOT")

# Detect all Gradle modules
modules=$(find "$PROJECT_ROOT" -name "build.gradle" -o -name "build.gradle.kts" \
    | xargs -n1 dirname \
    | sort -u)

if [ -z "$modules" ]; then
    echo "Keine Gradle-Module gefunden."
    exit 1
fi

echo "Gefundene Module:"
echo "$modules"
echo "------------------------"

for module in $modules; do
    echo "Verarbeite Modul: $module"

    cd "$module" || { echo "Fehler beim Wechseln in $module"; continue; }

    # Detect build file
    if [ -f "build.gradle.kts" ]; then
        build_file="build.gradle.kts"
        is_kts=true
    elif [ -f "build.gradle" ]; then
        build_file="build.gradle"
        is_kts=false
    else
        echo "Fehler: build.gradle oder build.gradle.kts nicht gefunden in $module"
        cd - > /dev/null
        continue
    fi

    # Backup build file
    backup_file="$build_file.bak"
    cp "$build_file" "$backup_file"
    echo "Backup erstellt: $backup_file"

    # Inject plugin if not present
    if ! grep -q "com.autonomousapps.dependency-analysis" "$build_file"; then
        echo "Füge Dependency Analysis Plugin temporär hinzu..."

        if $is_kts; then
            # Kotlin DSL: insert inside existing plugins block if it exists
            if grep -q "plugins\s*{" "$build_file"; then
                awk '
                    /plugins\s*{/ && !found {
                        print
                        print "    id(\"com.autonomousapps.dependency-analysis\") version \"1.31.0\""
                        found=1
                        next
                    }
                    { print }
                ' "$build_file" > "$build_file.tmp" && mv "$build_file.tmp" "$build_file"
            else
                # No plugins block: prepend
                {
                    echo "plugins {"
                    echo "    id(\"com.autonomousapps.dependency-analysis\") version \"1.31.0\""
                    echo "}"
                    echo ""
                    cat "$build_file"
                } > "$build_file.tmp" && mv "$build_file.tmp" "$build_file"
            fi
        else
            # Groovy DSL: prepend plugins block
            {
                echo "plugins {"
                echo "    id 'com.autonomousapps.dependency-analysis' version '1.31.0'"
                echo "}"
                echo ""
                cat "$build_file"
            } > "$build_file.tmp" && mv "$build_file.tmp" "$build_file"
        fi
    else
        echo "Dependency Analysis Plugin bereits vorhanden."
    fi

    # Run dependency analysis
    echo "Führe Dependency Analysis durch..."
    if ! ./gradlew buildHealth --quiet; then
        echo "Fehler beim Ausführen von gradlew buildHealth in $module"
        mv "$backup_file" "$build_file"
        cd - > /dev/null
        continue
    fi

    # Find JSON report
    report_path=$(find build/reports/dependency-analysis -type f -name "*.json" | head -n 1 || true)
    if [ -z "$report_path" ]; then
        echo "Fehler: Keine JSON-Reportdatei gefunden in $module"
        mv "$backup_file" "$build_file"
        cd - > /dev/null
        continue
    fi

    # Create per-module reports folder
    module_report_dir="gepardec-reports"
    mkdir -p "$module_report_dir"

    # Copy JSON report
    cp "$report_path" "$module_report_dir/dependency-analysis.json"
    echo "Dependency Analysis JSON für $module gespeichert in $module_report_dir/dependency-analysis.json"

    # Restore original build file
    mv "$backup_file" "$build_file"
    echo "Original $build_file wiederhergestellt."

    cd - > /dev/null
    echo "Modul $module abgeschlossen"
    echo "------------------------"
done

echo "Alle Module wurden verarbeitet."
echo "Berichte befinden sich in jedem Modul unter ./gepardec-reports/dependency-analysis.json"
