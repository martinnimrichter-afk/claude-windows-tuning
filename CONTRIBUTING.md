# Contributing to windows-tuning

Thanks for your interest. This skill follows a strict safety contract — see `references/antipatterns.md` for the full NEVER-DO list.

## What is in scope

- New reversible **safe** tweaks (registry-policy or per-user UI settings)
- Improvements to profile detection (`scripts/profile-detect.ps1`)
- Better audit signals (`scripts/audit.ps1`)
- Bugfixes to `preflight.ps1` blockers
- Documentation, especially `references/antipatterns.md` additions

## What is out of scope (for v0.x at least)

- AppX removal — planned for v0.2 with explicit safelist + blocklist + vendor lockin guards
- winutil / Win11Debloat orchestration — also v0.2
- Driver tweaks (out of scope permanently)
- Firewall / network hardening (out of scope permanently)
- DISM `/resetbase` or anything that limits Windows Update rollback capacity

## Adding a new tweak

Each tweak is a directory under `tweaks/` with three files: `detect.ps1`, `apply.ps1`, `verify.ps1`. All three dot-source `scripts/tweak-helpers.ps1` and call a one-line `Invoke-TweakDetect/Apply/Verify` with the tweak's constants.

### Template — single-value tweak

```powershell
# tweaks/example-tweak/detect.ps1
. (Join-Path (Split-Path $PSScriptRoot -Parent) '..\scripts\tweak-helpers.ps1')

Invoke-TweakDetect `
    -TweakId 'example-tweak' `
    -RegistryPath 'HKCU:\Software\Example\Path' `
    -Targets @{ ValueName = 0 }
```

### Template — multi-value tweak

```powershell
# tweaks/example-tweak/apply.ps1
param([Parameter(Mandatory)][string]$RollbackDir)

. (Join-Path (Split-Path $PSScriptRoot -Parent) '..\scripts\tweak-helpers.ps1')

Invoke-TweakApply `
    -TweakId 'example-tweak' `
    -RegistryPath 'HKCU:\Software\Example\Path' `
    -Targets @{
        'Value1' = 0
        'Value2' = 1
    } `
    -RollbackDir $RollbackDir
```

`verify.ps1` mirrors `detect.ps1` but calls `Invoke-TweakVerify` with the same targets.

### Required for every new tweak

- [ ] All three files (`detect.ps1`, `apply.ps1`, `verify.ps1`) with matching `TweakId`, `RegistryPath`, `Targets`
- [ ] Comment block at the top of `detect.ps1` explaining what the tweak does and why
- [ ] Idempotent — `detect.ps1` must return `AlreadyApplied = $true` when the change is already in place
- [ ] Reversible — the helper's `undo.reg` generation must capture the BEFORE state at apply time (the helpers do this automatically)
- [ ] Listed in one or more `presets/*.json` files
- [ ] Tested on a real machine (not just dry-run): the apply changes the value, the verify confirms it, and rollback restores it
- [ ] Add an entry to `tweaks-catalog.md` (will be created when there are 10+ tweaks)

### Adding to presets

Presets in `presets/*.json` are lists of tweak IDs. If your tweak is safe for everyone, add it to all four (office / gamer / devwsl / creator). If it conflicts with a profile's primary workflow, exclude it from that preset and document the reason in the preset's `description` field.

### Anti-patterns — your PR will be rejected if

- The tweak removes any AppX package (use v0.2 aggressive mode instead, once that exists)
- The tweak disables Windows Update, the Update Orchestrator, or any service in the WU dependency chain
- The tweak calls `dism /resetbase` or `/StartComponentCleanup`
- The tweak manipulates ACLs on SYSTEM or TrustedInstaller
- The tweak suspends `EdgeUpdate` without a prominent warning
- The tweak performs external downloads (the F0/F1/F2 MVP intentionally has zero external dependencies)

## Adding a new profile

Profile detection lives in `scripts/profile-detect.ps1`. Each profile has a max-100 score from weighted signals.

To add a new profile (e.g. `Clinical` for medical workstations):
1. Add its scoring block to `Get-WinTuningProfile`
2. Add `references/profile-detection.md` row for the algorithm rationale
3. Add `presets/<profile>.json`
4. Tune weights against at least 3 real machines per profile
5. Update `scripts/audit.ps1` recommendation-mapping if the new profile excludes tweaks

## Reporting a bug

Open a GitHub issue with:
- Windows build (`winver`)
- PowerShell version (`$PSVersionTable.PSVersion`)
- Full output of `.\scripts\preflight.ps1`
- Relevant run directory contents (`runs/<timestamp>/run.log`)
- What you expected vs what happened

## Style

- No diacritics in `.ps1` files (Windows PowerShell 5.1 ANSI parser can choke)
- Comments only when the *why* is non-obvious
- One blank line between logical sections
- 4-space indent
- Use `$ErrorActionPreference = 'Stop'` in scripts that must fail loudly
- Avoid Bash-isms — this is Windows-only
