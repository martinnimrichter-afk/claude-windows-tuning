# rollback.ps1 — reverses a specific run by merging all undo.reg files in reverse order.
#
# Usage:
#   .\rollback.ps1 -RunId 2026-05-24_18-00-00
#   .\rollback.ps1 -RunId 2026-05-24_18-00-00 -DryRun

[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$RunId,
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

$skillRoot = Split-Path $PSScriptRoot -Parent
$runDir    = Join-Path $skillRoot "runs\$RunId"

if (-not (Test-Path $runDir)) {
    throw "Run directory not found: $runDir"
}

$rollbackDir = Join-Path $runDir 'rollback'
if (-not (Test-Path $rollbackDir)) {
    throw "No rollback directory found in $runDir"
}

$undoFiles = Get-ChildItem -Path $rollbackDir -Filter '*.reg' -ErrorAction SilentlyContinue
if (-not $undoFiles -or $undoFiles.Count -eq 0) {
    Write-Host "No undo.reg files found in $rollbackDir — nothing to rollback." -ForegroundColor Yellow
    exit 0
}

# Reverse chronological order (newest applied first → undone last by file creation time, but for safety
# we simply iterate alphabetically reversed which mirrors apply order in this MVP)
$undoFiles = $undoFiles | Sort-Object Name -Descending

Write-Host ""
Write-Host "=== ROLLBACK $RunId ===" -ForegroundColor Cyan
Write-Host "$($undoFiles.Count) tweak(s) to undo."
if ($DryRun) { Write-Host "[DRY-RUN — no changes will be made]" -ForegroundColor Yellow }

$ok   = 0
$fail = 0
$rollbackLog = Join-Path $runDir 'rollback.log'

foreach ($f in $undoFiles) {
    Write-Host ""
    Write-Host "[undo] $($f.Name)" -ForegroundColor White
    if ($DryRun) {
        Write-Host "  DRY-RUN — would merge $($f.FullName)" -ForegroundColor Yellow
        continue
    }

    try {
        $output = & reg.exe import $f.FullName 2>&1
        $entry = [ordered]@{
            ts     = (Get-Date).ToString('o')
            file   = $f.Name
            status = 'ok'
            output = ($output -join '; ')
        }
        Add-Content -Path $rollbackLog -Value ($entry | ConvertTo-Json -Compress)
        Write-Host "  OK" -ForegroundColor Green
        $ok++
    } catch {
        $entry = [ordered]@{
            ts     = (Get-Date).ToString('o')
            file   = $f.Name
            status = 'fail'
            error  = $_.Exception.Message
        }
        Add-Content -Path $rollbackLog -Value ($entry | ConvertTo-Json -Compress)
        Write-Host "  FAILED — $($_.Exception.Message)" -ForegroundColor Red
        $fail++
    }
}

Write-Host ""
Write-Host "=== ROLLBACK DONE ===" -ForegroundColor Cyan
Write-Host ("Undone: {0} ok, {1} failed (of {2})" -f $ok, $fail, $undoFiles.Count)
Write-Host "Rollback log: $rollbackLog"

if (-not $DryRun) {
    # Append to history.md
    $historyPath = 'C:\AIPC1\LOCALMEMORY\win-tuning-history.md'
    $hDir = Split-Path $historyPath -Parent
    if (-not (Test-Path $hDir)) { New-Item -ItemType Directory -Force -Path $hDir | Out-Null }
    $md = "`r`n## $((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')) - ROLLBACK $RunId`r`n`r`n- Undone: $ok ok, $fail failed (of $($undoFiles.Count))`r`n- Run dir: $runDir`r`n- Log: $rollbackLog`r`n"
    Add-Content -Path $historyPath -Value $md -Encoding UTF8
}

if ($fail -gt 0) { exit 2 } else { exit 0 }
