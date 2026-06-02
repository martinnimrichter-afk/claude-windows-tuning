# tweaks/ui-widgets-off/apply.ps1
param([Parameter(Mandatory)][string]$RollbackDir)

. (Join-Path (Split-Path $PSScriptRoot -Parent) '..\scripts\tweak-helpers.ps1')

Invoke-TweakApply `
    -TweakId 'ui-widgets-off' `
    -RegistryPath 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' `
    -Targets @{ TaskbarDa = 0 } `
    -RollbackDir $RollbackDir
