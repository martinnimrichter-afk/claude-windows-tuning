# Profile detection — algorithm and rationale

This skill detects one of four user profiles to tailor tweak recommendations:

- **Gamer** — uses Game Pass, Steam, Epic, or Battle.net
- **DevWSL** — uses WSL, Docker Desktop, Hyper-V, or Git heavily
- **Creator** — uses Adobe, Affinity, DaVinci Resolve, or Substance
- **Office** — default fallback for everyone else

## Why detect a profile at all

Forum research (Reddit r/Windows11, r/sysadmin, GitHub winutil issues) revealed that the #1 complaint about existing debloat tools is *"I clicked Essential Tweaks and it broke something I actually use."* Profile detection lets the skill skip tweaks that would break the user's primary toolchain.

In F0/F1, the only available tweak (`telemetry-required`) is safe for all profiles, so profile detection is purely informational. In F2 it gates which tweaks are applied per preset.

## Algorithm

Each profile gets a score from 0 to 100 based on multiple weighted signals. The dominant profile is selected as follows:

1. Compute scores for **Gamer**, **DevWSL**, **Creator**, and **Office** (the latter starts at +50 as the safe-default baseline).
2. Find the highest-scoring **non-Office** profile.
3. If that score is **≥ 70**, use it as dominant.
4. Otherwise, use **Office** as dominant.

The 70 threshold is intentionally conservative: we'd rather call a casual gamer "Office" (and skip Game-Bar-protecting logic) than mis-tag an Office user as "Gamer" and then later (v0.2) skip an AppX removal they actually wanted.

User override: `--profile devwsl` forces a profile regardless of detection. `--also-apply gamer` adds a second profile's safe tweaks on top of dominant (planned in v0.2).

## Signal weights

### DevWSL (max 100)

| Signal | Weight |
|--------|--------|
| `wsl.exe` present in System32 | +30 |
| `.wslconfig` in user profile | +20 |
| Docker Desktop installed (registry) | +20 |
| Hyper-V VMMS service present (not Disabled) | +20 |
| Git for Windows installed | +10 |

### Gamer (max 100)

| Signal | Weight |
|--------|--------|
| Microsoft.GamingApp AppX installed | +30 |
| Steam in Program Files (or local appdata) | +25 |
| Epic Games launcher in Program Files | +20 |
| Battle.net in Program Files | +20 |
| Xbox / GamePass services not disabled | +15 |

### Creator (max 100)

| Signal | Weight |
|--------|--------|
| Adobe in Program Files | +40 |
| Affinity in Program Files | +30 |
| Blackmagic Design / DaVinci Resolve | +25 |
| Substance 3D installed | +10 |

### Office (max 100, baseline 50)

| Signal | Weight |
|--------|--------|
| Baseline (default fallback) | +50 |
| Microsoft Office (Click-to-Run or MSI) | +30 |
| Microsoft Teams installed | +15 |

## Edge cases

**Multi-profile users (Gamer + DevWSL):** F1 picks dominant only. v0.2 will support `--also-apply <profile>` to union the safe-tweak sets. For Gamer/DevWSL conflicts (Xbox vs Hyper-V), v0.2 has a denylist resolver.

**No signals at all:** Office wins with score 50.

**Adobe Creative Cloud Trial:** Creator score will hit 40 from Adobe alone. Not enough to clear 70 → user is classified Office, which is correct (trial is not a primary workflow).

**Hyper-V auto-enabled by Windows for VBS/HVCI:** This is rare and would add +20 to DevWSL alone, not enough to clear 70. No false positive.

## What this algorithm intentionally does NOT do

- **Telemetry-based detection.** We do not inspect app launch frequency, focus time, or any usage telemetry. Detection is based on installed-software presence only.
- **AI/LLM classification.** Pure deterministic rules.
- **Cloud sync.** No phone-home to a profile registry.

## Tuning the weights

Open a PR with rationale. Changes to weights should be tested against at least 3 real machines per profile (Gamer/DevWSL/Creator/Office) and not change the dominant verdict in obvious cases.
