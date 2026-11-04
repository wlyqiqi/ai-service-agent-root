#Requires -Version 5.1
<#
.SYNOPSIS
  Start the local AI Service Agent demo with a real model, Chatwoot and LangSmith.

.DESCRIPTION
  This script intentionally runs the Agent from the local .venv instead of Docker.
  Chatwoot is expected to be started separately, normally through its own Docker
  Compose project.

  It validates the real model settings, Chatwoot wiring and LangSmith tracing
  configuration before starting the FastAPI runtime. The v2 landing page and
  Chatwoot Widget are used as the demo UI.

.EXAMPLE
  .\scripts\start_demo.ps1

.EXAMPLE
  .\scripts\start_demo.ps1 -RuntimeBase "http://192.168.1.20:8766"

.EXAMPLE
  .\scripts\start_demo.ps1 -NoBrowser
#>
[CmdletBinding()]
param(
    [ValidateRange(1, 65535)]
    [int]$Port = 8766,

    [switch]$NoBrowser,

    [string]$RuntimeBase = "",

    [switch]$SkipChatwootWebhookCheck
)

$ErrorActionPreference = "Stop"

$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
Set-Location $ProjectRoot

$TmpDir = Join-Path $ProjectRoot "tmp"
$PidFile = Join-Path $TmpDir "demo-runtime.pid"
$OutLog = Join-Path $TmpDir "demo-runtime.log"
$ErrLog = Join-Path $TmpDir "demo-runtime.err.log"
$EntryPoint = Join-Path $ProjectRoot ".venv\Scripts\ai-service-agent.exe"
$PythonExe = Join-Path $ProjectRoot ".venv\Scripts\python.exe"
$DemoUrl = "http://127.0.0.1:$Port/landing-v2.html"
$ConfigUrl = "http://127.0.0.1:$Port/config"
$EnvFile = Join-Path $ProjectRoot ".env"
$LandingFile = Join-Path $ProjectRoot "web\landing-v2.html"

function Fail([string]$Message) {
    throw $Message
}

function Read-DotEnv([string]$Path) {
    $map = @{}
    foreach ($line in Get-Content -LiteralPath $Path -Encoding UTF8) {
        $trimmed = $line.Trim()
        if (-not $trimmed -or $trimmed.StartsWith("#")) {
            continue
        }
        if ($trimmed -match '^(?:export\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*)$') {
            $key = $Matches[1]
            $value = $Matches[2].Trim()
            if ($value.Length -ge 2) {
                $first = $value.Substring(0, 1)
                $last = $value.Substring($value.Length - 1, 1)
                if (($first -eq '"' -and $last -eq '"') -or ($first -eq "'" -and $last -eq "'")) {
                    $value = $value.Substring(1, $value.Length - 2)
                }
            }
            $map[$key] = $value
        }
    }
    return $map
}

function Get-EffectiveValue([hashtable]$EnvMap, [string]$Name) {
    $processValue = [Environment]::GetEnvironmentVariable($Name, "Process")
    if (-not [string]::IsNullOrWhiteSpace($processValue)) {
        return $processValue
    }
    if ($EnvMap.ContainsKey($Name)) {
        return [string]$EnvMap[$Name]
    }
    return ""
}

function Get-OptionalValue([hashtable]$EnvMap, [string[]]$Names) {
    foreach ($name in $Names) {
        $value = Get-EffectiveValue $EnvMap $name
        if (-not [string]::IsNullOrWhiteSpace($value)) {
            return $value
        }
    }
    return ""
}

function Test-Truthy([string]$Value) {
    if ([string]::IsNullOrWhiteSpace($Value)) {
        return $false
    }
    return @("1", "true", "yes", "on") -contains $Value.Trim().ToLowerInvariant()
}

function Test-HttpOk([string]$Url) {
    try {
        $response = Invoke-WebRequest -Uri $Url -UseBasicParsing -TimeoutSec 3
        return ($response.StatusCode -ge 200 -and $response.StatusCode -lt 400)
    }
    catch {
        return $false
    }
}

function Open-DemoPage {
    if (-not $NoBrowser) {
        Start-Process $DemoUrl | Out-Null
    }
}

function Get-RecordedRuntimePid {
    if (-not (Test-Path -LiteralPath $PidFile)) {
        return 0
    }
    $raw = (Get-Content -LiteralPath $PidFile -Raw).Trim()
    if ($raw -notmatch '^\d+$') {
        Remove-Item -LiteralPath $PidFile -Force -ErrorAction SilentlyContinue
        return 0
    }
    $runtimePid = [int]$raw
    $process = Get-Process -Id $runtimePid -ErrorAction SilentlyContinue
    if ($null -eq $process) {
        Remove-Item -LiteralPath $PidFile -Force -ErrorAction SilentlyContinue
        return 0
    }
    return $runtimePid
}

function Wait-DemoReady([System.Diagnostics.Process]$Process, [int]$TimeoutSeconds) {
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        if ($Process.HasExited) {
            return $false
        }
        if ((Test-HttpOk $ConfigUrl) -and (Test-HttpOk $DemoUrl)) {
            return $true
        }
        Start-Sleep -Seconds 1
    }
    return $false
}

if (-not (Test-Path -LiteralPath $EnvFile)) {
    Fail "Missing $EnvFile. Create it from .env.example first."
}
if (-not (Test-Path -LiteralPath $EntryPoint)) {
    Fail "Missing $EntryPoint. Run: uv sync --group dev"
}
if (-not (Test-Path -LiteralPath $PythonExe)) {
    Fail "Missing $PythonExe. Run: uv sync --group dev"
}
if (-not (Test-Path -LiteralPath $LandingFile)) {
    Fail "Missing v2 landing page: $LandingFile"
}

$recordedPid = Get-RecordedRuntimePid
if ($recordedPid -gt 0) {
    if ((Test-HttpOk $ConfigUrl) -and (Test-HttpOk $DemoUrl)) {
        Write-Host "Demo already running (PID $recordedPid): $DemoUrl" -ForegroundColor Green
        Open-DemoPage
        exit 0
    }
    Fail "Demo process PID $recordedPid exists but the HTTP endpoints are not ready. Run .\scripts\stop_demo.ps1 first."
}

$listener = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue |
    Select-Object -First 1
if ($listener) {
    $ownerPid = $listener.OwningProcess
    $owner = Get-Process -Id $ownerPid -ErrorAction SilentlyContinue
    $ownerName = if ($owner) { $owner.ProcessName } else { "unknown" }
    Fail "Port $Port is already in use by PID $ownerPid ($ownerName). Stop it or choose -Port."
}

$envMap = Read-DotEnv $EnvFile

$noProxy = [Environment]::GetEnvironmentVariable("NO_PROXY", "Process")
$noProxyItems = @()
if (-not [string]::IsNullOrWhiteSpace($noProxy)) {
    $noProxyItems += $noProxy.Split(",") | ForEach-Object { $_.Trim() } | Where-Object { $_ }
}
foreach ($item in @("127.0.0.1", "localhost")) {
    if ($noProxyItems -notcontains $item) {
        $noProxyItems += $item
    }
}
$env:NO_PROXY = $noProxyItems -join ","
$env:no_proxy = $env:NO_PROXY

if (Test-Truthy (Get-EffectiveValue $envMap "FAKE_MODEL")) {
    Fail "FAKE_MODEL is enabled. This demo requires a real model; set FAKE_MODEL=false."
}

$llmModel = Get-OptionalValue $envMap @("LLM_MODEL", "ARK_MODEL")
$llmBase = Get-OptionalValue $envMap @("LLM_BASE_URL", "ARK_BASE_URL")
$llmKey = Get-OptionalValue $envMap @("LLM_API_KEY", "ARK_API_KEY")
$missingModel = @()
if ([string]::IsNullOrWhiteSpace($llmModel)) { $missingModel += "LLM_MODEL or ARK_MODEL" }
if ([string]::IsNullOrWhiteSpace($llmBase)) { $missingModel += "LLM_BASE_URL or ARK_BASE_URL" }
if ([string]::IsNullOrWhiteSpace($llmKey)) { $missingModel += "LLM_API_KEY or ARK_API_KEY" }
if ($missingModel.Count -gt 0) {
    Fail ("Real model configuration is incomplete: " + ($missingModel -join ", "))
}

if (Test-Truthy (Get-EffectiveValue $envMap "AUTH_ENABLED")) {
    if ([string]::IsNullOrWhiteSpace((Get-EffectiveValue $envMap "JWT_SECRET"))) {
        Fail "AUTH_ENABLED=true requires JWT_SECRET."
    }
}

$tracingEnabled = Test-Truthy (Get-EffectiveValue $envMap "LANGSMITH_TRACING")
$langsmithProject = Get-EffectiveValue $envMap "LANGSMITH_PROJECT"
if ($tracingEnabled) {
    if ([string]::IsNullOrWhiteSpace((Get-EffectiveValue $envMap "LANGSMITH_API_KEY"))) {
        Fail "LANGSMITH_TRACING=true requires LANGSMITH_API_KEY."
    }
    if ([string]::IsNullOrWhiteSpace($langsmithProject)) {
        $langsmithProject = "ai-service-agent-local"
        $env:LANGSMITH_PROJECT = $langsmithProject
    } else {
        $env:LANGSMITH_PROJECT = $langsmithProject
    }
    $env:LANGSMITH_TRACING = "true"
}
else {
    Write-Warning "LangSmith tracing is disabled. Set LANGSMITH_TRACING=true and LANGSMITH_API_KEY to observe runs."
}

if (-not (Test-Truthy (Get-EffectiveValue $envMap "CHATWOOT_ENABLED"))) {
    Fail "CHATWOOT_ENABLED must be true for the Chatwoot Widget demo."
}

$chatwootBaseUrl = (Get-EffectiveValue $envMap "CHATWOOT_BASE_URL").Trim().TrimEnd("/")
$chatwootRequired = @(
    "CHATWOOT_BASE_URL",
    "CHATWOOT_ACCOUNT_ID",
    "CHATWOOT_INBOX_ID",
    "CHATWOOT_API_TOKEN",
    "CHATWOOT_AGENT_BOT_TOKEN",
    "CHATWOOT_AGENT_BOT_SECRET",
    "CHATWOOT_WEBSITE_TOKEN",
    "CHATWOOT_WEBHOOK_SECRET",
    "CHATWOOT_HMAC_SECRET"
)
$missingChatwoot = @()
foreach ($name in $chatwootRequired) {
    if ([string]::IsNullOrWhiteSpace((Get-EffectiveValue $envMap $name))) {
        $missingChatwoot += $name
    }
}
if ($missingChatwoot.Count -gt 0) {
    Fail ("Chatwoot configuration is incomplete: " + ($missingChatwoot -join ", "))
}
if (-not (Test-HttpOk $chatwootBaseUrl)) {
    Fail "Chatwoot is not reachable at $chatwootBaseUrl. Start Chatwoot first."
}

if ([string]::IsNullOrWhiteSpace($RuntimeBase)) {
    $RuntimeBase = "http://host.docker.internal:$Port"
}
$RuntimeBase = $RuntimeBase.Trim().TrimEnd("/")

$env:PYTHONPATH = Join-Path $ProjectRoot "src"

if (-not $SkipChatwootWebhookCheck) {
    Write-Host "Checking Chatwoot Account Webhook -> $RuntimeBase/webhooks/chatwoot ..."
    & $PythonExe (Join-Path $ProjectRoot "scripts\check_seat_gated_webhooks.py") --runtime-base $RuntimeBase
    if ($LASTEXITCODE -ne 0) {
        Fail "Chatwoot webhook preflight failed. Fix the webhook or use -SkipChatwootWebhookCheck."
    }
}
else {
    Write-Warning "Skipping Chatwoot Account Webhook preflight."
}

$env:AI_SERVICE_HOST = "0.0.0.0"
$env:AI_SERVICE_PORT = "$Port"
if ([string]::IsNullOrWhiteSpace((Get-EffectiveValue $envMap "APPROVAL_LINK_BASE_URL"))) {
    $env:APPROVAL_LINK_BASE_URL = "http://127.0.0.1:$Port"
}

$seatApprovalSecret = Get-EffectiveValue $envMap "SEAT_APPROVAL_SECRET"
$approvalLinkSecret = Get-EffectiveValue $envMap "APPROVAL_LINK_SECRET"
if ([string]::IsNullOrWhiteSpace($seatApprovalSecret) -and [string]::IsNullOrWhiteSpace($approvalLinkSecret)) {
    Write-Warning "SEAT_APPROVAL_SECRET and APPROVAL_LINK_SECRET are empty; approval card decision links will be invalid."
}

New-Item -ItemType Directory -Path $TmpDir -Force | Out-Null
Remove-Item -LiteralPath $OutLog, $ErrLog -Force -ErrorAction SilentlyContinue

Write-Host "Starting AI Service Agent on http://127.0.0.1:$Port ..."
$process = Start-Process -FilePath $EntryPoint -WorkingDirectory $ProjectRoot `
    -RedirectStandardOutput $OutLog -RedirectStandardError $ErrLog `
    -WindowStyle Hidden -PassThru
Set-Content -LiteralPath $PidFile -Value $process.Id -Encoding ASCII

if (-not (Wait-DemoReady -Process $process -TimeoutSeconds 90)) {
    if (Test-Path -LiteralPath $ErrLog) {
        Get-Content -LiteralPath $ErrLog -Tail 40 | ForEach-Object { Write-Host $_ -ForegroundColor Red }
    }
    if (-not $process.HasExited) {
        Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
    }
    Remove-Item -LiteralPath $PidFile -Force -ErrorAction SilentlyContinue
    Fail "AI Service Agent did not become ready within 90 seconds. Check $ErrLog."
}

Write-Host ""
Write-Host "Demo ready" -ForegroundColor Green
Write-Host "  Agent:      $DemoUrl"
Write-Host "  Chatwoot:   $chatwootBaseUrl"
Write-Host "  LangSmith:  $langsmithProject"
Write-Host "  Runtime:    $RuntimeBase"
Write-Host "  PID:        $($process.Id)"
Write-Host "  Logs:       $OutLog"
Write-Host "  Errors:     $ErrLog"
Write-Host ""

Open-DemoPage
