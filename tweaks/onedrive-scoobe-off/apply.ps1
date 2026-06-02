# tweaks/onedrive-scoobe-off/apply.ps1
param([Parameter(Mandatory)][string]$RollbackDir)

. (Join-Path (Split-Path $PSScriptRoot -Parent) '..\scripts\tweak-helpers.ps1')

Invoke-TweakApply `
    -TweakId 'onedrive-scoobe-off' `
    -RegistryPath 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\UserProfileEngagement' `
    -Targets @{ ScoobeSystemSettingEnabled = 0 } `
    -RollbackDir $RollbackDir
