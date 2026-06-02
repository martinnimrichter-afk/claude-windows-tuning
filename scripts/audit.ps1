# audit.ps1 — read-only Windows 11 audit. Produces a markdown report and JSON sidecar.
#
# Usage:
#   .\audit.ps1                       # Default — writes report under runs/audit_<ts>/
#   .\audit.ps1 -OutDir C:\some\dir   # Custom output directory
#   .\audit.ps1 -Json                 # Also emit raw audit data JSON to stdout
#
# This script does NOT change anything. It does not require admin (but runs more completely with it).

[CmdletBinding()]
param(
    [string]$OutDir,
    [switch]$Json,
    [switch]$Quiet
)

$ErrorActionPreference = 'Continue'

$skillRoot = Split-Path $PSScriptRoot -Parent

# Output directory
if (-not $OutDir) {
    $ts = Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'
    $OutDir = Join-Path $skillRoot "runs\audit_$ts"
}
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

$reportPath = Join-Path $OutDir 'report.md'
$auditJson  = Join-Path $OutDir 'audit.json'

# ---------- Collect ----------

if (-not $Quiet) { Write-Host "Collecting environment..." -ForegroundColor Cyan }

$os         = Get-CimInstance Win32_OperatingSystem
$cs         = Get-CimInstance Win32_ComputerSystem
$id         = [System.Security.Principal.WindowsIdentity]::GetCurrent()
$principal  = New-Object System.Security.Principal.WindowsPrincipal($id)
$isAdmin    = $principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
$execPolicy = Get-ExecutionPolicy

$env = [ordered]@{
    timestamp        = (Get-Date).ToString('o')
    host             = $env:COMPUTERNAME
    user             = $env:USERNAME
    os_caption       = $os.Caption
    os_build         = $os.BuildNumber
    os_version       = $os.Version
    architecture     = $env:PROCESSOR_ARCHITECTURE
    ps_version       = $PSVersionTable.PSVersion.ToString()
    admin            = $isAdmin
    execution_policy = $execPolicy.ToString()
    total_ram_gb     = [math]::Round($cs.TotalPhysicalMemory / 1GB, 2)
    cpu              = (Get-CimInstance Win32_Processor | Select-Object -First 1).Name
}

# Managed state — mirrors preflight check #11
if (-not $Quiet) { Write-Host "Checking managed state..." -ForegroundColor Cyan }
$managedSignals = @()
try {
    $dsr = & dsregcmd.exe /status 2>$null | Out-String
    if ($dsr -match 'AzureAdJoined\s*:\s*YES')    { $managedSignals += 'AzureAdJoined' }
    if ($dsr -match 'DomainJoined\s*:\s*YES')     { $managedSignals += 'DomainJoined' }
    if ($dsr -match 'EnterpriseJoined\s*:\s*YES') { $managedSignals += 'EnterpriseJoined' }
    if ($dsr -match 'MdmUrl\s*:\s*\S+')           { $managedSignals += 'MdmEnrolled' }
} catch { }
try {
    $wuPol = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate'
    if (Test-Path $wuPol) {
        $vals = Get-ItemProperty -Path $wuPol -ErrorAction SilentlyContinue
        $hasVals = $vals.PSObject.Properties | Where-Object { $_.Name -notmatch '^PS' }
        if ($hasVals) { $managedSignals += 'GPO:WindowsUpdate' }
    }
} catch { }
$managed = @{
    is_managed = ($managedSignals.Count -gt 0)
    signals    = $managedSignals
}

# Crashes (eventlog last 7 days)
if (-not $Quiet) { Write-Host "Scanning eventlog crashes (last 7 days)..." -ForegroundColor Cyan }
$crashes = @{ unexpected_shutdown = 0; application_hang = 0; bsod_whea = 0; recent = @() }
try {
    $since = (Get-Date).AddDays(-7)
    # 41 = unexpected shutdown (Kernel-Power), 1001 = BSOD (BugCheck), 6008 = unexpected shutdown (EventLog)
    $sys = Get-WinEvent -FilterHashtable @{
        LogName = 'System'; StartTime = $since; Id = 41, 1001, 6008
    } -MaxEvents 50 -ErrorAction SilentlyContinue
    foreach ($e in $sys) {
        switch ($e.Id) {
            41   { $crashes.unexpected_shutdown++ }
            1001 { $crashes.bsod_whea++ }
            6008 { $crashes.unexpected_shutdown++ }
        }
        if ($crashes.recent.Count -lt 10) {
            $crashes.recent += @{
                ts     = $e.TimeCreated.ToString('o')
                id     = $e.Id
                source = $e.ProviderName
                msg    = ($e.Message -split "`n" | Select-Object -First 1).Trim()
            }
        }
    }
    # 1002 = app hang (Application Hang Reporting)
    $appHangs = Get-WinEvent -FilterHashtable @{
        LogName = 'Application'; StartTime = $since; Id = 1002
    } -MaxEvents 50 -ErrorAction SilentlyContinue
    if ($appHangs) { $crashes.application_hang = $appHangs.Count }
} catch {
    $crashes.error = $_.Exception.Message
}

# Profile detection
if (-not $Quiet) { Write-Host "Detecting user profile..." -ForegroundColor Cyan }
. "$PSScriptRoot\profile-detect.ps1"
$profile = Get-WinTuningProfile

# AppX inventory (current user — no admin needed for own packages)
if (-not $Quiet) { Write-Host "Inventorying AppX packages..." -ForegroundColor Cyan }
$appx = @{ count = 0; by_publisher = @{}; non_microsoft = @() }
try {
    $packages = Get-AppxPackage -ErrorAction SilentlyContinue
    if ($packages) {
        $appx.count = $packages.Count
        foreach ($p in $packages) {
            # Publisher field may be "CN=X, O=\"Acme, Inc.\", L=..." or "CN=X, O=Acme, L=..."
            $pub = 'Unknown'
            if     ($p.Publisher -match 'O="([^"]+)"') { $pub = $matches[1].Trim() }
            elseif ($p.Publisher -match 'O=([^,]+)')   { $pub = $matches[1].Trim() }
            if (-not $appx.by_publisher.ContainsKey($pub)) {
                $appx.by_publisher[$pub] = 0
            }
            $appx.by_publisher[$pub]++

            if ($pub -ne 'Microsoft Corporation' -and $pub -ne 'Unknown') {
                $appx.non_microsoft += $p.Name
            }
        }
    }
} catch {
    $appx.error = $_.Exception.Message
}

# Privacy posture
if (-not $Quiet) { Write-Host "Reading privacy posture..." -ForegroundColor Cyan }
function Get-RegInt {
    param([string]$Path, [string]$Name)
    try {
        $v = (Get-ItemProperty -Path $Path -Name $Name -ErrorAction Stop).$Name
        return [int]$v
    } catch {
        return $null
    }
}
$privacy = @{
    telemetry_policy        = Get-RegInt 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection' 'AllowTelemetry'
    telemetry_setting       = Get-RegInt 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection' 'AllowTelemetry'
    copilot_disabled        = Get-RegInt 'HKCU:\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot' 'TurnOffWindowsCopilot'
    widgets_disabled        = Get-RegInt 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'TaskbarDa'
    onedrive_running        = [bool](Get-Process OneDrive -ErrorAction SilentlyContinue)
    edge_default_check      = $null   # complex, deferred to F2
    news_interests_disabled = Get-RegInt 'HKLM:\SOFTWARE\Policies\Microsoft\Dsh' 'AllowNewsAndInterests'
}

# Recommended tweaks (mapped from profile — F1 has one tweak available)
$availableTweaks = @('telemetry-required')
$profileExclusions = @{
    Gamer   = @()  # F1: telemetry tweak is safe for everyone
    DevWSL  = @()
    Office  = @()
    Creator = @()
}
$recommended = $availableTweaks | Where-Object { $_ -notin $profileExclusions[$profile.Dominant] }

# ---------- Build markdown report ----------

$md = New-Object System.Text.StringBuilder
[void]$md.AppendLine("# Windows tuning audit — $($env.host)")
[void]$md.AppendLine("")
[void]$md.AppendLine("Generated: $($env.timestamp)")
[void]$md.AppendLine("")
[void]$md.AppendLine("## Environment")
[void]$md.AppendLine("")
[void]$md.AppendLine("| Field | Value |")
[void]$md.AppendLine("|-------|-------|")
[void]$md.AppendLine("| OS | $($env.os_caption) |")
[void]$md.AppendLine("| Build | $($env.os_build) |")
[void]$md.AppendLine("| Version | $($env.os_version) |")
[void]$md.AppendLine("| Architecture | $($env.architecture) |")
[void]$md.AppendLine("| CPU | $($env.cpu) |")
[void]$md.AppendLine("| RAM | $($env.total_ram_gb) GB |")
[void]$md.AppendLine("| PowerShell | $($env.ps_version) |")
[void]$md.AppendLine("| User | $($env.user) |")
[void]$md.AppendLine("| Admin | $($env.admin) |")
[void]$md.AppendLine("| ExecutionPolicy | $($env.execution_policy) |")
[void]$md.AppendLine("")

[void]$md.AppendLine("## Managed state")
[void]$md.AppendLine("")
if ($managed.is_managed) {
    [void]$md.AppendLine("**MANAGED.** Signals: $($managed.signals -join ', ')")
    [void]$md.AppendLine("")
    [void]$md.AppendLine("Applied tweaks may be reverted by policy.")
} else {
    [void]$md.AppendLine("**Standalone.** No GPO / MDM / AzureAD / domain join detected.")
}
[void]$md.AppendLine("")

[void]$md.AppendLine("## System health (last 7 days)")
[void]$md.AppendLine("")
[void]$md.AppendLine("| Event type | Count |")
[void]$md.AppendLine("|------------|-------|")
[void]$md.AppendLine("| Unexpected shutdowns (Kernel-Power 41 / EventLog 6008) | $($crashes.unexpected_shutdown) |")
[void]$md.AppendLine("| BSOD / WHEA (BugCheck 1001) | $($crashes.bsod_whea) |")
[void]$md.AppendLine("| Application hangs (1002) | $($crashes.application_hang) |")
[void]$md.AppendLine("")
if ($crashes.recent.Count -gt 0) {
    [void]$md.AppendLine("Most recent (up to 10):")
    [void]$md.AppendLine("")
    foreach ($c in $crashes.recent) {
        [void]$md.AppendLine("- ``$($c.ts)`` — [$($c.id)] $($c.source): $($c.msg)")
    }
    [void]$md.AppendLine("")
}

[void]$md.AppendLine("## Detected profile")
[void]$md.AppendLine("")
[void]$md.AppendLine("**$($profile.Dominant)** (confidence: $($profile.Confidence))")
[void]$md.AppendLine("")
[void]$md.AppendLine("Scores:")
[void]$md.AppendLine("")
foreach ($k in @('Gamer','DevWSL','Office','Creator')) {
    [void]$md.AppendLine("- $($k): $($profile.Scores[$k])")
}
[void]$md.AppendLine("")
[void]$md.AppendLine("Evidence:")
[void]$md.AppendLine("")
foreach ($k in @('Gamer','DevWSL','Office','Creator')) {
    if ($profile.Evidence[$k].Count -gt 0) {
        [void]$md.AppendLine("**$($k):**")
        foreach ($e in $profile.Evidence[$k]) {
            [void]$md.AppendLine("- $e")
        }
        [void]$md.AppendLine("")
    }
}

[void]$md.AppendLine("## AppX inventory")
[void]$md.AppendLine("")
[void]$md.AppendLine("Total installed: **$($appx.count)** packages")
[void]$md.AppendLine("")
[void]$md.AppendLine("By publisher (top 10):")
[void]$md.AppendLine("")
[void]$md.AppendLine("| Publisher | Count |")
[void]$md.AppendLine("|-----------|-------|")
$appx.by_publisher.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 10 | ForEach-Object {
    [void]$md.AppendLine("| $($_.Key) | $($_.Value) |")
}
[void]$md.AppendLine("")
if ($appx.non_microsoft.Count -gt 0) {
    [void]$md.AppendLine("Non-Microsoft AppX (first 20):")
    [void]$md.AppendLine("")
    $appx.non_microsoft | Select-Object -First 20 | ForEach-Object {
        [void]$md.AppendLine("- $_")
    }
    [void]$md.AppendLine("")
}

[void]$md.AppendLine("## Privacy posture")
[void]$md.AppendLine("")
[void]$md.AppendLine("| Setting | Current value | Notes |")
[void]$md.AppendLine("|---------|---------------|-------|")
$tval = if ($null -eq $privacy.telemetry_policy) { 'not set (default = 3 / Optional)' } else { "$($privacy.telemetry_policy)" }
[void]$md.AppendLine("| Telemetry policy (AllowTelemetry) | $tval | target for safe tweak: 1 (Required) |")
$copilot = if ($null -eq $privacy.copilot_disabled) { 'not set (enabled)' } else { "TurnOffWindowsCopilot = $($privacy.copilot_disabled)" }
[void]$md.AppendLine("| Copilot | $copilot | F2 tweak planned |")
$widgets = if ($null -eq $privacy.widgets_disabled) { 'default (enabled)' } else { "TaskbarDa = $($privacy.widgets_disabled)" }
[void]$md.AppendLine("| Taskbar widgets | $widgets | F2 tweak planned |")
[void]$md.AppendLine("| OneDrive process | $(if ($privacy.onedrive_running) { 'running' } else { 'not running' }) | F2 tweak (prompts only, not removal) |")
$news = if ($null -eq $privacy.news_interests_disabled) { 'default (enabled)' } else { "AllowNewsAndInterests = $($privacy.news_interests_disabled)" }
[void]$md.AppendLine("| News & Interests | $news | F2 tweak planned |")
[void]$md.AppendLine("")

[void]$md.AppendLine("## Recommended tweaks for profile '$($profile.Dominant)'")
[void]$md.AppendLine("")
if ($recommended.Count -eq 0) {
    [void]$md.AppendLine("No tweaks recommended.")
} else {
    foreach ($t in $recommended) {
        [void]$md.AppendLine("- ``$t``")
    }
    [void]$md.AppendLine("")
    [void]$md.AppendLine("Apply with:")
    [void]$md.AppendLine("")
    [void]$md.AppendLine('```powershell')
    [void]$md.AppendLine(".\scripts\apply-safe.ps1 -Preset $($profile.Dominant.ToLower())")
    [void]$md.AppendLine('```')
}
[void]$md.AppendLine("")

[void]$md.AppendLine("## Notes")
[void]$md.AppendLine("")
[void]$md.AppendLine("- This audit is read-only. No system changes were made.")
[void]$md.AppendLine("- After a Windows Feature Update (annual), some tweaks may be reverted by Microsoft. Re-run audit then.")
if (-not $env.admin) {
    [void]$md.AppendLine("- **Audit ran without admin elevation.** Some checks may be incomplete (eventlog filtering, AppX -AllUsers).")
}
[void]$md.AppendLine("- Audit health checks (eventlog) are inherited from ``melodic-software/claude-code-plugins/windows-diagnostics``. See ``references/audit-inherited.md`` for attribution.")
[void]$md.AppendLine("")

# ---------- Write ----------

$md.ToString() | Out-File -FilePath $reportPath -Encoding UTF8

$auditData = [ordered]@{
    env         = $env
    managed     = $managed
    crashes     = $crashes
    profile     = $profile
    appx        = $appx
    privacy     = $privacy
    recommended = $recommended
}
$auditData | ConvertTo-Json -Depth 10 | Out-File -FilePath $auditJson -Encoding UTF8

if (-not $Quiet) {
    Write-Host ""
    Write-Host "Audit done." -ForegroundColor Green
    Write-Host "Report: $reportPath" -ForegroundColor Cyan
    Write-Host "Data:   $auditJson" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Profile: $($profile.Dominant) (confidence $($profile.Confidence))" -ForegroundColor White
    if ($managed.is_managed) {
        Write-Host "Managed state: $(($managed.signals) -join ', ')" -ForegroundColor Yellow
    } else {
        Write-Host "Managed state: standalone" -ForegroundColor Green
    }
    Write-Host "Crashes (7d): unexpected=$($crashes.unexpected_shutdown), bsod=$($crashes.bsod_whea), hangs=$($crashes.application_hang)"
    Write-Host "AppX: $($appx.count) packages"
    if ($recommended.Count -gt 0) {
        Write-Host "Recommended: $($recommended -join ', ')" -ForegroundColor Cyan
    }
}

if ($Json) {
    $auditData | ConvertTo-Json -Depth 10
}
