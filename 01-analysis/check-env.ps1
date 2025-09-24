[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

Write-Host "🔍 Checking for Git Bash..."

# Standard-Pfade für Git Bash
$gitBashPaths = @(
    "${env:ProgramFiles}\Git\bin\bash.exe",
    "${env:ProgramFiles(x86)}\Git\bin\bash.exe",
    "${env:ProgramW6432}\Git\bin\bash.exe"
)

$gitBashExe = $gitBashPaths | Where-Object { Test-Path $_ } | Select-Object -First 1

if (-not $gitBashExe) {
    Write-Host "❌ Git Bash not found. Please install Git for Windows."
    exit 1
}

Write-Host "✅ Git Bash found at $gitBashExe"

# --- Temp-Datei erstellen ---
$tempFile = [System.IO.Path]::GetTempFileName() + ".sh"

# --- Bash Script Inhalt ---
$scriptContent = @'
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
    return 1
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
  fi
}

check_build_tool() {
  echo "🔧 Checking build tools (Maven/Gradle)..."

  if command_exists mvn; then
    if mvn -v >/dev/null 2>&1; then
      echo "✅ Maven is installed: $(mvn -v | head -n 1)"
      return
    else
      echo "❌ Maven found, but it cannot run (likely missing JAVA_HOME or Java)."
    fi
  fi

  if command_exists gradle; then
    if gradle -v >/dev/null 2>&1; then
      echo "✅ Gradle is installed: $(gradle -v | head -n 1)"
      return
    else
      echo "❌ Gradle found, but it cannot run."
    fi
  fi

  echo "⚠️ No working Maven or Gradle installation detected."
  echo "If you use the according wrapper, make sure it is available in the project folder."
}

echo "🔍 Checking system environment..."

# 1. Build tools
check_build_tool

# 2. OS detection
OS_TYPE="$(uname)"
echo "✅ Detected OS: $(uname)"

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
'@

# --- Datei ohne BOM schreiben ---
[System.IO.File]::WriteAllText($tempFile, $scriptContent, (New-Object System.Text.UTF8Encoding($false)))

# --- Konvertiere Windows-Pfad -> Bash-Pfad ---
$bashTempFile = & "$gitBashExe" -lc "cygpath -u '$tempFile'"

# --- Run the temp .sh file with Git Bash ---
& "$gitBashExe" -lc "'$bashTempFile'"

# --- Cleanup temp file ---
Remove-Item $tempFile -Force -ErrorAction SilentlyContinue

Write-Host "`n✅ Finished. Press Enter to close..."
[void][System.Console]::ReadLine()
