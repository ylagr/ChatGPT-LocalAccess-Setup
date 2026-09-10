param(
    [string]$Model = "",
    [switch]$NoPause
)

$ErrorActionPreference = "Stop"
$Host.UI.RawUI.WindowTitle = "Coding Tools MCP Desktop Launcher"
$root = $PSScriptRoot
$usageScript = Join-Path $root "Usage-Tracker.ps1"

function Find-DesktopExecutable {
    $command = Get-Command "coding-tools-mcp-desktop" -ErrorAction SilentlyContinue
    if ($command) { return $command.Source }

    $python = Get-Command "python" -ErrorAction SilentlyContinue
    if ($python) {
        try {
            $scriptsDir = (& $python.Source -c "import sysconfig; print(sysconfig.get_path('scripts'))").Trim()
            $candidate = Join-Path $scriptsDir "coding-tools-mcp-desktop.exe"
            if (Test-Path $candidate -PathType Leaf) { return $candidate }
        } catch {}
    }
    return $null
}

$desktopExe = Find-DesktopExecutable
if (-not $desktopExe) { throw "coding-tools-mcp-desktop was not found. Run 01-安装.cmd first." }
if (-not (Get-Command "cloudflared" -ErrorAction SilentlyContinue)) { throw "cloudflared was not found. Run 01-安装.cmd first." }

$desktop = [Environment]::GetFolderPath("Desktop")
$defaultWorkspace = Join-Path $desktop "CodingTool"
New-Item -ItemType Directory -Path $defaultWorkspace -Force | Out-Null

if (Test-Path $usageScript -PathType Leaf) {
    if ($Model.Trim()) { & $usageScript -Action set-model -Model $Model -Quiet }
    & $usageScript -Action collect -Quiet
}

# coding-tools-mcp's official debug telemetry writes its closed-schema counters
# to the Desktop client's stderr.log instead of sending those events upstream.
$env:CODING_TOOLS_MCP_TELEMETRY = "debug"

Set-Clipboard -Value $defaultWorkspace
Write-Host "Coding Tools MCP Desktop" -ForegroundColor Green
Write-Host "Official GUI: $desktopExe"
Write-Host "Default workspace copied to clipboard: $defaultWorkspace" -ForegroundColor Cyan
Write-Host ""
Write-Host "Recommended first profile:" -ForegroundColor Yellow
Write-Host "  Workspace       : $defaultWorkspace"
Write-Host "  Local port      : 28766"
Write-Host "  Permission mode : trusted"
Write-Host "  Authentication  : OAuth"
Write-Host "  Tunnel           : Cloudflare -> Quick tunnel"
Write-Host ""
Write-Host "Click Start in the official GUI, then copy the generated https://*.trycloudflare.com/mcp URL."
Write-Host "Create/update the custom MCP in ChatGPT Web, finish OAuth, and OPEN A NEW CHAT before testing it." -ForegroundColor Cyan
Write-Host "Do not start the retired extra :8000 MCP server."

$existingProcess = Get-Process -ErrorAction SilentlyContinue | Where-Object {
    try { $_.Path -and ([IO.Path]::GetFullPath($_.Path) -eq [IO.Path]::GetFullPath($desktopExe)) } catch { $false }
} | Select-Object -First 1

if ($existingProcess) {
    $process = $existingProcess
    Write-Host "`nThe official GUI is already running (PID $($process.Id))." -ForegroundColor Yellow
    Write-Host "Lifecycle/request tracking is active. Restart the GUI through this launcher next time to also enable local debug telemetry summaries."
} else {
    $process = Start-Process -FilePath $desktopExe -PassThru
    Write-Host "`nGUI started (PID $($process.Id)). This launcher can now be closed."
}

if (Test-Path $usageScript -PathType Leaf) {
    $watchArguments = "-NoProfile -ExecutionPolicy Bypass -File `"$usageScript`" -Action watch -ParentPid $($process.Id) -Quiet"
    Start-Process -FilePath "powershell.exe" -ArgumentList $watchArguments -WindowStyle Hidden | Out-Null
}

if (-not $NoPause) { Read-Host "Press Enter to close this launcher" | Out-Null }
