# log.ps1 — dot-source helper for structured logging.
# Two destinations:
#   1) C:\AIPC1\LOCALMEMORY\win-tuning-history.md  (human-readable append-only feed)
#   2) <RunDir>\run.log                            (per-run JSONL events)
#
# Usage:
#   . "$PSScriptRoot\log.ps1"
#   Initialize-WinTuningLog -RunDir $rd -Preset office
#   Write-WinTuningEvent -Level INFO -Event "preflight.ok" -Data @{ checks = 13 }
#   Close-WinTuningLog -Summary @{ tweaks_applied = 1; tweaks_failed = 0 }

# Initialize globals only once across dot-sources (re-sourcing must not reset live state).
# History destination defaults to %LOCALAPPDATA%\windows-tuning\history.md (portable).
# Override by setting $env:WIN_TUNING_HISTORY before running any script.
if (-not (Test-Path 'Variable:Global:WT_HistoryPath')) {
    if ($env:WIN_TUNING_HISTORY) {
        $global:WT_HistoryPath = $env:WIN_TUNING_HISTORY
    } else {
        $global:WT_HistoryPath = Join-Path $env:LOCALAPPDATA 'windows-tuning\history.md'
    }
    $global:WT_RunDir    = $null
    $global:WT_LogPath   = $null
    $global:WT_RunId     = $null
    $global:WT_StartTime = $null
    $global:WT_Preset    = $null
}

function Initialize-WinTuningLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RunDir,
        [Parameter(Mandatory)][string]$Preset
    )
    $global:WT_RunDir    = $RunDir
    $global:WT_LogPath   = Join-Path $RunDir 'run.log'
    $global:WT_RunId     = Split-Path $RunDir -Leaf
    $global:WT_StartTime = Get-Date
    $global:WT_Preset    = $Preset

    if (-not (Test-Path $RunDir)) {
        New-Item -ItemType Directory -Path $RunDir -Force | Out-Null
    }

    # Ensure history dir exists
    $hDir = Split-Path $global:WT_HistoryPath -Parent
    if (-not (Test-Path $hDir)) {
        New-Item -ItemType Directory -Path $hDir -Force | Out-Null
    }

    Write-WinTuningEvent -Level INFO -Event 'run.start' -Data @{
        run_id   = $global:WT_RunId
        preset   = $Preset
        run_dir  = $RunDir
        host     = $env:COMPUTERNAME
        user     = $env:USERNAME
        os_build = (Get-CimInstance Win32_OperatingSystem).BuildNumber
        ps_ver   = $PSVersionTable.PSVersion.ToString()
    }
}

function Write-WinTuningEvent {
    [CmdletBinding()]
    param(
        [ValidateSet('DEBUG','INFO','WARN','ERROR')]
        [string]$Level = 'INFO',
        [Parameter(Mandatory)][string]$Event,
        [hashtable]$Data = @{}
    )

    if (-not $global:WT_LogPath) {
        throw "Initialize-WinTuningLog must be called first."
    }

    $entry = [ordered]@{
        ts    = (Get-Date).ToString('o')
        level = $Level
        event = $Event
        data  = $Data
    }
    $line = $entry | ConvertTo-Json -Compress -Depth 10
    Add-Content -Path $global:WT_LogPath -Value $line -Encoding UTF8

    # Console echo
    $color = switch ($Level) {
        'ERROR' { 'Red' }
        'WARN'  { 'Yellow' }
        'INFO'  { 'Cyan' }
        default { 'Gray' }
    }
    Write-Host ("[{0}] {1}" -f $Level, $Event) -ForegroundColor $color
}

function Close-WinTuningLog {
    [CmdletBinding()]
    param(
        [hashtable]$Summary = @{}
    )

    $duration = (Get-Date) - $global:WT_StartTime
    $finalSummary = $Summary.Clone()
    $finalSummary['duration_seconds'] = [int]$duration.TotalSeconds

    Write-WinTuningEvent -Level INFO -Event 'run.end' -Data $finalSummary

    # Append to human-readable history
    $md = New-Object System.Text.StringBuilder
    [void]$md.AppendLine("")
    [void]$md.AppendLine("## $($global:WT_StartTime.ToString('yyyy-MM-dd HH:mm:ss')) - apply-safe $($global:WT_Preset)")
    [void]$md.AppendLine("")
    [void]$md.AppendLine("- Run ID: $($global:WT_RunId)")
    [void]$md.AppendLine("- Host: $env:COMPUTERNAME")
    [void]$md.AppendLine("- Preset: $($global:WT_Preset)")
    foreach ($k in $finalSummary.Keys) {
        [void]$md.AppendLine("- ${k}: $($finalSummary[$k])")
    }
    [void]$md.AppendLine("- Run dir: $($global:WT_RunDir)")
    [void]$md.AppendLine("- Rollback: .\scripts\rollback.ps1 -RunId $($global:WT_RunId)")
    [void]$md.AppendLine("")

    Add-Content -Path $global:WT_HistoryPath -Value $md.ToString() -Encoding UTF8
}

function Get-WinTuningRunDir {
    return $global:WT_RunDir
}

function Get-WinTuningRunId {
    return $global:WT_RunId
}
