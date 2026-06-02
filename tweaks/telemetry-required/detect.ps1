# tweaks/telemetry-required/detect.ps1
# Sets AllowTelemetry policy to 1 (Required diagnostic data, lowest permitted on Pro/Home).
# Note: 0 (Security) only works on Enterprise/Education editions.

. (Join-Path (Split-Path $PSScriptRoot -Parent) '..\scripts\tweak-helpers.ps1')

Invoke-TweakDetect `
    -TweakId 'telemetry-required' `
    -RegistryPath 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection' `
    -Targets @{ AllowTelemetry = 1 }
