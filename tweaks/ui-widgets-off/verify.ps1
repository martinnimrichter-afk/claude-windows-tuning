# tweaks/ui-widgets-off/verify.ps1
. (Join-Path (Split-Path $PSScriptRoot -Parent) '..\scripts\tweak-helpers.ps1')

Invoke-TweakVerify `
    -TweakId 'ui-widgets-off' `
    -RegistryPath 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' `
    -Targets @{ TaskbarDa = 0 }
