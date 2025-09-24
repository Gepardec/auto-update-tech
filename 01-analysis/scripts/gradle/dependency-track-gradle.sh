#!/bin/bash

die() {
    echo "❌ FEHLER: $1" >&2
    exit 1
}

PROJECT_ROOT=""
PROJECT_NAME="Analyzis Report Dependency"
API_URL="https://gepardec-dtrack.apps.cloudscale-lpg-2.appuio.cloud/api"
API_KEY=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --build-project-root)
            PROJECT_ROOT="$2"
            shift 2
            ;;
        --dependency-track-api-key)
            API_KEY="$2"
            shift 2
            ;;
        *)
            echo "Unexpected option: $1"
            exit 1
            ;;
    esac
done

if [ -z "$PROJECT_ROOT" ] || [ -z "$API_KEY" ]; then
    echo "Error: All arguments must be provided."
    echo "Usage: --gradle-project-root <path-to-gradle-project-root> --dependency-track-api-key <api-key>"
    exit 1
fi

BUILD_FILE_GRADLE="$PROJECT_ROOT/build.gradle"
BUILD_FILE_KTS="$PROJECT_ROOT/build.gradle.kts"
BOM_FILE="$PROJECT_ROOT/build/reports/bom.json"

if [ -f "$BUILD_FILE_GRADLE" ]; then
    BUILD_FILE="$BUILD_FILE_GRADLE"
    DSL="groovy"
elif [ -f "$BUILD_FILE_KTS" ]; then
    BUILD_FILE="$BUILD_FILE_KTS"
    DSL="kotlin"
else
    die "build.gradle or build.gradle.kts not found in project root"
fi

ORIGINAL_BUILD_CONTENT=$(<"$BUILD_FILE")
TMP_BOM_TMP=$(mktemp)

# Backup settings file if it exists
if [[ "$DSL" == "kotlin" ]]; then
    SETTINGS_FILE="$PROJECT_ROOT/settings.gradle.kts"
else
    SETTINGS_FILE="$PROJECT_ROOT/settings.gradle"
fi

if [ -f "$SETTINGS_FILE" ]; then
    SETTINGS_FILE_ORIGINAL=$(mktemp)
    cp "$SETTINGS_FILE" "$SETTINGS_FILE_ORIGINAL"
fi

cleanup() {
    echo "🧹 Führe Cleanup aus..."
    rm -f "$TMP_BOM_TMP" "${BOM_FILE}_base64.tmp"

    if [ -n "$ORIGINAL_BUILD_CONTENT" ]; then
        echo "$ORIGINAL_BUILD_CONTENT" > "$BUILD_FILE"
        echo "📄 Original build file wiederhergestellt"
        gradle -p "$PROJECT_ROOT" clean > /dev/null 2>&1
    fi

    # Restore original settings file
    if [ -n "$SETTINGS_FILE_ORIGINAL" ] && [ -f "$SETTINGS_FILE_ORIGINAL" ]; then
        cp "$SETTINGS_FILE_ORIGINAL" "$SETTINGS_FILE"
        echo "📄 Original settings file wiederhergestellt"
        rm -f "$SETTINGS_FILE_ORIGINAL"
    fi

    if [ -n "$PROJECT_UUID" ]; then
        echo "🗑️  Lösche Projekt von der API: $PROJECT_UUID"
        curl -s -X DELETE "$API_URL/v1/project/$PROJECT_UUID" \
             -H "Content-Type: application/json" \
             -H "X-API-Key: $API_KEY"
    fi

    echo "✅ Cleanup abgeschlossen"
}

addCycloneDxPlugin() {
    echo "🧩 Adding CycloneDX plugin inside existing plugins block..."
    if [[ "$DSL" == "kotlin" ]]; then
        if ! grep -q 'id("org.cyclonedx.bom")' "$BUILD_FILE"; then
            awk '/plugins\s*{/ {
                print
                print "    id(\"org.cyclonedx.bom\") version \"2.3.1\""
                next
            } { print }' "$BUILD_FILE" > "${BUILD_FILE}.new" && mv "${BUILD_FILE}.new" "$BUILD_FILE" || die "Fehler beim Hinzufügen des CycloneDX Plugins"
        fi
        if [ ! -f "$SETTINGS_FILE" ]; then
            echo -e "pluginManagement {\n    repositories {\n        gradlePluginPortal()\n        mavenCentral()\n    }\n}" > "$SETTINGS_FILE"
        elif ! grep -q 'gradlePluginPortal' "$SETTINGS_FILE"; then
            echo -e "\npluginManagement {\n    repositories {\n        gradlePluginPortal()\n        mavenCentral()\n    }\n}" >> "$SETTINGS_FILE"
        fi
    else
        if ! grep -q "id 'org.cyclonedx.bom'" "$BUILD_FILE"; then
            awk '/plugins\s*{/ {
                print
                print "    id '\''org.cyclonedx.bom'\'' version '\''2.3.1'\''"
                next
            } { print }' "$BUILD_FILE" > "${BUILD_FILE}.new" && mv "${BUILD_FILE}.new" "$BUILD_FILE" || die "Fehler beim Hinzufügen des CycloneDX Plugins"
        fi
        if [ ! -f "$SETTINGS_FILE" ]; then
            echo -e "pluginManagement {\n    repositories {\n        gradlePluginPortal()\n        mavenCentral()\n    }\n}" > "$SETTINGS_FILE"
        elif ! grep -q 'gradlePluginPortal' "$SETTINGS_FILE"; then
            echo -e "\npluginManagement {\n    repositories {\n        gradlePluginPortal()\n        mavenCentral()\n    }\n}" >> "$SETTINGS_FILE"
        fi
    fi
}

generateBomFile() {
    echo "⚙️  Generating BOM with Gradle..."
    mkdir -p "$(dirname "$BOM_FILE")"
    if ! gradle -p "$PROJECT_ROOT" cyclonedxBom; then
        die "Gradle BOM generation failed"
    fi

    if [ ! -f "$BOM_FILE" ]; then
        die "BOM file not found at $BOM_FILE"
    fi
}

createDependencyTrackProject() {
    response=$(curl -s -X PUT "$API_URL/v1/project" \
        -H "Content-Type: application/json" \
        -H "X-API-Key: $API_KEY" \
        -d "{\"name\": \"$PROJECT_NAME\", \"version\": \"1.0.0\", \"description\": \"Projektbeschreibung\"}")

    PROJECT_UUID=$(echo "$response" | grep -o '"uuid": *"[^"]*"' | cut -d'"' -f4)
    if [ -z "$PROJECT_UUID" ] || [ "$PROJECT_UUID" = "null" ]; then
        echo "API-Antwort: $response"
        die "Project UUID konnte nicht ermittelt werden"
    fi
    echo $PROJECT_UUID
}

uploadBomFile() {
    base64_bom=$(base64 < "$BOM_FILE" | tr -d '\r\n')
    echo "{\"project\": \"$PROJECT_UUID\", \"projectName\": \"$PROJECT_NAME\", \"projectVersion\": \"1.0.0\", \"bom\": \"$base64_bom\"}" > "${BOM_FILE}_base64.tmp"
    echo "📤 Uploading BOM..."
    curl -s -X PUT "$API_URL/v1/bom" \
        -H "Content-Type: application/json" \
        -H "X-API-Key: $API_KEY" \
        -d @"${BOM_FILE}_base64.tmp"
}

dependencyTrackAnalysis() {
    echo " ... Start analysis..."
    analyze_response=$(curl -s -X POST "$API_URL/v1/finding/project/$PROJECT_UUID/analyze" \
        -H "X-API-Key: $API_KEY")

    TOKEN_UUID=$(echo "$analyze_response" | sed -n 's/.*"token"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')

    echo " ... Check if analysis is done..."
    ANALYSIS_PROCESSING="true"
    while [ "$ANALYSIS_PROCESSING" == "true" ]; do
        analyze_progress=$(curl -s -X GET "$API_URL/v1/event/token/$TOKEN_UUID" \
            -H "X-API-Key: $API_KEY")
        ANALYSIS_PROCESSING=$(echo "$analyze_progress" | sed -n 's/.*"processing"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
        echo " ... Processing: $ANALYSIS_PROCESSING"
        sleep 2
    done
}

createDependencyTrackResultFile() {
    echo "📊 Fetching metrics and findings..."
    RESULT_FILE="dependency-track-vulnerability-report.json"
    if ! curl -s -X GET "$API_URL/v1/finding/project/$PROJECT_UUID" \
        -H "X-API-Key: $API_KEY" \
        -H "Content-Type: application/json" > "$RESULT_FILE"; then
        die "Fehler beim Abrufen der Ergebnisse"
    fi

    if [ ! -s "$RESULT_FILE" ]; then
        die "Die erstellte Ergebnisdatei ist leer"
    fi

    echo "📁 Result saved in: ${RESULT_FILE}"
}

########################
# PROGRAM STARTS HERE
########################

exit_handler() {
  exit_code=$?
  if [ "$exit_code" -ne 0 ]; then
    cleanup
  fi
  exit "$exit_code"
}

trap exit_handler EXIT

addCycloneDxPlugin
generateBomFile

echo "📦 Creating project: $PROJECT_NAME..."
PROJECT_UUID=$(createDependencyTrackProject)
echo "🔑 Project UUID: $PROJECT_UUID"

uploadBomFile
dependencyTrackAnalysis
createDependencyTrackResultFile
cleanup
