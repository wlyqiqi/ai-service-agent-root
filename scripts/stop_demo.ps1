#Requires -Version 5.1
<#
.SYNOPSIS
  Stop the local AI Service Agent demo started by start_demo.ps1.

.DESCRIPTION
  Uses only the PID file written by start_demo.ps1. It does not search for or
  terminate unrelated Python/uv processes.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"

$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$PidFile = Join-Path $ProjectRoot "tmp\demo-runtime.pid"

if (-not (Test-Path -LiteralPath $PidFile)) {
    Write-Host "No demo runtime PID file found. Nothing to stop."
    exit 0
}

$raw = (Get-Content -LiteralPath $PidFile -Raw).Trim()
if ($raw -notmatch '^\d+$') {
    Remove-Item -LiteralPath $PidFile -Force -ErrorAction SilentlyContinue
    throw "Invalid demo runtime PID file: $PidFile"
}

$runtimePid = [int]$raw
if ($runtimePid -eq $PID) {
    throw "Refusing to stop the current PowerShell process."
}

$process = Get-Process -Id $runtimePid -ErrorAction SilentlyContinue
if ($null -eq $process) {
    Remove-Item -LiteralPath $PidFile -Force -ErrorAction SilentlyContinue
    Write-Host "Demo runtime is already stopped."
    exit 0
}

Write-Host "Stopping demo runtime PID $runtimePid ($($process.ProcessName)) ..."
Stop-Process -Id $runtimePid -Force
Start-Sleep -Milliseconds 500

if (Get-Process -Id $runtimePid -ErrorAction SilentlyContinue) {
    throw "Failed to stop demo runtime PID $runtimePid."
}

Remove-Item -LiteralPath $PidFile -Force -ErrorAction SilentlyContinue
Write-Host "Demo runtime stopped."
