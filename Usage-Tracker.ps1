param(
    [ValidateSet("collect", "show", "set-model", "watch")]
    [string]$Action = "show",
    [string]$Model = "",
    [int]$ParentPid = 0,
    [switch]$Quiet
)

$ErrorActionPreference = "Stop"

$localAppData = [Environment]::GetFolderPath("LocalApplicationData")
if (-not $localAppData) { $localAppData = $env:LOCALAPPDATA }
if (-not $localAppData) { throw "Could not resolve the current user's LocalApplicationData directory." }

$userProfile = [Environment]::GetFolderPath("UserProfile")
if (-not $userProfile) { throw "Could not resolve the current user's profile directory." }

$usageRoot = Join-Path $localAppData "ChatGPT-LocalAccess-Setup\Usage"
$sessionsPath = Join-Path $usageRoot "sessions.jsonl"
$csvPath = Join-Path $usageRoot "sessions.csv"
$activePath = Join-Path $usageRoot "active-sessions.json"
$modelHistoryPath = Join-Path $usageRoot "model-history.jsonl"
$desktopHome = Join-Path $userProfile ".coding-tools-mcp-desktop"
$profilesPath = Join-Path $desktopHome "profiles.json"
$stateRoot = Join-Path $desktopHome "state"
$telemetryPrefix = "telemetry (not sent): "
$collectorMutexName = "Local\ChatGPTLocalAccessUsageCollector"
$watcherMutexName = "Local\ChatGPTLocalAccessUsageWatcher"

function Ensure-UsageRoot {
    New-Item -ItemType Directory -Path $usageRoot -Force | Out-Null
}

function Read-JsonLines([string]$path) {
    if (-not (Test-Path $path -PathType Leaf)) { return @() }
    $items = @()
    foreach ($line in Get-Content -LiteralPath $path -Encoding UTF8) {
        if (-not $line.Trim()) { continue }
        try { $items += ($line | ConvertFrom-Json) } catch {}
    }
    return $items
}

function Write-ModelHistory([string]$label) {
    $clean = $label.Trim()
    if (-not $clean) { throw "Model name cannot be empty." }
    Ensure-UsageRoot
    $entry = [ordered]@{
        timestamp = [DateTimeOffset]::UtcNow.ToString("o")
        model = $clean
        source = "manual"
    }
    Add-Content -LiteralPath $modelHistoryPath -Value ($entry | ConvertTo-Json -Compress) -Encoding UTF8
    if (-not $Quiet) { Write-Host "Model label saved for future collected sessions: $clean" -ForegroundColor Green }
}

function Resolve-ModelForTimestamp([DateTimeOffset]$timestamp) {
    $history = @(Read-JsonLines $modelHistoryPath)
    $best = $null
    $bestTime = [DateTimeOffset]::MinValue
    foreach ($item in $history) {
        try { $itemTime = [DateTimeOffset]::Parse([string]$item.timestamp) } catch { continue }
        if ($itemTime -le $timestamp -and $itemTime -ge $bestTime) {
            $best = $item
            $bestTime = $itemTime
        }
    }
    if ($best) { return [pscustomobject]@{ Model = [string]$best.model; Source = "manual_history" } }
    return [pscustomobject]@{ Model = "unknown"; Source = "not_exposed_by_mcp" }
}

function Get-ProfileMap {
    $map = @{}
    if (-not (Test-Path $profilesPath -PathType Leaf)) { return $map }
    try { $data = Get-Content -LiteralPath $profilesPath -Raw -Encoding UTF8 | ConvertFrom-Json } catch { return $map }
    foreach ($profile in @($data.profiles)) {
        if (-not $profile.id) { continue }
        $map[[string]$profile.id] = [pscustomobject]@{
            Name = [string]$profile.name
            Path = [string]$profile.path
        }
    }
    return $map
}

function Get-ExistingSessionIds {
    $set = New-Object 'System.Collections.Generic.HashSet[string]'
    foreach ($record in @(Read-JsonLines $sessionsPath)) {
        if ($record.session_id) { [void]$set.Add([string]$record.session_id) }
    }
    return $set
}

function Read-ActiveSessions {
    $map = @{}
    if (-not (Test-Path $activePath -PathType Leaf)) { return $map }
    try { $data = Get-Content -LiteralPath $activePath -Raw -Encoding UTF8 | ConvertFrom-Json } catch { return $map }
    foreach ($item in @($data.sessions)) {
        if ($item.session_id) { $map[[string]$item.session_id] = $item }
    }
    return $map
}

function Save-ActiveSessions([hashtable]$map) {
    Ensure-UsageRoot
    $payload = [ordered]@{ sessions = @($map.Values) }
    Set-Content -LiteralPath $activePath -Value ($payload | ConvertTo-Json -Depth 6) -Encoding UTF8
}

function Get-McpRequestCount([string]$logPath) {
    if (-not (Test-Path $logPath -PathType Leaf)) { return 0 }
    $count = 0
    foreach ($line in Get-Content -LiteralPath $logPath -Encoding UTF8 -ErrorAction SilentlyContinue) {
        if ($line -match '"POST /mcp(?:\?[^ ]*)? HTTP/[0-9.]+"') { $count++ }
    }
    return $count
}

function Get-TelemetrySummary([string]$logPath) {
    $toolCalls = $null
    $tools = @()
    if (-not (Test-Path $logPath -PathType Leaf)) {
        return [pscustomobject]@{ ToolCalls = $toolCalls; Tools = $tools }
    }

    foreach ($line in Get-Content -LiteralPath $logPath -Encoding UTF8 -ErrorAction SilentlyContinue) {
        $index = $line.IndexOf($telemetryPrefix, [StringComparison]::Ordinal)
        if ($index -lt 0) { continue }
        $json = $line.Substring($index + $telemetryPrefix.Length)
        try { $event = $json | ConvertFrom-Json } catch { continue }
        if ($event.event -eq "session_end") {
            $toolCalls = [int]$event.properties.tool_calls
        } elseif ($event.event -eq "tool_summary") {
            $tools += [ordered]@{
                tool = [string]$event.properties.tool
                calls = [int]$event.properties.calls
                ok = [int]$event.properties.ok
                errors = [int]$event.properties.errors
            }
        }
    }
    return [pscustomobject]@{ ToolCalls = $toolCalls; Tools = $tools }
}

function Get-CurrentRuntimeSnapshots {
    $profiles = Get-ProfileMap
    $map = @{}
    if (-not (Test-Path $stateRoot -PathType Container)) { return $map }

    foreach ($directory in Get-ChildItem -LiteralPath $stateRoot -Directory -ErrorAction SilentlyContinue) {
        $runtimePath = Join-Path $directory.FullName "runtime.json"
        if (-not (Test-Path $runtimePath -PathType Leaf)) { continue }
        try { $runtime = Get-Content -LiteralPath $runtimePath -Raw -Encoding UTF8 | ConvertFrom-Json } catch { continue }
        if (-not $runtime.runtime_pid -or -not $runtime.runtime_create_time) { continue }

        $profileId = [string]$directory.Name
        $profile = $profiles[$profileId]
        $sessionId = "$profileId-$($runtime.runtime_pid)-$($runtime.runtime_create_time)"
        $logPath = Join-Path $directory.FullName "stderr.log"
        $telemetry = Get-TelemetrySummary $logPath
        try {
            $startedAt = [DateTimeOffset]::FromUnixTimeMilliseconds([int64]([double]$runtime.runtime_create_time * 1000))
        } catch {
            $startedAt = [DateTimeOffset]::UtcNow
        }
        $stderrBytes = if (Test-Path $logPath -PathType Leaf) { [int64](Get-Item -LiteralPath $logPath).Length } else { 0 }

        $map[$sessionId] = [pscustomobject]@{
            session_id = $sessionId
            profile_id = $profileId
            runtime_pid = [int]$runtime.runtime_pid
            runtime_create_time = [double]$runtime.runtime_create_time
            started_at = $startedAt.ToString("o")
            workspace_name = if ($profile) { $profile.Name } else { $profileId }
            workspace_path = if ($profile) { $profile.Path } elseif ($runtime.workspace) { [string]$runtime.workspace } else { "unknown" }
            tunnel_type = [string]$runtime.tunnel_type
            tunnel_mode = [string]$runtime.tunnel_mode
            public_url = [string]$runtime.public_url
            log_path = $logPath
            mcp_http_requests = Get-McpRequestCount $logPath
            mcp_tool_calls = $telemetry.ToolCalls
            tools = @($telemetry.Tools)
            stderr_bytes = $stderrBytes
            last_seen_at = [DateTimeOffset]::UtcNow.ToString("o")
        }
    }
    return $map
}

function Export-UsageCsv {
    $records = @(Read-JsonLines $sessionsPath)
    if ($records.Count -eq 0) { return }
    $records |
        Select-Object ended_at, workspace_name, workspace_path, model, model_source,
            mcp_http_requests, mcp_tool_calls, duration_ms, web_tokens_exact, web_token_status |
        Export-Csv -LiteralPath $csvPath -NoTypeInformation -Encoding UTF8
}

function Finalize-Session($active, [System.Collections.Generic.HashSet[string]]$existing) {
    $sessionId = [string]$active.session_id
    if ($existing.Contains($sessionId)) { return $false }

    $endedAt = [DateTimeOffset]::UtcNow
    try { $startedAt = [DateTimeOffset]::Parse([string]$active.started_at) } catch { $startedAt = $endedAt }
    $modelInfo = Resolve-ModelForTimestamp $endedAt

    $record = [ordered]@{
        started_at = $startedAt.ToString("o")
        ended_at = $endedAt.ToString("o")
        session_id = $sessionId
        channel = "coding-tools-mcp-desktop"
        workspace_name = [string]$active.workspace_name
        workspace_path = [string]$active.workspace_path
        tunnel_type = [string]$active.tunnel_type
        tunnel_mode = [string]$active.tunnel_mode
        model = $modelInfo.Model
        model_source = $modelInfo.Source
        mcp_http_requests = [int]$active.mcp_http_requests
        mcp_tool_calls = $active.mcp_tool_calls
        tools = @($active.tools)
        duration_ms = [int64][math]::Max(0, ($endedAt - $startedAt).TotalMilliseconds)
        stderr_bytes = [int64]$active.stderr_bytes
        web_tokens_exact = $null
        web_token_status = "unavailable_to_mcp"
        token_note = "ChatGPT Web does not expose per-conversation model token usage in the MCP request metadata received by coding-tools-mcp. No fake token estimate is generated."
    }
    Add-Content -LiteralPath $sessionsPath -Value ($record | ConvertTo-Json -Compress -Depth 6) -Encoding UTF8
    [void]$existing.Add($sessionId)
    return $true
}

function Collect-Usage {
    Ensure-UsageRoot
    $mutex = [System.Threading.Mutex]::new($false, $collectorMutexName)
    $locked = $false
    try {
        $locked = $mutex.WaitOne(5000)
        if (-not $locked) { return 0 }

        $active = Read-ActiveSessions
        $current = Get-CurrentRuntimeSnapshots
        $existing = Get-ExistingSessionIds
        $added = 0

        foreach ($sessionId in $current.Keys) {
            $snapshot = $current[$sessionId]
            if ($active.ContainsKey($sessionId)) {
                $tracked = $active[$sessionId]
                $tracked | Add-Member -NotePropertyName public_url -NotePropertyValue $snapshot.public_url -Force
                $tracked | Add-Member -NotePropertyName mcp_http_requests -NotePropertyValue $snapshot.mcp_http_requests -Force
                if ($null -ne $snapshot.mcp_tool_calls) {
                    $tracked | Add-Member -NotePropertyName mcp_tool_calls -NotePropertyValue $snapshot.mcp_tool_calls -Force
                    $tracked | Add-Member -NotePropertyName tools -NotePropertyValue @($snapshot.tools) -Force
                }
                $tracked | Add-Member -NotePropertyName stderr_bytes -NotePropertyValue $snapshot.stderr_bytes -Force
                $tracked | Add-Member -NotePropertyName last_seen_at -NotePropertyValue $snapshot.last_seen_at -Force
                $active[$sessionId] = $tracked
            } else {
                $active[$sessionId] = $snapshot
            }
        }

        foreach ($sessionId in @($active.Keys)) {
            if ($current.ContainsKey($sessionId)) { continue }
            if (Finalize-Session $active[$sessionId] $existing) { $added++ }
            $active.Remove($sessionId)
        }

        Save-ActiveSessions $active
        Export-UsageCsv
        if (-not $Quiet) { Write-Host "Collected $added newly completed MCP runtime session(s)." -ForegroundColor Green }
        return $added
    } finally {
        if ($locked) { $mutex.ReleaseMutex() }
        $mutex.Dispose()
    }
}

function Has-ActiveDesktopRuntime {
    if (-not (Test-Path $stateRoot -PathType Container)) { return $false }
    return [bool](Get-ChildItem -LiteralPath $stateRoot -Filter "runtime.json" -File -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1)
}

function Watch-Usage([int]$processId) {
    if ($processId -le 0) { throw "watch requires -ParentPid." }
    $watcherMutex = [System.Threading.Mutex]::new($false, $watcherMutexName)
    $ownsWatcher = $false
    try {
        $ownsWatcher = $watcherMutex.WaitOne(0)
        if (-not $ownsWatcher) { return }

        while ($true) {
            try { [void](Collect-Usage) } catch {}
            $guiAlive = [bool](Get-Process -Id $processId -ErrorAction SilentlyContinue)
            if (-not $guiAlive -and -not (Has-ActiveDesktopRuntime)) { break }
            Start-Sleep -Seconds 1
        }
        try { [void](Collect-Usage) } catch {}
    } finally {
        if ($ownsWatcher) { $watcherMutex.ReleaseMutex() }
        $watcherMutex.Dispose()
    }
}

function Show-Usage {
    [void](Collect-Usage)
    $records = @(Read-JsonLines $sessionsPath)
    Write-Host "`nLocal usage directory: $usageRoot" -ForegroundColor Cyan
    Write-Host "Exact ChatGPT Web token counts: unavailable through MCP; records intentionally show N/A instead of invented values." -ForegroundColor Yellow
    if ($records.Count -eq 0) {
        $active = Read-ActiveSessions
        if ($active.Count -gt 0) {
            Write-Host "$($active.Count) MCP runtime session(s) are currently being tracked; they will be finalized after Stop." -ForegroundColor Cyan
        } else {
            Write-Host "No completed tracked runtime sessions yet. Start/use an MCP runtime, then run 05 again."
        }
        return
    }

    $records |
        Select-Object -Last 20 |
        Select-Object @{N="Ended";E={$_.ended_at}}, @{N="Workspace";E={$_.workspace_name}},
            @{N="Model";E={$_.model}}, @{N="MCP Requests";E={$_.mcp_http_requests}},
            @{N="Tool Calls";E={if ($null -eq $_.mcp_tool_calls) { "N/A" } else { $_.mcp_tool_calls }}},
            @{N="Duration(s)";E={[math]::Round(([double]$_.duration_ms / 1000), 1)}},
            @{N="Web Tokens";E={"N/A"}} |
        Format-Table -AutoSize
}

switch ($Action) {
    "set-model" {
        if (-not $Model.Trim()) { $Model = Read-Host "Enter the ChatGPT model label to associate with future sessions (example: GPT-5.6 Sol)" }
        Write-ModelHistory $Model
    }
    "collect" { [void](Collect-Usage) }
    "watch" { Watch-Usage $ParentPid }
    "show" {
        if (-not (Test-Path $modelHistoryPath -PathType Leaf) -and -not $Quiet) {
            Write-Host "The MCP protocol does not tell the local server which ChatGPT model is running." -ForegroundColor Yellow
            $answer = Read-Host "Optional: enter the current model label now, or press Enter to keep it unknown"
            if ($answer.Trim()) { Write-ModelHistory $answer }
        }
        Show-Usage
        if (-not $Quiet) { Read-Host "Press Enter to close" | Out-Null }
    }
}
