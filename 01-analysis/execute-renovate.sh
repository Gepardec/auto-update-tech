#!/bin/bash

OPTS=$(getopt -o "" --long node-path:,node-modules: -- "$@")

if [ $? -ne 0 ]; then
    echo "Error parsing options."
    exit 1
fi

eval set -- "$OPTS"

while true; do
    case "$1" in
        --node-path) NODE_PATH="$2"; shift 2 ;;
        --node-modules) NODE_MODULES_PATH="$2"; shift 2 ;;
        --) shift; break ;;
        *) echo "Unexpected option: $1"; exit 1 ;;
    esac
done

# Check if all required arguments are provided
if [ -z "$NODE_PATH" ] || [ -z "$NODE_MODULES_PATH" ]; then
    echo "Error: All arguments must be provided."
    echo "Usage: $0 --node-path <NODE_PATH> --node-modules <NODE_MODULES_PATH>"
    exit 1
fi

PATH="$NODE_PATH:$PATH"

ROOT_SCRIPT_PATH=$(pwd)
RENOVATE_LOGFILE="renovate.json"
RENOVATE_FILTERED_LOGFILE="renovate-filtered.json"

# find all folders with pom.xml, exclude target/, und save them sorted
modules=$(find ../ -type f -name "pom.xml" | grep -v "/target/" | while read -r pom; do
    # extract file path; if pom.xml is in root dir return .
    dir=$(dirname "$pom")
    echo "${dir#./}"
done | sort -u)

# check if modules were found
if [ -z "$modules" ]; then
    echo "Keine Module mit pom.xml gefunden."
    exit 1
fi

echo "Will execute renovate in: "
echo "$modules"

for module in $modules; do
  echo "Executing Renovate in: $module"
  # npx is called from the environment variable PATH, which is set temporally in the previous script
  cd $module && mkdir "gepardec-reports" -p && LOG_FORMAT=json LOG_LEVEL=debug npx --prefix "$NODE_MODULES_PATH" renovate --platform=local --require-config=ignored --enabled-managers=maven > "gepardec-reports/$RENOVATE_LOGFILE"
  cat "gepardec-reports/$RENOVATE_LOGFILE" | grep "packageFiles with updates" > "gepardec-reports/$RENOVATE_FILTERED_LOGFILE"

  # Check if final json file is not empty and exists
  finished_file="$(pwd)/gepardec-reports/$RENOVATE_FILTERED_LOGFILE"
  if [ ! -e "$finished_file" ]; then
      echo -e "\033[0;31m[ERROR] After running script file does not exist: $finished_file\033[0m"
      exit 2
  elif [ ! -s "$finished_file" ]; then
      echo -e "\033[0;31m[ERROR] After running script file is empty: $finished_file\033[0m"
      exit 1
  fi

  cd $ROOT_SCRIPT_PATH
done