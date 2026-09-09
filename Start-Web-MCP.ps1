param(
    [int]$Port = 8000,
    [ValidateSet("safe","trusted","dangerous")]
    [string]$PermissionMode = "safe"
)

$ErrorActionPreference = "Stop"
$Host.UI.RawUI.WindowTitle = "ChatGPT Web MCP Launcher"
$root = $PSScriptRoot
$workspaceFile = Join-Path $root "workspace.txt"

if (-not (Test-Path $workspaceFile)) { throw "workspace.txt is missing. Run Install.ps1 first." }
$workspace = (Get-Content $workspaceFile -Raw).Trim()
if (-not (Test-Path $workspace -PathType Container)) { throw "Workspace does not exist: $workspace" }

$portInUse = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue
if ($portInUse) { throw "Port $Port is already in use. Stop the old MCP process or choose another port." }

$uvx = (Get-Command uvx -ErrorAction Stop).Source
$cloudflared = (Get-Command cloudflared -ErrorAction Stop).Source
$oauthPassword = ([guid]::NewGuid().ToString("N") + [guid]::NewGuid().ToString("N"))

$serverOut = Join-Path $root "coding-tools.stdout.log"
$serverErr = Join-Path $root "coding-tools.stderr.log"
$tunnelOut = Join-Path $root "cloudflared.stdout.log"
$tunnelErr = Join-Path $root "cloudflared.stderr.log"
Remove-Item $serverOut,$serverErr,$tunnelOut,$tunnelErr -Force -ErrorAction SilentlyContinue

Write-Host "Starting coding-tools-mcp..." -ForegroundColor Cyan

$env:CODING_TOOLS_MCP_OAUTH_PASSWORD = $oauthPassword
$server = Start-Process -FilePath $uvx -ArgumentList @(
    "coding-tools-mcp","--workspace","`"$workspace`"",
    "--host","127.0.0.1","--port",$Port,
    "--oauth-mode","--permission-mode",$PermissionMode
) -PassThru -WindowStyle Hidden -RedirectStandardOutput $serverOut -RedirectStandardError $serverErr
Remove-Item Env:CODING_TOOLS_MCP_OAUTH_PASSWORD -ErrorAction SilentlyContinue

Start-Sleep -Seconds 2
if ($server.HasExited) {
    Write-Host (Get-Content $serverErr -Raw -ErrorAction SilentlyContinue) -ForegroundColor Red
    throw "coding-tools-mcp failed to start."
}

Write-Host "Starting temporary Cloudflare tunnel..." -ForegroundColor Cyan
$tunnel = Start-Process -FilePath $cloudflared -ArgumentList @(
    "tunnel","--url","http://127.0.0.1:$Port","--no-autoupdate"
) -PassThru -WindowStyle Hidden -RedirectStandardOutput $tunnelOut -RedirectStandardError $tunnelErr

$url = $null
for ($i = 0; $i -lt 40 -and -not $url; $i++) {
    Start-Sleep -Milliseconds 500
    $logs = ""
    if (Test-Path $tunnelOut) { $logs += (Get-Content $tunnelOut -Raw -ErrorAction SilentlyContinue) }
    if (Test-Path $tunnelErr) { $logs += "`n" + (Get-Content $tunnelErr -Raw -ErrorAction SilentlyContinue) }
    $m = [regex]::Match($logs, 'https://[a-z0-9-]+\.trycloudflare\.com')
    if ($m.Success) { $url = $m.Value }
}

if (-not $url) {
    if (-not $tunnel.HasExited) { Stop-Process -Id $tunnel.Id -Force -ErrorAction SilentlyContinue }
    if (-not $server.HasExited) { Stop-Process -Id $server.Id -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath (Join-Path $root "CURRENT_CONNECTION.txt") -Force -ErrorAction SilentlyContinue }
    Write-Host (Get-Content $tunnelErr -Raw -ErrorAction SilentlyContinue) -ForegroundColor Red
    throw "Could not obtain a trycloudflare.com URL."
}

$mcpUrl = "$url/mcp"
$connection = @"
MCP URL: $mcpUrl
OAuth authorization password: $oauthPassword
Workspace: $workspace
Permission mode: $PermissionMode
Server PID: $($server.Id)
Tunnel PID: $($tunnel.Id)
"@
Set-Content -Path (Join-Path $root "CURRENT_CONNECTION.txt") -Value $connection -Encoding UTF8
Set-Clipboard -Value $mcpUrl

Write-Host "`nREADY" -ForegroundColor Green
Write-Host "MCP URL: $mcpUrl" -ForegroundColor Yellow
Write-Host "OAuth password: $oauthPassword" -ForegroundColor Yellow
Write-Host "The MCP URL has been copied to the clipboard."
Write-Host "In ChatGPT Web Developer Mode, create/refresh the custom MCP using this URL."
Write-Host "When the OAuth authorization page opens, enter the password above."
Write-Host "`nKeep this window open while using the temporary tunnel." -ForegroundColor Cyan

Write-Host "Press Enter to stop both services."
Read-Host | Out-Null

Stop-Process -Id $tunnel.Id -Force -ErrorAction SilentlyContinue
Stop-Process -Id $server.Id -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath (Join-Path $root "CURRENT_CONNECTION.txt") -Force -ErrorAction SilentlyContinue
Write-Host "Stopped."
