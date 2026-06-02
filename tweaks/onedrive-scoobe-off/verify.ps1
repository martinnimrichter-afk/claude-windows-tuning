# tweaks/onedrive-scoobe-off/verify.ps1
. (Join-Path (Split-Path $PSScriptRoot -Parent) '..\scripts\tweak-helpers.ps1')

Invoke-TweakVerify `
    -TweakId 'onedrive-scoobe-off' `
    -RegistryPath 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\UserProfileEngagement' `
    -Targets @{ ScoobeSystemSettingEnabled = 0 }
