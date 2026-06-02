# tweaks/telemetry-required/apply.ps1
param([Parameter(Mandatory)][string]$RollbackDir)

. (Join-Path (Split-Path $PSScriptRoot -Parent) '..\scripts\tweak-helpers.ps1')

Invoke-TweakApply `
    -TweakId 'telemetry-required' `
    -RegistryPath 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection' `
    -Targets @{ AllowTelemetry = 1 } `
    -RollbackDir $RollbackDir
