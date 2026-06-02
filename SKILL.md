---
name: windows-tuning
description: Audits and tunes Windows 11 safely with profile-aware recommendations, declarative rollback, and reversible-only changes. Read-only audit mode plus safe tweak mode (UI, Edge defaults, OneDrive prompts, telemetry policy). Use when user asks to audit, clean, tune, debloat (lightly), or de-promote Windows 11, or asks about telemetry, Copilot prompts, OneDrive auto-backup, taskbar widgets, or Edge defaults. NOT for aggressive AppX removal — see v0.2 roadmap.
allowed-tools: Read, Write, PowerShell
tested_builds: ["22631", "26100", "26200"]
version: 0.3.0-F2
---

# windows-tuning

Agent-native tuning skill for Windows 11. Audits the system and applies reversible safe tweaks based on a detected user profile.

## When to use this skill

Invoke when the user asks for any of:
- "debloat Windows 11" / "tune Windows" / "clean up Windows"
- "vypni Copilot / telemetrii / Edge prompty / OneDrive prompty"
- "audit toho co je nainstalované"
- "Start menu reklamy / lock screen tipy / News & Interests"
- "proč mi pomalu naběhne PC" (combine with audit before recommending)

## What this skill DOES (MVP v0.1)

- **Audit mode** (read-only): generates a system health and bloat report
- **Safe mode**: applies only reversible tweaks (UI, Edge defaults, OneDrive prompts, telemetry policy)
- **Rollback**: every change captured in per-run manifest with .reg undo files
- **Profile-aware**: detects Gamer / DevWSL / Office / Creator and skips tweaks that would break that profile's tools

## What this skill does NOT DO

- ❌ No AppX removal (Microsoft Store apps, Xbox, Game Pass apps stay)
- ❌ No winutil / Win11Debloat wrappers (planned for v0.2)
- ❌ No DISM `/resetbase` or `/StartComponentCleanup`
- ❌ No ACL manipulation on SYSTEM or TrustedInstaller
- ❌ No driver tweaks or firewall hardening
- ❌ No external tool downloads (uses only built-in PowerShell)

See `references/antipatterns.md` for the full NEVER-DO list with rationale.

## How to invoke

All entry points are PowerShell scripts in `scripts/`. Run as **Administrator** in PowerShell 5.1 or 7+.

```powershell
# 1) Always preflight first — checks 13 mandatory blockers
.\scripts\preflight.ps1

# 2) Audit mode — read-only, generates report.md
.\scripts\audit.ps1

# 3) Safe mode — applies tweaks from a preset
.\scripts\apply-safe.ps1 -Preset office

# 4) Rollback a specific run
.\scripts\rollback.ps1 -RunId 2026-05-24_18-00-00
```

## Mandatory blockers (preflight)

Before any apply, `preflight.ps1` checks all 13 mantinels (see `references/blockers-checklist.md`):

1. Admin elevation
2. ExecutionPolicy not Restricted
3. No pending reboot
4. Free space on system drive > 2 GB
5. VSS service running
6. Restore point can be created
7. Manifest snapshot succeeds
8. Dry-run flag respected (optional)
9. Per-tweak undo.reg generation works
10. Post-apply verify available
11. Managed state (GPO/Intune) detected and user warned
12. No external downloads attempted
13. ARM64 detected and disclaimer shown

Any failure halts execution with a clear message.

## Profile detection (MVP: dominant + override)

Scored 0–100 per profile. The highest score ≥70 wins. Tie or all <70 → Office (default).

| Profile | Indicators |
|---------|-----------|
| DevWSL  | `wsl.exe` in PATH, `.wslconfig` exists, Docker Desktop, Hyper-V enabled |
| Gamer   | Microsoft.GamingApp AppX, Game Bar enabled, Steam/Epic/Battle.net in Program Files |
| Creator | Adobe Creative Cloud or Affinity in Program Files, NVIDIA Studio driver, RAW image associations |
| Office  | Default fallback |

User override: `--profile devwsl` or `--also-apply gamer`.

## Logging

Two destinations:
- **Human-readable feed:** `C:\AIPC1\LOCALMEMORY\win-tuning-history.md` (append-only)
- **Per-run machine data:** `runs/<timestamp>/run.log` (JSONL), `before.json`, `after.json`, `actions.jsonl`, `rollback/*.reg`

## Tweaks in F2 (this version)

8 reversible safe tweaks. Each has `detect/apply/verify` and per-run `undo.reg`.

| Tweak ID | Scope | What it does |
|----------|-------|--------------|
| `telemetry-required` | HKLM policy | `AllowTelemetry = 1` (Required, lowest level on Pro/Home) |
| `ui-widgets-off` | HKCU per-user | Hides taskbar Widgets button (`TaskbarDa = 0`) |
| `ui-start-suggestions-off` | HKCU per-user | Disables Start menu app suggestions, tips/tricks, Settings suggestions (3 values) |
| `ui-lock-screen-tips-off` | HKCU per-user | Disables Spotlight rotating images, fun-facts overlay, lock screen tips (3 values) |
| `search-highlights-off` | HKCU per-user | Disables dynamic decorative content inside taskbar Search box |
| `edge-promotional-off` | HKLM Edge policy | Hides first-run flow and disables promotional content on new tabs (2 values). Does NOT touch EdgeUpdate. |
| `onedrive-scoobe-off` | HKLM policy | Disables "Finish setting up your PC" post-login nag screen. Does NOT disable OneDrive sync. |
| `notifications-news-off` | HKLM Dsh policy | Disables News & Interests feed (machine-wide complement to ui-widgets-off) |

Presets (per profile from `profile-detect.ps1`):
- **office** / **gamer** / **devwsl**: all 8 tweaks (none of them touch Game Bar / Hyper-V / WSL)
- **creator**: 6 tweaks (excludes `onedrive-scoobe-off` and `edge-promotional-off` since Adobe workflows commonly use OneDrive sync and color-managed Edge)

## Agent guidance

When the user asks for a Windows tune-up:

1. **Always run audit first** to detect their profile and current state.
2. **Show the audit report** and ask which preset to apply.
3. **Confirm before apply.** Especially in managed environments (GPO/Intune detected).
4. **After apply: tell the user how to rollback** — give them the `RunId` and the exact `rollback.ps1` command.
5. **If anything in preflight fails**, explain which check failed and how to fix it.

## Safety contract

- Every apply creates a restore point AND a JSON snapshot. Both must succeed or no changes are made.
- Every tweak generates a per-tweak `undo.reg` at apply time (captures current value before changing).
- Every tweak has a `verify.ps1` that confirms the change took effect.
- If verify fails, that tweak is auto-rolled back from its undo.reg.
- Managed Windows (GPO/Intune detected): user gets a warning + choice (continue / abort), NOT silent skip.

## Related work and attribution

The audit module reuses event-log and SMART-disk inspection patterns from [`melodic-software/claude-code-plugins/windows-diagnostics`](https://github.com/melodic-software/claude-code-plugins/blob/main/plugins/windows-diagnostics/skills/system-diagnostics/SKILL.md) — full attribution in `references/audit-inherited.md` (added in F1).

## v0.2 roadmap (post-MVP)

After 2+ weeks of validation on dedicated test PC + 3+ other users:
- Aggressive mode (AppX removal via curated safelist)
- winutil wrapper (commit hash pin + SHA256 verify)
- Win11Debloat wrapper (release tag pin)
- Vendor lockin guards (Game Pass licence, Adobe CC, Office 365)
- Multi-profile scoring (Gamer + DevWSL simultaneously with denylist conflict resolver)
- Optional Autorunsc download for deeper audit

## License

MIT.
