# Antipatterns — NIKDY (never do)

Compiled from forum research (Reddit r/Windows11, r/sysadmin, r/PowerShell, GitHub winutil/Win11Debloat issues). Each entry: what NOT to do, why, and what we do instead.

## ❌ NEVER: Remove core AppX packages

**Don't remove:**
- `Microsoft.WindowsStore`
- `Microsoft.UI.Xaml.*`
- `Microsoft.VCLibs.*`
- `Microsoft.NET.Native.*`
- `Microsoft.Services.Store.Engagement`

**Why:** These are runtime dependencies for the Start menu, share dialog, photos, certificate UI, and most modern Win 11 surfaces. Removing them leads to "stuck right-click menu", Start menu won't open, share dialogs disappear, and `DISM /Online /Cleanup-Image /RestoreHealth` from install media is the only fix short of reinstall.

**Our policy:** F0 doesn't touch AppX at all. v0.2 aggressive mode uses an explicit safelist + blocklist that excludes everything above.

## ❌ NEVER: Disable Windows Update service (`wuauserv`) or Update Orchestrator

**Why:** Without updates, root certificates expire (~6 months), Edge stops loading HTTPS sites, you can't install new software via winget or the Store, and accumulating critical security patches creates exposure that dwarfs whatever performance you gained. Users on r/sysadmin repeatedly report this scenario.

**Our policy:** Never. Not in F0, not in v0.2, not ever. If a user wants to defer updates, that's `wuauclt /AUOptions 2` or Group Policy — not service disable.

## ❌ NEVER: `dism /Online /Cleanup-Image /StartComponentCleanup /ResetBase`

**Why:** This deletes WinSxS superseded payloads. After it runs, you cannot uninstall any subsequent Windows update because the rollback data is gone. If that update causes a regression, your only option is reinstall.

**Our policy:** Out of scope permanently. If user manually frees disk space, recommend `cleanmgr` instead.

## ❌ NEVER: Mass-revoke registry ACLs for SYSTEM or TrustedInstaller

**Why:** Tweak guides occasionally suggest changing ACLs on telemetry registry keys to "lock out" updates from re-enabling them. This breaks Component-Based Servicing (CBS). The symptom: `sfc /scannow` loops forever, future cumulative updates fail with cryptic errors, and Windows Update reports success without actually installing anything.

**Our policy:** Use policy-backed registry settings (under `HKLM\SOFTWARE\Policies\...`) which are the supported override mechanism. Never touch ACLs.

## ❌ NEVER: Disable VSS service while applying tweaks

**Why:** Some "performance" guides suggest disabling VSS. Then `Checkpoint-Computer` silently fails (Windows treats VSS-disabled as "restore points can't be created" — no error, just no checkpoint). Rollback later becomes impossible.

**Our policy:** Preflight check #5 hard-fails if VSS is not running.

## ❌ NEVER: Suspend EdgeUpdate without warning the user

**Why:** Edge gets weekly security patches. If you suspend `EdgeUpdate` and `MicrosoftEdgeUpdateTaskMachine*` scheduled tasks, Edge stays on whatever version was installed at the time. Within 1–2 months you have a browser missing critical CVE patches. Users don't always realize this — they think "I disabled the auto-update prompt" not "I stopped Edge from getting security fixes".

**Our policy:** When the Edge defaults tweak ships (F2), the explanation explicitly warns about this. We do NOT touch EdgeUpdate.

## ❌ NEVER: Remove AppX without checking vendor lockin

**Why:** Removing `Microsoft.GamingApp` on a machine with active Game Pass breaks all Game Pass titles. Removing `Microsoft.WindowsCalculator` after a Store install breaks reinstall (provisioned package gone). Removing Xbox Identity Provider kills Minecraft sign-in. The user usually doesn't connect "I debloated" with "Minecraft stopped working" until reinstall.

**Our policy:** v0.2 aggressive mode requires vendor lockin guards (Game Pass licence reg query, Adobe CC presence, Office 365 subscription). F0 doesn't touch AppX so this is N/A here.

## ❌ NEVER: Apply tweaks during pending reboot

**Why:** Writing registry values while `PendingFileRenameOperations` is queued can result in the OS replaying the rename after your write, effectively undoing your tweak silently. Or worse, corrupting the registry hive transaction.

**Our policy:** Preflight check #3 hard-fails on pending reboot.

## ❌ NEVER: Stage external downloads without hash verification

**Why:** Even legitimate projects like winutil and Autorunsc have been subject to typosquatting and CDN poisoning attempts. Pulling "latest" via raw URL with no hash check is a supply-chain risk.

**Our policy:** F0 has zero external downloads (preflight check #12). v0.2 will pin tooling to a specific commit hash + SHA256 verify before execution.

## ❌ NEVER: Skip the restore point because "I have backups"

**Why:** Backups are great for full disaster recovery but slow to restore (hours). A restore point is granular and reverses only system state in ~5 minutes. For tweak rollback, restore points win on speed even when backups exist.

**Our policy:** `checkpoint.ps1` always creates one. `-SkipRestorePoint` is documented as "emergencies / debugging only" and triggers a WARN log entry.

## ❌ NEVER: Silently apply policy-backed changes on managed Windows

**Why:** On a corporate machine, Intune / GPO will revert your changes on next policy sync (typically 8 hours). The user sees their tweak "stop working" with no log entry. Worse: some Intune policies trigger compliance failures when their values change.

**Our policy:** Preflight check #11 detects managed state and WARNS. `apply-safe.ps1` prompts the user before continuing. Automation can pass `-YesToManagedWarning` to suppress.

## ❌ NEVER: Promise non-registry implementations of telemetry control

**Why:** A reviewer (GPT55) flagged: "Windows often doesn't have clean public Settings API for these. In practice it's registry/policy/CSP depending on edition." Promising "we use the proper API not a registry hack" is misleading if the underlying mechanism is still a Policy registry key.

**Our policy:** We DO use policy registry keys (under `HKLM\SOFTWARE\Policies\Microsoft\Windows\...`) but we describe them honestly as "policy-backed registry settings", not "registry hacks" and not "Settings API". They are the documented Microsoft mechanism for overriding telemetry on Pro/Home.
