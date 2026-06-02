# tweaks/onedrive-scoobe-off/detect.ps1
# Disables the "Finish setting up your PC" full-screen post-login interruption (Scoobe)
# that nags about OneDrive, Microsoft 365 trial, Edge, mobile sync, etc.
# Machine-wide. Does NOT disable OneDrive sync itself — only the post-login nag screen.

. (Join-Path (Split-Path $PSScriptRoot -Parent) '..\scripts\tweak-helpers.ps1')

Invoke-TweakDetect `
    -TweakId 'onedrive-scoobe-off' `
    -RegistryPath 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\UserProfileEngagement' `
    -Targets @{ ScoobeSystemSettingEnabled = 0 }
