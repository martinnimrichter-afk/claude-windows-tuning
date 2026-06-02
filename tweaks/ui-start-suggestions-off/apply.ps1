# tweaks/ui-start-suggestions-off/apply.ps1
param([Parameter(Mandatory)][string]$RollbackDir)

. (Join-Path (Split-Path $PSScriptRoot -Parent) '..\scripts\tweak-helpers.ps1')

Invoke-TweakApply `
    -TweakId 'ui-start-suggestions-off' `
    -RegistryPath 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' `
    -Targets @{
        'SubscribedContent-338388Enabled' = 0
        'SubscribedContent-338389Enabled' = 0
        'SystemPaneSuggestionsEnabled'    = 0
    } `
    -RollbackDir $RollbackDir
