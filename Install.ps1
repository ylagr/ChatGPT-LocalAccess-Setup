param(
    [string]$Workspace = "",
    [switch]$SkipRemoteDesktopCommander
)

$ErrorActionPreference = "Stop"
$Host.UI.RawUI.WindowTitle = "ChatGPT Local Access Setup"

function Step($text) { Write-Host "`n==> $text" -ForegroundColor Cyan }
function Has-Command($name) { return [bool](Get-Command $name -ErrorAction SilentlyContinue) }
function Refresh-Path {
    $env:Path = [Environment]::GetEnvironmentVariable("Path","Machine") + ";" +
                [Environment]::GetEnvironmentVariable("Path","User")
}
function Ensure-Winget {
    if (-not (Has-Command "winget")) {
        throw "winget is required. Install/update Microsoft App Installer first."
    }
}

Write-Host "ChatGPT Local Access - One-click Setup" -ForegroundColor Green
Write-Host "Installs prerequisites for coding-tools MCP, Cloudflare Tunnel, and Desktop Commander."

Step "Checking Python 3.11+"
if (-not (Has-Command "python")) {
    Ensure-Winget
    winget install -e --id Python.Python.3.11 --accept-source-agreements --accept-package-agreements
    Refresh-Path
}
$pyVersion = & python -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}.{sys.version_info.micro}')"
$pyOk = & python -c "import sys; print(1 if sys.version_info >= (3,11) else 0)"
if ($pyOk -ne "1") { throw "Python 3.11 or newer is required." }
Write-Host "Python: $pyVersion"

Step "Checking uv / uvx"
if (-not (Has-Command "uvx")) {
    Ensure-Winget
    winget install -e --id astral-sh.uv --accept-source-agreements --accept-package-agreements
    Refresh-Path
}
if (-not (Has-Command "uvx")) { throw "uvx is unavailable. Reopen PowerShell and rerun Install.ps1." }
Write-Host "uvx: $((Get-Command uvx).Source)"

Step "Checking coding-tools-mcp"
& uvx coding-tools-mcp --help *> $null
if ($LASTEXITCODE -ne 0) { throw "coding-tools-mcp could not start." }
Write-Host "coding-tools-mcp: ready"

Step "Checking cloudflared"
if (-not (Has-Command "cloudflared")) {
    Write-Host "Downloading official Windows x64 MSI from Cloudflare GitHub Releases..."
    $release = Invoke-RestMethod -Uri "https://api.github.com/repos/cloudflare/cloudflared/releases/latest" -Headers @{"User-Agent"="ChatGPT-LocalAccess-Setup"}
    $asset = $release.assets | Where-Object { $_.name -eq "cloudflared-windows-amd64.msi" } | Select-Object -First 1
    if (-not $asset) { throw "Official cloudflared Windows x64 MSI was not found in the latest release." }
    $msi = Join-Path $env:TEMP "cloudflared-windows-amd64.msi"
    Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $msi
    $msiArgs = "/i `"$msi`" /qn /norestart"
    $msiProc = Start-Process -FilePath "msiexec.exe" -ArgumentList $msiArgs -Wait -PassThru
    if ($msiProc.ExitCode -ne 0) { throw "cloudflared MSI install failed with exit code $($msiProc.ExitCode)." }
    Remove-Item $msi -Force -ErrorAction SilentlyContinue
    Refresh-Path
}
if (-not (Has-Command "cloudflared")) { throw "cloudflared is still unavailable after MSI installation." }
Write-Host "cloudflared: $(& cloudflared --version)"

Step "Checking Node.js 18+ for Remote Desktop Commander"
if (-not (Has-Command "node")) {
    Ensure-Winget
    winget install -e --id OpenJS.NodeJS.LTS --accept-source-agreements --accept-package-agreements
    Refresh-Path
}
if (-not (Has-Command "node")) { throw "Node.js is unavailable. Reopen PowerShell and rerun Install.ps1." }
$nodeMajor = [int]((& node -p "process.versions.node.split('.')[0]").Trim())
if ($nodeMajor -lt 18) { throw "Node.js 18 or newer is required." }
Write-Host "Node: $(& node --version)"

if (-not $SkipRemoteDesktopCommander) {
    Step "Remote Desktop Commander"
    Write-Host "After this installer finishes, run Start-Remote-Desktop-Commander.ps1 (or the 04 launcher CMD)."
    Write-Host "On first run, complete browser/device authorization with the SAME account used on your other PCs."
    Write-Host "One Remote Desktop Commander plugin can manage multiple registered computers by deviceId."
}
Step "Preparing workspace"
if (-not $Workspace) {
    $desktopPath = [Environment]::GetFolderPath("Desktop")
    $Workspace = Join-Path $desktopPath "CodingTool"
    if (-not (Test-Path $Workspace -PathType Container)) {
        New-Item -ItemType Directory -Path $Workspace -Force | Out-Null
        Write-Host "Created default workspace: $Workspace"
    } else {
        Write-Host "Default workspace already exists: $Workspace"
    }
} else {
    $Workspace = [IO.Path]::GetFullPath($Workspace)
    if (-not (Test-Path $Workspace -PathType Container)) {
        throw "Workspace does not exist: $Workspace"
    }
}

Set-Content -Path (Join-Path $PSScriptRoot "workspace.txt") -Value $Workspace -Encoding UTF8
Write-Host "Saved workspace: $Workspace"

Write-Host "`nLocal installation is complete." -ForegroundColor Green
Write-Host "Default coding workspace: $Workspace"
Write-Host "Next: run Start-Web-MCP.ps1 to start coding-tools + a temporary Cloudflare HTTPS tunnel."
Write-Host "Then add the copied /mcp URL in ChatGPT Developer Mode."
Read-Host "Press Enter to close"