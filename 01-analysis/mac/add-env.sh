#!/bin/bash

# Load profile settings if they exist
[ -f "$HOME/.bash_profile" ] && source "$HOME/.bash_profile"
[ -f "$HOME/.zshrc" ] && source "$HOME/.zshrc"

# Detect shell and determine which profile file to use
get_shell_profile() {
    local shell_name
    shell_name=$(basename "$SHELL")

    case "$shell_name" in
        bash) echo "$HOME/.bash_profile" ;;  # bash on macOS uses .bash_profile
        zsh) echo "$HOME/.zshrc" ;;
        *) echo "$HOME/.profile" ;;  # fallback
    esac
}

# Function to set or update an environment variable in the profile
set_env_var() {
    local var_name=$1
    local var_value=$2
    local profile_file=$(get_shell_profile)

    # Ensure profile file exists
    [ -f "$profile_file" ] || touch "$profile_file"

    # Remove old line if it exists and write a new one
    if grep -q "^export $var_name=" "$profile_file"; then
        # Copy all lines except the one for this variable
        grep -v "^export $var_name=" "$profile_file" > "$profile_file.tmp"
        mv "$profile_file.tmp" "$profile_file"
    fi

    echo "export $var_name=\"$var_value\"" >> "$profile_file"
    echo "$var_name variable updated in $profile_file"
}

# Check and prompt for DEPENDENCY_TRACK_API_KEY
if [ -z "$DEPENDENCY_TRACK_API_KEY" ]; then
    echo "Environment variable DEPENDENCY_TRACK_API_KEY is not set."
    read -p "Please enter a value for DEPENDENCY_TRACK_API_KEY: " user_input
    export DEPENDENCY_TRACK_API_KEY="$user_input"
    set_env_var "DEPENDENCY_TRACK_API_KEY" "$user_input"
fi

# Check and prompt for SONAR_QUBE_ADMIN_PASSWORD
if [ -z "$SONAR_QUBE_ADMIN_PASSWORD" ]; then
    echo "Environment variable SONAR_QUBE_ADMIN_PASSWORD is not set."
    read -p "Please enter a value for SONAR_QUBE_ADMIN_PASSWORD: " user_input
    export SONAR_QUBE_ADMIN_PASSWORD="$user_input"
    set_env_var "SONAR_QUBE_ADMIN_PASSWORD" "$user_input"
fi
