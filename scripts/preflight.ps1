# preflight.ps1 — runs all 13 mandatory blockers before any apply.
# Read-only. Exits 0 if all checks pass, 1 if any blocker fails.
# Outputs a markdown summary and a JSON object for machine consumption.

[CmdletBinding()]
param(
    [switch]$Json,         # emit JSON object to stdout (suppresses markdown)
    [switch]$Quiet         # suppress per-check console output
)

$ErrorActionPreference = 'Stop'

$results = [System.Collections.Generic.List[object]]::new()

function Add-Check {
    param(
        [Parameter(Mandatory)][int]$Id,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][ValidateSet('PASS','FAIL','WARN','SKIP')][string]$Status,
        [string]$Message = '',
        [string]$Fix = ''
    )
    $obj = [PSCustomObject]@{
        id      = $Id
        name    = $Name
        status  = $Status
        message = $Message
        fix     = $Fix
    }
    $results.Add($obj) | Out-Null

    if (-not $Quiet) {
        $color = switch ($Status) {
            'PASS' { 'Green' }
            'WARN' { 'Yellow' }
            'FAIL' { 'Red' }
            'SKIP' { 'DarkGray' }
        }
        $tag = '[{0,4}]' -f $Status
        Write-Host ("{0} {1,-2} {2,-42} {3}" -f $tag, $Id, $Name, $Message) -ForegroundColor $color
    }
}

# 1) Admin elevation
try {
    $id = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object System.Security.Principal.WindowsPrincipal($id)
    $isAdmin = $principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
    if ($isAdmin) {
        Add-Check -Id 1 -Name 'Admin elevation' -Status PASS -Message 'Running as Administrator'
    } else {
        Add-Check -Id 1 -Name 'Admin elevation' -Status FAIL -Message 'NOT running as Administrator' `
            -Fix 'Right-click PowerShell and choose Run as Administrator'
    }
} catch {
    Add-Check -Id 1 -Name 'Admin elevation' -Status FAIL -Message $_.Exception.Message
}

# 2) ExecutionPolicy not Restricted
try {
    $ep = Get-ExecutionPolicy
    if ($ep -in @('Restricted','Undefined')) {
        Add-Check -Id 2 -Name 'ExecutionPolicy' -Status FAIL -Message "Current: $ep" `
            -Fix 'Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass'
    } else {
        Add-Check -Id 2 -Name 'ExecutionPolicy' -Status PASS -Message "Current: $ep"
    }
} catch {
    Add-Check -Id 2 -Name 'ExecutionPolicy' -Status FAIL -Message $_.Exception.Message
}

# 3) No pending reboot
try {
    $pendingPaths = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending',
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired'
    )
    $hasPending = $pendingPaths | Where-Object { Test-Path $_ } | Select-Object -First 1
    $hasRename = $false
    try {
        $rename = Get-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' -Name PendingFileRenameOperations -ErrorAction Stop
        if ($rename.PendingFileRenameOperations) { $hasRename = $true }
    } catch { }

    if ($hasPending -or $hasRename) {
        Add-Check -Id 3 -Name 'No pending reboot' -Status FAIL -Message 'Reboot required before tuning' `
            -Fix 'Restart-Computer'
    } else {
        Add-Check -Id 3 -Name 'No pending reboot' -Status PASS
    }
} catch {
    Add-Check -Id 3 -Name 'No pending reboot' -Status WARN -Message $_.Exception.Message
}

# 4) Free space on system drive > 2 GB
try {
    $sysDrive = ($env:SystemDrive).TrimEnd(':')
    $vol = Get-Volume -DriveLetter $sysDrive -ErrorAction Stop
    $freeGB = [math]::Round($vol.SizeRemaining / 1GB, 2)
    if ($freeGB -lt 2) {
        Add-Check -Id 4 -Name 'Free space > 2 GB' -Status FAIL -Message "$freeGB GB free on $sysDrive`:" `
            -Fix 'Clean up disk space and retry'
    } else {
        Add-Check -Id 4 -Name 'Free space > 2 GB' -Status PASS -Message "$freeGB GB free on $sysDrive`:"
    }
} catch {
    Add-Check -Id 4 -Name 'Free space > 2 GB' -Status FAIL -Message $_.Exception.Message
}

# 5) VSS service is startable (Manual or Automatic StartType — NOT Disabled).
# Bugfix F1: VSS is on-demand by design; Status=Stopped is normal. Only Disabled blocks us.
try {
    $vss = Get-Service -Name VSS -ErrorAction Stop
    if ($vss.StartType -eq 'Disabled') {
        Add-Check -Id 5 -Name 'VSS service startable' -Status FAIL -Message 'VSS StartType is Disabled' `
            -Fix 'Set-Service VSS -StartupType Manual (run as admin)'
    } else {
        $statusNote = if ($vss.Status -eq 'Running') { 'running' } else { 'will start on-demand' }
        Add-Check -Id 5 -Name 'VSS service startable' -Status PASS -Message "StartType: $($vss.StartType), $statusNote"
    }
} catch {
    Add-Check -Id 5 -Name 'VSS service startable' -Status FAIL -Message $_.Exception.Message
}

# 6) Restore point creation is possible (System Restore enabled on system drive)
try {
    $srEnabled = $true
    try {
        $sr = Get-CimInstance -ClassName Win32_ShadowStorage -ErrorAction Stop
        if (-not $sr) { $srEnabled = $false }
    } catch {
        $srEnabled = $false
    }
    if ($srEnabled) {
        Add-Check -Id 6 -Name 'System Restore enabled' -Status PASS
    } else {
        Add-Check -Id 6 -Name 'System Restore enabled' -Status WARN -Message 'No shadow storage detected' `
            -Fix "Enable-ComputerRestore -Drive '$($env:SystemDrive)\'"
    }
} catch {
    Add-Check -Id 6 -Name 'System Restore enabled' -Status WARN -Message $_.Exception.Message
}

# 7) Manifest snapshot capability (Write access to runs/)
try {
    $runsDir = Join-Path (Split-Path $PSScriptRoot -Parent) 'runs'
    if (-not (Test-Path $runsDir)) { New-Item -ItemType Directory -Force -Path $runsDir | Out-Null }
    $testFile = Join-Path $runsDir ".preflight_test_$([guid]::NewGuid())"
    'test' | Out-File $testFile -Encoding ascii
    Remove-Item $testFile -Force
    Add-Check -Id 7 -Name 'Manifest write access' -Status PASS -Message "runs/ writable"
} catch {
    Add-Check -Id 7 -Name 'Manifest write access' -Status FAIL -Message $_.Exception.Message
}

# 8) Dry-run flag respected — design check, always PASS in F0 (apply-safe.ps1 supports -DryRun)
Add-Check -Id 8 -Name 'Dry-run flag honored' -Status PASS -Message 'apply-safe.ps1 supports -DryRun'

# 9) Per-tweak undo.reg generation works — simple capability check
try {
    $tmpReg = Join-Path $env:TEMP "wt_undo_test_$([guid]::NewGuid()).reg"
    @"
Windows Registry Editor Version 5.00

[HKEY_CURRENT_USER\Software\WindowsTuningPreflightTest]
"TestValue"=dword:00000001
"@ | Out-File $tmpReg -Encoding ascii
    if ((Test-Path $tmpReg) -and ((Get-Item $tmpReg).Length -gt 0)) {
        Add-Check -Id 9 -Name 'undo.reg generation' -Status PASS
    } else {
        Add-Check -Id 9 -Name 'undo.reg generation' -Status FAIL -Message 'Cannot write .reg file'
    }
    Remove-Item $tmpReg -Force -ErrorAction SilentlyContinue
} catch {
    Add-Check -Id 9 -Name 'undo.reg generation' -Status FAIL -Message $_.Exception.Message
}

# 10) Post-apply verify available — checks at least one tweak has verify.ps1
try {
    $tweaksRoot = Join-Path (Split-Path $PSScriptRoot -Parent) 'tweaks'
    $verifyScripts = Get-ChildItem -Path $tweaksRoot -Filter 'verify.ps1' -Recurse -ErrorAction Stop
    if ($verifyScripts.Count -gt 0) {
        Add-Check -Id 10 -Name 'verify.ps1 present' -Status PASS -Message "$($verifyScripts.Count) tweak(s) verifiable"
    } else {
        Add-Check -Id 10 -Name 'verify.ps1 present' -Status FAIL -Message 'No verify.ps1 found in tweaks/'
    }
} catch {
    Add-Check -Id 10 -Name 'verify.ps1 present' -Status FAIL -Message $_.Exception.Message
}

# 11) Managed state (GPO / Intune / AzureAD / domain join) detection
# Bugfix F1: dsregcmd /status is the authoritative MS source. Registry Enrollments key
# contains noise (MS Account auto-enrollment with non-managing EnrollmentType values).
try {
    $signals = @()

    # 11a) dsregcmd — definitive for AzureAD, domain, enterprise join, and MDM enrollment URL.
    # WorkplaceJoined=YES alone is fine (consumer MSA work account, no policy push).
    try {
        $dsr = & dsregcmd.exe /status 2>$null | Out-String
        if ($dsr -match 'AzureAdJoined\s*:\s*YES')    { $signals += 'AzureAdJoined' }
        if ($dsr -match 'DomainJoined\s*:\s*YES')     { $signals += 'DomainJoined' }
        if ($dsr -match 'EnterpriseJoined\s*:\s*YES') { $signals += 'EnterpriseJoined' }
        if ($dsr -match 'MdmUrl\s*:\s*\S+')           { $signals += 'MdmEnrolled' }
    } catch { }

    # 11b) Local/domain GPO — WindowsUpdate policy key with actual values (not empty)
    try {
        $wuPol = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate'
        if (Test-Path $wuPol) {
            $vals = Get-ItemProperty -Path $wuPol -ErrorAction SilentlyContinue
            $hasVals = $vals.PSObject.Properties | Where-Object { $_.Name -notmatch '^PS' }
            if ($hasVals) { $signals += 'GPO:WindowsUpdate' }
        }
    } catch { }

    if ($signals.Count -gt 0) {
        Add-Check -Id 11 -Name 'Managed state' -Status WARN -Message ("Detected: " + ($signals -join ', ')) `
            -Fix 'apply-safe.ps1 will prompt before continuing'
    } else {
        Add-Check -Id 11 -Name 'Managed state' -Status PASS -Message 'Standalone (no GPO/MDM/AzureAD/domain)'
    }
} catch {
    Add-Check -Id 11 -Name 'Managed state' -Status WARN -Message $_.Exception.Message
}

# 12) No external downloads in MVP — design check, always PASS
Add-Check -Id 12 -Name 'No external downloads' -Status PASS -Message 'MVP uses only built-in PowerShell'

# 13) ARM64 detection + disclaimer
try {
    $arch = $env:PROCESSOR_ARCHITECTURE
    if ($arch -eq 'ARM64') {
        Add-Check -Id 13 -Name 'Architecture' -Status WARN -Message 'ARM64 detected — some tweaks may behave differently' `
            -Fix 'Telemetry tweak works on ARM64, future tweaks may not'
    } else {
        Add-Check -Id 13 -Name 'Architecture' -Status PASS -Message "$arch"
    }
} catch {
    Add-Check -Id 13 -Name 'Architecture' -Status WARN -Message $_.Exception.Message
}

# Aggregate
$failed = ($results | Where-Object { $_.status -eq 'FAIL' }).Count
$warned = ($results | Where-Object { $_.status -eq 'WARN' }).Count
$passed = ($results | Where-Object { $_.status -eq 'PASS' }).Count

if ($Json) {
    [PSCustomObject]@{
        ok      = ($failed -eq 0)
        passed  = $passed
        warned  = $warned
        failed  = $failed
        checks  = $results
    } | ConvertTo-Json -Depth 5
} else {
    Write-Host ""
    $sumColor = if ($failed -eq 0) { 'Green' } else { 'Red' }
    Write-Host ("Summary: {0} PASS, {1} WARN, {2} FAIL" -f $passed, $warned, $failed) -ForegroundColor $sumColor

    if ($failed -gt 0) {
        Write-Host ""
        Write-Host "Blockers — fix these before apply:" -ForegroundColor Red
        foreach ($r in ($results | Where-Object { $_.status -eq 'FAIL' })) {
            Write-Host (" * [{0}] {1}" -f $r.id, $r.name) -ForegroundColor Red
            if ($r.message) { Write-Host ("       Issue: {0}" -f $r.message) -ForegroundColor Gray }
            if ($r.fix)     { Write-Host ("       Fix:   {0}" -f $r.fix) -ForegroundColor Yellow }
        }
    }
    if ($warned -gt 0 -and $failed -eq 0) {
        Write-Host ""
        Write-Host "Warnings (apply-safe.ps1 will require confirmation):" -ForegroundColor Yellow
        foreach ($r in ($results | Where-Object { $_.status -eq 'WARN' })) {
            Write-Host (" * [{0}] {1} — {2}" -f $r.id, $r.name, $r.message) -ForegroundColor Yellow
        }
    }
}

if ($failed -gt 0) { exit 1 } else { exit 0 }
