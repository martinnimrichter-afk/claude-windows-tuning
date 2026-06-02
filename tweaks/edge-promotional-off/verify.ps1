# tweaks/edge-promotional-off/verify.ps1
. (Join-Path (Split-Path $PSScriptRoot -Parent) '..\scripts\tweak-helpers.ps1')

Invoke-TweakVerify `
    -TweakId 'edge-promotional-off' `
    -RegistryPath 'HKLM:\SOFTWARE\Policies\Microsoft\Edge' `
    -Targets @{
        'HideFirstRunExperience' = 1
        'PromotionalTabsEnabled' = 0
    }
