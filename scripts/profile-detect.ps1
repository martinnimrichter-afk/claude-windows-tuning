# profile-detect.ps1 — dot-source helper. Exports Get-WinTuningProfile.
#
# Returns:
#   @{
#       Dominant   = 'Office' | 'Gamer' | 'DevWSL' | 'Creator'
#       Confidence = 0..100
#       Scores     = @{ Gamer = N; DevWSL = N; Office = N; Creator = N }
#       Evidence   = @{ Gamer = [strings]; DevWSL = [strings]; ... }
#   }
#
# Dominant selection rule:
#   - If best non-Office profile has score >= 70 → use it
#   - Otherwise → Office (default)
#
# Algorithm is intentionally conservative: it errs toward Office (safe default).

function Get-WinTuningProfile {
    [CmdletBinding()]
    param()

    $scores   = @{ Gamer = 0; DevWSL = 0; Office = 50; Creator = 0 }
    $evidence = @{ Gamer = @(); DevWSL = @(); Office = @('Default fallback baseline (+50)'); Creator = @() }

    # ---------- DevWSL ----------
    $wslExe = Test-Path "$env:SystemRoot\System32\wsl.exe"
    if ($wslExe) {
        $scores.DevWSL += 30
        $evidence.DevWSL += "wsl.exe in System32 (+30)"
    }
    $wslConfig = Test-Path (Join-Path $env:USERPROFILE '.wslconfig')
    if ($wslConfig) {
        $scores.DevWSL += 20
        $evidence.DevWSL += ".wslconfig in user profile (+20)"
    }
    # Docker Desktop registry
    $dockerKeys = @(
        'HKLM:\SOFTWARE\Docker Inc.\Docker Desktop',
        'HKLM:\SOFTWARE\WOW6432Node\Docker Inc.\Docker Desktop'
    )
    if ($dockerKeys | Where-Object { Test-Path $_ } | Select-Object -First 1) {
        $scores.DevWSL += 20
        $evidence.DevWSL += "Docker Desktop installed (+20)"
    }
    # Hyper-V VMMS service
    $vmms = Get-Service -Name vmms -ErrorAction SilentlyContinue
    if ($vmms -and $vmms.StartType -ne 'Disabled') {
        $scores.DevWSL += 20
        $evidence.DevWSL += "Hyper-V VMMS service present (+20)"
    }
    # Git for Windows — dev signal
    if (Test-Path 'C:\Program Files\Git') {
        $scores.DevWSL += 10
        $evidence.DevWSL += "Git for Windows in Program Files (+10)"
    }

    # ---------- Gamer ----------
    # Microsoft Gaming App AppX (cheap check via registry)
    $gamingApp = Get-ChildItem 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModel\PackageRepository\Packages' -ErrorAction SilentlyContinue |
                 Where-Object { $_.PSChildName -match '^Microsoft\.GamingApp_' } |
                 Select-Object -First 1
    if ($gamingApp) {
        $scores.Gamer += 30
        $evidence.Gamer += "Microsoft.GamingApp installed (+30)"
    }
    # Steam
    $steamPaths = @('C:\Program Files (x86)\Steam', 'C:\Program Files\Steam', "$env:LOCALAPPDATA\Steam")
    if ($steamPaths | Where-Object { Test-Path $_ } | Select-Object -First 1) {
        $scores.Gamer += 25
        $evidence.Gamer += "Steam installed (+25)"
    }
    # Epic Games
    $epicPaths = @('C:\Program Files (x86)\Epic Games', 'C:\Program Files\Epic Games')
    if ($epicPaths | Where-Object { Test-Path $_ } | Select-Object -First 1) {
        $scores.Gamer += 20
        $evidence.Gamer += "Epic Games installed (+20)"
    }
    # Battle.net
    $bnetPaths = @('C:\Program Files (x86)\Battle.net', 'C:\Program Files\Battle.net')
    if ($bnetPaths | Where-Object { Test-Path $_ } | Select-Object -First 1) {
        $scores.Gamer += 20
        $evidence.Gamer += "Battle.net installed (+20)"
    }
    # Xbox / GamePass services running
    $xblServices = @('XblAuthManager', 'XblGameSave', 'XboxGipSvc')
    $xblPresent = $xblServices | ForEach-Object { Get-Service -Name $_ -ErrorAction SilentlyContinue } |
                  Where-Object { $_ -and $_.StartType -ne 'Disabled' }
    if ($xblPresent) {
        $scores.Gamer += 15
        $evidence.Gamer += "Xbox/GamePass services active (+15)"
    }

    # ---------- Creator ----------
    # Adobe (multiple possible paths)
    $adobePaths = @('C:\Program Files\Adobe', 'C:\Program Files (x86)\Adobe',
                    'C:\Program Files\Common Files\Adobe', "$env:ProgramData\Adobe")
    if ($adobePaths | Where-Object { Test-Path $_ } | Select-Object -First 1) {
        $scores.Creator += 40
        $evidence.Creator += "Adobe products in Program Files (+40)"
    }
    # Affinity
    $affinityPaths = @('C:\Program Files\Affinity', 'C:\Program Files (x86)\Affinity')
    if ($affinityPaths | Where-Object { Test-Path $_ } | Select-Object -First 1) {
        $scores.Creator += 30
        $evidence.Creator += "Affinity suite installed (+30)"
    }
    # DaVinci Resolve / Blackmagic
    $bmdPaths = @('C:\Program Files\Blackmagic Design', 'C:\Program Files (x86)\Blackmagic Design')
    if ($bmdPaths | Where-Object { Test-Path $_ } | Select-Object -First 1) {
        $scores.Creator += 25
        $evidence.Creator += "Blackmagic Design (DaVinci Resolve) installed (+25)"
    }
    # Substance
    $substancePaths = @('C:\Program Files\Allegorithmic', 'C:\Program Files\Adobe\Adobe Substance 3D Painter')
    if ($substancePaths | Where-Object { Test-Path $_ } | Select-Object -First 1) {
        $scores.Creator += 10
        $evidence.Creator += "Substance 3D installed (+10)"
    }

    # ---------- Office ----------
    # Microsoft Office (Click-to-Run or MSI)
    $officeKeys = @(
        'HKLM:\SOFTWARE\Microsoft\Office\ClickToRun\Configuration',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Office',
        'HKLM:\SOFTWARE\Microsoft\Office'
    )
    if ($officeKeys | Where-Object { Test-Path $_ } | Select-Object -First 1) {
        $scores.Office += 30
        $evidence.Office += "Microsoft Office installed (+30)"
    }
    # Teams (machine-wide or per-user)
    $teamsPaths = @("$env:LOCALAPPDATA\Microsoft\Teams",
                    'C:\Program Files\Microsoft\Teams',
                    'C:\Program Files (x86)\Microsoft\Teams',
                    "$env:LOCALAPPDATA\Microsoft\WindowsApps\ms-teams.exe")
    if ($teamsPaths | Where-Object { Test-Path $_ } | Select-Object -First 1) {
        $scores.Office += 15
        $evidence.Office += "Microsoft Teams installed (+15)"
    }

    # ---------- Cap scores at 100 ----------
    foreach ($k in @($scores.Keys)) {
        if ($scores[$k] -gt 100) { $scores[$k] = 100 }
    }

    # ---------- Pick dominant ----------
    # Exclude Office from competition, find best of (Gamer, DevWSL, Creator)
    $contenders   = @('Gamer','DevWSL','Creator')
    $bestNonOffice = $contenders | Sort-Object { $scores[$_] } -Descending | Select-Object -First 1
    $bestScore    = $scores[$bestNonOffice]

    if ($bestScore -ge 70) {
        $dominant   = $bestNonOffice
        $confidence = $bestScore
    } else {
        $dominant   = 'Office'
        $confidence = $scores.Office
    }

    return @{
        Dominant   = $dominant
        Confidence = $confidence
        Scores     = $scores
        Evidence   = $evidence
    }
}
