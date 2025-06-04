#!/bin/bash

# Default values
NODE_VERSION=""
NODE_ARCHIVE=""
NODE_PATH=""
RENOVATE_VERSION=""

# Parse command-line options using getopt
OPTS=$(getopt -o "" --long node-version:,node-archive:,node-path:,renovate-version: -- "$@")

if [ $? -ne 0 ]; then
    echo "Error parsing options."
    exit 1
fi

eval set -- "$OPTS"

while true; do
    case "$1" in
        --node-version) NODE_VERSION="$2"; shift 2 ;;
        --node-archive) NODE_ARCHIVE="$2"; shift 2 ;;
        --node-path) NODE_PATH="$2"; shift 2 ;;
        --renovate-version) RENOVATE_VERSION="$2"; shift 2 ;;
        --) shift; break ;;
        *) echo "Unexpected option: $1"; exit 1 ;;
    esac
done

# Check if all required arguments are provided
if [ -z "$NODE_VERSION" ] || [ -z "$NODE_ARCHIVE" ] || [ -z "$NODE_PATH" ] || [ -z "$RENOVATE_VERSION" ]; then
    echo "Error: All arguments must be provided."
    echo "Usage: --node-version <NODE_VERSION> --node-archive <NODE_ARCHIVE> --node-path <NODE_PATH> --renovate-version <RENOVATE_VERSION>"
    exit 1
fi

# Your script logic here
echo "Node Version: $NODE_VERSION"
echo "Node Archive: $NODE_ARCHIVE"
echo "Node Path: $NODE_PATH"
echo "Renovate Version: $RENOVATE_VERSION"

echo "Downloading $NODE_ARCHIVE"
curl https://nodejs.org/dist/$NODE_VERSION/$NODE_ARCHIVE -o $NODE_ARCHIVE
echo "Unpacking..."
# Check file extension and extract accordingly
if echo "$NODE_ARCHIVE" | grep -q '\.zip$'; then
    echo "Extracting $NODE_ARCHIVE file..."
    unzip -qq "$NODE_ARCHIVE"
elif echo "$NODE_ARCHIVE" | grep -q '\.tar\.xz$'; then
    echo "Extracting $NODE_ARCHIVE file..."
    tar -xf "$NODE_ARCHIVE"
else
    echo "Unsupported file type: $NODE_ARCHIVE"
    exit 2
fi

# set environment variable PATH for the node folder; is only set temporally in the running script
export NODE_DIR="$(pwd)/${NODE_PATH%/}"
export PATH="$NODE_DIR:$PATH"

echo $PATH

# Install Renovate
echo "Install renovate..."
npm install --save-dev renovate@$RENOVATE_VERSION

echo "Node init..."
npm init -y

echo "Node version..."
node -v

echo "Npm version..."
npm -v

echo "Renovate version..."
npx renovate --version