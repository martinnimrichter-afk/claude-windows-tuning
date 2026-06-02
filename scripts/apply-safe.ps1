# apply-safe.ps1 — orchestrator: preflight -> checkpoint -> per-tweak (detect/apply/verify) -> after snapshot -> log.
#
# Usage:
#   .\apply-safe.ps1 -Preset office
#   .\apply-safe.ps1 -Preset office -DryRun
#   .\apply-safe.ps1 -Preset office -SkipPreflight   # (testing only)

[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Preset,
    [switch]$DryRun,
    [switch]$SkipPreflight,
    [switch]$YesToManagedWarning   # auto-accept if managed state detected (CI/automation)
)

$ErrorActionPreference = 'Stop'

$skillRoot   = Split-Path $PSScriptRoot -Parent
$presetPath  = Join-Path $skillRoot "presets\$Preset.json"
$tweaksRoot  = Join-Path $skillRoot 'tweaks'

if (-not (Test-Path $presetPath)) {
    throw "Preset not found: $presetPath"
}

. "$PSScriptRoot\log.ps1"

# 1) Preflight
if (-not $SkipPreflight) {
    Write-Host ""
    Write-Host "=== PREFLIGHT ===" -ForegroundColor Cyan
    $preflightResult = & "$PSScriptRoot\preflight.ps1" -Json | ConvertFrom-Json
    if (-not $preflightResult.ok) {
        Write-Host ""
        Write-Host "Preflight FAILED. See blockers above. Aborting." -ForegroundColor Red
        exit 1
    }

    # Managed Windows warning — user choice required
    $managedWarn = $preflightResult.checks | Where-Object { $_.id -eq 11 -and $_.status -eq 'WARN' }
    if ($managedWarn) {
        Write-Host ""
        Write-Host "WARNING: Managed Windows detected (GPO or Intune)." -ForegroundColor Yellow
        Write-Host "         Some tweaks may be overridden by policy after apply." -ForegroundColor Yellow
        Write-Host "         Detail: $($managedWarn.message)" -ForegroundColor Gray
        if (-not $YesToManagedWarning) {
            $resp = Read-Host "Continue anyway? [y/N]"
            if ($resp -notmatch '^[yY]') {
                Write-Host "Aborted by user." -ForegroundColor Red
                exit 1
            }
        } else {
            Write-Host "[auto-accept via -YesToManagedWarning]" -ForegroundColor DarkGray
        }
    }
} else {
    Write-Host "[!] Preflight skipped via -SkipPreflight" -ForegroundColor Yellow
}

# 2) Load preset
$presetData = Get-Content $presetPath -Raw | ConvertFrom-Json
$tweakIds = @($presetData.tweaks)
if ($tweakIds.Count -eq 0) {
    throw "Preset '$Preset' has no tweaks defined."
}

Write-Host ""
$plural = if ($tweakIds.Count -ne 1) { 's' } else { '' }
Write-Host ("=== APPLY: {0} ({1} tweak{2}) ===" -f $Preset, $tweakIds.Count, $plural) -ForegroundColor Cyan
if ($DryRun) { Write-Host "[DRY-RUN — no changes will be made]" -ForegroundColor Yellow }

# 3) Run directory
$runId  = Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'
$runDir = Join-Path $skillRoot "runs\$runId"
New-Item -ItemType Directory -Force -Path $runDir | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $runDir 'rollback') | Out-Null

# 4) Initialize logging
Initialize-WinTuningLog -RunDir $runDir -Preset $Preset

# 5) Collect registry paths to snapshot from all tweaks
$snapshotPaths = [System.Collections.Generic.List[string]]::new()
foreach ($tid in $tweakIds) {
    $detectScript = Join-Path $tweaksRoot "$tid\detect.ps1"
    if (Test-Path $detectScript) {
        $detect = & $detectScript
        if ($detect.RegistryPath) {
            $snapshotPaths.Add($detect.RegistryPath) | Out-Null
        }
    }
}

# 6) Checkpoint (restore point + before.json snapshot)
Write-Host ""
Write-Host "=== CHECKPOINT ===" -ForegroundColor Cyan
$checkpoint = & "$PSScriptRoot\checkpoint.ps1" -RunDir $runDir -RegistryPaths $snapshotPaths -SkipRestorePoint:$DryRun

# 7) Per-tweak loop: detect -> apply -> verify
$actionsLog = Join-Path $runDir 'actions.jsonl'
$appliedCount = 0
$skippedCount = 0
$failedCount  = 0

Write-Host ""
Write-Host "=== TWEAKS ===" -ForegroundColor Cyan

foreach ($tid in $tweakIds) {
    $tweakDir = Join-Path $tweaksRoot $tid
    if (-not (Test-Path $tweakDir)) {
        Write-WinTuningEvent -Level ERROR -Event 'tweak.missing' -Data @{ tweak = $tid }
        $failedCount++
        continue
    }

    Write-Host ""
    Write-Host "[tweak] $tid" -ForegroundColor White

    # DETECT
    $detect = $null
    try {
        $detect = & (Join-Path $tweakDir 'detect.ps1')
        Write-WinTuningEvent -Level INFO -Event 'tweak.detect' -Data @{
            tweak       = $tid
            applicable  = [bool]$detect.Applicable
            current     = $detect.Current
            target      = $detect.Target
            reason      = $detect.Reason
        }
    } catch {
        Write-WinTuningEvent -Level ERROR -Event 'tweak.detect.fail' -Data @{ tweak = $tid; error = $_.Exception.Message }
        $failedCount++
        continue
    }

    if (-not $detect.Applicable) {
        Write-Host "  SKIP — $($detect.Reason)" -ForegroundColor DarkGray
        $skippedCount++
        $action = [ordered]@{
            tweak  = $tid
            action = 'skip'
            reason = $detect.Reason
            ts     = (Get-Date).ToString('o')
        }
        Add-Content -Path $actionsLog -Value ($action | ConvertTo-Json -Compress)
        continue
    }

    if ($detect.AlreadyApplied) {
        $targetStr = ($detect.Values.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join ', '
        Write-Host "  ALREADY APPLIED — current matches target [$targetStr]" -ForegroundColor DarkGray
        $skippedCount++
        $action = [ordered]@{
            tweak  = $tid
            action = 'noop'
            reason = 'already_applied'
            ts     = (Get-Date).ToString('o')
        }
        Add-Content -Path $actionsLog -Value ($action | ConvertTo-Json -Compress)
        continue
    }

    # APPLY (or simulate)
    if ($DryRun) {
        Write-Host "  DRY-RUN — would change $($detect.RegistryPath):" -ForegroundColor Yellow
        foreach ($vname in $detect.Values.Keys) {
            $cur = if ($null -eq $detect.Current[$vname]) { 'not_set' } else { $detect.Current[$vname] }
            Write-Host "    $vname : $cur -> $($detect.Values[$vname])" -ForegroundColor Yellow
        }
        $action = [ordered]@{
            tweak       = $tid
            action      = 'dry_run'
            would_apply = $detect
            ts          = (Get-Date).ToString('o')
        }
        Add-Content -Path $actionsLog -Value ($action | ConvertTo-Json -Compress)
        continue
    }

    try {
        $rollbackDir = Join-Path $runDir 'rollback'
        $applied = & (Join-Path $tweakDir 'apply.ps1') -RollbackDir $rollbackDir
        Write-WinTuningEvent -Level INFO -Event 'tweak.apply' -Data @{
            tweak    = $tid
            before   = $applied.Before
            after    = $applied.After
            undo_reg = $applied.UndoRegPath
        }
        $beforeStr = ($applied.Before.GetEnumerator() | ForEach-Object { "$($_.Key)=$(if ($null -eq $_.Value) {'(unset)'} else {$_.Value})" }) -join ', '
        $afterStr  = ($applied.After.GetEnumerator()  | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join ', '
        Write-Host "  APPLIED — before [$beforeStr] -> after [$afterStr]" -ForegroundColor Green
    } catch {
        Write-WinTuningEvent -Level ERROR -Event 'tweak.apply.fail' -Data @{ tweak = $tid; error = $_.Exception.Message }
        Write-Host "  APPLY FAILED — $($_.Exception.Message)" -ForegroundColor Red
        $failedCount++
        continue
    }

    # VERIFY
    try {
        $verify = & (Join-Path $tweakDir 'verify.ps1')
        if ($verify.Ok) {
            Write-WinTuningEvent -Level INFO -Event 'tweak.verify.ok' -Data @{ tweak = $tid; current = $verify.Current }
            Write-Host "  VERIFY OK" -ForegroundColor Green
            $appliedCount++

            $action = [ordered]@{
                tweak    = $tid
                action   = 'apply'
                before   = $applied.Before
                after    = $applied.After
                undo_reg = $applied.UndoRegPath
                ts       = (Get-Date).ToString('o')
            }
            Add-Content -Path $actionsLog -Value ($action | ConvertTo-Json -Compress)
        } else {
            Write-WinTuningEvent -Level ERROR -Event 'tweak.verify.fail' -Data @{ tweak = $tid; reason = $verify.Reason }
            Write-Host "  VERIFY FAILED — $($verify.Reason). Rolling back this tweak..." -ForegroundColor Red
            # Auto-rollback this single tweak from its undo.reg
            if (Test-Path $applied.UndoRegPath) {
                & reg.exe import $applied.UndoRegPath 2>&1 | Out-Null
                Write-WinTuningEvent -Level WARN -Event 'tweak.auto_rollback' -Data @{ tweak = $tid; undo_reg = $applied.UndoRegPath }
                Write-Host "  Auto-rollback merged from $($applied.UndoRegPath)" -ForegroundColor Yellow
            }
            $failedCount++
        }
    } catch {
        Write-WinTuningEvent -Level ERROR -Event 'tweak.verify.exception' -Data @{ tweak = $tid; error = $_.Exception.Message }
        $failedCount++
    }
}

# 8) After snapshot (re-read same paths)
Write-Host ""
Write-Host "=== AFTER SNAPSHOT ===" -ForegroundColor Cyan
$afterSnapshot = [ordered]@{
    run_id    = $runId
    timestamp = (Get-Date).ToString('o')
    registry  = @{}
}
foreach ($rp in $snapshotPaths) {
    if (Test-Path $rp) {
        $values = Get-ItemProperty -Path $rp -ErrorAction SilentlyContinue
        $clean = [ordered]@{}
        foreach ($prop in $values.PSObject.Properties) {
            if ($prop.Name -notmatch '^PS') { $clean[$prop.Name] = $prop.Value }
        }
        $afterSnapshot.registry[$rp] = @{ exists = $true; values = $clean }
    } else {
        $afterSnapshot.registry[$rp] = @{ exists = $false; values = @{} }
    }
}
$afterPath = Join-Path $runDir 'after.json'
$afterSnapshot | ConvertTo-Json -Depth 10 | Out-File -FilePath $afterPath -Encoding UTF8
Write-WinTuningEvent -Level INFO -Event 'snapshot.after' -Data @{ path = $afterPath }

# 9) Close log + history append
Close-WinTuningLog -Summary @{
    tweaks_total   = $tweakIds.Count
    tweaks_applied = $appliedCount
    tweaks_skipped = $skippedCount
    tweaks_failed  = $failedCount
    restore_point  = $checkpoint.RestorePointSequence
    dry_run        = [bool]$DryRun
}

# 10) Final summary
Write-Host ""
Write-Host "=== DONE ===" -ForegroundColor Cyan
Write-Host ("Tweaks: {0} applied, {1} skipped, {2} failed (of {3})" -f $appliedCount, $skippedCount, $failedCount, $tweakIds.Count)
Write-Host "Run dir: $runDir"
Write-Host "Rollback: .\scripts\rollback.ps1 -RunId $runId" -ForegroundColor Yellow

if ($failedCount -gt 0) { exit 2 } else { exit 0 }
