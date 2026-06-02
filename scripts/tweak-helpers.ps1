# tweak-helpers.ps1 — dot-source. Exports Invoke-TweakDetect/Apply/Verify.
#
# All F2+ tweaks call these helpers with their constants. Single-value tweaks pass
# a one-entry hashtable. Multi-value tweaks (e.g. ui-start-suggestions-off) pass
# multiple entries — they share one RegistryPath but write multiple values.

function Invoke-TweakDetect {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$TweakId,
        [Parameter(Mandatory)][string]$RegistryPath,
        [Parameter(Mandatory)][hashtable]$Targets   # value-name -> target-int
    )

    $current   = @{}
    $allMatch  = $true
    $keyExists = Test-Path $RegistryPath

    foreach ($name in $Targets.Keys) {
        $val = $null
        if ($keyExists) {
            try {
                $val = (Get-ItemProperty -Path $RegistryPath -Name $name -ErrorAction Stop).$name
            } catch { $val = $null }
        }
        $current[$name] = $val
        if ($null -eq $val -or [int]$val -ne [int]$Targets[$name]) {
            $allMatch = $false
        }
    }

    $reason = if ($allMatch) {
        "All $($Targets.Count) value(s) already match target"
    } elseif (-not $keyExists) {
        "Key does not exist; apply will create it and set $($Targets.Count) value(s)"
    } else {
        "Apply will set $($Targets.Count) value(s) under existing key"
    }

    [PSCustomObject]@{
        TweakId        = $TweakId
        RegistryPath   = $RegistryPath
        Values         = $Targets
        Current        = $current
        KeyExists      = $keyExists
        Applicable     = $true
        AlreadyApplied = $allMatch
        Reason         = $reason
    }
}

function Invoke-TweakApply {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$TweakId,
        [Parameter(Mandatory)][string]$RegistryPath,
        [Parameter(Mandatory)][hashtable]$Targets,
        [Parameter(Mandatory)][string]$RollbackDir
    )

    $ErrorActionPreference = 'Stop'

    # Convert PS hive prefix to .reg-importable hive name
    $regHive = $RegistryPath `
        -replace '^HKLM:\\', 'HKEY_LOCAL_MACHINE\' `
        -replace '^HKCU:\\', 'HKEY_CURRENT_USER\' `
        -replace '^HKCR:\\', 'HKEY_CLASSES_ROOT\' `
        -replace '^HKU:\\',  'HKEY_USERS\'

    # Capture before
    $before     = @{}
    $keyExisted = Test-Path $RegistryPath
    foreach ($name in $Targets.Keys) {
        $val = $null
        if ($keyExisted) {
            try {
                $val = (Get-ItemProperty -Path $RegistryPath -Name $name -ErrorAction Stop).$name
            } catch { $val = $null }
        }
        $before[$name] = $val
    }

    # Build undo.reg
    if (-not (Test-Path $RollbackDir)) {
        New-Item -ItemType Directory -Force -Path $RollbackDir | Out-Null
    }
    $undoFile = Join-Path $RollbackDir "$TweakId.reg"

    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine('Windows Registry Editor Version 5.00')
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine("[$regHive]")
    foreach ($name in $Targets.Keys) {
        $b = $before[$name]
        if ($null -ne $b) {
            $hex = '{0:x8}' -f [int]$b
            [void]$sb.AppendLine("`"$name`"=dword:$hex")
        } else {
            [void]$sb.AppendLine("`"$name`"=-")
        }
    }
    $sb.ToString() | Out-File $undoFile -Encoding unicode

    # Apply
    if (-not $keyExisted) {
        New-Item -Path $RegistryPath -Force | Out-Null
    }
    foreach ($name in $Targets.Keys) {
        New-ItemProperty -Path $RegistryPath -Name $name -Value $Targets[$name] -PropertyType DWord -Force | Out-Null
    }

    # Re-read for after
    $after = @{}
    foreach ($name in $Targets.Keys) {
        try {
            $after[$name] = (Get-ItemProperty -Path $RegistryPath -Name $name -ErrorAction Stop).$name
        } catch {
            $after[$name] = $null
        }
    }

    [PSCustomObject]@{
        TweakId     = $TweakId
        Before      = $before
        After       = $after
        UndoRegPath = $undoFile
        KeyCreated  = (-not $keyExisted)
    }
}

function Invoke-TweakVerify {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$TweakId,
        [Parameter(Mandatory)][string]$RegistryPath,
        [Parameter(Mandatory)][hashtable]$Targets
    )

    $actual = @{}
    $allOk  = $true
    $first_fail = $null

    foreach ($name in $Targets.Keys) {
        try {
            $v = (Get-ItemProperty -Path $RegistryPath -Name $name -ErrorAction Stop).$name
            $actual[$name] = $v
            if ([int]$v -ne [int]$Targets[$name]) {
                $allOk = $false
                if (-not $first_fail) { $first_fail = "$name = $v (expected $($Targets[$name]))" }
            }
        } catch {
            $actual[$name] = $null
            $allOk = $false
            if (-not $first_fail) { $first_fail = "$name not found" }
        }
    }

    [PSCustomObject]@{
        Ok      = $allOk
        Current = $actual
        Target  = $Targets
        Reason  = if ($allOk) { "All $($Targets.Count) value(s) match" } else { $first_fail }
    }
}
