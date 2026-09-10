param(
    [switch]$NoPause,
    [switch]$SkipRemoteDesktopCommander
)

$ErrorActionPreference = "Continue"
$root = $PSScriptRoot
Write-Host "ChatGPT Local Access - Verification" -ForegroundColor Green

function CheckCommand($name, $versionArgs) {
    $cmd = Get-Command $name -ErrorAction SilentlyContinue
    if (-not $cmd) {
        Write-Host "[FAIL] $name not found" -ForegroundColor Red
        return $false
    }
    Write-Host "[ OK ] $name -> $($cmd.Source)" -ForegroundColor Green
    if ($versionArgs) {
        try { & $name @versionArgs | Select-Object -First 1 | ForEach-Object { Write-Host "       $_" } } catch {}
    }
    return $true
}

function Get-CompatiblePython {
    $python = Get-Command "python" -ErrorAction SilentlyContinue
    if ($python) {
        try {
            $ok = (& $python.Source -c "import sys; print('1' if sys.version_info >= (3,11) else '0')").Trim()
            if ($ok -eq "1") { return [pscustomobject]@{ Executable = $python.Source; Prefix = @() } }
        } catch {}
    }
    $launcher = Get-Command "py" -ErrorAction SilentlyContinue
    if ($launcher) {
        try {
            $ok = (& $launcher.Source -3.11 -c "import sys; print('1' if sys.version_info >= (3,11) else '0')").Trim()
            if ($ok -eq "1") { return [pscustomobject]@{ Executable = $launcher.Source; Prefix = @("-3.11") } }
        } catch {}
    }
    return $null
}

function Invoke-CompatiblePython($pythonInfo, [string[]]$arguments) {
    $allArguments = @($pythonInfo.Prefix) + $arguments
    return & $pythonInfo.Executable @allArguments
}

$all = $true
$pythonInfo = Get-CompatiblePython
if ($pythonInfo) {
    $pythonVersion = (Invoke-CompatiblePython $pythonInfo @("--version") | Select-Object -First 1)
    Write-Host "[ OK ] Python 3.11+ -> $($pythonInfo.Executable)" -ForegroundColor Green
    Write-Host "       $pythonVersion"
} else {
    Write-Host "[FAIL] Python 3.11 or newer not found" -ForegroundColor Red
    $all = $false
}
if (-not $SkipRemoteDesktopCommander) {
    if (CheckCommand "node" @("--version")) {
        try { $nodeMajor = [int]((& node -p "process.versions.node.split('.')[0]").Trim()) } catch { $nodeMajor = 0 }
        if ($nodeMajor -lt 18) {
            Write-Host "[FAIL] Node.js 18+ required; current major version is $nodeMajor" -ForegroundColor Red
            $all = $false
        }
    } else { $all = $false }
    $all = (CheckCommand "npx" @("--version")) -and $all
}
$all = (CheckCommand "cloudflared" @("--version")) -and $all

Write-Host "`nChecking Coding Tools MCP Desktop..."
try {
    if (-not $pythonInfo) { throw "Python 3.11+ is unavailable" }
    $desktopCommand = Get-Command "coding-tools-mcp-desktop" -ErrorAction SilentlyContinue
    if (-not $desktopCommand) {
        $scriptsDir = (Invoke-CompatiblePython $pythonInfo @("-c", "import sysconfig; print(sysconfig.get_path('scripts'))")).Trim()
        $candidate = Join-Path $scriptsDir "coding-tools-mcp-desktop.exe"
        if (Test-Path $candidate -PathType Leaf) { $desktopCommand = Get-Item $candidate }
    }
    if (-not $desktopCommand) { throw "coding-tools-mcp-desktop executable not found" }
    $desktopPath = if ($desktopCommand -is [System.IO.FileInfo]) { $desktopCommand.FullName } else { $desktopCommand.Source }
    Write-Host "[ OK ] coding-tools-mcp-desktop -> $desktopPath" -ForegroundColor Green
    $packageVersion = (Invoke-CompatiblePython $pythonInfo @("-c", "import importlib.metadata; print(importlib.metadata.version('coding-tools-mcp'))")).Trim()
    Write-Host "       coding-tools-mcp package $packageVersion"
}
catch {
    Write-Host "[FAIL] Coding Tools MCP Desktop: $_" -ForegroundColor Red
    $all = $false
}

$defaultWorkspace = Join-Path ([Environment]::GetFolderPath("Desktop")) "CodingTool"
Write-Host "`nChecking default workspace..."
if (Test-Path $defaultWorkspace -PathType Container) { Write-Host "[ OK ] $defaultWorkspace" -ForegroundColor Green }
else { Write-Host "[FAIL] Default workspace does not exist: $defaultWorkspace" -ForegroundColor Red; $all = $false }

$profilesPath = Join-Path ([Environment]::GetFolderPath("UserProfile")) ".coding-tools-mcp-desktop\profiles.json"
if (Test-Path $profilesPath -PathType Leaf) { Write-Host "[ OK ] Desktop GUI profile store exists" -ForegroundColor Green }
else { Write-Host "[INFO] No GUI profile yet. Add the first workspace in Coding Tools MCP Desktop." -ForegroundColor Yellow }

Write-Host "`nRemote Desktop Commander is account/device based and supports multiple PCs."
Write-Host "Run Start-Remote-Desktop-Commander.ps1 (or the 04 launcher CMD), then ask ChatGPT to list active Desktop Commander devices."

if ($all) {
    Write-Host "`nLocal prerequisites look good." -ForegroundColor Green
} else {
    Write-Host "`nOne or more local prerequisites need attention." -ForegroundColor Yellow
}
if (-not $NoPause) { Read-Host "Press Enter to close" | Out-Null }
if (-not $all) { exit 1 }
