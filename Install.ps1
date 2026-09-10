param(
    [switch]$SkipRemoteDesktopCommander,
    [switch]$NoLaunch
)
$ErrorActionPreference = "Stop"
$Host.UI.RawUI.WindowTitle = "ChatGPT Local Access Setup"
$root = $PSScriptRoot

function Step($text) { Write-Host "`n==> $text" -ForegroundColor Cyan }
function Has-Command($name) { [bool](Get-Command $name -ErrorAction SilentlyContinue) }
function Refresh-Path {
    $env:Path = [Environment]::GetEnvironmentVariable("Path","Machine") + ";" +
                [Environment]::GetEnvironmentVariable("Path","User")
}
function Ensure-Winget {
    if (-not (Has-Command "winget")) {
        throw "winget is required. Install Microsoft App Installer first."
    }
}

function Install-WingetPackage([string]$id, [string]$label) {
    Ensure-Winget
    Write-Host "Installing/updating $label..."
    & winget install -e --id $id --accept-source-agreements --accept-package-agreements
    if ($LASTEXITCODE -ne 0) { throw "$label installation failed (winget exit $LASTEXITCODE)." }
    Refresh-Path
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

function Invoke-Python($pythonInfo, [string[]]$arguments) {
    $allArguments = @($pythonInfo.Prefix) + $arguments
    & $pythonInfo.Executable @allArguments
    if ($LASTEXITCODE -ne 0) { throw "Python command failed (exit $LASTEXITCODE)." }
}

function Get-NodeMajor {
    if (-not (Has-Command "node")) { return 0 }
    try { return [int]((& node -p "process.versions.node.split('.')[0]").Trim()) } catch { return 0 }
}

Write-Host "ChatGPT Local Access - One-click Setup" -ForegroundColor Green
Write-Host "Official GUI based setup: Coding Tools MCP Desktop + Cloudflare Tunnel."

$desktop = [Environment]::GetFolderPath("Desktop")
$defaultWorkspace = Join-Path $desktop "CodingTool"
New-Item -ItemType Directory -Path $defaultWorkspace -Force | Out-Null
Write-Host "Default workspace: $defaultWorkspace"

Step "Checking Python 3.11+"
$pythonInfo = Get-CompatiblePython
if (-not $pythonInfo) {
    Install-WingetPackage "Python.Python.3.11" "Python 3.11"
    $pythonInfo = Get-CompatiblePython
}
if (-not $pythonInfo) { throw "Python 3.11 or newer was installed but could not be resolved. Reopen the installer after Windows refreshes PATH." }
$pythonVersionArgs = @($pythonInfo.Prefix) + @("--version")
Write-Host "Python: $(& $pythonInfo.Executable @pythonVersionArgs)"

Step "Installing Coding Tools MCP Desktop"
Invoke-Python $pythonInfo @("-m", "pip", "install", "--upgrade", "coding-tools-mcp[desktop]")
Refresh-Path

$scriptsArgs = @($pythonInfo.Prefix) + @("-c", "import sysconfig; print(sysconfig.get_path('scripts'))")
$scriptsDir = (& $pythonInfo.Executable @scriptsArgs).Trim()
$desktopExe = Join-Path $scriptsDir "coding-tools-mcp-desktop.exe"
if (-not (Test-Path $desktopExe)) { throw "Desktop launcher not found: $desktopExe" }
Write-Host "Coding Tools MCP Desktop: $desktopExe"

Step "Checking Cloudflare Tunnel CLI"
if (-not (Has-Command "cloudflared")) {
    Install-WingetPackage "Cloudflare.cloudflared" "cloudflared"
}
if (-not (Has-Command "cloudflared")) { throw "cloudflared is still unavailable after installation." }
Write-Host "cloudflared: $(& cloudflared --version | Select-Object -First 1)"

if (-not $SkipRemoteDesktopCommander) {
    Step "Checking Node.js for Remote Desktop Commander"
    if ((Get-NodeMajor) -lt 18) {
        Install-WingetPackage "OpenJS.NodeJS.LTS" "Node.js LTS"
    }
    $nodeMajor = Get-NodeMajor
    if ($nodeMajor -lt 18) { throw "Node.js 18+ is required for Remote Desktop Commander." }
    Write-Host "Node: $(& node --version)"
}

Step "Verifying installation"
& (Join-Path $root "Verify.ps1") -NoPause -SkipRemoteDesktopCommander:$SkipRemoteDesktopCommander
if ($LASTEXITCODE -ne 0) { throw "Verification reported a failure." }

Write-Host "`nInstallation complete." -ForegroundColor Green
Write-Host "The retired extra :8000 MCP launcher is not used anymore." -ForegroundColor Cyan
Write-Host "The official GUI owns the MCP runtime, OAuth and Cloudflare Quick/Fixed tunnel lifecycle."

if (-not $NoLaunch) {
    Step "Opening official Coding Tools MCP Desktop GUI"
    & (Join-Path $root "Start-CodingTools-Desktop.ps1") -NoPause
}
