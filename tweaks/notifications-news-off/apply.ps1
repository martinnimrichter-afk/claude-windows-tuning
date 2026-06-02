# tweaks/notifications-news-off/apply.ps1
param([Parameter(Mandatory)][string]$RollbackDir)

. (Join-Path (Split-Path $PSScriptRoot -Parent) '..\scripts\tweak-helpers.ps1')

Invoke-TweakApply `
    -TweakId 'notifications-news-off' `
    -RegistryPath 'HKLM:\SOFTWARE\Policies\Microsoft\Dsh' `
    -Targets @{ AllowNewsAndInterests = 0 } `
    -RollbackDir $RollbackDir
