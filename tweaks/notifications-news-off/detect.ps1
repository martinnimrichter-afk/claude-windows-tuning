# tweaks/notifications-news-off/detect.ps1
# Disables the "News and Interests" / "Widgets" feed on the taskbar via the Dsh policy.
# Machine-wide. Removes the clickbait feed entirely (complementary to ui-widgets-off
# which only hides the button at the user level).

. (Join-Path (Split-Path $PSScriptRoot -Parent) '..\scripts\tweak-helpers.ps1')

Invoke-TweakDetect `
    -TweakId 'notifications-news-off' `
    -RegistryPath 'HKLM:\SOFTWARE\Policies\Microsoft\Dsh' `
    -Targets @{ AllowNewsAndInterests = 0 }
