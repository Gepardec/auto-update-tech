#!/bin/bash

PROJECT_ROOT=""
MAVEN_PROJECT_ROOT=""
DEPENDENCY_TRACK_API_KEY=""
SONAR_QUBE_ADMIN_PASSWORD=""
CLEANUP=true

# Load profile settings if they exist
[ -f "$HOME/.bashrc" ] && source "$HOME/.bashrc"
[ -f "$HOME/.bash_profile" ] && source "$HOME/.bash_profile"

if ! command -v jq &> /dev/null; then
  echo -e "❌ jq is NOT installed.\n"
  echo "Running check-env.sh ..."
  source ./check-env.sh
  echo -e "\nIf everything is installed and accessible rerun this script."
  exit 1
fi

# 4. Python 3
if ! command -v python3 &> /dev/null; then
  echo -e "❌ Python 3 is NOT installed - PLease run check-env.sh\n"
  echo "Running check-env.sh ..."
  source ./check-env.sh
  echo -e "\nIf everything is installed and accessible rerun this script."
  exit 1
fi

  while [[ $# -gt 0 ]]; do
      case "$1" in
          --project-root)
              PROJECT_ROOT="$2"
              MAVEN_PROJECT_ROOT="$2"
              shift 2
              ;;
          --maven-project-root)
              MAVEN_PROJECT_ROOT="$2"
              shift 2
              ;;
          --dependency-track-api-key)
              DEPENDENCY_TRACK_API_KEY="$2"
              shift 2
              ;;
          --sonar-qube-admin-password)
              SONAR_QUBE_ADMIN_PASSWORD="$2"
              shift 2
              ;;
          --cleanup)
              CLEANUP="$2"
              shift 2
              ;;
          *)
              echo "Unexpected option: $1"
              exit 1
              ;;
      esac
  done

if [ -z "$PROJECT_ROOT" ] || [ -z "$MAVEN_PROJECT_ROOT" ] ; then
    echo "Error: All arguments must be provided."
    echo "Usage: $0 --project-root <absolute-path-to-project-root>"
    exit 1
fi


AUTO_UPDATE_ROOT="$(pwd)"

# Detect OS
OS_TYPE="unknown"
case "$(uname -s)" in
    Linux*)     OS_TYPE="Linux";;
    Darwin*)    OS_TYPE="macOS";;
    CYGWIN*|MINGW*|MSYS*) OS_TYPE="Windows";;
esac

# Detect architecture
ARCH_TYPE="unknown"
case "$(uname -m)" in
    x86_64) ARCH_TYPE="x64";;
    arm64|aarch64) ARCH_TYPE="arm64";;
esac


if [ "$OS_TYPE" = "macOS" ]; then
  cd "$AUTO_UPDATE_ROOT/mac"
else
  cd "$AUTO_UPDATE_ROOT/linux"
fi

source ./add-env.sh

# Check if all required arguments are provided
if [ -z "$DEPENDENCY_TRACK_API_KEY" ] || [ -z "$SONAR_QUBE_ADMIN_PASSWORD" ] ; then
    echo "Error: All arguments must be provided."
    echo "Usage: $0 --project-root <absolute-path-to-project-root> --dependency-track-api-key <dependency-track-api-key> --sonar-qube-admin-password <sonar-qube-admin-password>"
    exit 1
fi

POM_FILE="$MAVEN_PROJECT_ROOT/pom.xml"

# Prüfe, ob POM-Datei existiert
if [ ! -f "$POM_FILE" ]; then
    echo "Error: pom.xml not found - add --maven-project-root <absolute-path-to-maven-project-root>"
    exit 1
fi

echo "Using PROJECT_ROOT: $PROJECT_ROOT"
echo "Using MAVEN_PROJECT_ROOT: $MAVEN_PROJECT_ROOT"
echo "Using DEPENDENCY_TRACK_API_KEY: $DEPENDENCY_TRACK_API_KEY"
echo "Using SONAR_QUBE_ADMIN_PASSWORD: $SONAR_QUBE_ADMIN_PASSWORD"

#----------------------------------------------------------

echo "Operating System: $OS_TYPE"
echo "Architecture: $ARCH_TYPE"

nodeVersion="v22.14.0"
echo "Using Node Version: $nodeVersion"

renovateVersion="40.30.0"
echo "Using Renovate Version: $renovateVersion"

#----------------------------------------------------------

# Setup NPM / NVM
if [ "$OS_TYPE" = "Windows" ] && [ "$ARCH_TYPE" = "x64" ]; then
    NODE_ARCHIVE="node-$nodeVersion-win-x64.zip"
    NODE_BASE_PATH="node-$nodeVersion-win-x64"
    NODE_PATH="$NODE_BASE_PATH/"
elif [ "$OS_TYPE" = "Windows" ] && [ "$ARCH_TYPE" = "arm64" ]; then
    NODE_ARCHIVE="node-$nodeVersion-win-arm64.zip"
    NODE_BASE_PATH="node-$nodeVersion-win-arm64"
    NODE_PATH="$NODE_BASE_PATH/"
elif [ "$OS_TYPE" = "Linux" ] && [ "$ARCH_TYPE" = "x64" ]; then
    NODE_ARCHIVE="node-$nodeVersion-linux-x64.tar.xz"
    NODE_BASE_PATH="node-$nodeVersion-linux-x64"
    NODE_PATH="$NODE_BASE_PATH/bin/"
elif [ "$OS_TYPE" = "Linux" ] && [ "$ARCH_TYPE" = "arm64" ]; then
    NODE_ARCHIVE="node-$nodeVersion-linux-arm64.tar.xz"
    NODE_BASE_PATH="node-$nodeVersion-linux-arm64"
    NODE_PATH="$NODE_BASE_PATH/bin/"
elif [ "$OS_TYPE" = "macOS" ] && [ "$ARCH_TYPE" = "x64" ]; then
    NODE_ARCHIVE="node-$nodeVersion-darwin-x64.tar.xz"
    NODE_BASE_PATH="node-$nodeVersion-darwin-x64"
    NODE_PATH="$NODE_BASE_PATH/bin/"
elif [ "$OS_TYPE" = "macOS" ] && [ "$ARCH_TYPE" = "arm64" ]; then
    NODE_ARCHIVE="node-$nodeVersion-darwin-arm64.tar.xz"
    NODE_BASE_PATH="node-$nodeVersion-darwin-arm64"
    NODE_PATH="$NODE_BASE_PATH/bin/"
else
    echo "Unsupported Operating System or Architecture"
    exit 2
fi

echoHeader_yellow() {
    echo
    echo -e "\033[1;33m==========  $1  ==========\033[0m"
    echo
}

echoHeader_green() {
    echo
    echo -e "\033[1;32m==========  $1  ==========\033[0m"
    echo
}


# Run sh scripts
echoHeader_green "Start Scripts"
AUTO_UPDATE_ROOT_SYSTEM="$(pwd)"

echoHeader_yellow "Running dependency-relocated-date.sh"
cd $AUTO_UPDATE_ROOT_SYSTEM
source ./dependency-relocated-date.sh --project-root $PROJECT_ROOT

echoHeader_yellow "Running dependency-analysis.sh"
cd $AUTO_UPDATE_ROOT_SYSTEM
source ./dependency-analysis.sh --project-root $PROJECT_ROOT

echoHeader_yellow "Running dependency-track.sh"
cd $AUTO_UPDATE_ROOT_SYSTEM
source ./dependency-track.sh --maven-project-root $MAVEN_PROJECT_ROOT --dependency-track-api-key $DEPENDENCY_TRACK_API_KEY

echoHeader_yellow "Installing Renovate"
cd $AUTO_UPDATE_ROOT_SYSTEM
# source is important so the script runs in the current shell, so any environment variable changes (like PATH) persist in the parent script
source ./install-renovate.sh --node-version $nodeVersion --node-archive $NODE_ARCHIVE --node-path $NODE_PATH --renovate-version $renovateVersion

echoHeader_yellow "Execute Renovate"
cd $AUTO_UPDATE_ROOT_SYSTEM
# source is important because environment variables are used which are added in the previous script
source ./execute-renovate.sh --node-path $NODE_PATH --node-modules "$AUTO_UPDATE_ROOT_SYSTEM/node_modules" --project-root $PROJECT_ROOT

mkdir "${AUTO_UPDATE_ROOT}/final-reports"

echoHeader_yellow "Create auto-update-report.json"
cd $AUTO_UPDATE_ROOT_SYSTEM
$AUTO_UPDATE_ROOT_SYSTEM/$NODE_PATH/node $AUTO_UPDATE_ROOT_SYSTEM/parse.js $PROJECT_ROOT

echoHeader_yellow "Move module dependency-analysis.json Files"

find "$PROJECT_ROOT" -type f -name "dependency-analysis.json" ! -path "./auto-update-report/*" | while read -r file; do
    grandparent_dir=$(basename "$(dirname "$(dirname "$file")")")  # Get grandparent folder name
    new_filename="${grandparent_dir}-dependency-analysis.json"  # Prefix with grandparent folder name
    mv "$file" "$AUTO_UPDATE_ROOT/final-reports/$new_filename"
done

echoHeader_yellow "Move dependency-track-vulnerability-report.json"

mv "${AUTO_UPDATE_ROOT_SYSTEM}/dependency-track-vulnerability-report.json" "${AUTO_UPDATE_ROOT}/final-reports/dependency-track-vulnerability-report.json"

echoHeader_yellow "Create CSV files"
cd $AUTO_UPDATE_ROOT_SYSTEM
source ./create-all-csvs.sh --json-file ./../final-reports/auto-update-report.json

echoHeader_yellow "Create Sonar Report"
cd "$AUTO_UPDATE_ROOT_SYSTEM/sonar"
source ./sonar-init.sh --project-root ${PROJECT_ROOT} --sonar-qube-admin-password $SONAR_QUBE_ADMIN_PASSWORD

mv "./sonar-report.json" "${AUTO_UPDATE_ROOT}/final-reports/sonar-report.json"
mv "./test-coverage-report.json" "${AUTO_UPDATE_ROOT}/final-reports/test-coverage-report.json"

echoHeader_yellow "Create Sonar CSV files"
cd "$AUTO_UPDATE_ROOT_SYSTEM/sonar"
source ./sonar-report-to-csv.sh --json-file ./../../final-reports/sonar-report.json

echoHeader_yellow "Create Test Coverage CSV file"
cd "$AUTO_UPDATE_ROOT_SYSTEM/sonar"
# needs to be sh command other wise it will not work
sh ./test-coverage-report-to-csv.sh --json-file ./../../final-reports/test-coverage-report.json


if [ "$CLEANUP" = true ]; then
echoHeader_green "Cleaning up..."
find "$PROJECT_ROOT" -type d -name "gepardec-reports" -exec rm -rf {} +
rm -rf "$AUTO_UPDATE_ROOT_SYSTEM/$NODE_BASE_PATH"
rm -rf "$AUTO_UPDATE_ROOT_SYSTEM/$NODE_ARCHIVE"
rm -rf "$AUTO_UPDATE_ROOT_SYSTEM/node_modules"
rm -f "$AUTO_UPDATE_ROOT_SYSTEM/package.json"
rm -f "$AUTO_UPDATE_ROOT_SYSTEM/package-lock.json"
source $AUTO_UPDATE_ROOT_SYSTEM/remove-env.sh
fi

echoHeader_green "Successful finished"