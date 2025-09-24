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
    echo "Usage: $0 <project-root>"
    exit 1
fi

PROJECT_ROOT=$(realpath "$PROJECT_ROOT")

# Detect root build file
if [ -f "$PROJECT_ROOT/build.gradle.kts" ]; then
    BUILD_FILE="$PROJECT_ROOT/build.gradle.kts"
    DSL="kts"
elif [ -f "$PROJECT_ROOT/build.gradle" ]; then
    BUILD_FILE="$PROJECT_ROOT/build.gradle"
    DSL="groovy"
else
    echo "Kein build.gradle(.kts) im Projekt-Root gefunden."
    exit 1
fi

BACKUP_FILE="$BUILD_FILE.bak"
cp "$BUILD_FILE" "$BACKUP_FILE"

# Inject Dependency Analysis plugin if not present
if ! grep -q "com.autonomousapps.dependency-analysis" "$BUILD_FILE"; then
    echo "Füge Dependency Analysis Plugin zum Root hinzu..."
    if [ "$DSL" = "kts" ]; then
        if grep -q "plugins\\s*{" "$BUILD_FILE"; then
            awk '
                /plugins\s*{/ && !found {
                    print
                    print "    id(\"com.autonomousapps.dependency-analysis\") version \"1.31.0\""
                    found=1
                    next
                }
                { print }
            ' "$BUILD_FILE" > "$BUILD_FILE.tmp" && mv "$BUILD_FILE.tmp" "$BUILD_FILE"
        else
            {
                echo "plugins {"
                echo "    id(\"com.autonomousapps.dependency-analysis\") version \"1.31.0\""
                echo "}"
                echo ""
                cat "$BUILD_FILE"
            } > "$BUILD_FILE.tmp" && mv "$BUILD_FILE.tmp" "$BUILD_FILE"
        fi
    else
        if grep -q "plugins\\s*{" "$BUILD_FILE"; then
            awk '
                /plugins\s*{/ && !found {
                    print
                    print "    id '\''com.autonomousapps.dependency-analysis'\'' version '\''1.31.0'\''"
                    found=1
                    next
                }
                { print }
            ' "$BUILD_FILE" > "$BUILD_FILE.tmp" && mv "$BUILD_FILE.tmp" "$BUILD_FILE"
        else
            {
                echo "plugins {"
                echo "    id 'com.autonomousapps.dependency-analysis' version '1.31.0'"
                echo "}"
                echo ""
                cat "$BUILD_FILE"
            } > "$BUILD_FILE.tmp" && mv "$BUILD_FILE.tmp" "$BUILD_FILE"
        fi
    fi
else
    echo "Dependency Analysis Plugin bereits im Root vorhanden."
fi

# Run buildHealth
cd "$PROJECT_ROOT"
gradle --quiet buildHealth

# Copy the JSON report to root/ gepardec-reports
REPORT_PATH=$(find "$PROJECT_ROOT/build/reports/dependency-analysis" -type f -name "*.json" | head -n1 || true)
if [ -n "$REPORT_PATH" ]; then
    TARGET_DIR="$PROJECT_ROOT/gepardec-reports"
    mkdir -p "$TARGET_DIR"
    cp "$REPORT_PATH" "$TARGET_DIR/dependency-analysis.json"
    echo "Report gespeichert in $TARGET_DIR/dependency-analysis.json"
else
    echo "Keine JSON-Reportdatei gefunden."
fi

# Restore original build file
mv "$BACKUP_FILE" "$BUILD_FILE"

echo "Fertig! Root enthält nun ./gepardec-reports/dependency-analysis.json"
