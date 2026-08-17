<#
.SYNOPSIS
    Bind every control on a Thrustmaster T.Flight Hotas 4 in Arma Reforger.

.DESCRIPTION
    Writes the joystick config Arma Reforger reads, working from the hardware
    rather than from the game's action list. The difference matters: walking the
    action list lets you finish with a trigger that does nothing, which is
    exactly what Reforger's own generated preset does. This walks the twelve
    buttons, the hat and the four live axes, and refuses to write a file that
    leaves any of them without a job.

.PARAMETER Identify
    Learn this unit: press each control when asked, and the tool records which
    winmm index it is and which way its axes travel. Do this once.

.PARAMETER Apply
    Generate and install the config.

.PARAMETER Show
    Print the physical layout and what each control currently does.

.PARAMETER Verify
    Audit coverage and the installed file. Exit code 1 if anything is unbound.

.PARAMETER Watch
    Live reader: move a control, see the token Reforger would use.

.PARAMETER CheckLog
    Read Reforger's newest log and report whether the engine took the bindings.

.PARAMETER Restore
    Put Reforger's own stock preset back.

.PARAMETER SelfTest
    Run the test suite. No hardware needed, nothing written.

.PARAMETER ProfileName
    Which binding profile to apply: helicopter (default), full, conservative.

.EXAMPLE
    .\Hotas4.ps1 -Identify
    .\Hotas4.ps1 -Apply -ProfileName helicopter
#>

[CmdletBinding(PositionalBinding = $false)]
param(
    [switch] $Identify,
    [switch] $Apply,
    [switch] $Show,
    [switch] $Verify,
    [switch] $Watch,
    [switch] $KeyTest,
    [switch] $CheckLog,
    [switch] $Restore,
    [switch] $SelfTest,

    [ValidateSet('helicopter', 'full', 'conservative')]
    [string] $ProfileName = 'helicopter',

    [string] $ConfigName,
    [switch] $DryRun,
    [switch] $Replace,
    [switch] $Force
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$script:Root = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $script:Root 'lib\Common.ps1')
. (Join-Path $script:Root 'lib\Ui.ps1')
. (Join-Path $script:Root 'lib\Device.ps1')
. (Join-Path $script:Root 'lib\Layout.ps1')
. (Join-Path $script:Root 'lib\Reforger.ps1')

$script:DeviceMapPath = Join-Path $script:Root 'device-map.json'
$script:BackupDir     = Join-Path $script:Root 'backups'
$script:StockPath     = Join-Path $script:Root 'reference\stock-preset.conf'

# =============================================================================
# Paths and preflight
# =============================================================================

function Get-ReforgerRoot {
    return (Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'My Games\ArmaReforger')
}

function Get-InputConfigDir {
    return (Join-Path (Get-ReforgerRoot) 'profile\.save\settings\customInputConfigs')
}

function Get-ConfigFileName {
    <#
        Reforger names the file after the device. If it has already written one,
        that name is authoritative and we use it verbatim; otherwise build the
        name the same way it does -- device name with the punctuation stripped.
    #>
    param($Stick)
    if ($ConfigName) { return $ConfigName }

    $dir = Get-InputConfigDir
    if (Test-Path $dir) {
        $existing = @(Get-ChildItem -Path $dir -Filter 'Joystick_*.conf' -ErrorAction SilentlyContinue)
        if ($existing.Count -eq 1) { return $existing[0].Name }
        if ($existing.Count -gt 1 -and $Stick) {
            $want = ($Stick.Name -replace '[^A-Za-z0-9]', '')
            foreach ($f in $existing) { if ($f.Name -replace '[^A-Za-z0-9]', '' -like "*$want*") { return $f.Name } }
        }
        if ($existing.Count -gt 1) { return $existing[0].Name }
    }
    # winmm often reports the generic driver name rather than the product's, so
    # a known VID/PID wins over whatever string the driver handed back.
    if ($Stick -and $Stick.Vid -eq 0x044F -and ($Stick.Pid -eq 0xB67C -or $Stick.Pid -eq 0xB67B)) {
        return 'Joystick_TFlightHotas4_0.conf'
    }
    if ($Stick) { return ('Joystick_' + ($Stick.Name -replace '[^A-Za-z0-9]', '') + '_0.conf') }
    return 'Joystick_TFlightHotas4_0.conf'
}

function Test-GameRunning {
    return @(Get-Process -Name 'ArmaReforgerSteam', 'ArmaReforger_BE' -ErrorAction SilentlyContinue).Count -gt 0
}

function Assert-GameClosed {
    <#
        Reforger rewrites this file when it exits. Anything saved while it is
        running is thrown away, silently, and looks exactly like the tool having
        not worked.
    #>
    if (-not (Test-GameRunning)) { return $true }
    Write-Warn 'Arma Reforger is running.'
    Write-Note 'It rewrites the input config when it closes, so anything written now is lost.'
    if ($Force) { Write-Warn 'Continuing anyway (-Force).'; return $true }
    return (Confirm-Action 'Continue regardless?')
}

function Resolve-Stick {
    <# The device to work with, with anything worrying about it printed. #>
    $sticks = Get-Joystick
    if ($sticks.Count -eq 0) {
        Write-Bad 'No joystick found.'
        Write-Note 'Plug the Hotas in, set the switch on the base to PC, and try again.'
        return $null
    }
    $stick = Select-Hotas $sticks
    Write-Field 'device' "$($stick.Name)" 'White'
    Write-Field 'usb id' ('VID 0x{0:X4}  PID 0x{1:X4}' -f $stick.Vid, $stick.Pid)
    Write-Field 'reports' "$($stick.AxisCount) axes, $($stick.ButtonCount) buttons, hat: $($stick.HasHat)"
    foreach ($w in (Get-DeviceWarning $stick)) { Write-Warn $w }
    return $stick
}

function Get-Map {
    param([switch] $Quiet)
    $map = Import-DeviceMap $script:DeviceMapPath
    if (-not $map -and -not $Quiet) {
        Write-Bad 'This unit has not been identified yet.'
        Write-Note 'Run:  .\Hotas4.ps1 -Identify'
        Write-Note 'It takes about a minute and only has to be done once.'
    }
    return $map
}

# =============================================================================
# Identify
# =============================================================================

function Invoke-Identify {
    Write-Title 'IDENTIFY' 'teach the tool what is on your stick, and where'

    $stick = Resolve-Stick
    if (-not $stick) { return 1 }

    $map = Import-DeviceMap $script:DeviceMapPath
    if (-not $map) { $map = New-DeviceMap }
    $map.Device = $stick.Name
    $map.Vid = $stick.Vid
    $map.Pid = $stick.Pid

    Write-Host ''
    Write-Note 'Each step names a control and asks you to move it. Keep your other'
    Write-Note 'hand clear -- whatever moves furthest is what gets recorded.'
    Write-Note 'At any prompt:  [s] this unit has not got one   [b] back   [q] stop'

    $drift = Get-RestingDrift -Id $stick.Id
    if ($drift) {
        $worst = ($drift | Measure-Object -Maximum).Maximum
        if ($worst -gt 0.05) {
            Write-Host ''
            Write-Warn ("Resting drift of {0:N2} on at least one axis." -f $worst)
            Write-Note 'Reforger has no deadzone setting. Fix this in the Thrustmaster'
            Write-Note 'control panel (joy.cpl -> Properties) or the aircraft will wander.'
        }
    }

    if (-not (Invoke-IdentifyAxes -Stick $stick -Map $map)) { return 1 }
    Invoke-IdentifyHat     -Stick $stick -Map $map
    Invoke-IdentifyButtons -Stick $stick -Map $map

    $map.Verified = $true
    Show-DeviceMap -Map $map -Stick $stick

    Write-Host ''
    if (-not (Confirm-Action 'Save this layout?')) { Write-Note 'Discarded, nothing written.'; return 0 }

    Export-DeviceMap -Map $map -Path $script:DeviceMapPath
    Write-Good "saved -> $(Split-Path -Leaf $script:DeviceMapPath)"
    Write-Host ''
    Write-Note 'Next:  .\Hotas4.ps1 -Apply'
    return 0
}

function Invoke-IdentifyAxes {
    param($Stick, $Map)
    $axes = Get-ControlsByKind 'Axis'
    $i = 0
    while ($i -lt $axes.Count) {
        $c = $axes[$i]
        Write-Section ("AXIS {0} of {1}   {2}" -f ($i + 1), $axes.Count, $c.Label)
        Write-Strong $c.Probe
        if ($c.ContainsKey('Note')) { Write-Note "($($c.Note))" }
        if (Get-Opt $c 'Optional' $false) { Write-Note 'Optional -- press [s] if this does not apply.' }
        Write-Host ''
        Write-Keys 'keys are live:   [s] this unit has not got one   [b] back   [q] stop'
        Write-Note 'hold it there until it reads...'

        $r = Wait-Control -Id $Stick.Id -Accept 'Any'

        if ($r.Kind -eq 'Gone')    { Write-Bad 'The stick stopped responding.'; return $false }
        if ($r.Kind -eq 'Timeout') { Write-Warn 'Nothing read. Skipping.'; $i++; continue }
        if ($r.Kind -eq 'Key') {
            if ($r.Key -eq 'q') { return $true }
            if ($r.Key -eq 'b') { if ($i -gt 0) { $i-- }; continue }
            if ($r.Key -eq 's') { $Map.Axes.Remove($c.Id); $i++; continue }
            continue
        }

        if ($r.Kind -eq 'Button') {
            if (Get-Opt $c 'Optional' $false) {
                # Not a failure, and the reason the rocker is marked optional.
                # This is how the tool learns that a control some units expose
                # as an analogue axis is a pair of buttons on this one.
                Write-Warn "That came through as button$($r.Index), not an axis."
                Write-Note 'So this unit has it as buttons. The button pass will pick it up.'
                $Map.Axes.Remove($c.Id)
                $i++
                continue
            }
            # A stray press during a real axis probe. Retrying costs nothing;
            # skipping the axis would lose it silently.
            Write-Warn "That was button$($r.Index), not an axis. Try again."
            continue
        }
        if ($r.Kind -eq 'Hat') { Write-Warn 'That was the hat switch. Try again.'; continue }

        $clash = $null
        foreach ($k in $Map.Axes.Keys) {
            if ($k -ne $c.Id -and $Map.Axes[$k].Index -eq $r.Index) { $clash = $k }
        }

        Write-Good ("read as axis$($r.Index), moving $($r.Sign) (Reforger token: joystick0:axis$($r.Index)$($r.Sign))")
        if ($clash) {
            Write-Warn "axis$($r.Index) is already recorded as $(Get-ControlLabel $clash)."
            Write-Note 'On a Hotas 4 the twist grip and the rudder rocker really do share one'
            Write-Note 'axis -- that is the dual rudder, and keeping both here is correct.'
        }

        $k = Read-Choice -Prompt '[Enter] that is right   [r] try again   [s] skip   [q] stop' `
                         -Keys @("`r", 'r', 's', 'q')
        if ($k -eq 'q') { return $true }
        if ($k -eq 'r') { continue }
        if ($k -eq 's') { $Map.Axes.Remove($c.Id); $i++; continue }

        $Map.Axes[$c.Id] = @{ Index = $r.Index; Sign = $r.Sign }
        $i++
    }
    return $true
}

function Invoke-IdentifyHat {
    param($Stick, $Map)
    if (-not $Stick.HasHat) { $Map.Hat = $false; return }
    Write-Section 'HAT SWITCH'
    Write-Strong 'Push the HAT on top of the stick head in any direction.'
    Write-Host ''
    Write-Keys 'keys are live:   [s] no hat   [q] stop'
    $r = Wait-Control -Id $Stick.Id -Accept 'Digital'
    if ($r.Kind -eq 'Hat') {
        Write-Good ("read as the hat, direction: " + ($r.Directions -join ' + '))
        $Map.Hat = $true
    } elseif ($r.Kind -eq 'Button') {
        Write-Warn "That came through as button$($r.Index), not a hat. Leaving the hat unset."
        $Map.Hat = $false
    } else {
        Write-Warn 'No hat reading. Leaving it unset.'
        $Map.Hat = $false
    }
}

function Invoke-IdentifyButtons {
    param($Stick, $Map)
    $buttons = Get-ControlsByKind 'Button'
    $i = 0
    while ($i -lt $buttons.Count) {
        $c = $buttons[$i]
        $remaining = (Get-UnmappedButtonIndex -Map $Map -ButtonCount $Stick.ButtonCount).Count
        Write-Section ("BUTTON {0} of {1}   {2}      ({3} still unaccounted for)" -f `
                       ($i + 1), $buttons.Count, $c.Label, $remaining)
        Write-Strong "Press: $($c.Label)"
        Write-Note $c.Where
        if ($c.ContainsKey('Ps4')) { Write-Note "(the $($c.Ps4) button, if you know the PlayStation layout)" }
        Write-Host ''
        Write-Keys 'keys are live:   [s] this unit has not got one   [b] back   [q] stop'

        $r = Wait-Control -Id $Stick.Id -Accept 'Digital'

        if ($r.Kind -eq 'Gone')    { Write-Bad 'The stick stopped responding.'; return }
        if ($r.Kind -eq 'Timeout') { Write-Warn 'Nothing read. Skipping.'; $i++; continue }
        if ($r.Kind -eq 'Key') {
            if ($r.Key -eq 'q') { return }
            if ($r.Key -eq 'b') { if ($i -gt 0) { $i-- }; continue }
            if ($r.Key -eq 's') {
                foreach ($k in @($Map.Buttons.Keys)) { if ($Map.Buttons[$k] -eq $c.Id) { $Map.Buttons.Remove($k) } }
                $i++
                continue
            }
            continue
        }
        if ($r.Kind -ne 'Button') { Write-Warn 'That was not a button. Try again.'; continue }

        $existing = $null
        if ($Map.Buttons.ContainsKey("$($r.Index)")) { $existing = $Map.Buttons["$($r.Index)"] }
        Write-Good "read as button$($r.Index)"
        if ($existing -and $existing -ne $c.Id) {
            Write-Warn "button$($r.Index) is already recorded as $(Get-ControlLabel $existing)."
            Write-Note 'Confirming will move it to this one.'
        }

        $k = Read-Choice -Prompt '[Enter] that is right   [r] try again   [s] no such button   [q] stop' `
                         -Keys @("`r", 'r', 's', 'q')
        if ($k -eq 'q') { return }
        if ($k -eq 'r') { continue }
        if ($k -eq 's') { $i++; continue }

        Set-MappedButton -Map $Map -Index $r.Index -ControlId $c.Id
        $i++
    }

    Invoke-IdentifyStragglers -Stick $Stick -Map $Map
}

function Invoke-IdentifyStragglers {
    <#
        Whatever the catalogue did not account for. A unit with a control this
        tool has never heard of still gets it named and bound, which is the
        whole promise -- so this asks for a free-form label rather than giving
        up and leaving a hole.
    #>
    param($Stick, $Map)
    $left = Get-UnmappedButtonIndex -Map $Map -ButtonCount $Stick.ButtonCount
    if ($left.Count -eq 0) { return }

    Write-Section "$($left.Count) BUTTON(S) NOT YET ACCOUNTED FOR"
    Write-Note ('winmm reports these and nothing has claimed them: ' + (($left | ForEach-Object { "button$_" }) -join ', '))
    Write-Note 'Press each one and give it a name, or press [q] to leave them unnamed.'

    while ($true) {
        $left = Get-UnmappedButtonIndex -Map $Map -ButtonCount $Stick.ButtonCount
        if ($left.Count -eq 0) { Write-Good 'Every button is now accounted for.'; return }

        Write-Host ''
        Write-Strong ("Press any unnamed button  ({0} left)" -f $left.Count)
        $r = Wait-Control -Id $Stick.Id -Accept 'Button'
        if ($r.Kind -eq 'Key' -and $r.Key -eq 'q') { return }
        if ($r.Kind -ne 'Button') { return }

        if ($Map.Buttons.ContainsKey("$($r.Index)")) {
            Write-Note "button$($r.Index) is already $(Get-ControlLabel $Map.Buttons["$($r.Index)"]). Try another."
            continue
        }

        Write-Good "button$($r.Index)"
        $name = Read-Host '    what is that control called?'
        if ([string]::IsNullOrWhiteSpace($name)) { continue }
        $Map.Buttons["$($r.Index)"] = "custom:$($name.Trim())"
        Write-Note "recorded as '$($name.Trim())'"
    }
}

function Show-DeviceMap {
    param($Map, $Stick)
    Write-Title 'YOUR LAYOUT'
    foreach ($zone in @('Stick', 'Throttle', 'Base')) {
        $any = $false
        foreach ($c in $script:ControlCatalogue) {
            if ($c.Zone -ne $zone) { continue }
            $token = $null
            if ($c.Kind -eq 'Button') {
                $idx = Get-MappedButtonIndex -Map $Map -ControlId $c.Id
                if ($null -ne $idx) { $token = "button$idx" }
            } elseif ($c.Kind -eq 'Hat') {
                if ($Map.Hat) { $token = 'pov_up/down/left/right' }
            } elseif ($Map.Axes.ContainsKey($c.Id)) {
                $token = "axis$($Map.Axes[$c.Id].Index) ($($Map.Axes[$c.Id].Sign) is the way you moved it)"
            }
            if (-not $token) { continue }
            if (-not $any) { Write-Section $zone.ToUpper(); $any = $true }
            Write-Field $c.Label $token
        }
    }
    $left = Get-UnmappedButtonIndex -Map $Map -ButtonCount $Stick.ButtonCount
    if ($left.Count -gt 0) {
        Write-Host ''
        Write-Warn ('unnamed: ' + (($left | ForEach-Object { "button$_" }) -join ', '))
    }
    foreach ($k in $Map.Buttons.Keys) {
        if ($Map.Buttons[$k] -like 'custom:*') { Write-Field ($Map.Buttons[$k].Substring(7)) "button$k" 'Cyan' }
    }
}

# =============================================================================
# Coverage reporting -- shared by -Show, -Verify and -Apply
# =============================================================================

function Show-Coverage {
    param($Rows, $Profile)
    $colours = @{ Bound = 'Gray'; Free = 'DarkGray'; Unassigned = 'Yellow'; Unnamed = 'Red' }

    foreach ($zone in @('Stick', 'Throttle', 'Base', 'Unknown', 'Other')) {
        $inZone = @($Rows | Where-Object { $_.Zone -eq $zone })
        if ($inZone.Count -eq 0) { continue }
        Write-Section $zone.ToUpper()
        foreach ($r in $inZone) {
            $what = Get-JobLabel $r.JobId
            if ($r.Status -eq 'Unassigned') { $what = 'NOTHING -- no job assigned' }
            if ($r.Status -eq 'Unnamed')    { $what = 'NOT IDENTIFIED -- run -Identify' }
            $tier = ''
            $job = Get-Job $r.JobId
            if ($job -and $job.Tier -eq 'B') { $tier = '  [unconfirmed]' }
            Write-Host ('    ' + $r.Token.PadRight(10)) -NoNewline -ForegroundColor DarkGray
            Write-Host ($r.Label.PadRight(28)) -NoNewline -ForegroundColor DarkCyan
            Write-Host ($what + $tier) -ForegroundColor $colours[$r.Status]
        }
    }

    $bound = @($Rows | Where-Object { $_.Status -eq 'Bound' }).Count
    $free  = @($Rows | Where-Object { $_.Status -eq 'Free' }).Count
    $holes = @($Rows | Where-Object { $_.Status -eq 'Unassigned' -or $_.Status -eq 'Unnamed' })

    Write-Host ''
    Write-Rule
    if ($holes.Count -eq 0) {
        Write-Good ("COMPLETE -- {0} of {0} controls have a job ({1} deliberately free)." -f ($bound + $free), $free)
    } else {
        Write-Bad ("INCOMPLETE -- {0} control(s) do nothing:" -f $holes.Count)
        foreach ($h in $holes) { Write-Bad ("  $($h.Token)  $($h.Label)  [$($h.Status)]") }
    }
    return ($holes.Count -eq 0)
}

function Get-CoverageForCurrent {
    param($Stick, $Map, $Profile)
    return (Get-Coverage -Map $Map -Profile $Profile -ButtonCount $Stick.ButtonCount -HasHat $Stick.HasHat)
}

# =============================================================================
# Show / Verify
# =============================================================================

function Invoke-Show {
    Write-Title 'LAYOUT AND BINDINGS' "profile: $ProfileName"
    $stick = Resolve-Stick
    if (-not $stick) { return 1 }
    $map = Get-Map
    if (-not $map) { return 1 }

    $profile = Get-Profile $ProfileName
    Write-Host ''
    Write-Field 'profile' $profile.Label 'White'
    Write-Note $profile.Desc

    $rows = Get-CoverageForCurrent -Stick $stick -Map $map -Profile $profile
    [void](Show-Coverage -Rows $rows -Profile $profile)

    $installed = Join-Path (Get-InputConfigDir) (Get-ConfigFileName $stick)
    Write-Host ''
    Write-Section 'INSTALLED FILE'
    if (Test-Path $installed) {
        $parsed = Read-Config $installed
        Write-Field 'path' $installed
        Write-Field 'actions in file' "$($parsed.Actions.Count)"
        $unknown = Get-UnknownActionBlock $parsed
        if ($unknown.Count -gt 0) { Write-Note "$($unknown.Count) action(s) this tool does not manage; they will be preserved." }
    } else {
        Write-Warn "No config installed yet at $installed"
    }
    return 0
}

function Invoke-Verify {
    Write-Title 'VERIFY'
    $stick = Resolve-Stick
    if (-not $stick) { return 1 }
    $map = Get-Map
    if (-not $map) { return 1 }

    $profile = Get-Profile $ProfileName
    $rows = Get-CoverageForCurrent -Stick $stick -Map $map -Profile $profile
    $ok = Show-Coverage -Rows $rows -Profile $profile

    $tierB = Get-TierBActions (Resolve-Bindings -Map $map -Profile $profile)
    if ($tierB.Count -gt 0) {
        Write-Host ''
        Write-Section 'UNCONFIRMED ACTIONS THIS WOULD WRITE'
        Write-Note 'Extracted from the game binary but not yet watched being accepted.'
        Write-Note 'Launch Reforger once, then run -CheckLog to confirm.'
        foreach ($a in $tierB) { Write-Field '' $a 'Yellow' }
    }

    $installed = Join-Path (Get-InputConfigDir) (Get-ConfigFileName $stick)
    if (Test-Path $installed) {
        Write-Host ''
        Write-Section 'INSTALLED FILE'
        $problems = Test-Config (Get-Content -Raw $installed)
        if ($problems.Count -eq 0) { Write-Good 'structurally valid' }
        else {
            $ok = $false
            foreach ($p in $problems) { Write-Bad $p }
        }
    }

    if ($ok) { return 0 }
    return 1
}

# =============================================================================
# Apply
# =============================================================================

function Invoke-ApplyFill {
    <#
        Add jobs to controls that do nothing. Change nothing else -- not the
        token, not the preset, not the order of anything already in the file.
    #>
    param($Stick, $Map, $Profile, $Parsed, [string] $Installed)

    $fill = Resolve-FillBindings -Map $Map -Profile $Profile -Parsed $Parsed

    Write-Host ''
    Write-Section 'ALREADY BOUND -- LEFT EXACTLY AS THEY ARE'
    foreach ($id in ($fill.Untouched | Sort-Object)) {
        $token = '-'
        $idx = Get-MappedButtonIndex -Map $Map -ControlId $id
        if ($null -ne $idx) { $token = "button$idx" }
        elseif ($id -eq 'StickHat') { $token = 'pov' }
        elseif ($Map.Axes.ContainsKey($id)) { $token = "axis$($Map.Axes[$id].Index)" }
        Write-Field $token (Get-ControlLabel $id) 'DarkGray'
    }

    if ($fill.Add.Count -eq 0) {
        Write-Host ''
        Write-Good 'Every control already does something. Nothing to add.'
        return 0
    }

    Write-Host ''
    Write-Section 'WOULD ADD -- CONTROLS THAT CURRENTLY DO NOTHING'
    foreach ($id in $fill.Chosen.Keys) {
        $job = Get-Job $fill.Chosen[$id]
        $idx = Get-MappedButtonIndex -Map $Map -ControlId $id
        $tier = ''
        if ($job.Tier -eq 'B') { $tier = '   [unconfirmed]' }
        Write-Host ('    ' + "button$idx".PadRight(10)) -NoNewline -ForegroundColor DarkGray
        Write-Host ((Get-ControlLabel $id).PadRight(28)) -NoNewline -ForegroundColor DarkCyan
        Write-Host ($job.Label + $tier) -ForegroundColor Green
        Write-Note ("            " + $job.Desc)
    }
    if ($fill.Unfillable.Count -gt 0) {
        Write-Host ''
        Write-Warn ('no action left to give these: ' +
                    (($fill.Unfillable | ForEach-Object { Get-ControlLabel $_ }) -join ', '))
        Write-Note 'Every job this tool knows is already used somewhere in your config.'
    }

    # Everything already in the file is carried through verbatim.
    $preserve = @()
    foreach ($name in $Parsed.Actions.Keys) { $preserve += $Parsed.Raw[$name] }

    $text = Build-Config -Bindings $fill.Add -Preserve $preserve

    $problems = Test-Config $text
    if ($problems.Count -gt 0) {
        Write-Host ''
        Write-Bad 'The generated config is malformed. Nothing was written.'
        foreach ($p in $problems) { Write-Bad "  $p" }
        return 1
    }

    Write-Host ''
    Write-Section 'SUMMARY'
    Write-Field 'to' $Installed
    Write-Field 'kept unchanged' "$($Parsed.Actions.Count) action(s)"
    Write-Field 'added' "$($fill.Add.Count) action(s)"
    Write-Field 'validation' 'passed' 'Green'

    if ($DryRun) {
        Write-Host ''
        Write-Note '-DryRun: nothing written.'
        return 0
    }
    if (-not $Force -and -not (Confirm-Action 'Add these, leaving everything else untouched?')) {
        Write-Note 'Nothing written.'
        return 0
    }

    Backup-Installed -Installed $Installed
    Set-Content -Path $Installed -Value $text -Encoding UTF8 -NoNewline

    $after = Get-Content -Raw $Installed
    $afterProblems = Test-Config $after
    if ($afterProblems.Count -gt 0) {
        Write-Bad 'The file on disk does not validate after writing:'
        foreach ($p in $afterProblems) { Write-Bad "  $p" }
        return 1
    }
    Write-Good 'written and verified'
    return 0
}

function Backup-Installed {
    param([string] $Installed)
    if (-not (Test-Path $Installed)) { return }
    if (-not (Test-Path $script:BackupDir)) { New-Item -ItemType Directory -Path $script:BackupDir -Force | Out-Null }
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $backup = Join-Path $script:BackupDir "$stamp-$(Split-Path -Leaf $Installed)"
    Copy-Item -Path $Installed -Destination $backup -Force
    Write-Good "backed up -> backups\$(Split-Path -Leaf $backup)"
}

function Invoke-Apply {
    Write-Title 'APPLY' "profile: $ProfileName"

    $stick = Resolve-Stick
    if (-not $stick) { return 1 }
    $map = Get-Map
    if (-not $map) { return 1 }
    if (-not (Assert-GameClosed)) { return 1 }

    $profile = Get-Profile $ProfileName
    Write-Host ''
    Write-Field 'profile' $profile.Label 'White'
    Write-Note $profile.Desc

    $dir = Get-InputConfigDir
    $installed = Join-Path $dir (Get-ConfigFileName $stick)
    $parsed = Read-Config $installed

    # FILL is the default. Replace only on request, because replacing moves
    # bindings the user already has in their hands.
    if (-not $Replace -and $parsed.Actions.Count -gt 0) {
        return (Invoke-ApplyFill -Stick $stick -Map $map -Profile $profile -Parsed $parsed -Installed $installed)
    }

    if ($Replace -and $parsed.Actions.Count -gt 0) {
        Write-Host ''
        Write-Warn 'REPLACE: every binding in the current config will be regenerated.'
        Write-Note 'Anything you have got used to may end up on a different button.'
        Write-Note 'Drop -Replace to add jobs to dead controls and leave the rest alone.'
        if (-not $Force -and -not (Confirm-Action 'Replace the whole layout?')) { return 1 }
    }

    $rows = Get-CoverageForCurrent -Stick $stick -Map $map -Profile $profile
    $complete = Show-Coverage -Rows $rows -Profile $profile
    if (-not $complete -and -not $Force) {
        Write-Host ''
        Write-Note 'Fix the gaps above, or pass -Force to write anyway.'
        return 1
    }

    $bindings = Resolve-Bindings -Map $map -Profile $profile
    if ($bindings.Count -eq 0) { Write-Bad 'Nothing to write.'; return 1 }

    $conflicts = Get-BindingConflict $bindings
    if ($conflicts.Count -gt 0) {
        Write-Host ''
        Write-Section 'CONFLICTS'
        foreach ($c in $conflicts) { Write-Warn $c }
        Write-Note 'Cyclic and turret aim sharing the stick is fine -- different seats.'
        if (-not $Force -and -not (Confirm-Action 'Write anyway?')) { return 1 }
    }

    $preserve = Get-UnknownActionBlock $parsed
    if ($preserve.Count -gt 0) { Write-Note "keeping $($preserve.Count) action(s) this tool does not manage" }

    $text = Build-Config -Bindings $bindings -Preserve $preserve

    $problems = Test-Config $text
    if ($problems.Count -gt 0) {
        Write-Host ''
        Write-Bad 'The generated config is malformed. Nothing was written.'
        foreach ($p in $problems) { Write-Bad "  $p" }
        return 1
    }

    Write-Host ''
    Write-Section 'ABOUT TO WRITE'
    Write-Field 'to' $installed
    Write-Field 'actions' "$($bindings.Count)"
    Write-Field 'inputs' ("{0}" -f (($bindings | ForEach-Object { $_.Sources.Count }) | Measure-Object -Sum).Sum)
    Write-Field 'validation' 'passed' 'Green'

    if ($DryRun) {
        Write-Host ''
        Write-Note '-DryRun: printing instead of writing.'
        Write-Host ''
        Write-Host $text
        return 0
    }

    if (-not $Force -and -not (Confirm-Action 'Install it?')) { Write-Note 'Nothing written.'; return 0 }

    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    if (Test-Path $installed) {
        if (-not (Test-Path $script:BackupDir)) { New-Item -ItemType Directory -Path $script:BackupDir -Force | Out-Null }
        $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
        $backup = Join-Path $script:BackupDir "$stamp-$(Split-Path -Leaf $installed)"
        Copy-Item -Path $installed -Destination $backup -Force
        Write-Good "backed up -> backups\$(Split-Path -Leaf $backup)"
    }

    Set-Content -Path $installed -Value $text -Encoding UTF8 -NoNewline

    # Read it back rather than trust the write. A half-written file is the one
    # failure mode that would leave the stick dead with no error anywhere.
    $after = Get-Content -Raw $installed
    $afterProblems = Test-Config $after
    if ($afterProblems.Count -gt 0) {
        Write-Bad 'The file on disk does not validate after writing:'
        foreach ($p in $afterProblems) { Write-Bad "  $p" }
        return 1
    }

    Write-Good 'written and verified'
    Write-Host ''
    Write-Note 'Start Reforger, then run  .\Hotas4.ps1 -CheckLog  to confirm the engine took it.'
    return 0
}

# =============================================================================
# Watch
# =============================================================================

function Invoke-KeyTest {
    <#
        Diagnostic. Proves whether this console delivers keystrokes to the tool
        at all, and shows exactly what each key resolves to. If the wizard ever
        seems to ignore the keyboard, run this first: it separates "the console
        is not giving us keys" from "the tool is not acting on them".
    #>
    Write-Title 'KEY TEST' 'does this console give the tool your keystrokes?'
    Write-Field 'host' $Host.Name
    Write-Field 'PowerShell' $PSVersionTable.PSVersion.ToString()

    $available = 'yes'
    try { [void][Console]::KeyAvailable } catch { $available = "NO -- $($_.Exception.Message)" }
    Write-Field 'KeyAvailable works' $available $(if ($available -eq 'yes') { 'Green' } else { 'Red' })

    if ($available -ne 'yes') {
        Write-Host ''
        Write-Bad 'This console does not support polled key input.'
        Write-Note 'Run the tool from a normal PowerShell or Windows Terminal window,'
        Write-Note 'not through a pipe, a redirect, or an editor task runner.'
        return 1
    }

    Write-Host ''
    Write-Strong 'Press keys. Each one is echoed with what the tool makes of it.'
    Write-Note 'Press Esc to finish.'
    Write-Host ''

    while ($true) {
        $raw = [Console]::ReadKey($true)
        $resolved = Read-KeyCharFrom $raw
        $shown = $resolved
        if ($resolved -eq "`r") { $shown = '<enter>' }
        Write-Host ('    ConsoleKey=' + $raw.Key.ToString().PadRight(12)) -NoNewline -ForegroundColor DarkGray
        Write-Host ("KeyChar='" + $raw.KeyChar + "'").PadRight(16) -NoNewline -ForegroundColor DarkGray
        Write-Host ("tool reads: $shown") -ForegroundColor Green
        if ($raw.Key -eq 'Escape') { break }
    }
    Write-Host ''
    Write-Good 'Keyboard input is reaching the tool.'
    return 0
}

function Invoke-Watch {
    Write-Title 'WATCH' 'move a control, see the token Reforger uses'
    $stick = Resolve-Stick
    if (-not $stick) { return 1 }
    Write-Host ''
    Write-Note 'Ctrl+C to stop.'
    Write-Host ''

    $prev = Read-Device $stick.Id
    if (-not $prev) { Write-Bad 'Cannot read the device.'; return 1 }
    $prevHat = $prev.Hat

    while ($true) {
        $now = Read-Device $stick.Id
        if (-not $now) { Start-Sleep -Milliseconds 250; continue }

        foreach ($i in 0..5) {
            if ([math]::Abs($now.Axes[$i] - $prev.Axes[$i]) -lt 0.08) { continue }
            $sign = '+'
            if ($now.Axes[$i] -lt 0) { $sign = '-' }
            Write-Host ('    ' + "axis$i".PadRight(10)) -NoNewline -ForegroundColor DarkGray
            Write-Host ((Get-AxisBar $now.Axes[$i]) + ('{0,7:N2}' -f $now.Axes[$i]) + "   joystick0:axis$i$sign") -ForegroundColor Gray
            $prev.Axes[$i] = $now.Axes[$i]
        }

        foreach ($i in (Get-PressedButton -Before $prev.Buttons -Now $now.Buttons)) {
            $label = 'not identified'
            $map = Get-Map -Quiet
            if ($map -and $map.Buttons.ContainsKey("$i")) { $label = Get-ControlLabel $map.Buttons["$i"] }
            Write-Host ('    ' + "button$i".PadRight(10)) -NoNewline -ForegroundColor DarkGray
            Write-Host ($label.PadRight(30) + "joystick0:button$i") -ForegroundColor Green
        }
        $prev.Buttons = $now.Buttons

        if ($now.Hat -ne $prevHat) {
            foreach ($d in (Get-HatNames $now.Hat)) {
                Write-Host ('    ' + 'hat'.PadRight(10)) -NoNewline -ForegroundColor DarkGray
                Write-Host ("$d".PadRight(30) + "joystick0:pov_$d") -ForegroundColor Cyan
            }
            $prevHat = $now.Hat
        }

        Start-Sleep -Milliseconds 40
    }
}

# =============================================================================
# Log check
# =============================================================================

function Invoke-CheckLog {
    Write-Title 'LOG CHECK' 'did the engine accept the bindings?'
    $logRoot = Join-Path (Get-ReforgerRoot) 'logs'
    if (-not (Test-Path $logRoot)) { Write-Bad "No logs at $logRoot"; return 1 }

    $newest = Get-ChildItem -Path $logRoot -Directory | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if (-not $newest) { Write-Bad 'No log runs found.'; return 1 }
    Write-Field 'run' $newest.Name
    Write-Field 'when' $newest.LastWriteTime

    $lines = @()
    foreach ($f in @('console.log', 'error.log')) {
        $p = Join-Path $newest.FullName $f
        if (Test-Path $p) { $lines += Get-Content -Path $p | Where-Object { $_ -match 'INPUT\s+\(E\)' } }
    }
    $lines = @($lines | Sort-Object -Unique)

    # The Hotas 4 has no force-feedback motor, so the engine always fails to
    # create the effect and always says so. It is not an input error.
    $real = @($lines | Where-Object { $_ -notmatch 'ForceFeedback effect failed to create' })

    Write-Host ''
    if ($real.Count -eq 0) {
        Write-Good 'No input errors. The engine took every binding in the file.'
        if ($lines.Count -gt 0) { Write-Note "($($lines.Count) force-feedback line(s) ignored -- the stick has no motor.)" }
        return 0
    }
    Write-Bad "$($real.Count) input error(s):"
    foreach ($l in $real) { Write-Bad "  $($l.Trim())" }
    return 1
}

# =============================================================================
# Restore
# =============================================================================

function Invoke-Restore {
    Write-Title 'RESTORE' "put Reforger's own preset back"
    if (-not (Test-Path $script:StockPath)) { Write-Bad "No stock preset at $script:StockPath"; return 1 }
    $stick = Resolve-Stick
    if (-not (Assert-GameClosed)) { return 1 }

    $dir = Get-InputConfigDir
    $installed = Join-Path $dir (Get-ConfigFileName $stick)
    Write-Host ''
    Write-Field 'from' $script:StockPath
    Write-Field 'to' $installed
    if (-not $Force -and -not (Confirm-Action 'Overwrite the installed config with the stock preset?')) { return 0 }

    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    if (Test-Path $installed) {
        if (-not (Test-Path $script:BackupDir)) { New-Item -ItemType Directory -Path $script:BackupDir -Force | Out-Null }
        $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
        Copy-Item -Path $installed -Destination (Join-Path $script:BackupDir "$stamp-prerestore-$(Split-Path -Leaf $installed)") -Force
    }
    Copy-Item -Path $script:StockPath -Destination $installed -Force
    Write-Good 'restored'
    return 0
}

# =============================================================================
# Menu
# =============================================================================

function Invoke-Menu {
    Write-Title 'T.FLIGHT HOTAS 4  ->  ARMA REFORGER' 'bind every control, or say why not'

    $map = Import-DeviceMap $script:DeviceMapPath
    if ($map) { Write-Good "layout known: $($map.Device)" }
    else       { Write-Warn 'this unit has not been identified yet -- start with [1]' }

    Write-Host ''
    Write-Strong '  [1] Identify    learn what is on your stick        (do this once)'
    Write-Strong '  [2] Apply       write the config'
    Write-Strong '  [3] Show        what every control currently does'
    Write-Strong '  [4] Verify      audit coverage'
    Write-Strong "  [5] Watch       live input reader"
    Write-Strong '  [6] Check log   did the engine accept it?'
    Write-Strong '  [7] Restore     put the stock preset back'
    Write-Strong '  [q] Quit'
    Write-Note ''
    Write-Note 'If the keyboard seems dead anywhere in here, run -KeyTest.'

    $k = Read-Choice -Prompt 'choose:' -Keys @('1', '2', '3', '4', '5', '6', '7', 'q')
    switch ($k) {
        '1' { return (Invoke-Identify) }
        '2' { return (Invoke-Apply) }
        '3' { return (Invoke-Show) }
        '4' { return (Invoke-Verify) }
        '5' { return (Invoke-Watch) }
        '6' { return (Invoke-CheckLog) }
        '7' { return (Invoke-Restore) }
        'q' { return 0 }
    }
    return 0
}

# =============================================================================

if ($SelfTest) {
    $code = 0
    & (Join-Path $script:Root 'tests\Run-Tests.ps1') -Root $script:Root
    $code = $LASTEXITCODE
    exit $code
}

$exit = 0
if     ($Identify) { $exit = Invoke-Identify }
elseif ($Apply)    { $exit = Invoke-Apply }
elseif ($Show)     { $exit = Invoke-Show }
elseif ($Verify)   { $exit = Invoke-Verify }
elseif ($Watch)    { $exit = Invoke-Watch }
elseif ($KeyTest)  { $exit = Invoke-KeyTest }
elseif ($CheckLog) { $exit = Invoke-CheckLog }
elseif ($Restore)  { $exit = Invoke-Restore }
else               { $exit = Invoke-Menu }

Write-Host ''
exit $exit
