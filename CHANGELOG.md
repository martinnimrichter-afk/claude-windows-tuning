# Changelog

All notable changes to this project are documented in this file. Versions follow `<semver>-F<phase>` until v1.0.

## [0.3.0-F2] - 2026-05-26

### Added
- 7 new reversible safe tweaks: `ui-widgets-off`, `ui-start-suggestions-off`, `ui-lock-screen-tips-off`, `search-highlights-off`, `edge-promotional-off`, `onedrive-scoobe-off`, `notifications-news-off`
- `scripts/tweak-helpers.ps1` — shared module (`Invoke-TweakDetect/Apply/Verify`) supporting multi-value tweaks uniformly
- 4 profile presets fully populated: `office`, `gamer`, `devwsl` (all 8 tweaks), `creator` (6 tweaks; excludes onedrive-scoobe + edge-promotional)
- E2E validation on dedicated test PC including reboot survival and full rollback

### Changed
- Refactored `telemetry-required` to use the shared helper module
- `apply-safe.ps1` now prints per-value before/after for multi-value tweaks
- Increased `tested_builds` to include `26200` (Win 11 25H2 dev branch)

### Fixed
- "ALREADY APPLIED" log line no longer prints empty `()` for multi-value tweaks

## [0.2.0-F1] - 2026-05-24

### Added
- `scripts/audit.ps1` — read-only audit producing markdown report + JSON sidecar (environment, managed state, eventlog crashes, profile detection, AppX inventory, privacy posture, recommended tweaks)
- `scripts/profile-detect.ps1` — scored detection of Gamer / DevWSL / Office / Creator (dominant + override pattern)
- `references/audit-inherited.md` — attribution for `melodic-software/claude-code-plugins/windows-diagnostics`
- `references/profile-detection.md` — algorithm + weights + rationale
- 3 skeleton profile presets (`gamer.json`, `devwsl.json`, `creator.json`)

### Fixed
- Managed state check no longer false-positives on consumer Windows. Switched from `HKLM\SOFTWARE\Microsoft\PolicyManager\current` (present on every Win11 install) to `dsregcmd /status` + actual GPO values + real MDM enrollment URL.
- VSS service check now inspects `StartType` (Disabled = FAIL) instead of `Status` (Stopped is the default state for an on-demand service)

## [0.1.0-F0] - 2026-05-24

### Added
- Initial runnable build
- `SKILL.md` — Claude Code agent contract with YAML frontmatter, trigger phrasing, three-tier progressive disclosure
- `scripts/preflight.ps1` — 13 mandatory blockers (admin, ExecutionPolicy, pending reboot, free space, VSS, restore point, manifest write, dry-run support, undo.reg generation, verify.ps1 presence, managed state, no external downloads, architecture)
- `scripts/log.ps1` — JSONL events + human-readable history feed
- `scripts/checkpoint.ps1` — restore point + JSON registry snapshot
- `scripts/apply-safe.ps1` — orchestrator (preflight → checkpoint → tweak detect/apply/verify loop → after snapshot)
- `scripts/rollback.ps1` — reverse a specific run via merged `.reg` undo files
- One tweak shipped: `telemetry-required` — sets `HKLM\SOFTWARE\Policies\Microsoft\Windows\DataCollection\AllowTelemetry = 1` (Required diagnostic data, lowest level permitted on Pro/Home)
- 1 preset (`office.json`)
- `references/blockers-checklist.md`, `references/antipatterns.md`

## Pre-0.1

Project conceived 2026-05-24 after multi-AI review (the "Valná hromada" process) concluded that no existing Claude Code skill addresses Windows 11 tuning (the closest, `melodic-software/claude-code-plugins/windows-diagnostics`, is read-only diagnostic only). The two dominant PowerShell-based debloaters (ChrisTitusTech/winutil with 55k★, Raphire/Win11Debloat with 47k★) lack agent-native invocation, profile-aware recommendations, and declarative per-tweak rollback.

The conservative-MVP path was chosen over aggressive AppX removal in MVP, based on reviewer consensus that "MVP must be a trustworthy audit + reversible safe mode, not another debloat script with an agent wrapper." Aggressive mode + winutil/Win11Debloat orchestration is planned for v0.2 (see `references/v02-roadmap.md` when present).
