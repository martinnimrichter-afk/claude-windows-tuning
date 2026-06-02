# tweaks/search-highlights-off/detect.ps1
# Disables "Search Highlights" — the rotating decorative icon and content suggestions
# inside the taskbar Search box (sponsored/news/holiday-themed dynamic content).
# Per-user.

. (Join-Path (Split-Path $PSScriptRoot -Parent) '..\scripts\tweak-helpers.ps1')

Invoke-TweakDetect `
    -TweakId 'search-highlights-off' `
    -RegistryPath 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Feeds\DSB' `
    -Targets @{ ShowDynamicContent = 0 }
