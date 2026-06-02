# windows-tuning

Agent-native Windows 11 tuning skill for [Claude Code](https://docs.anthropic.com/claude-code). Read-only audit and reversible safe tweaks with declarative rollback. **Not a debloater** — see [What this is and is not](#what-this-is-and-is-not).

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B%20%7C%207%2B-blue.svg)]()
[![Windows](https://img.shields.io/badge/Windows-11-blue.svg)]()
[![Status](https://img.shields.io/badge/status-v0.3.0--F2-green.svg)](CHANGELOG.md)

## What it does

Tells you what's installed and what privacy/telemetry/UI noise is enabled (`audit`), then applies a curated set of reversible safe tweaks tailored to a detected user profile (`apply-safe`). Every change is captured to a per-run `.reg` undo file, plus a Windows restore point, so any change can be reversed cleanly even after a reboot.

```text
       ┌─────────────┐      ┌─────────────┐      ┌─────────────┐
input  │  audit.ps1  │ ───> │apply-safe   │ ───> │rollback.ps1 │  output
       │  read-only  │      │ 13 guards   │      │ reverses    │
       │  report.md  │      │ + 8 tweaks  │      │ specific    │
       │ + JSON data │      │ + restore   │      │ run by ID   │
       └─────────────┘      │   point     │      └─────────────┘
                            │ + undo.reg  │
                            └─────────────┘
```

## What this is and is not

**This is:** a careful, profile-aware tuning skill that an AI agent (Claude Code, Cursor, Codex CLI, Gemini CLI) or a human can invoke to remove UI noise (taskbar Widgets, News & Interests, Start menu suggestions, lock screen tips, Edge promotional content), reduce telemetry to the minimum permitted on Pro/Home, and silence "Finish setting up your PC" interruptions — without removing a single app, breaking Windows Update, or touching anything Microsoft's Feature Updates would consider unsafe.

**This is not:** a debloater. It does not remove AppX packages. It does not wrap [winutil](https://github.com/ChrisTitusTech/winutil) or [Win11Debloat](https://github.com/Raphire/Win11Debloat) — those are excellent tools, and an `aggressive` mode that orchestrates them is planned for v0.2 (see [v0.2 roadmap](#v02-roadmap)).

## Why this exists

The two dominant Windows debloaters cover most use cases:

| Tool | Stars | What it is |
|------|------:|------------|
| [ChrisTitusTech/winutil](https://github.com/ChrisTitusTech/winutil) | 55k+ | PowerShell GUI — apps, tweaks, fixes, updates, ISO builder |
| [Raphire/Win11Debloat](https://github.com/Raphire/Win11Debloat) | 47k+ | Single PowerShell script with a checkbox UI |

Neither is **agent-native**. An AI agent (Claude Code, Codex, Cursor, Gemini CLI) trying to help a user clean up Windows cannot:

1. **Detect the user's primary workflow** (gamer vs developer vs creator vs office) and skip tweaks that would break it
2. **Simulate impact** before applying ("this will hide the Widgets button — does that matter to you?")
3. **Maintain a per-run declarative manifest** so any specific apply can be reversed cleanly later
4. **Explain each change** in natural language with rollback instructions ready

This skill fills that gap. The only Claude Code skill in the same area, [`melodic-software/claude-code-plugins/windows-diagnostics`](https://github.com/melodic-software/claude-code-plugins/blob/main/plugins/windows-diagnostics/skills/system-diagnostics/SKILL.md), is read-only diagnostic — it tells you what's broken but never changes anything. We borrow its eventlog-scan pattern (attributed in [`references/audit-inherited.md`](references/audit-inherited.md)) and extend with remediation.

## Quick start

### Requirements

- Windows 11 (tested on builds 22631, 26100, 26200)
- PowerShell 5.1 or 7+
- Administrator rights for `preflight` and `apply-safe` (audit runs without admin)
- ~5 MB free disk (per-run state)

### Install

Clone the repo and either work from it directly or symlink it into the Claude Code skills directory:

```powershell
git clone https://github.com/martinnimrichter-afk/claude-windows-tuning.git
cd claude-windows-tuning

# Optional: symlink into Claude Code skills (run elevated)
New-Item -ItemType SymbolicLink `
    -Path "$env:USERPROFILE\.claude\skills\windows-tuning" `
    -Target "$PWD"
```

### Use it (manual, no agent)

```powershell
# 1) Always preflight first (admin) — 13 blockers
.\scripts\preflight.ps1

# 2) Audit (no admin needed) — read-only report
.\scripts\audit.ps1

# 3) Dry-run before any real change
.\scripts\apply-safe.ps1 -Preset office -DryRun

# 4) Apply for real
.\scripts\apply-safe.ps1 -Preset office

# 5) Rollback if needed (use the RunId from step 4)
.\scripts\rollback.ps1 -RunId 2026-05-26_18-00-00
```

### Use it (via Claude Code agent)

After symlinking into `~/.claude/skills/`, just ask the agent in natural language:

> "Audit my Windows install and tell me what's bloating it."
>
> "Apply the safe debloat for my gamer setup."
>
> "Roll back the tuning we just applied."

The skill's `SKILL.md` description triggers the agent automatically.

## What's in the box

### 8 tweaks (all reversible, all profile-aware)

| Tweak | Scope | What it changes |
|-------|-------|-----------------|
| `telemetry-required` | HKLM policy | `AllowTelemetry = 1` (Required — the lowest level permitted on Pro/Home; Security/0 requires Enterprise) |
| `ui-widgets-off` | HKCU per-user | Hides the taskbar Widgets button (`TaskbarDa = 0`) |
| `ui-start-suggestions-off` | HKCU per-user | Disables Start menu suggested apps + tips notifications + Settings home suggestions |
| `ui-lock-screen-tips-off` | HKCU per-user | Disables Spotlight rotating images, fun-fact overlays, lock-screen tip popups |
| `search-highlights-off` | HKCU per-user | Disables decorative dynamic content inside the taskbar Search box |
| `edge-promotional-off` | HKLM Edge policy | Skips Edge first-run flow and disables promotional new-tab content. **Does NOT touch EdgeUpdate** — Edge keeps getting security patches. |
| `onedrive-scoobe-off` | HKLM policy | Disables the "Finish setting up your PC" post-login nag screen. **Does NOT disable OneDrive sync.** |
| `notifications-news-off` | HKLM Dsh policy | Disables the News & Interests feed (machine-wide complement to `ui-widgets-off`) |

### 4 profile presets

Profiles are scored from installed software (no telemetry, no cloud, fully deterministic). See [`references/profile-detection.md`](references/profile-detection.md) for the full algorithm.

| Preset | Tweaks | Detection signals |
|--------|--------|-------------------|
| `office` | All 8 | Default fallback |
| `gamer` | All 8 | Microsoft.GamingApp AppX, Steam, Epic, Battle.net, Xbox services |
| `devwsl` | All 8 | `wsl.exe`, `.wslconfig`, Docker Desktop, Hyper-V, Git |
| `creator` | 6 (skips `onedrive-scoobe-off` and `edge-promotional-off`) | Adobe, Affinity, Blackmagic, Substance |

The `creator` preset is more conservative because Adobe workflows often rely on OneDrive sync (the Scoobe nag prompts for it) and some color-managed Edge configurations interact with policy restrictions.

### 13 mandatory safety blockers

`preflight.ps1` halts before any apply if:

1. Not running as Administrator
2. ExecutionPolicy is Restricted/Undefined
3. Pending reboot is queued
4. Free space on system drive < 2 GB
5. VSS service StartType is Disabled
6. System Restore is not enabled on the system drive
7. `runs/` directory is not writable
8. Dry-run flag is not honored (design-level check)
9. `.reg` undo file generation fails
10. No `verify.ps1` found in `tweaks/` (installation integrity)
11. Managed state (GPO / Intune / AzureAD / domain) — **WARN with user prompt**, not FAIL
12. External downloads attempted (MVP is download-free; always PASS in v0.x)
13. ARM64 disclaimer

Full documentation in [`references/blockers-checklist.md`](references/blockers-checklist.md).

### Safety contract

Every apply produces:
- A Windows restore point (verifiable in `rstrui.exe`)
- A JSON snapshot of all touched registry keys (`runs/<ts>/before.json`)
- Per-tweak `.reg` undo files (`runs/<ts>/rollback/<tweak>.reg`)
- A JSONL event log (`runs/<ts>/run.log`)
- A human-readable history entry (`%LOCALAPPDATA%\windows-tuning\history.md`)

If verify fails after apply, the affected tweak is auto-rolled back from its undo.reg. The other tweaks are unaffected.

## Comparison

| | windows-tuning | winutil | Win11Debloat | windows-diagnostics |
|---|:-:|:-:|:-:|:-:|
| Agent-native (Claude Code skill) | ✅ | ❌ | ❌ | ✅ |
| GUI for humans | ❌ | ✅ | ✅ | ❌ |
| Read-only audit | ✅ | partial | partial | ✅ |
| Profile-aware tweaks | ✅ | ❌ | ❌ | n/a |
| Per-run rollback manifest | ✅ | ❌ | partial | n/a |
| AppX removal | ❌ planned v0.2 | ✅ | ✅ | ❌ |
| Restore point automation | ✅ | optional | optional | ❌ |
| Managed Windows (GPO/Intune) detection | ✅ | ❌ | ❌ | partial |
| Zero external downloads in core | ✅ | ❌ | ❌ | ✅ |

If you want a Windows debloat tool with a GUI, use winutil or Win11Debloat. If you want a Claude Code skill that lets an AI agent reason about your machine and apply only the safe parts, that's this.

## v0.2 roadmap

After v0.1 (current) has been validated by 3+ users for 2+ weeks:

- **Aggressive mode** — a third mode beyond `audit` and `safe` that wraps `winutil` (commit-hash-pinned + SHA256 verified) and `Win11Debloat` (release-tag-pinned) for actual AppX removal
- **Vendor lockin guards** — query Game Pass licence, Adobe CC presence, Office 365 subscription before allowing related AppX removal
- **AppX safelist + blocklist** — explicit lists of what's never safe (Store, UI.Xaml, VCLibs, Hyper-V-*, Containers, WSL) and what's safely removable per profile
- **Multi-profile scoring** — for users who are simultaneously Gamer + DevWSL etc., union the safe tweak sets with conflict resolution via denylist
- **Post-reboot boot verify** — eventlog scan after the next reboot to confirm no Application Errors (ID 1000) were introduced
- **Optional Autorunsc download** — SHA256-verified, for deeper startup inventory

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for the tweak template, profile-extension guide, and the strict anti-pattern list (no AppX in v0.x, no Windows Update tampering, no `DISM /resetbase`, no ACL stunts).

Bug reports welcome — include `winver` output, `$PSVersionTable.PSVersion`, the full `preflight.ps1` output, and the relevant `runs/<timestamp>/run.log`.

## Credits

- Forum research (Reddit r/Windows11, r/sysadmin, r/PowerShell, GitHub winutil/Win11Debloat issues) compiled into [`references/antipatterns.md`](references/antipatterns.md)
- Audit pattern (eventlog crash IDs, read-only safety contract) adapted from [`melodic-software/claude-code-plugins/windows-diagnostics`](https://github.com/melodic-software/claude-code-plugins/blob/main/plugins/windows-diagnostics/skills/system-diagnostics/SKILL.md) — full attribution in [`references/audit-inherited.md`](references/audit-inherited.md)
- Per-tweak `.reg` undo file pattern inspired by [Raphire/Win11Debloat](https://github.com/Raphire/Win11Debloat/wiki/Reverting-Changes) Regfiles folder
- Multi-AI review process ("Valná hromada") — design validated by parallel reviews from four AI systems before implementation began. The conservative-MVP path (drop aggressive from v0.1) came directly from that review.

## License

[MIT](LICENSE) © 2026 Martin Nimrichter
