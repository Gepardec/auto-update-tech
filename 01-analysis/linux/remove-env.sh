#!/bin/bash

# List of environment variables to remove
VARS=("DEPENDENCY_TRACK_API_KEY" "SONAR_QUBE_ADMIN_PASSWORD")

# List of shell profile files to clean
FILES=("$HOME/.bashrc" "$HOME/.bash_profile" "$HOME/.profile")

echo "Removing environment variables permanently..."

for var in "${VARS[@]}"; do
  for file in "${FILES[@]}"; do
    if [ -f "$file" ]; then
      sed -i "/^export $var=/d" "$file"
    fi
  done
  # Unset from current session
  unset "$var"
  echo "Removed $var"
done

# Reload shell config (bashrc is most common)
if [ -f "$HOME/.bashrc" ]; then
  source "$HOME/.bashrc"
fi

echo "Done. You may want to restart your terminal."
