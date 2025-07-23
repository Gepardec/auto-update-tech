#!/bin/bash

# Load profile settings if they exist
[ -f "$HOME/.bashrc" ] && source "$HOME/.bashrc"
[ -f "$HOME/.bash_profile" ] && source "$HOME/.bash_profile"

# Function to detect the user's shell profile
get_shell_profile() {
    local shell_name
    shell_name=$(basename "$SHELL")

    case "$shell_name" in
        bash) echo "$HOME/.bashrc" ;;
        zsh) echo "$HOME/.zshrc" ;;
        *) echo "$HOME/.profile" ;;  # fallback
    esac
}

# Check if TEST is set
if [ -z "$DEPENDENCY_TRACK_API_KEY" ]; then
    echo "Environment variable DEPENDENCY_TRACK_API_KEY is not set."
    read -p "Please enter a value for DEPENDENCY_TRACK_API_KEY: " user_input
    export DEPENDENCY_TRACK_API_KEY="$user_input"

    profile_file=$(get_shell_profile)

    # Create profile file if missing
    if [ ! -f "$profile_file" ]; then
        touch "$profile_file"
        echo "# Created by script to store environment variables" >> "$profile_file"
    fi

    # Add or update the export line
    if grep -q '^export DEPENDENCY_TRACK_API_KEY=' "$profile_file"; then
        sed -i "s|^export DEPENDENCY_TRACK_API_KEY=.*|export DEPENDENCY_TRACK_API_KEY=\"$user_input\"|" "$profile_file"
    else
        echo "export DEPENDENCY_TRACK_API_KEY=\"$user_input\"" >> "$profile_file"
    fi

    echo "DEPENDENCY_TRACK_API_KEY variable updated in $profile_file"
else
    echo "Environment variable DEPENDENCY_TRACK_API_KEY is already set to: $DEPENDENCY_TRACK_API_KEY"
fi

if [ -z "$SONAR_QUBE_ADMIN_PASSWORD" ]; then
    echo "Environment variable SONAR_QUBE_ADMIN_PASSWORD is not set."
    read -p "Please enter a value for SONAR_QUBE_ADMIN_PASSWORD: " user_input
    export SONAR_QUBE_ADMIN_PASSWORD="$user_input"

    profile_file=$(get_shell_profile)

    # Create profile file if missing
    if [ ! -f "$profile_file" ]; then
        touch "$profile_file"
        echo "# Created by script to store environment variables" >> "$profile_file"
    fi

    # Add or update the export line
    if grep -q '^export SONAR_QUBE_ADMIN_PASSWORD=' "$profile_file"; then
        sed -i "s|^export SONAR_QUBE_ADMIN_PASSWORD=.*|export SONAR_QUBE_ADMIN_PASSWORD=\"$user_input\"|" "$profile_file"
    else
        echo "export SONAR_QUBE_ADMIN_PASSWORD=\"$user_input\"" >> "$profile_file"
    fi

    echo "SONAR_QUBE_ADMIN_PASSWORD variable updated in $profile_file"
else
    echo "Environment variable SONAR_QUBE_ADMIN_PASSWORD is already set to: $SONAR_QUBE_ADMIN_PASSWORD"
fi