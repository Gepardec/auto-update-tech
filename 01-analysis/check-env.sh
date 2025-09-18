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

check_java() {
  echo "☕ Checking Java installation..."

  if command_exists java; then
    JAVA_VERSION=$(java -version 2>&1 | awk -F '"' '/version/ {print $2}')
    echo "✅ Java is installed: version $JAVA_VERSION"
  else
    echo "❌ Java is NOT installed."
    return
  fi

  if command_exists javac; then
    JAVAC_VERSION=$(javac -version 2>&1)
    echo "✅ javac is installed: $JAVAC_VERSION"
  else
    echo "❌ javac is NOT installed."
  fi

  echo -n "📌 JAVA_HOME is "
  if [ -n "$JAVA_HOME" ]; then
    echo "set to '$JAVA_HOME'"
    if [ -x "$JAVA_HOME/bin/java" ]; then
      JAVA_HOME_VER=$("$JAVA_HOME/bin/java" -version 2>&1 | awk -F '"' '/version/ {print $2}')
      echo "   ➤ JAVA_HOME points to Java version $JAVA_HOME_VER"
    else
      echo "   ⚠️ But 'java' executable not found under JAVA_HOME"
    fi
  else
    echo "❌ NOT set"
    echo -n "🔧 Attempting to set JAVA_HOME automatically... "

    JAVA_PATH=$(readlink -f "$(command -v java)" 2>/dev/null)
    if [ -n "$JAVA_PATH" ]; then
      JAVA_HOME_CANDIDATE=$(dirname "$(dirname "$JAVA_PATH")")
      if [ -x "$JAVA_HOME_CANDIDATE/bin/java" ]; then
        export JAVA_HOME="$JAVA_HOME_CANDIDATE"
        echo "✅ Set to '$JAVA_HOME'"

        # Determine shell rc file (default to bashrc)
        SHELL_RC="$HOME/.bashrc"
        [[ "$SHELL" =~ "zsh" ]] && SHELL_RC="$HOME/.zshrc"

        # Persist if not already present
        if grep -q "^export JAVA_HOME=" "$SHELL_RC"; then
          echo "ℹ️ JAVA_HOME already set in $SHELL_RC"
        else
          echo "export JAVA_HOME=\"$JAVA_HOME\"" >> "$SHELL_RC"
          echo "✅ Persisted JAVA_HOME to $SHELL_RC"
          # Warn user to source script only if we just persisted JAVA_HOME
          if [[ "$0" == "$BASH_SOURCE" ]]; then
            echo "⚠️  JAVA_HOME was set, but this script was not sourced."
            echo "   Please run the script using: source $0"
            echo "   This ensures JAVA_HOME is applied to your current terminal session."
            exit 1
          fi
        fi
      else
        echo "❌ Could not determine JAVA_HOME"
      fi
    else
      echo "❌ Could not resolve java path"
    fi
  fi
}


echo "🔍 Checking system environment..."

# 1. Maven and or Gradle
if command_exists mvn; then
  echo "✅ Maven is installed: $(mvn -v | head -n 1)"
else
  if command_exists gradle; then
    echo "✅ Gradle is installed: $(gradle -v | head -n 1)"
  else
    echo "❌ Gradle or MAVEN is NOT installed."
  fi
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

# 5. Java
check_java

# 6. IntelliJ IDEA
check_intellij

# 7. Network access
echo "🌐 Checking network access..."
check_url "https://nodejs.org/dist/"
check_url "https://gepardec-sonarqube.apps.cloudscale-lpg-2.appuio.cloud"
check_url "https://gepardec-dtrack.apps.cloudscale-lpg-2.appuio.cloud"
check_url "https://www.github.com"
