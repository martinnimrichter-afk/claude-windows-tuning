# Audit module — inherited patterns and attribution

The audit functionality in `scripts/audit.ps1` reuses several patterns from the open-source [`melodic-software/claude-code-plugins/windows-diagnostics`](https://github.com/melodic-software/claude-code-plugins/blob/main/plugins/windows-diagnostics/skills/system-diagnostics/SKILL.md) skill by melodic-software.

## What we adopted

| Pattern | Source skill | Our usage |
|---------|--------------|-----------|
| **Eventlog crash IDs** (41, 1001, 6008, 1002) | `windows-diagnostics/SKILL.md` — System Health section | `audit.ps1` → `Get-WinEvent -FilterHashtable @{ Id = 41, 1001, 6008 }` for unexpected shutdowns, BSOD, hangs |
| **Read-only safety contract** | `windows-diagnostics` design model | Our `audit.ps1` mirrors this — no `chkdsk /f`, no `sfc /scannow`, no `DISM` restoration, no driver reinstalls. We only inventory and recommend. |
| **Progressive disclosure** | YAML always loaded → SKILL.md body → linked refs on-demand | Our `SKILL.md` uses the same three-tier structure |
| **WHEA event filtering approach** | `windows-diagnostics` references | Will be adopted in F2 when we add disk/hardware health checks |

## What we did NOT take

We did NOT copy code verbatim. The implementation is independent — we re-wrote the PowerShell using the same approach but our own structure, error handling, and output format.

We did NOT take:
- Their report format (we use a different markdown structure)
- Their SKILL.md prose (ours is in Czech in places, theirs is English)
- Their plugin packaging (we ship as a standalone skill, not a plugin)

## License compatibility

The melodic-software skill (as of December 2025 commit) has **no explicit LICENSE file**. Per GitHub's default policy, this means all rights are reserved by the author and forking / direct re-use is technically restricted.

**Our position:** We use only public concepts (eventlog IDs are Microsoft documentation, read-only design is a common safety pattern) and our implementation is independent. We attribute prominently to honor the author's contribution to the ecosystem.

**If the author of `melodic-software/windows-diagnostics` objects:** open an issue at this skill's repo or contact us. We will adapt — either remove the pattern, or rewrite to be demonstrably independent.

## When to re-read this file

- Before adding any new audit feature inspired by another open-source skill
- When publishing this skill to a public marketplace (GitHub, awesome-agent-skills, etc.)
- When `melodic-software/claude-code-plugins` adds a LICENSE file (recheck terms)

## Related work (other skills consulted, not used)

| Skill | Status | Why not |
|-------|--------|---------|
| `NotMyself/claude-win11-speckit-update-skill` | Archived 2026-02-01 | About SpecKit template updates, unrelated to tuning |
| `ChrisTitusTech/winutil` | Active, MIT | Will be wrapped in v0.2 aggressive mode (cited there) |
| `Raphire/Win11Debloat` | Active, MIT | Will be wrapped in v0.2 aggressive mode (cited there); we already use their `.reg` undo file pattern |
