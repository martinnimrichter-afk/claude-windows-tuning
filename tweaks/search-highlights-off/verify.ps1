# tweaks/search-highlights-off/verify.ps1
. (Join-Path (Split-Path $PSScriptRoot -Parent) '..\scripts\tweak-helpers.ps1')

Invoke-TweakVerify `
    -TweakId 'search-highlights-off' `
    -RegistryPath 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Feeds\DSB' `
    -Targets @{ ShowDynamicContent = 0 }
