# tweaks/ui-widgets-off/detect.ps1
# Hides the Widgets button on the taskbar (the news/weather panel).
# Per-user setting. Does not remove the underlying AppX, just hides the button.

. (Join-Path (Split-Path $PSScriptRoot -Parent) '..\scripts\tweak-helpers.ps1')

Invoke-TweakDetect `
    -TweakId 'ui-widgets-off' `
    -RegistryPath 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' `
    -Targets @{ TaskbarDa = 0 }
