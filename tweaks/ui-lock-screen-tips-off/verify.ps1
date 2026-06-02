# tweaks/ui-lock-screen-tips-off/verify.ps1
. (Join-Path (Split-Path $PSScriptRoot -Parent) '..\scripts\tweak-helpers.ps1')

Invoke-TweakVerify `
    -TweakId 'ui-lock-screen-tips-off' `
    -RegistryPath 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' `
    -Targets @{
        'RotatingLockScreenEnabled'        = 0
        'RotatingLockScreenOverlayEnabled' = 0
        'SubscribedContent-338387Enabled'  = 0
    }
