# tweaks/ui-start-suggestions-off/detect.ps1
# Disables "Suggested" apps in Start menu, tips/tricks notifications, and Settings suggestions.
# Per-user. SubscribedContent IDs correspond to specific surfaces in the OS.

. (Join-Path (Split-Path $PSScriptRoot -Parent) '..\scripts\tweak-helpers.ps1')

Invoke-TweakDetect `
    -TweakId 'ui-start-suggestions-off' `
    -RegistryPath 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' `
    -Targets @{
        'SubscribedContent-338388Enabled' = 0   # Suggested apps in Start
        'SubscribedContent-338389Enabled' = 0   # Tips, tricks, suggestions notifications
        'SystemPaneSuggestionsEnabled'    = 0   # Settings home suggestions
    }
