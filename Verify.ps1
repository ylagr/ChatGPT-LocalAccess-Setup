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

$all = $true
$all = (CheckCommand "python" @("--version")) -and $all
$all = (CheckCommand "uvx" @("--version")) -and $all
$all = (CheckCommand "node" @("--version")) -and $all
$all = (CheckCommand "npx" @("--version")) -and $all
$all = (CheckCommand "cloudflared" @("--version")) -and $all

Write-Host "`nChecking coding-tools-mcp..."
try {
    & uvx coding-tools-mcp --help *> $null
    if ($LASTEXITCODE -eq 0) { Write-Host "[ OK ] coding-tools-mcp" -ForegroundColor Green }
    else { throw "exit $LASTEXITCODE" }
}

catch {
    Write-Host "[FAIL] coding-tools-mcp: $_" -ForegroundColor Red
    $all = $false
}

$workspaceFile = Join-Path $root "workspace.txt"
Write-Host "`nChecking workspace..."
if (Test-Path $workspaceFile) {
    $workspace = (Get-Content $workspaceFile -Raw).Trim()
    if (Test-Path $workspace -PathType Container) {
        Write-Host "[ OK ] $workspace" -ForegroundColor Green
    } else {
        Write-Host "[FAIL] Saved workspace does not exist: $workspace" -ForegroundColor Red
        $all = $false
    }
} else {
    Write-Host "[WARN] workspace.txt not configured" -ForegroundColor Yellow
}

Write-Host "`nRemote Desktop Commander is account/device based and supports multiple PCs."
Write-Host "Run Start-Remote-Desktop-Commander.ps1 (or the 04 launcher CMD), then ask ChatGPT to list active Desktop Commander devices."

if ($all) {
    Write-Host "`nLocal prerequisites look good." -ForegroundColor Green
} else {
    Write-Host "`nOne or more local prerequisites need attention." -ForegroundColor Yellow
}
Read-Host "Press Enter to close"
