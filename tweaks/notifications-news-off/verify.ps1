# tweaks/notifications-news-off/verify.ps1
. (Join-Path (Split-Path $PSScriptRoot -Parent) '..\scripts\tweak-helpers.ps1')

Invoke-TweakVerify `
    -TweakId 'notifications-news-off' `
    -RegistryPath 'HKLM:\SOFTWARE\Policies\Microsoft\Dsh' `
    -Targets @{ AllowNewsAndInterests = 0 }
