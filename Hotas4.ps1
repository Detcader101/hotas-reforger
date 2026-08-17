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
    [switch] $Audit,
    [switch] $Register,
    [switch] $Learn,
    [switch] $Reset,
    [switch] $KeyTest,
    [switch] $CheckLog,
    [switch] $Restore,
    [switch] $SelfTest,

    [ValidateSet('pilot', 'helicopter', 'full', 'conservative')]
    [string] $ProfileName = 'pilot',

    [string] $ConfigName,
    [switch] $DryRun,
    [switch] $Replace,
    [switch] $Repair,
    [switch] $All,
    [string[]] $Bind,
    [switch] $Force
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$script:Root = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $script:Root 'lib\Common.ps1')
. (Join-Path $script:Root 'lib\Ui.ps1')
. (Join-Path $script:Root 'lib\Device.ps1')
. (Join-Path $script:Root 'lib\Layout.ps1')
. (Join-Path $script:Root 'lib\Audit.ps1')
. (Join-Path $script:Root 'lib\Reforger.ps1')

$script:DeviceMapPath = Join-Path $script:Root 'device-map.json'
$script:BackupDir     = Join-Path $script:Root 'backups'
$script:StockPath     = Join-Path $script:Root 'reference\stock-preset.conf'
$script:AuditPath     = Join-Path $script:Root 'device-audit.json'

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
    param([switch] $Quiet, $Stick)
    $map = Import-DeviceMap $script:DeviceMapPath
    if (-not $map -and -not $Quiet) {
        Write-Bad 'This unit has not been identified yet.'
        Write-Note 'Run:  .\Hotas4.ps1 -Identify'
        Write-Note 'It takes about a minute and only has to be done once.'
    }
    if ($map -and $Stick -and -not $Quiet) {
        $changed = Test-CapsChanged -Map $map -Stick $Stick
        if ($changed.Count -gt 0) {
            Write-Host ''
            Write-Bad 'THIS STICK IS NOT REPORTING WHAT IT DID WHEN IT WAS IDENTIFIED.'
            foreach ($c in $changed) { Write-Bad "  $c" }
            Write-Note 'On a T.Flight Hotas 4 that is the mode switch on the base. Every'
            Write-Note 'index in the saved layout now describes a control the stick does'
            Write-Note 'not have, and a config built from it will be valid and wrong.'
            Write-Note 'Either put the switch back, or re-run -Identify -All.'
        }
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
    $map.Caps = @{ Axes = $stick.AxisCount; Buttons = $stick.ButtonCount; Hat = $stick.HasHat }

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
    $allAxes = Get-ControlsByKind 'Axis'
    $axes = @()
    foreach ($a in $allAxes) {
        if ($All -or -not $Map.Axes.ContainsKey($a.Id)) { $axes += $a }
    }
    if ($axes.Count -eq 0) { Write-Section 'AXES'; Write-Good 'Every axis is already identified.'; return $true }
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
    <#
        Only asks about controls it does not already know. Re-running after a
        catalogue correction should cost three presses, not twelve. -All forces
        the whole walk.
    #>
    param($Stick, $Map)
    $all = Get-ControlsByKind 'Button'
    $buttons = @()
    foreach ($c in $all) {
        if ($All -or $null -eq (Get-MappedButtonIndex -Map $Map -ControlId $c.Id)) { $buttons += $c }
    }
    if ($buttons.Count -eq 0) {
        Write-Section 'BUTTONS'
        Write-Good 'Every button is already identified. Pass -All to redo them.'
        return
    }
    if ($buttons.Count -lt $all.Count) {
        Write-Section 'BUTTONS'
        Write-Note ("$($all.Count - $buttons.Count) already known; asking about the remaining $($buttons.Count).")
    }

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
    $colours = @{ Bound = 'Gray'; Free = 'DarkGray'; NoInput = 'DarkYellow'; NeedsBind = 'Cyan'; Unassigned = 'Yellow'; Unnamed = 'Red' }

    foreach ($zone in @('Stick', 'Throttle', 'Base', 'Unknown', 'Other')) {
        $inZone = @($Rows | Where-Object { $_.Zone -eq $zone })
        if ($inZone.Count -eq 0) { continue }
        Write-Section $zone.ToUpper()
        foreach ($r in $inZone) {
            $what = Get-JobLabel $r.JobId
            if ($r.Status -eq 'Unassigned') { $what = 'NOTHING -- no job assigned' }
            if ($r.Status -eq 'Unnamed')    { $what = 'NOT IDENTIFIED -- run -Identify' }
            if ($r.Status -eq 'NoInput')    { $what = 'SENDS NO INPUT -- cannot be bound by anything' }
            if ($r.Status -eq 'NeedsBind')  { $what = 'winmm cannot read it -- use -Bind with the token the game shows' }
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
    # The audit is optional. Without it a control that sends nothing looks like
    # a control nobody bound, which is the wrong complaint.
    $audit = Import-AuditState $script:AuditPath
    return (Get-Coverage -Map $Map -Profile $Profile -ButtonCount $Stick.ButtonCount -HasHat $Stick.HasHat -Audit $audit)
}

# =============================================================================
# Show / Verify
# =============================================================================

function Invoke-Show {
    Write-Title 'LAYOUT AND BINDINGS' "profile: $ProfileName"
    $stick = Resolve-Stick
    if (-not $stick) { return 1 }
    $map = Get-Map -Stick $stick
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
    $map = Get-Map -Stick $stick
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

    # A valid file the game is not pointed at does nothing at all, and looks
    # from inside the game exactly like a config with no bindings in it.
    $settings = Get-InputUserSettingsPath
    if ($settings) {
        Write-Host ''
        Write-Section 'IS REFORGER ACTUALLY LOADING IT?'
        if (Test-ConfigRegistered -SettingsPath $settings -ConfigFileName (Get-ConfigFileName $stick)) {
            Write-Good 'yes -- registered in CustomConfigs'
        } else {
            $ok = $false
            Write-Bad 'NO. The game is pointed at a different joystick scheme:'
            foreach ($p in (Get-RegisteredConfig -SettingsPath $settings)) { Write-Bad "  $p" }
            Write-Note 'The config below can be flawless and still do nothing. Fix with:'
            Write-Note '  .\Hotas4.ps1 -Register'
        }
    }

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
    Write-TextFile -Path $Installed -Text $text

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

function Write-AxisWarning {
    <#
        Two things about axes that only measurement can tell you, and that a
        valid config will happily hide.
    #>
    param($Stick, $Map, $Profile, $Bindings)

    $inferred = Get-InferredAxisWarning $Bindings
    if ($inferred.Count -gt 0) {
        Write-Host ''
        Write-Section 'AXIS INDEX NOT CONFIRMED'
        foreach ($i in $inferred) { Write-Warn $i }
        Write-Note 'winmm calls these U and V; that they are Reforger axis3 and axis4 is'
        Write-Note 'inferred, not observed. X, Y, Z and the rudder do line up. To confirm:'
        Write-Note 'Reforger -> Settings -> Controls, pick the action, move the control --'
        Write-Note 'the game prints the real token, which is authoritative.'
    }

    # A two-way action driven by an axis that does not rest at centre applies
    # that input permanently. On rudder that is a helicopter yawing on its own.
    $rest = Get-RestingPosition -Id $Stick.Id
    if (-not $rest) { return }

    $offCentre = @()
    foreach ($c in (Get-ControlsByKind 'Axis')) {
        if (-not $Map.Axes.ContainsKey($c.Id)) { continue }
        $jobId = Get-Opt $Profile.Bind $c.Id 'Free'
        if ($jobId -eq 'Free' -or -not $jobId) { continue }
        $job = Get-Job $jobId
        # Collective is one-way in feel: a throttle lever resting at an end is
        # normal and correct. A centring control resting off-centre is not.
        if (-not $job -or $job.Id -eq 'Collective') { continue }
        $v = $rest[$Map.Axes[$c.Id].Index]
        if ([math]::Abs($v) -gt 0.25) { $offCentre += ('{0} rests at {1:N2}, not centre' -f $c.Label, $v) }
    }

    if ($offCentre.Count -gt 0) {
        Write-Host ''
        Write-Section 'AXIS NOT RESTING AT CENTRE'
        foreach ($o in $offCentre) { Write-Warn $o }
        Write-Note 'Bound to a two-way action this applies that input constantly -- on the'
        Write-Note 'tail rotor it is a permanent yaw you cannot trim out. Let go of'
        Write-Note 'everything and re-run, or leave that control unbound.'
    }
}

function Invoke-ApplyRepair {
    <#
        Fill the empty controls, replace the ones bound to something inert in
        this seat, and leave everything that already works exactly where it is.
    #>
    param($Stick, $Map, $Profile, $Parsed, [string] $Installed, [string] $Seat)

    $r = Resolve-RepairBindings -Map $Map -Profile $Profile -Parsed $Parsed -Seat $Seat

    Write-Host ''
    Write-Section 'WORKING ALREADY -- NOT TOUCHED'
    foreach ($id in ($r.Untouched | Sort-Object)) {
        $token = '-'
        $idx = Get-MappedButtonIndex -Map $Map -ControlId $id
        if ($null -ne $idx) { $token = "button$idx" }
        elseif ($id -eq 'StickHat') { $token = 'pov' }
        elseif ($Map.Axes.ContainsKey($id)) { $token = "axis$($Map.Axes[$id].Index)" }
        Write-Field $token (Get-ControlLabel $id) 'DarkGray'
    }

    if ($r.Repaired.Count -gt 0) {
        Write-Host ''
        Write-Section "DOES NOTHING IN THE $($Seat.ToUpper()) SEAT -- REPLACED"
        foreach ($id in $r.Repaired) {
            Write-Field (Get-ControlLabel $id) '' 'Yellow' 30
        }
        Write-Note ('dropping: ' + ($r.Remove -join ', '))
    }

    if ($r.Add.Count -eq 0) {
        Write-Host ''
        Write-Good "Nothing to change. Every control already works in the $Seat seat."
        return 0
    }

    Write-Host ''
    Write-Section 'WILL NOW DO'
    foreach ($id in $r.Chosen.Keys) {
        $job = Get-Job $r.Chosen[$id]
        $token = '-'
        $idx = Get-MappedButtonIndex -Map $Map -ControlId $id
        if ($null -ne $idx) { $token = "button$idx" }
        elseif ($Map.Axes.ContainsKey($id)) { $token = "axis$($Map.Axes[$id].Index)" }
        $tier = ''
        if ($job.Tier -eq 'B') { $tier = '   [unconfirmed]' }
        Write-Host ('    ' + $token.PadRight(10)) -NoNewline -ForegroundColor DarkGray
        Write-Host ((Get-ControlLabel $id).PadRight(26)) -NoNewline -ForegroundColor DarkCyan
        Write-Host ($job.Label + $tier) -ForegroundColor Green
        Write-Note ("            " + $job.Desc)
        if (Get-Opt $job 'Hazard' $false) {
            Write-Warn ("            " + (Get-Opt $job 'Hazard_Note' 'This one can bite.'))
        }
    }
    if ($r.Unfillable.Count -gt 0) {
        Write-Host ''
        Write-Warn ('no action left for: ' + (($r.Unfillable | ForEach-Object { Get-ControlLabel $_ }) -join ', '))
    }

    $preserve = @()
    foreach ($name in $r.Pruned.Actions.Keys) { $preserve += $r.Pruned.Raw[$name] }
    $text = Build-Config -Bindings $r.Add -Preserve $preserve

    $problems = Test-Config $text
    if ($problems.Count -gt 0) {
        Write-Host ''
        Write-Bad 'The generated config is malformed. Nothing was written.'
        foreach ($p in $problems) { Write-Bad "  $p" }
        return 1
    }

    Write-AxisWarning -Stick $Stick -Map $Map -Profile $Profile -Bindings $r.Add

    Write-Host ''
    Write-Section 'SUMMARY'
    Write-Field 'to' $Installed
    Write-Field 'left alone' "$($r.Untouched.Count) control(s)"
    Write-Field 'replaced' "$($r.Repaired.Count) control(s)"
    Write-Field 'actions added' "$($r.Add.Count)"
    Write-Field 'actions dropped' "$($r.Remove.Count)"
    Write-Field 'validation' 'passed' 'Green'

    if ($DryRun) { Write-Host ''; Write-Note '-DryRun: nothing written.'; return 0 }
    if (-not $Force -and -not (Confirm-Action 'Apply this?')) { Write-Note 'Nothing written.'; return 0 }

    Backup-Installed -Installed $Installed
    Write-TextFile -Path $Installed -Text $text

    $afterProblems = Test-Config (Get-Content -Raw $Installed)
    if ($afterProblems.Count -gt 0) {
        Write-Bad 'The file on disk does not validate after writing:'
        foreach ($p in $afterProblems) { Write-Bad "  $p" }
        return 1
    }
    Write-Good 'written and verified'
    Write-Host ''
    Write-Note 'Start Reforger, then run  .\Hotas4.ps1 -CheckLog'
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
    $map = Get-Map -Stick $stick
    if (-not $map) { return 1 }
    if (-not (Assert-GameClosed)) { return 1 }

    $profile = Get-Profile $ProfileName
    Write-Host ''
    Write-Field 'profile' $profile.Label 'White'
    Write-Note $profile.Desc

    $dir = Get-InputConfigDir
    $installed = Join-Path $dir (Get-ConfigFileName $stick)
    $parsed = Read-Config $installed

    # -Repair also replaces bindings that are inert in the profile's seat.
    if ($Repair -and $parsed.Actions.Count -gt 0) {
        $seat = Get-Opt $profile 'Seat' 'Pilot'
        return (Invoke-ApplyRepair -Stick $stick -Map $map -Profile $profile -Parsed $parsed -Installed $installed -Seat $seat)
    }

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

    Write-AxisWarning -Stick $stick -Map $map -Profile $profile -Bindings $bindings

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

    Write-TextFile -Path $installed -Text $text

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

function Invoke-Audit {
    <#
        Find out what actually sends anything, before deciding what to bind.
        Nothing here writes a game config.
    #>
    Write-Title 'AUDIT' 'which controls actually send input to the PC'

    $stick = Resolve-Stick
    if (-not $stick) { return 1 }

    $state = Import-AuditState $script:AuditPath
    if (-not $state -or $state.Pid -ne $stick.Pid) { $state = New-AuditState $stick }
    $state.ButtonCount = $stick.ButtonCount

    $keys = Get-AuditKeyMap

    while ($true) {
        Show-AuditMenu -State $state -Keys $keys -Stick $stick
        $valid = @($keys.Keys) + @('t', 'w', 'r', 'x', 'q')
        $k = Read-Choice -Prompt '[letter] test one   [t] test every untested   [r] reset   [w] save report   [x] done' -Keys $valid
        if ($k -eq 'x' -or $k -eq 'q') { break }
        if ($k -eq 'r') { $state.Results = @{}; continue }
        if ($k -eq 'w') { Export-AuditState -State $state -Path $script:AuditPath; Write-Good "saved -> $(Split-Path -Leaf $script:AuditPath)"; Wait-AnyKey; continue }
        if ($k -eq 't') {
            foreach ($id in @($keys.Values)) {
                if ((Get-AuditStatus -State $state -Id $id) -ne 'untested') { continue }
                if (-not (Invoke-AuditOne -Stick $stick -State $state -Id $id)) { break }
            }
            continue
        }
        [void](Invoke-AuditOne -Stick $stick -State $state -Id $keys["$k"])
    }

    Export-AuditState -State $state -Path $script:AuditPath
    Show-AuditReport -State $state -Stick $stick
    return 0
}

function Show-AuditMenu {
    param($State, $Keys, $Stick)
    Write-Title 'AUDIT' "$($Stick.ButtonCount) buttons reported by the driver"
    $glyph = @{ Responds = 'RESPONDS'; Dead = 'NO RESPONSE'; untested = '- untested' }
    $colour = @{ Responds = 'Green'; Dead = 'Red'; untested = 'DarkGray' }

    foreach ($k in $Keys.Keys) {
        $id = $Keys[$k]
        $c = Get-Control $id
        $status = Get-AuditStatus -State $State -Id $id
        $token = Get-AuditToken -State $State -Id $id
        Write-Host ('    [' + $k + ']  ') -NoNewline -ForegroundColor White
        Write-Host ($c.Label.PadRight(26)) -NoNewline -ForegroundColor DarkCyan
        Write-Host ($glyph[$status].PadRight(13)) -NoNewline -ForegroundColor $colour[$status]
        Write-Host $token -ForegroundColor DarkGray
    }

    $sum = Get-AuditSummary $State
    Write-Host ''
    Write-Rule
    Write-Host ('    ' + $sum.Responds.Count + ' respond    ' + $sum.Dead.Count +
                ' dead    ' + $sum.Untested.Count + ' untested') -ForegroundColor White
    if ($sum.UnseenIndices.Count -gt 0) {
        Write-Warn ('driver reports these indices but nothing has produced them yet: ' +
                    (($sum.UnseenIndices | ForEach-Object { "button$_" }) -join ', '))
    }
}

function Invoke-AuditOne {
    <# Returns $false if the user wants to stop the whole run. #>
    param($Stick, $State, [string] $Id)
    $c = Get-Control $Id

    Write-Title 'AUDIT' $c.Label
    if ($c.Kind -eq 'Axis') {
        Write-Strong $c.Probe
    } else {
        Write-Strong "Press: $($c.Label)"
        Write-Note $c.Where
        if ($c.ContainsKey('Ps4')) { Write-Note "(the $($c.Ps4) button in PlayStation terms)" }
    }
    Write-Host ''
    Write-Keys 'do it now   -- or --   [n] I pressed it and NOTHING happened   [s] skip   [q] stop'

    # ALWAYS 'Any'. The audit exists to discover what a control produces, so
    # restricting what it will look at defeats the entire point. This was
    # 'Digital' for anything catalogued as a button, and Digital ignores axes --
    # so the throttle rocker, catalogued as a button, moved a slider the audit
    # was deliberately not watching, and got reported as sending nothing. A
    # crippled test reported as a hardware fact is worse than no test.
    $r = Wait-Control -Id $Stick.Id -Accept 'Any' -Keys @('n', 's', 'q') -TimeoutMs 20000

    if ($r.Kind -eq 'Gone') { Write-Bad 'The stick stopped responding.'; return $false }

    if ($r.Kind -eq 'Key') {
        if ($r.Key -eq 'q') { return $false }
        if ($r.Key -eq 's') { return $true }
        if ($r.Key -eq 'n') {
            Set-AuditResult -State $State -Id $Id -Status 'Dead'
            Write-Bad "$($c.Label): recorded as sending NOTHING."
            Start-Sleep -Milliseconds 700
            return $true
        }
    }

    if ($r.Kind -eq 'Timeout') {
        Set-AuditResult -State $State -Id $Id -Status 'Dead'
        Write-Bad "$($c.Label): nothing read in 20 seconds. Recorded as dead."
        Start-Sleep -Milliseconds 900
        return $true
    }

    $token = ''
    if ($r.Kind -eq 'Button') { $token = "button$($r.Index)" }
    elseif ($r.Kind -eq 'Hat') { $token = 'pov_' + $r.Directions[0] }
    elseif ($r.Kind -eq 'Axis') { $token = "axis$($r.Index)$($r.Sign)" }

    # A control that reads as something already claimed is worth saying out
    # loud: two physical controls on one index means one of them is a relabel
    # of the other, and a binding put on it will fire from both.
    $clash = $null
    foreach ($other in $State.Results.Keys) {
        if ($other -eq $Id) { continue }
        if ($State.Results[$other].Token -eq $token) { $clash = $other }
    }

    Set-AuditResult -State $State -Id $Id -Status 'Responds' -Token $token
    Write-Good "$($c.Label): responds as $token"
    if ($clash) { Write-Warn "...but $(Get-ControlLabel $clash) also reads as $token. They are the same input." }
    Start-Sleep -Milliseconds 700
    return $true
}

function Show-AuditReport {
    param($State, $Stick)
    $sum = Get-AuditSummary $State
    Write-Title 'AUDIT REPORT' $State.Device

    Write-Section "RESPONDS ($($sum.Responds.Count))"
    foreach ($id in $sum.Responds) { Write-Field (Get-AuditToken -State $State -Id $id) (Get-ControlLabel $id) 'Green' 12 }

    if ($sum.Dead.Count -gt 0) {
        Write-Section "SENDS NOTHING ($($sum.Dead.Count))"
        foreach ($id in $sum.Dead) { Write-Field '-' (Get-ControlLabel $id) 'Red' 12 }
        Write-Host ''
        Write-Note 'A control that sends nothing cannot be bound by any tool or by the'
        Write-Note 'game itself. If that is a surprise, check the PC/PS4 switch on the'
        Write-Note 'base, and confirm against Windows: joy.cpl -> Properties -> Test.'
    }

    if ($sum.Untested.Count -gt 0) {
        Write-Section "NOT YET TESTED ($($sum.Untested.Count))"
        foreach ($id in $sum.Untested) { Write-Field '?' (Get-ControlLabel $id) 'DarkGray' 12 }
    }

    if ($sum.UnseenIndices.Count -gt 0) {
        Write-Host ''
        Write-Warn ('The driver reports ' + $State.ButtonCount + ' buttons, but these never appeared: ' +
                    (($sum.UnseenIndices | ForEach-Object { "button$_" }) -join ', '))
        Write-Note 'Either a control in the list above is dead, or this stick has a control'
        Write-Note 'the catalogue does not describe.'
    }

    Write-Host ''
    Write-Field 'report saved' $script:AuditPath
    Write-Note 'Next:  .\Hotas4.ps1 -Apply -ProfileName pilot'
}

function Get-InputUserSettingsPath {
    <#
        Lives under a per-app, per-Steam-account folder, so it is found rather
        than assumed. Newest wins if somehow there are several.
    #>
    $root = Join-Path (Get-ReforgerRoot) 'profile\.save'
    if (-not (Test-Path $root)) { return $null }
    $hit = Get-ChildItem -Path $root -Filter 'InputUserSettings.conf' -Recurse -ErrorAction SilentlyContinue |
           Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if (-not $hit) { return $null }
    return $hit.FullName
}

function Invoke-Register {
    <#
        Point Reforger at the config this tool writes.

        A valid file in customInputConfigs does nothing on its own. The game
        keeps a CustomConfigs list naming the active joystick scheme, and it
        will repoint that at one of its own built-in presets -- at which point
        the custom file is unread and the game shows no bindings, with nothing
        wrong in the file itself to find.
    #>
    Write-Title 'REGISTER' 'make Reforger actually load the config'

    $stick = Resolve-Stick
    $name = Get-ConfigFileName $stick
    $settings = Get-InputUserSettingsPath
    if (-not $settings) {
        Write-Bad 'Cannot find InputUserSettings.conf.'
        Write-Note 'Launch Reforger once so it creates a profile, then try again.'
        return 1
    }

    Write-Host ''
    Write-Field 'settings file' $settings
    Write-Field 'wants to load' $name

    $current = Get-RegisteredConfig -SettingsPath $settings
    Write-Host ''
    Write-Section 'CURRENTLY REGISTERED'
    if ($current.Count -eq 0) { Write-Warn 'nothing -- no joystick scheme is active' }
    foreach ($p in $current) { Write-Field '' $p 'Yellow' }

    if (Test-ConfigRegistered -SettingsPath $settings -ConfigFileName $name) {
        Write-Host ''
        Write-Good 'Already registered. The game is reading the config this tool writes.'
        return 0
    }

    Write-Host ''
    Write-Bad "Reforger is NOT loading $name."
    Write-Note 'The file can be perfectly valid and still do nothing, because the'
    Write-Note 'game is pointed at a different scheme entirely.'

    if (-not (Assert-GameClosed)) { return 1 }

    $text = Get-Content -Raw -Path $settings
    $new = Set-RegisteredConfig -Text $text -ConfigFileName $name

    # Only the CustomConfigs block may change. This file also holds keyboard and
    # mouse rebinds, and losing those would be a poor trade for fixing this.
    $before = ([regex]::Matches($text, '(?m)^\s*Action\s+(\w+)\s*\{')).Count
    $after  = ([regex]::Matches($new,  '(?m)^\s*Action\s+(\w+)\s*\{')).Count
    if ($before -ne $after) {
        Write-Bad "Refusing to write: the edit would change $before action blocks to $after."
        return 1
    }

    Write-Host ''
    Write-Section 'WILL REGISTER'
    Write-Field '' ('$profile:.save/settings/customInputConfigs/' + $name) 'Green'
    Write-Note "$before keyboard/mouse rebind(s) in this file, left untouched"

    if ($DryRun) { Write-Host ''; Write-Note '-DryRun: nothing written.'; return 0 }
    if (-not $Force -and -not (Confirm-Action 'Register it?')) { Write-Note 'Nothing written.'; return 0 }

    if (-not (Test-Path $script:BackupDir)) { New-Item -ItemType Directory -Path $script:BackupDir -Force | Out-Null }
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    Copy-Item -Path $settings -Destination (Join-Path $script:BackupDir "$stamp-InputUserSettings.conf") -Force
    Write-Good "backed up -> backups\$stamp-InputUserSettings.conf"

    Write-TextFile -Path $settings -Text $new

    if (Test-ConfigRegistered -SettingsPath $settings -ConfigFileName $name) {
        Write-Good 'registered and verified'
        Write-Host ''
        Write-Note 'If the game repoints this again, it is the joystick preset picker in'
        Write-Note 'Settings -> Controls. Choosing a preset there overwrites this line.'
        return 0
    }
    Write-Bad 'Wrote the file but it still does not reference the config.'
    return 1
}

function Invoke-Learn {
    <#
        Learn an action's real name from Reforger, instead of guessing it.

        Every wrong call this tool has made came from inferring what the engine
        would accept -- which context an action lives in, whether a byte-order
        mark is tolerated, whether "toggle" is a filter preset. Each time the
        fix was to trust only what Reforger had written itself.

        This makes that a procedure. Snapshot InputUserSettings.conf, rebind the
        thing you want in the game's own controls screen, and the diff names the
        action exactly -- spelling, context and filter preset included, straight
        from the engine.
    #>
    Write-Title 'LEARN' "read an action's real name out of Reforger"

    $settings = Get-InputUserSettingsPath
    if (-not $settings) { Write-Bad 'Cannot find InputUserSettings.conf.'; return 1 }
    $snapPath = Join-Path $script:Root 'learn-snapshot.json'

    $now = Read-Config $settings
    $current = @{}
    foreach ($n in $now.Actions.Keys) {
        $current[$n] = (@($now.Actions[$n] | ForEach-Object { "$($_.Token)/$($_.Preset)" } | Sort-Object) -join ' + ')
    }

    if ($Reset -or -not (Test-Path $snapPath)) {
        Write-TextFile -Path $snapPath -Text ($current | ConvertTo-Json -Depth 4)
        Write-Field 'snapshot taken' "$($current.Count) rebind(s) currently in the file"
        Write-Host ''
        Write-Section 'NOW GO AND DO THIS'
        Write-Strong '1. Launch Reforger.'
        Write-Strong '2. Settings -> Controls.'
        Write-Strong '3. Find the action you want -- the helicopter sight, say -- and'
        Write-Strong '   bind it to any spare KEY. A keyboard key is fine; the point is'
        Write-Strong '   to make the game write the action name down.'
        Write-Strong '4. Quit the game so it saves.'
        Write-Strong '5. Run:  .\Hotas4.ps1 -Learn'
        Write-Host ''
        Write-Note 'The game records the exact name, context and filter preset it uses.'
        Write-Note 'Nothing that comes out of this is a guess.'
        return 0
    }

    try { $raw = Get-Content -Raw -Path $snapPath | ConvertFrom-Json } catch { $raw = $null }
    $before = @{}
    if ($raw) { foreach ($p in $raw.PSObject.Properties) { $before[$p.Name] = [string]$p.Value } }

    $added = @()
    $changed = @()
    foreach ($n in $current.Keys) {
        if (-not $before.ContainsKey($n)) { $added += $n }
        elseif ($before[$n] -ne $current[$n]) { $changed += $n }
    }

    Write-Field 'snapshot' "$($before.Count) rebind(s)"
    Write-Field 'now' "$($current.Count) rebind(s)"

    if ($added.Count -eq 0 -and $changed.Count -eq 0) {
        Write-Host ''
        Write-Warn 'Nothing changed since the snapshot.'
        Write-Note 'Reforger only writes an action here once you REBIND it, so a default'
        Write-Note 'binding you left alone will not appear. Change it to something else,'
        Write-Note 'quit, and run this again. -Reset takes a fresh snapshot.'
        return 0
    }

    Write-Host ''
    Write-Section 'REFORGER NAMED THESE'
    foreach ($n in $added) {
        Write-Host ('    ' + $n.PadRight(30)) -NoNewline -ForegroundColor Green
        Write-Host $current[$n] -ForegroundColor Gray
    }
    foreach ($n in $changed) {
        Write-Host ('    ' + $n.PadRight(30)) -NoNewline -ForegroundColor Cyan
        Write-Host ($before[$n] + '   ->   ' + $current[$n]) -ForegroundColor Gray
    }

    Write-Host ''
    Write-Note 'That is the action name and filter preset the engine itself uses --'
    Write-Note 'Tier A by definition. Tell me the name and I will bind it to a control,'
    Write-Note 'or add it to $script:Jobs in lib\Reforger.ps1 yourself.'
    return 0
}

function Invoke-Bind {
    <#
        Record a control's input token by hand.

        winmm is a legacy shim over six axes. A control it cannot read is not
        necessarily a control Reforger cannot read -- the game uses its own
        input layer, and the Hotas 4's throttle rocker is exactly this case: it
        works in joy.cpl, it moves none of winmm's six axes, and no amount of
        measuring here will find it.

        So: get the real token from the game, and tell the tool.

            Reforger -> Settings -> Controls -> pick any helicopter action
            -> move the control -> the game prints the token it sees

            .\Hotas4.ps1 -Bind "ThrottleRocker=joystick0:axis6+"

        That is authoritative in a way nothing this tool can do is.
    #>
    param([string[]] $Pairs)
    Write-Title 'BIND' 'record a token this tool cannot measure'

    $map = Get-Map -Stick $stick
    if (-not $map) { return 1 }

    $bad = 0
    foreach ($pair in $Pairs) {
        if ($pair -notmatch '^\s*([A-Za-z0-9]+)\s*=\s*(\S+)\s*$') {
            Write-Bad "cannot read '$pair' -- expected ControlId=token"
            $bad++
            continue
        }
        $id = $Matches[1]
        $token = $Matches[2]

        if (-not (Get-Control $id)) {
            Write-Bad "no control called '$id'"
            Write-Note ('known: ' + ((@($script:ControlCatalogue | ForEach-Object { $_.Id })) -join ', '))
            $bad++
            continue
        }
        if (-not (Test-InputToken $token)) {
            Write-Bad "'$token' is not a token Reforger would write"
            Write-Note 'expected joystick0:axisN+ , joystick0:buttonN , or joystick0:pov_up'
            $bad++
            continue
        }

        if ($token -match 'axis(\d)([+-])$') {
            $map.Axes[$id] = @{ Index = [int]$Matches[1]; Sign = $Matches[2] }
            Write-Good "$(Get-ControlLabel $id) -> $token"
            Write-Note 'recorded by hand; this tool cannot verify it, the game can'
        }
        elseif ($token -match 'button(\d+)$') {
            Set-MappedButton -Map $map -Index ([int]$Matches[1]) -ControlId $id
            Write-Good "$(Get-ControlLabel $id) -> $token"
        }
        elseif ($token -match 'pov_') {
            $map.Hat = $true
            Write-Good "hat recorded"
        }
    }

    if ($bad -gt 0) { Write-Host ''; Write-Warn "$bad entr(y/ies) rejected; nothing saved."; return 1 }

    Export-DeviceMap -Map $map -Path $script:DeviceMapPath
    Write-Host ''
    Write-Good "saved -> $(Split-Path -Leaf $script:DeviceMapPath)"
    Write-Note 'Next:  .\Hotas4.ps1 -Verify'
    return 0
}

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
    <#
        Every axis is shown continuously, live, whether it moves or not. The
        earlier version only printed an axis when it changed by more than 0.08,
        which is no use at all for the question "does this control send
        anything" -- an axis with little travel, or one you are not sure how to
        actuate, just stays silent and looks identical to a dead one.
    #>
    Write-Title 'WATCH' 'live readout of every axis, button and hat'
    $stick = Resolve-Stick
    if (-not $stick) { return 1 }
    Write-Host ''
    Write-Note 'Every axis is shown live. Move a control and watch the bars.'
    Write-Note 'winmm exposes six axes: X Y Z then R U V. If a control moves NONE'
    Write-Note 'of them, winmm cannot see it -- but Reforger uses its own input'
    Write-Note 'layer and may still be able to. Check the game controls screen.'
    Write-Note 'Ctrl+C to stop.'
    Write-Host ''

    $prev = Read-Device $stick.Id
    if (-not $prev) { Write-Bad 'Cannot read the device.'; return 1 }
    $prevHat = $prev.Hat
    $peak = New-Object double[] 6
    foreach ($i in 0..5) { $peak[$i] = 0 }
    $map = Get-Map -Quiet
    $lastButton = '    (no button pressed yet)'
    $lastHat    = '    (hat not moved yet)'

    # winmm field per Reforger axis index, so a reading can be traced back to
    # what Windows itself calls the axis.
    $fieldOf = @{ 0 = 'X'; 1 = 'Y'; 2 = 'Z'; 3 = 'U'; 4 = 'V'; 5 = 'R' }
    $top = [Console]::CursorTop

    while ($true) {
        $now = Read-Device $stick.Id
        if (-not $now) { Start-Sleep -Milliseconds 250; continue }

        [Console]::SetCursorPosition(0, $top)
        foreach ($i in 0..5) {
            $v = $now.Axes[$i]
            $moved = [math]::Abs($v - $prev.Axes[$i])
            if ($moved -gt $peak[$i]) { $peak[$i] = $moved }
            $colour = 'DarkGray'
            if ($peak[$i] -gt 0.1) { $colour = 'Green' }
            $line = '    axis{0} ({1})  {2} {3,7:N2}   moved so far: {4,5:N2}' -f `
                    $i, $fieldOf[$i], (Get-AxisBar $v), $v, $peak[$i]
            Write-Host $line.PadRight(78) -ForegroundColor $colour
        }
        foreach ($i in 0..5) { $prev.Axes[$i] = $now.Axes[$i] }
        Write-Host ''.PadRight(78)

        # Buttons and hat go on fixed lines rather than scrolling, so the axis
        # bars above them stay put and stay readable while you work.
        foreach ($i in (Get-PressedButton -Before $prev.Buttons -Now $now.Buttons)) {
            $label = 'not identified'
            if ($map -and $map.Buttons.ContainsKey("$i")) { $label = Get-ControlLabel $map.Buttons["$i"] }
            $lastButton = '    button{0,-3} {1,-28} joystick0:button{0}' -f $i, $label
        }
        $prev.Buttons = $now.Buttons

        if ($now.Hat -ne $prevHat) {
            $names = Get-HatNames $now.Hat
            if ($names.Count -gt 0) {
                $lastHat = '    hat        {0,-28} joystick0:pov_{1}' -f ($names -join ' + '), $names[0]
            }
            $prevHat = $now.Hat
        }

        Write-Host $lastButton.PadRight(78) -ForegroundColor Green
        Write-Host $lastHat.PadRight(78) -ForegroundColor Cyan

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
elseif ($Register) { $exit = Invoke-Register }
elseif ($Learn)    { $exit = Invoke-Learn }
elseif ($Bind)     { $exit = Invoke-Bind -Pairs $Bind }
elseif ($Audit)    { $exit = Invoke-Audit }
elseif ($KeyTest)  { $exit = Invoke-KeyTest }
elseif ($CheckLog) { $exit = Invoke-CheckLog }
elseif ($Restore)  { $exit = Invoke-Restore }
else               { $exit = Invoke-Menu }

Write-Host ''
exit $exit
