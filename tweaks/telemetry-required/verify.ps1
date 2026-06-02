# tweaks/telemetry-required/verify.ps1
. (Join-Path (Split-Path $PSScriptRoot -Parent) '..\scripts\tweak-helpers.ps1')

Invoke-TweakVerify `
    -TweakId 'telemetry-required' `
    -RegistryPath 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection' `
    -Targets @{ AllowTelemetry = 1 }
