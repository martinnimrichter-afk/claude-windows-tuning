# tweaks/search-highlights-off/apply.ps1
param([Parameter(Mandatory)][string]$RollbackDir)

. (Join-Path (Split-Path $PSScriptRoot -Parent) '..\scripts\tweak-helpers.ps1')

Invoke-TweakApply `
    -TweakId 'search-highlights-off' `
    -RegistryPath 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Feeds\DSB' `
    -Targets @{ ShowDynamicContent = 0 } `
    -RollbackDir $RollbackDir
