# tweaks/edge-promotional-off/detect.ps1
# Disables Edge's first-run experience pages and promotional tabs (Bing rewards ads,
# "discover what Edge can do" splash, sponsored new-tab content).
# Machine-wide policy under HKLM\SOFTWARE\Policies\Microsoft\Edge.
#
# NOTE: This tweak does NOT touch EdgeUpdate. Edge still receives security patches.
# It only suppresses promotional UI surfaces.

. (Join-Path (Split-Path $PSScriptRoot -Parent) '..\scripts\tweak-helpers.ps1')

Invoke-TweakDetect `
    -TweakId 'edge-promotional-off' `
    -RegistryPath 'HKLM:\SOFTWARE\Policies\Microsoft\Edge' `
    -Targets @{
        'HideFirstRunExperience' = 1   # Skip Edge first-launch onboarding flow
        'PromotionalTabsEnabled' = 0   # Disable promo content on new tab
    }
