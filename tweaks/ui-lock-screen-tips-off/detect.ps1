# tweaks/ui-lock-screen-tips-off/detect.ps1
# Disables lock screen rotating Spotlight images, fun facts overlays, and tip suggestions.
# Per-user. Keeps lock screen functional but without Microsoft promotional content.

. (Join-Path (Split-Path $PSScriptRoot -Parent) '..\scripts\tweak-helpers.ps1')

Invoke-TweakDetect `
    -TweakId 'ui-lock-screen-tips-off' `
    -RegistryPath 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' `
    -Targets @{
        'RotatingLockScreenEnabled'        = 0   # Spotlight rotating images
        'RotatingLockScreenOverlayEnabled' = 0   # Fun-fact / location overlay
        'SubscribedContent-338387Enabled'  = 0   # Lock screen tips and tricks
    }
