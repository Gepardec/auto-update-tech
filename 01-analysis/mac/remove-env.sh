#!/bin/bash

# List of environment variables to remove
VARS=("DEPENDENCY_TRACK_API_KEY" "SONAR_QUBE_ADMIN_PASSWORD")

# List of shell profile files to clean
FILES=("$HOME/.bashrc" "$HOME/.bash_profile" "$HOME/.profile")

echo "Removing environment variables permanently..."

for var in "${VARS[@]}"; do
  for file in "${FILES[@]}"; do
    if [ -f "$file" ]; then
      # Use grep to filter out the export line and overwrite the file
      grep -v "^export $var=" "$file" > "${file}.tmp" && mv "${file}.tmp" "$file"
    fi
  done
  # Unset from current session
  unset "$var"
  echo "Removed $var"
done

# Reload the most common profile file
if [ -f "$HOME/.bash_profile" ]; then
  source "$HOME/.bash_profile"
elif [ -f "$HOME/.bashrc" ]; then
  source "$HOME/.bashrc"
elif [ -f "$HOME/.profile" ]; then
  source "$HOME/.profile"
fi

echo "Done. You may want to restart your terminal."
