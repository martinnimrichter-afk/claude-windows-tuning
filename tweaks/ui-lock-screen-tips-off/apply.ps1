# tweaks/ui-lock-screen-tips-off/apply.ps1
param([Parameter(Mandatory)][string]$RollbackDir)

. (Join-Path (Split-Path $PSScriptRoot -Parent) '..\scripts\tweak-helpers.ps1')

Invoke-TweakApply `
    -TweakId 'ui-lock-screen-tips-off' `
    -RegistryPath 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' `
    -Targets @{
        'RotatingLockScreenEnabled'        = 0
        'RotatingLockScreenOverlayEnabled' = 0
        'SubscribedContent-338387Enabled'  = 0
    } `
    -RollbackDir $RollbackDir
