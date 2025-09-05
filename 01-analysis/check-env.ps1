[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

function Command-Exists {
    param ([string]$command)
    return (Get-Command $command -ErrorAction SilentlyContinue) -ne $null
}

function Check-Url {
    param ([string]$url)
    Write-Host "🔍  Checking access to $url... " -NoNewline
    try {
        $response = Invoke-WebRequest -Uri $url -UseBasicParsing -Method Head -TimeoutSec 5
        if ($response.StatusCode -ge 200 -and $response.StatusCode -lt 400) {
            Write-Host "✅ Accessible"
        } else {
            Write-Host "❌ Not accessible (HTTP $($response.StatusCode))"
        }
    } catch {
        Write-Host "❌ Not accessible"
    }
}

function Check-IntelliJ {
    Write-Host "🔍  Checking if IntelliJ IDEA is installed..."

    if (Command-Exists "idea") {
        Write-Host "✅ IntelliJ IDEA found in PATH (via 'idea' command)"
        return
    }

    $locations = @(
        "$env:ProgramFiles\JetBrains\IntelliJ IDEA*",
        "$env:ProgramFiles(x86)\JetBrains\IntelliJ IDEA*",
        "$env:LOCALAPPDATA\JetBrains\Toolbox\apps\IDEA-U",
        "$env:USERPROFILE\scoop\apps\intellij*",
        "/Applications/IntelliJ IDEA.app"
    )

    foreach ($loc in $locations) {
        if (Test-Path $loc) {
            Write-Host "✅ IntelliJ IDEA found at $loc"
            return
        }
    }

    Write-Host "❌ IntelliJ IDEA NOT found"
}

Write-Host "`n🔍 Starting system environment check..."

# 1. Maven
if (Command-Exists "mvn") {
    $mvnOutput = & mvn -v 2>&1 | Out-String
    $mvnClean = $mvnOutput -replace '[^\u0009\u000A\u000D\u0020-\u007E\u00A0-\u00FF\u2000-\u2FFF]', ''
    Write-Host "✅ Maven is installed: $mvnClean"
} else {
    Write-Host "❌ Maven is NOT installed."
}

# 2. OS Detection
$os = $env:OS.Trim()

if ($IsMacOS) {
    Write-Host "✅ Detected macOS"
} elseif ($IsLinux) {
    Write-Host "✅ Detected Linux"
} else {
    Write-Host "⚠️ Detected non-macOS/non-Linux system: $os"

    $gitBashAvailable = $false
    if ($env:BASH_VERSION -or (Command-Exists "git" -and (& git --version) -match "git")) {
        Write-Host "✅ Git Bash is present"
        $gitBashAvailable = $true
    } else {
        Write-Host "❌ Git Bash not found or not in a bash environment"
    }

    # Check for jq if Git Bash is available
    if ($gitBashAvailable) {
        $gitBashPaths = @(
            "${env:ProgramFiles}\Git\bin\bash.exe",
            "${env:ProgramFiles(x86)}\Git\bin\bash.exe",
            "${env:ProgramW6432}\Git\bin\bash.exe"
        )

        $gitBashExe = $gitBashPaths | Where-Object { Test-Path $_ } | Select-Object -First 1

        if ($gitBashExe) {
            Write-Host "✅ Git Bash executable found at $gitBashExe"
            try {
                $jqCheck = & "$gitBashExe" -c "command -v jq"
                if ($jqCheck) {
                    Write-Host "✅ jq is installed in Git Bash: $jqCheck"
                } else {
                    Write-Host "❌ jq is NOT installed in Git Bash"
                }
            } catch {
                Write-Host "⚠️ Could not execute jq check in Git Bash: $_"
            }
        } else {
            Write-Host "⚠️ Git Bash executable not found, skipping jq check"
        }
    }
}

# 3. Python 3
if (Command-Exists "python3") {
    $pythonVersion = (& python3 --version).Trim()
    Write-Host "✅ Python 3 is installed: $pythonVersion"
} else {
    Write-Host "❌ Python 3 is NOT installed."
}

# 4. IntelliJ IDEA
Check-IntelliJ

# 5. Network access
Write-Host "`n🌐 Checking network access..."
Check-Url "https://nodejs.org/dist/"
Check-Url "https://gepardec-sonarqube.apps.cloudscale-lpg-2.appuio.cloud"
Check-Url "https://gepardec-dtrack.apps.cloudscale-lpg-2.appuio.cloud"
Check-Url "https://www.github.com"

Write-Host "`n✅ Checks complete. Press Enter to close..."
[void][System.Console]::ReadLine()
