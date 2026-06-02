# tweaks/edge-promotional-off/apply.ps1
param([Parameter(Mandatory)][string]$RollbackDir)

. (Join-Path (Split-Path $PSScriptRoot -Parent) '..\scripts\tweak-helpers.ps1')

Invoke-TweakApply `
    -TweakId 'edge-promotional-off' `
    -RegistryPath 'HKLM:\SOFTWARE\Policies\Microsoft\Edge' `
    -Targets @{
        'HideFirstRunExperience' = 1
        'PromotionalTabsEnabled' = 0
    } `
    -RollbackDir $RollbackDir
