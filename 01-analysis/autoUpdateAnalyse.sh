#!/bin/bash

PROJECT_ROOT=""
MAVEN_PROJECT_ROOT=""
DEPENDENCY_TRACK_API_KEY=""
CLEANUP=true

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

# Assign Parameters for macos or Windows/Linux
if [ "$OS_TYPE" = "macOS" ]; then
  while [[ $# -gt 0 ]]; do
      case "$1" in
          --project-root)
              PROJECT_ROOT="$2"
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
else
  # Parse command-line options using getopt
  OPTS=$(getopt -o "" --long project-root:,maven-project-root:,dependency-track-api-key:,cleanup: -- "$@")

  if [ $? -ne 0 ]; then
      echo "Error parsing options."
      exit 1
  fi

  eval set -- "$OPTS"

  while true; do
      case "$1" in
          --project-root) PROJECT_ROOT="$2"; shift 2 ;;
          --maven-project-root) MAVEN_PROJECT_ROOT="$2"; shift 2 ;;
          --dependency-track-api-key) DEPENDENCY_TRACK_API_KEY="$2"; shift 2 ;;
          --cleanup) CLEANUP="$2"; shift 2 ;;
          --) shift; break ;;
          *) echo "Unexpected option: $1"; exit 1 ;;
      esac
  done
fi

# Check if all required arguments are provided
if [ -z "$PROJECT_ROOT" ] || [ -z "$MAVEN_PROJECT_ROOT" ] || [ -z "$DEPENDENCY_TRACK_API_KEY" ]; then
    echo "Error: All arguments must be provided."
    echo "Usage: $0 --project-root <path-to-project-root> --maven-project-root <path-to-maven-project-root> --dependency-track-api-key <dependency-track-api-key>"
    exit 1
fi

echo "Using PROJECT_ROOT: $PROJECT_ROOT"
echo "Using MAVEN_PROJECT_ROOT: $MAVEN_PROJECT_ROOT"
echo "Using DEPENDENCY_TRACK_API_KEY: $DEPENDENCY_TRACK_API_KEY"

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
AUTO_UPDATE_ROOT="$(pwd)"
if [ "$OS_TYPE" = "macOS" ]; then
    echoHeader_yellow "Running dependency-relocated-date-mac.sh"
    cd $AUTO_UPDATE_ROOT
    source ./dependency-relocated-date-mac.sh --project-root $PROJECT_ROOT

    echoHeader_yellow "Running dependency-analysis-mac.sh"
    cd $AUTO_UPDATE_ROOT
    source ./dependency-analysis-mac.sh --project-root $PROJECT_ROOT

    echoHeader_yellow "Running dependency-track-mac.sh"
    cd $AUTO_UPDATE_ROOT
    source ./dependency-track-mac.sh --maven-project-root $MAVEN_PROJECT_ROOT --dependency-track-api-key $DEPENDENCY_TRACK_API_KEY

    echoHeader_yellow "Installing Renovate"
    cd $AUTO_UPDATE_ROOT
    # source is important so the script runs in the current shell, so any environment variable changes (like PATH) persist in the parent script
    source ./install-renovate-mac.sh --node-version $nodeVersion --node-archive $NODE_ARCHIVE --node-path $NODE_PATH --renovate-version $renovateVersion

    echoHeader_yellow "Execute Renovate"
    cd $AUTO_UPDATE_ROOT
    # source is important because environment variables are used which are added in the previous script
    source ./execute-renovate-mac.sh --node-path $NODE_PATH --node-modules "$AUTO_UPDATE_ROOT/node_modules"
else
    echoHeader_yellow "Running dependency-relocated-date.sh"
    cd $AUTO_UPDATE_ROOT
    source ./dependency-relocated-date.sh --project-root $PROJECT_ROOT

    echoHeader_yellow "Running dependency-analysis.sh"
    cd $AUTO_UPDATE_ROOT
    source ./dependency-analysis.sh --project-root $PROJECT_ROOT

    echoHeader_yellow "Running dependency-track.sh"
    cd $AUTO_UPDATE_ROOT
    source ./dependency-track.sh --maven-project-root $MAVEN_PROJECT_ROOT --dependency-track-api-key $DEPENDENCY_TRACK_API_KEY

    echoHeader_yellow "Installing Renovate"
    cd $AUTO_UPDATE_ROOT
    # source is important so the script runs in the current shell, so any environment variable changes (like PATH) persist in the parent script
    source ./install-renovate.sh --node-version $nodeVersion --node-archive $NODE_ARCHIVE --node-path $NODE_PATH --renovate-version $renovateVersion

    echoHeader_yellow "Execute Renovate"
    cd $AUTO_UPDATE_ROOT
    # source is important because environment variables are used which are added in the previous script
    source ./execute-renovate.sh --node-path $NODE_PATH --node-modules "$AUTO_UPDATE_ROOT/node_modules"
fi



mkdir "${AUTO_UPDATE_ROOT}/final-reports"

echoHeader_yellow "Create auto-update-report.json"

$NODE_PATH/node parse.js $PROJECT_ROOT

echoHeader_yellow "Move module dependency-analysis.json Files"

find "$PROJECT_ROOT" -type f -name "dependency-analysis.json" ! -path "./auto-update-report/*" | while read -r file; do
    grandparent_dir=$(basename "$(dirname "$(dirname "$file")")")  # Get grandparent folder name
    new_filename="${grandparent_dir}-dependency-analysis.json"  # Prefix with grandparent folder name
    mv "$file" "$AUTO_UPDATE_ROOT/final-reports/$new_filename"
done

echoHeader_yellow "Move dependency-track-vulnerability-report.json"

mv "${AUTO_UPDATE_ROOT}/dependency-track-vulnerability-report.json" "${AUTO_UPDATE_ROOT}/final-reports/dependency-track-vulnerability-report.json"

echoHeader_yellow "Create CSV files"
if [ "$OS_TYPE" = "macOS" ]; then
  source ./create_all_csvs-mac.sh --json-file ${AUTO_UPDATE_ROOT}/auto-update-report.json
else
  source ./create_all_csvs.sh --json-file ${AUTO_UPDATE_ROOT}/auto-update-report.json
fi

if [ "$CLEANUP" = true ]; then
echoHeader_green "Cleaning up..."
find "$PROJECT_ROOT" -type d -name "gepardec-reports" -exec rm -rf {} +
rm -rf "$AUTO_UPDATE_ROOT/$NODE_BASE_PATH"
rm -rf "$AUTO_UPDATE_ROOT/$NODE_ARCHIVE"
rm -rf "$AUTO_UPDATE_ROOT/node_modules"
rm -f "$AUTO_UPDATE_ROOT/package.json"
rm -f "$AUTO_UPDATE_ROOT/package-lock.json"
fi

echoHeader_green "Successful finished"