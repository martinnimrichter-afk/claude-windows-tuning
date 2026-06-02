# Blockers checklist

The 13 mandatory checks that `preflight.ps1` runs before any apply. Each documented with what it checks, why, and how the user can fix a failure.

| # | Check | Why | Fix |
|---|-------|-----|-----|
| 1 | **Admin elevation** | Restore points, AppX, HKLM registry, policy CSP, and service control all require admin. Without it the skill fails with cryptic errors halfway through. | Right-click PowerShell → Run as Administrator. |
| 2 | **ExecutionPolicy ≠ Restricted/Undefined** | A `.ps1` script won't even start under Restricted. | `Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass` (Process scope only — does not change system policy). |
| 3 | **No pending reboot** | Applying tweaks while `PendingFileRenameOperations` is queued can corrupt the change. | `Restart-Computer` then re-run. |
| 4 | **Free space on system drive > 2 GB** | Restore points need at least ~1 GB of VSS storage, plus headroom for the snapshot JSON. | Free up disk space (Storage Sense, `cleanmgr /sageset:1`). |
| 5 | **VSS service running** | Restore points are built on Volume Shadow Copy. | `Start-Service VSS` (as admin). If it refuses to start, check Event Viewer → Application for VSS errors. |
| 6 | **System Restore enabled on system drive** | Without restore enabled, `Checkpoint-Computer` will silently no-op (returns success without creating anything). | `Enable-ComputerRestore -Drive 'C:\'` (as admin). |
| 7 | **Manifest write access** | The skill writes `before.json`, `after.json`, `actions.jsonl`, and undo `.reg` files into `runs/<ts>/`. | Verify `runs/` is writable by the current user; on shared/locked-down machines, run from a folder you own. |
| 8 | **Dry-run flag honored** | Design-level check: `apply-safe.ps1` supports `-DryRun`. Always PASS in F0. | n/a |
| 9 | **undo.reg generation works** | Each apply generates a `.reg` undo file at apply time. Tests basic temp-file write capability. | If FAIL, check antivirus is not blocking `.reg` file writes in `%TEMP%`. |
| 10 | **`verify.ps1` present in tweaks** | Every tweak ships with a verify script. If none exist, the skill cannot confirm changes took effect. | This is an installation integrity check. If FAIL, re-download the skill. |
| 11 | **Managed state (GPO / Intune)** | Detects `HKLM\SOFTWARE\Policies\Microsoft\Windows`, `PolicyManager\current`, or `Enrollments` keys. If present, applied tweaks may be reverted by group policy on next sync. | This is WARN, not FAIL. `apply-safe.ps1` prompts the user to continue or abort. Pass `-YesToManagedWarning` for automation. |
| 12 | **No external downloads in MVP** | F0/v0.1 strictly uses built-in PowerShell. Always PASS. v0.2 (winutil wrapper) will introduce hash-verified downloads. | n/a |
| 13 | **Architecture (ARM64 disclaimer)** | Some tweaks (especially v0.2 ones using `Autorunsc.exe`) are x86/x64 only. The Telemetry tweak in F0 works on ARM64 since it's pure registry. | This is WARN on ARM64. Apply continues. |

## How blockers are used

`preflight.ps1` returns:
- Exit code **0** if all checks are PASS or WARN
- Exit code **1** if any check is FAIL

`apply-safe.ps1` calls preflight in JSON mode, inspects the result, and:
- Aborts if any FAIL
- Prompts the user if check #11 is WARN (managed state)
- Continues otherwise

## Adding a new blocker

For v0.2 and beyond, additions go here:
1. Add the check to `preflight.ps1` (`Add-Check -Id <next-id> ...`)
2. Document it here in the same format
3. Decide: FAIL (hard stop) or WARN (user choice)
4. If WARN, decide how `apply-safe.ps1` reacts (skip / prompt / continue silently)
