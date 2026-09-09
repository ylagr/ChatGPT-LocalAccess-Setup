$ErrorActionPreference = "Stop"
$Host.UI.RawUI.WindowTitle = "Remote Desktop Commander - Device Agent"

function Has-Command($name) {
    return [bool](Get-Command $name -ErrorAction SilentlyContinue)
}

Write-Host "Remote Desktop Commander - Device Registration / Launcher" -ForegroundColor Green
Write-Host ""
Write-Host "This PC will be registered as a separate device under your Remote Desktop Commander account."
Write-Host "Use the SAME account as your other computers if you want ChatGPT to see them together." -ForegroundColor Yellow
Write-Host ""

if (-not (Has-Command "node")) {
    throw "Node.js is missing. Run 01-安装.cmd first."
}
if (-not (Has-Command "npx")) {
    throw "npx is missing. Reinstall/repair Node.js, then retry."
}

$nodeMajor = [int]((& node -p "process.versions.node.split('.')[0]").Trim())
if ($nodeMajor -lt 18) {
    throw "Node.js 18 or newer is required. Current major version: $nodeMajor"
}
Write-Host "Node: $(& node --version)"
Write-Host ""
Write-Host "A browser authorization page may open on first run." -ForegroundColor Cyan
Write-Host "Complete the authorization with the SAME Remote Desktop Commander account used on your other PC."
Write-Host "After authorization, keep this window open while you want this PC to stay online." -ForegroundColor Cyan
Write-Host ""
Write-Host "Starting Remote Desktop Commander..." -ForegroundColor Green
Write-Host "Command: npx -y @wonderwhy-er/desktop-commander@latest remote"
Write-Host ""

& npx -y @wonderwhy-er/desktop-commander@latest remote
$exitCode = $LASTEXITCODE

Write-Host ""
if ($exitCode -eq 0) {
    Write-Host "Remote Desktop Commander stopped normally." -ForegroundColor Yellow
} else {
    Write-Host "Remote Desktop Commander exited with code $exitCode." -ForegroundColor Red
}
Read-Host "Press Enter to close"
