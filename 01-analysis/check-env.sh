#!/bin/bash

# Function to check if a command exists
command_exists() {
  command -v "$1" >/dev/null 2>&1
}

# Function to test URL access
check_url() {
  local url=$1
  echo -n "Checking access to $url... "
  if curl --head --silent --fail "$url" >/dev/null; then
    echo "✅ Accessible"
  else
    echo "❌ Not accessible"
  fi
}

# Function to check if IntelliJ is installed
check_intellij() {
  echo "🔍 Checking if IntelliJ IDEA is installed... "

  if command_exists idea; then
    echo "✅ IntelliJ IDEA found in PATH (via 'idea' command)"
    return
  fi

  case "$(uname)" in
    Darwin)
      if [ -d "/Applications/IntelliJ IDEA.app" ]; then
        echo "✅ IntelliJ IDEA found in /Applications"
        return
      fi
      ;;
    Linux)
      if [ -d "$HOME/.local/share/JetBrains/Toolbox/apps/IDEA-U" ] || [ -d "/opt/idea" ]; then
        echo "✅ IntelliJ IDEA found in JetBrains Toolbox or /opt"
        return
      fi
      ;;
    MINGW*|MSYS*|CYGWIN*)
      if compgen -G "/c/Program Files/JetBrains/IntelliJ IDEA*" > /dev/null; then
        echo "✅ IntelliJ IDEA found in Program Files"
        return
      fi
      ;;
  esac

  echo "❌ IntelliJ IDEA NOT found"
}

echo "🔍 Checking system environment..."

# 1. Maven
if command_exists mvn; then
  echo "✅ Maven is installed: $(mvn -v | head -n 1)"
else
  echo "❌ Maven is NOT installed."
fi

# 2. OS detection
OS_TYPE="$(uname)"
case "$OS_TYPE" in
  Darwin)
    echo "✅ Detected macOS"
    ;;
  Linux)
    echo "✅ Detected Linux"
    ;;
  *)
    echo "⚠️ Detected non-macOS/non-Linux system: $OS_TYPE"
    # On Windows, check Git Bash
    if [ -n "$BASH_VERSION" ] && command_exists git && git --version | grep -qi "git"; then
      echo "✅ Git Bash is present"
    else
      echo "❌ Git Bash not found or not in a bash environment"
    fi
    ;;
esac

# 3. jq
if command_exists jq; then
  echo "✅ jq is installed: $(jq --version)"
else
  echo "❌ jq is NOT installed."
fi

# 4. Python 3
if command_exists python3; then
  echo "✅ Python 3 is installed: $(python3 --version)"
else
  echo "❌ Python 3 is NOT installed."
fi

# 5. IntelliJ IDEA
check_intellij

# 6. Network access
echo "🌐 Checking network access..."
check_url "https://nodejs.org/dist/"
check_url "https://gepardec-sonarqube.apps.cloudscale-lpg-2.appuio.cloud"
check_url "https://gepardec-dtrack.apps.cloudscale-lpg-2.appuio.cloud"
check_url "https://www.github.com"
