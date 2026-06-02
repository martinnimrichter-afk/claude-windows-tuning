# checkpoint.ps1 — creates a system restore point and a JSON manifest snapshot.
# Returns: hashtable with RunDir, RunId, RestorePointSequence, BeforeJsonPath.

[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$RunDir,
    [string]$Description = "windows-tuning checkpoint",
    [string[]]$RegistryPaths = @(),
    [switch]$SkipRestorePoint    # for emergencies / debugging only
)

$ErrorActionPreference = 'Stop'

. "$PSScriptRoot\log.ps1"

if (-not (Test-Path $RunDir)) {
    New-Item -ItemType Directory -Force -Path $RunDir | Out-Null
}

$runId = Split-Path $RunDir -Leaf
$rpName = "windows-tuning $runId"

# 1) Create restore point
$rpSeq = $null
if (-not $SkipRestorePoint) {
    Write-WinTuningEvent -Level INFO -Event 'checkpoint.restore_point.start' -Data @{ name = $rpName }
    try {
        # Bypass the 24-hour restore point throttle by zeroing the registry value
        $srpFreq = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore'
        if (Test-Path $srpFreq) {
            $existingFreq = (Get-ItemProperty -Path $srpFreq -Name SystemRestorePointCreationFrequency -ErrorAction SilentlyContinue).SystemRestorePointCreationFrequency
        }
        New-ItemProperty -Path $srpFreq -Name SystemRestorePointCreationFrequency -Value 0 -PropertyType DWord -Force | Out-Null

        Checkpoint-Computer -Description $rpName -RestorePointType 'MODIFY_SETTINGS' -ErrorAction Stop

        # Find the sequence number we just created
        $rps = Get-ComputerRestorePoint | Sort-Object SequenceNumber -Descending | Select-Object -First 1
        if ($rps) { $rpSeq = $rps.SequenceNumber }

        # Restore the original frequency (default is 1440 minutes / 24 hours)
        if ($null -ne $existingFreq) {
            New-ItemProperty -Path $srpFreq -Name SystemRestorePointCreationFrequency -Value $existingFreq -PropertyType DWord -Force | Out-Null
        }

        Write-WinTuningEvent -Level INFO -Event 'checkpoint.restore_point.ok' -Data @{ name = $rpName; sequence = $rpSeq }
    } catch {
        Write-WinTuningEvent -Level ERROR -Event 'checkpoint.restore_point.fail' -Data @{ error = $_.Exception.Message }
        throw "Restore point creation failed: $($_.Exception.Message)"
    }
} else {
    Write-WinTuningEvent -Level WARN -Event 'checkpoint.restore_point.skipped' -Data @{ reason = 'SkipRestorePoint switch' }
}

# 2) Manifest snapshot — captures registry paths we know we may touch
$snapshot = [ordered]@{
    run_id              = $runId
    timestamp           = (Get-Date).ToString('o')
    host                = $env:COMPUTERNAME
    os_build            = (Get-CimInstance Win32_OperatingSystem).BuildNumber
    os_caption          = (Get-CimInstance Win32_OperatingSystem).Caption
    architecture        = $env:PROCESSOR_ARCHITECTURE
    restore_point       = @{
        name     = $rpName
        sequence = $rpSeq
    }
    registry            = @{}
}

# Default snapshot targets if caller didn't specify
if ($RegistryPaths.Count -eq 0) {
    $RegistryPaths = @(
        'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection',
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection'
    )
}

foreach ($rp in $RegistryPaths) {
    try {
        if (Test-Path $rp) {
            $values = Get-ItemProperty -Path $rp -ErrorAction SilentlyContinue
            $clean = [ordered]@{}
            foreach ($prop in $values.PSObject.Properties) {
                if ($prop.Name -notmatch '^PS') {
                    $clean[$prop.Name] = $prop.Value
                }
            }
            $snapshot.registry[$rp] = @{ exists = $true; values = $clean }
        } else {
            $snapshot.registry[$rp] = @{ exists = $false; values = @{} }
        }
    } catch {
        $snapshot.registry[$rp] = @{ exists = 'unknown'; error = $_.Exception.Message }
    }
}

$beforePath = Join-Path $RunDir 'before.json'
$snapshot | ConvertTo-Json -Depth 10 | Out-File -FilePath $beforePath -Encoding UTF8

Write-WinTuningEvent -Level INFO -Event 'checkpoint.snapshot.ok' -Data @{
    before_path = $beforePath
    paths_captured = $RegistryPaths.Count
}

# Return
[PSCustomObject]@{
    RunDir               = $RunDir
    RunId                = $runId
    RestorePointSequence = $rpSeq
    BeforeJsonPath       = $beforePath
}
