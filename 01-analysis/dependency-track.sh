#!/bin/bash

# Keine automatische Beendigung bei Fehlern, damit wir unser eigenes Cleanup durchführen können
# set -e wurde entfernt, um eigene Fehlerbehandlung zu implementieren

# Funktion für Fehlerausgabe und kontrolliertes Beenden
die() {
    echo "❌ FEHLER: $1" >&2
    exit 1
}

PROJECT_ROOT=""
PROJECT_NAME="Analysis Report Dependency"
API_URL="https://gepardec-dtrack.apps.cloudscale-lpg-2.appuio.cloud/api"
API_KEY=""

# Parse command-line options using getopt
OPTS=$(getopt -o "" --long maven-project-root:,dependency-track-api-key: -- "$@")

if [ $? -ne 0 ]; then
    echo "Error parsing options."
    exit 1
fi

eval set -- "$OPTS"

while true; do
    case "$1" in
        --maven-project-root) PROJECT_ROOT="$2"; shift 2 ;;
        --dependency-track-api-key) API_KEY="$2"; shift 2 ;;
        --) shift; break ;;
        *) echo "Unexpected option: $1"; exit 1 ;;
    esac
done

# Check if all required arguments are provided
if [ -z "$PROJECT_ROOT" ] || [ -z "$API_KEY" ] ; then
    echo "Error: All arguments must be provided."
    echo "Usage: --maven-project-root <path-to-maven-project-root> --dependency-track-api-key <api-key>"
    exit 1
fi

BOM="$PROJECT_ROOT/gepardec-reports/bom.json"
POM_FILE="$PROJECT_ROOT/pom.xml"

# Prüfe, ob POM-Datei existiert
if [ ! -f "$POM_FILE" ]; then
    echo "Error: pom.xml not found at $POM_FILE"
    exit 1
fi

# Sichere den Original-Inhalt des POM-Files
ORIGINAL_POM_CONTENT=$(<"$POM_FILE")

# Temp-Dateien
TMP_PROJECT_INFO=$(mktemp)
TMP_FINAL_OUTPUT=$(mktemp)
PLUGIN_TMP=$(mktemp)

# Cleanup-Funktion, die in jedem Fall ausgeführt werden soll
cleanup() {
    echo "🧹 Führe Cleanup aus..."

    # Lösche temporäre Dateien
    rm -f "$TMP_PROJECT_INFO" "$TMP_FINAL_OUTPUT" "$PLUGIN_TMP"

    # Stelle Original-POM wieder her
    if [ -n "$ORIGINAL_POM_CONTENT" ]; then
        echo "$ORIGINAL_POM_CONTENT" > "$POM_FILE"
        echo "📄 Original POM wiederhergestellt"

        # Führe maven clean aus
        mvn -f "$POM_FILE" clean > /dev/null 2>&1
        echo "🧼 Maven Clean ausgeführt"
    fi

#     Lösche das Projekt von der API, wenn eine UUID vorhanden ist
    if [ -n "$PROJECT_UUID" ]; then
        echo "🗑️  Lösche Projekt von der API: $PROJECT_UUID"
        curl -s -X DELETE "$API_URL/v1/project/$PROJECT_UUID" \
             -H "Content-Type: application/json" \
             -H "X-API-Key: $API_KEY"
    fi

    echo "✅ Cleanup abgeschlossen"
}

# Adds CyclonDx Maven Plugin to POM
addCyclonDxToPom(){
  echo "🧩 Adding CycloneDX plugin to pom.xml..."
  cat > "$PLUGIN_TMP" <<EOF
  <plugin>
      <groupId>org.cyclonedx</groupId>
      <artifactId>cyclonedx-maven-plugin</artifactId>
      <version>2.9.1</version>
      <configuration>
          <projectType>application</projectType>
          <outputDirectory>gepardec-reports</outputDirectory>
      </configuration>
      <executions>
          <execution>
              <phase>package</phase>
              <goals>
                  <goal>makeAggregateBom</goal>
              </goals>
          </execution>
      </executions>
  </plugin>
EOF

  # Füge Plugin zum POM hinzu
  if grep -q "<plugins>" "$POM_FILE"; then
      awk '
          /<plugins>/ {
              print
              while ((getline line < "'"$PLUGIN_TMP"'") > 0) print line
              close("'"$PLUGIN_TMP"'")
              next
          }
          { print }
      ' "$POM_FILE" > "${POM_FILE}.new" && mv "${POM_FILE}.new" "$POM_FILE" || die "Fehler beim Aktualisieren der pom.xml"
  else
      die "<plugins> block not found in pom.xml"
  fi
}

# Generate BOM File with Maven
generateBomFile(){
  echo "⚙️  Generating BOM with Maven..."
  if ! mvn -f "$POM_FILE" cyclonedx:makeAggregateBom; then
      die "Maven execution failed"
  fi

  if [ ! -f "$BOM" ]; then
      die "BOM file not found at $BOM"
  fi
}

# Creates Project in Dependency Track and returns Project UUID
createDependencyTrackProject(){
  response=$(curl -s -X PUT "$API_URL/v1/project" \
    -H "Content-Type: application/json" \
    -H "X-API-Key: $API_KEY" \
    -d "{\"name\": \"$PROJECT_NAME\", \"version\": \"1.0.0\", \"description\": \"Projektbeschreibung\"}")

  if [ -z "$response" ]; then
      die "Keine Antwort vom API-Server erhalten"
  fi

  PROJECT_UUID=$(echo "$response" | grep -o '"uuid": *"[^"]*"' | cut -d'"' -f4)

  if [ -z "$PROJECT_UUID" ] || [ "$PROJECT_UUID" = "null" ]; then
      echo "API-Antwort: $response"
      die "Project UUID konnte nicht ermittelt werden"
  fi

  echo $PROJECT_UUID
}

# Converts BOM File to base_64 and Uploads to Dependency Track
uploadBomFile(){
#  PROJECT_UUID=$1
  base64_bom=$(base64 < "$BOM" | tr -d '\r\n')

  echo "{\"project\": \"$PROJECT_UUID\", \"projectName\": \"$PROJECT_NAME\", \"projectVersion\": \"1.0.0\", \"bom\": \"$base64_bom\"}" > "${BOM}_base64.tmp"

  echo "📤 Uploading BOM..."
  upload_response=$(curl -s -X PUT "$API_URL/v1/bom" \
    -H "Content-Type: application/json" \
    -H "X-API-Key: $API_KEY" \
    -d @"${BOM}_base64.tmp")
}

# Start Dependency Track analysis
dependencyTrackAnalysis(){
  echo " ... Start analysis..."
  analyze_response=$(curl -s -X POST "$API_URL/v1/finding/project/$PROJECT_UUID/analyze" \
      -H "X-API-Key: $API_KEY")

  TOKEN_UUID=$(echo "$analyze_response" | grep -oP '"token"\s*:\s*"\K[^"]+')

  echo " ... Check if analysis is done..."
  ANALYSIS_PROCESSING="true"
  while [ "$ANALYSIS_PROCESSING" == "true" ]
  do
  analyze_progress=$(curl -s -X GET "$API_URL/v1/event/token/$TOKEN_UUID" \
      -H "X-API-Key: $API_KEY")
  ANALYSIS_PROCESSING=$(echo "$analyze_progress" | grep -oP '"processing"\s*:\s*"\K[^"]+')
  echo " ... Processing: $ANALYSIS_PROCESSING"
  sleep 2
  done
}

# Fetch metrics and findings and create the result file
createDependencyTrackResultFile(){
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

  TEMP_FILE="${RESULT_FILE}.tmp"

#  if [ "$DEBUG" ]; then
#    echo -e "\n✅ === RESULT REPORT ===\n"
#    cat $RESULT_FILE
#    echo -e "\n\n✅ === REPORT END ===\n"
#  fi
  echo "📁 Result saved in: ${RESULT_FILE}"
}


########################
# PROGRAM STARTS HERE
########################


# Registriere die Cleanup-Funktion für verschiedene Signale
trap cleanup EXIT INT TERM

addCyclonDxToPom

generateBomFile

echo "📦 Creating project: $PROJECT_NAME..."
PROJECT_UUID=$(createDependencyTrackProject)
echo "🔑 Project UUID: $PROJECT_UUID"

uploadBomFile

dependencyTrackAnalysis

createDependencyTrackResultFile