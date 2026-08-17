<#
    Reforger.ps1 -- what the game can be told to do, and how to write it down.

    PROVENANCE. Arma Reforger publishes no list of bindable actions and ships
    its game data packed, so every name here is sourced, and the source is
    recorded as a tier. Nothing is invented.

      Tier A  Observed. The engine either wrote this name into the joystick
              preset it generates itself, or into InputUserSettings.conf after
              a rebind. These are certain.

      Tier B  Extracted. Present as a plain-text symbol in ArmaReforgerSteam.exe
              in the same string region as the Tier A input-action names
              (offsets ~25.8M-27.4M), and unambiguously an input action rather
              than a class or a property. Very likely correct, not yet watched
              being consumed. Flagged in the UI and reported by -Verify.

    Actions absent from the binary but present in the game's own preset
    (GadgetMap, SelectAction, VONChannel) are script-side, not engine-side.
    That is why they do not appear in the extraction and are Tier A anyway.
#>

# -----------------------------------------------------------------------------
# Jobs -- a control's whole purpose, not a single action
# -----------------------------------------------------------------------------
#
# A profile assigns a JOB to a control, not an action, because most useful
# bindings are more than one action. "Fire" on a trigger has to mean TurretFire
# in a gunner seat and CharacterFire on foot; "Freelook" is a hold and a
# single-click reset on the same button. Bundling them means a profile cannot
# accidentally bind half of a thing.
#
# Button jobs list Actions. Axis jobs list Pos and Neg, applied to whichever
# direction the identify pass measured.

$script:Jobs = @(

    # --- axis jobs -----------------------------------------------------------
    @{ Id = 'CyclicRoll'; Kind = 'Axis'; Tier = 'A'
       Label = 'Cyclic roll'
       Desc  = 'rolls the helicopter, and traverses a turret in a gunner seat'
       Pos = @(@{ Name = 'HelicopterCyclicRight'; Preset = 'right'; Context = 'Helicopter' }
               @{ Name = 'TurretAimRight';        Preset = 'right'; Context = 'Turret' })
       Neg = @(@{ Name = 'HelicopterCyclicLeft';  Preset = 'left';  Context = 'Helicopter' }
               @{ Name = 'TurretAimLeft';         Preset = 'left';  Context = 'Turret' }) }

    @{ Id = 'CyclicPitch'; Kind = 'Axis'; Tier = 'A'
       Label = 'Cyclic pitch'
       Desc  = 'pitches the helicopter, and elevates a turret in a gunner seat'
       Pos = @(@{ Name = 'HelicopterCyclicForward'; Preset = 'forward'; Context = 'Helicopter' }
               @{ Name = 'TurretAimDown';          Preset = 'down';    Context = 'Turret' })
       Neg = @(@{ Name = 'HelicopterCyclicBack';   Preset = 'back';    Context = 'Helicopter' }
               @{ Name = 'TurretAimUp';            Preset = 'up';      Context = 'Turret' }) }

    @{ Id = 'Collective'; Kind = 'Axis'; Tier = 'A'
       Label = 'Collective'
       Desc  = 'raises and lowers the collective'
       Pos = @(@{ Name = 'HelicopterCollectiveIncrease'; Preset = 'up';   Context = 'Helicopter' })
       Neg = @(@{ Name = 'HelicopterCollectiveDecrease'; Preset = 'down'; Context = 'Helicopter' }) }

    @{ Id = 'AntiTorque'; Kind = 'Axis'; Tier = 'A'
       Label = 'Anti-torque'
       Desc  = 'tail rotor, and rotates a turret in a gunner seat'
       Pos = @(@{ Name = 'HelicopterAntiTorqueRight'; Preset = 'right'; Context = 'Helicopter' }
               @{ Name = 'TurretRotateRight';        Preset = 'right'; Context = 'Turret' })
       Neg = @(@{ Name = 'HelicopterAntiTorqueLeft';  Preset = 'left';  Context = 'Helicopter' }
               @{ Name = 'TurretRotateLeft';         Preset = 'left';  Context = 'Turret' }) }

    @{ Id = 'TurretElevation'; Kind = 'Axis'; Tier = 'B'
       Label = 'Turret elevation'
       Desc  = 'raises and lowers a turret without moving the aim point'
       Pos = @(@{ Name = 'TurretRotateUp';   Preset = 'up';   Context = 'Turret' })
       Neg = @(@{ Name = 'TurretRotateDown'; Preset = 'down'; Context = 'Turret' }) }

    # --- hat -----------------------------------------------------------------
    @{ Id = 'FreelookHat'; Kind = 'Hat'; Tier = 'A'
       Label = 'Freelook hat'
       Desc  = 'look around without moving the aircraft'
       Actions = @(
           @{ Name = 'FreelookUp';    Preset = 'up';    Context = 'Global'; Pov = 'pov_up' }
           @{ Name = 'FreelookDown';  Preset = 'down';  Context = 'Global'; Pov = 'pov_down' }
           @{ Name = 'FreelookLeft';  Preset = 'left';  Context = 'Global'; Pov = 'pov_left' }
           @{ Name = 'FreelookRight'; Preset = 'right'; Context = 'Global'; Pov = 'pov_right' }) }

    # --- button jobs ---------------------------------------------------------
    @{ Id = 'Fire'; Kind = 'Button'; Tier = 'A'
       Label = 'Fire'
       Desc  = 'fires the turret you are in, and your weapon on foot'
       Actions = @(@{ Name = 'TurretFire';    Preset = 'hold'; Context = 'Turret' }
                   @{ Name = 'CharacterFire'; Preset = 'hold'; Context = 'Character' }) }

    @{ Id = 'TurretFireOnly'; Kind = 'Button'; Tier = 'A'
       Label = 'Fire (turret only)'
       Desc  = 'fires a turret but never your rifle -- keeps the trigger safe on foot'
       Actions = @(@{ Name = 'TurretFire'; Preset = 'hold'; Context = 'Turret' }) }

    @{ Id = 'Freelook'; Kind = 'Button'; Tier = 'A'
       Label = 'Freelook'
       Desc  = 'hold to look around; a single click recentres'
       Actions = @(@{ Name = 'Freelook';      Preset = 'hold';  Context = 'Global' }
                   @{ Name = 'FreelookReset'; Preset = 'click'; Context = 'Global'; SingleClick = $true }) }

    @{ Id = 'FreelookToggle'; Kind = 'Button'; Tier = 'B'
       Label = 'Freelook toggle'
       Desc  = 'latching freelook -- press once on, once off'
       Actions = @(@{ Name = 'FreelookToggle'; Preset = 'click'; Context = 'Global' }) }

    @{ Id = 'Von'; Kind = 'Button'; Tier = 'A'
       Label = 'Voice (VON)'
       Desc  = 'hold to transmit; a click toggles direct speech'
       Actions = @(@{ Name = 'VONChannel';      Preset = 'hold';  Context = 'Global' }
                   @{ Name = 'VONDirectToggle'; Preset = 'click'; Context = 'Global' }) }

    @{ Id = 'Map'; Kind = 'Button'; Tier = 'A'
       Label = 'Map'
       Desc  = 'opens the map'
       Actions = @(@{ Name = 'GadgetMap'; Preset = 'select'; Context = 'Global' }) }

    @{ Id = 'SelectAction'; Kind = 'Button'; Tier = 'A'
       Label = 'Select action'
       Desc  = 'cycles the context action prompt'
       Actions = @(@{ Name = 'SelectAction'; Preset = 'next'; Context = 'Character' }) }

    @{ Id = 'NextWeapon'; Kind = 'Button'; Tier = 'A'
       Label = 'Next weapon'
       Desc  = 'cycles turret weapons, and your own on foot'
       Actions = @(@{ Name = 'TurretNextWeapon';    Preset = 'click'; Context = 'Turret' }
                   @{ Name = 'CharacterNextWeapon'; Preset = 'click'; Context = 'Character' }) }

    @{ Id = 'Reload'; Kind = 'Button'; Tier = 'A'
       Label = 'Reload'
       Desc  = 'reloads the turret, and your weapon on foot'
       Actions = @(@{ Name = 'TurretReload';    Preset = 'click'; Context = 'Turret' }
                   @{ Name = 'CharacterReload'; Preset = 'click'; Context = 'Character' }) }

    @{ Id = 'TurretReloadOnly'; Kind = 'Button'; Tier = 'A'
       Label = 'Reload (turret only)'
       Desc  = 'reloads a turret and nothing else'
       Actions = @(@{ Name = 'TurretReload'; Preset = 'click'; Context = 'Turret' }) }

    @{ Id = 'Sights'; Kind = 'Button'; Tier = 'B'
       Label = 'Sights / ADS'
       Desc  = 'hold to look down the turret sight, or your own sights on foot'
       Actions = @(@{ Name = 'TurretADSHold';          Preset = 'hold'; Context = 'Turret' }
                   @{ Name = 'CharacterWeaponADSHold'; Preset = 'hold'; Context = 'Character' }) }

    @{ Id = 'Autohover'; Kind = 'Button'; Tier = 'A'
       Label = 'Autohover'
       Desc  = 'toggles the autohover assist'
       Actions = @(@{ Name = 'HelicopterAutohoverToggle'; Preset = 'click'; Context = 'Helicopter' }) }

    @{ Id = 'WheelBrake'; Kind = 'Button'; Tier = 'A'
       Label = 'Wheel brake'
       Desc  = 'momentary brake, held'
       Actions = @(@{ Name = 'HelicopterWheelBrake'; Preset = 'pressed'; Context = 'Helicopter' }) }

    @{ Id = 'ParkingBrake'; Kind = 'Button'; Tier = 'A'
       Label = 'Parking brake'
       Desc  = 'the brake that stays on after you let go'
       Actions = @(@{ Name = 'HelicopterWheelBrakePersistent'; Preset = 'pressed'; Context = 'Helicopter' }) }

    @{ Id = 'EngineStart'; Kind = 'Button'; Tier = 'B'
       Label = 'Engine start'
       Desc  = 'starts the helicopter, and a ground vehicle you are driving'
       Actions = @(@{ Name = 'HelicopterEngineStart'; Preset = 'click'; Context = 'Helicopter' }
                   @{ Name = 'VehicleEngineStart';    Preset = 'click'; Context = 'Vehicle' }) }

    @{ Id = 'EngineStop'; Kind = 'Button'; Tier = 'B'; Hazard = $true
       Label = 'Engine stop'
       Desc  = 'cuts the engine'
       Hazard_Note = 'An engine cut on a button you can brush is an engine cut in the air. Put it somewhere recessed, or leave it on the keyboard.'
       Actions = @(@{ Name = 'HelicopterEngineStop'; Preset = 'click'; Context = 'Helicopter' }
                   @{ Name = 'VehicleEngineStop';    Preset = 'click'; Context = 'Vehicle' }) }

    @{ Id = 'CameraType'; Kind = 'Button'; Tier = 'A'
       Label = 'Camera view'
       Desc  = 'switches between first and third person'
       Actions = @(@{ Name = 'SwitchCameraType'; Preset = 'click'; Context = 'Global' }) }

    @{ Id = 'Zoom'; Kind = 'Button'; Tier = 'B'
       Label = 'Zoom'
       Desc  = 'hold to zoom the view'
       Actions = @(@{ Name = 'CharacterFocus'; Preset = 'hold'; Context = 'Character' }) }

    @{ Id = 'Horn'; Kind = 'Button'; Tier = 'B'
       Label = 'Horn'
       Desc  = 'ground vehicle horn'
       Actions = @(@{ Name = 'VehicleHorn'; Preset = 'hold'; Context = 'Vehicle' }) }

    @{ Id = 'Lights'; Kind = 'Button'; Tier = 'B'
       Label = 'Lights'
       Desc  = 'toggles vehicle lights'
       Actions = @(@{ Name = 'VehicleLightsToggle'; Preset = 'click'; Context = 'Vehicle' }) }
)

function Get-Job {
    param([string] $Id)
    foreach ($j in $script:Jobs) { if ($j.Id -eq $Id) { return $j } }
    return $null
}

function Get-JobsByKind {
    param([string] $Kind)
    return ,@($script:Jobs | Where-Object { $_.Kind -eq $Kind })
}

function Get-JobLabel {
    param([string] $Id)
    if ($Id -eq 'Free') { return '(deliberately free)' }
    $j = Get-Job $Id
    if ($j) { return $j.Label }
    return $Id
}

function Get-JobActionNames {
    param($Job)
    if (-not $Job) { return ,@() }
    $names = @()
    foreach ($key in @('Actions', 'Pos', 'Neg')) {
        if ($Job.ContainsKey($key)) { foreach ($a in $Job[$key]) { $names += $a.Name } }
    }
    return ,$names
}

# -----------------------------------------------------------------------------
# Profiles -- which control does which job
# -----------------------------------------------------------------------------
#
# Every button in the control catalogue appears in every profile. That is the
# rule the whole tool is built around: if a control is not here, -Verify fails
# and says so. To leave one alone on purpose, say 'Free' -- an explicit
# decision, which reads differently from an oversight and is treated as one.

$script:Profiles = @(
    @{
        Id    = 'helicopter'
        Label = 'Helicopter and door gunner'
        Desc  = 'Everything on the stick flies or shoots. No on-foot actions, so nothing here can fire your rifle while you are walking around.'
        Bind  = @{
            AxisRoll     = 'CyclicRoll'
            AxisPitch    = 'CyclicPitch'
            AxisThrottle = 'Collective'
            AxisTwist    = 'AntiTorque'
            AxisRocker   = 'AntiTorque'

            StickHat     = 'FreelookHat'

            StickTrigger  = 'TurretFireOnly'
            StickSide     = 'Freelook'
            StickTopLeft  = 'Von'
            StickTopRight = 'Map'
            StickRaised   = 'CameraType'

            RockerForward = 'NextWeapon'
            RockerBack    = 'TurretReloadOnly'

            ThrottleFaceUp    = 'Autohover'
            ThrottleFaceDown  = 'WheelBrake'
            ThrottleFaceLeft  = 'ParkingBrake'
            ThrottleFaceRight = 'SelectAction'
            ThrottleThumb     = 'Sights'

            BaseLeft  = 'EngineStart'
            BaseRight = 'EngineStop'
        }
    }

    @{
        Id    = 'full'
        Label = 'Fly, gun and fight on foot'
        Desc  = 'As above, but the trigger and reload also work when you are out of the aircraft. Convenient if the stick is the only thing you touch; it does mean the trigger fires your rifle.'
        Bind  = @{
            AxisRoll     = 'CyclicRoll'
            AxisPitch    = 'CyclicPitch'
            AxisThrottle = 'Collective'
            AxisTwist    = 'AntiTorque'
            AxisRocker   = 'AntiTorque'

            StickHat     = 'FreelookHat'

            StickTrigger  = 'Fire'
            StickSide     = 'Freelook'
            StickTopLeft  = 'Von'
            StickTopRight = 'Map'
            StickRaised   = 'CameraType'

            RockerForward = 'NextWeapon'
            RockerBack    = 'Reload'

            ThrottleFaceUp    = 'Autohover'
            ThrottleFaceDown  = 'WheelBrake'
            ThrottleFaceLeft  = 'ParkingBrake'
            ThrottleFaceRight = 'SelectAction'
            ThrottleThumb     = 'Sights'

            BaseLeft  = 'EngineStart'
            BaseRight = 'EngineStop'
        }
    }

    @{
        Id    = 'conservative'
        Label = 'Confirmed actions only'
        Desc  = 'Drops every Tier B action, so nothing in the file has gone unobserved. Costs you sights, engine start and engine stop, which move to explicit Free.'
        Bind  = @{
            AxisRoll     = 'CyclicRoll'
            AxisPitch    = 'CyclicPitch'
            AxisThrottle = 'Collective'
            AxisTwist    = 'AntiTorque'
            AxisRocker   = 'AntiTorque'

            StickHat     = 'FreelookHat'

            StickTrigger  = 'TurretFireOnly'
            StickSide     = 'Freelook'
            StickTopLeft  = 'Von'
            StickTopRight = 'Map'
            StickRaised   = 'CameraType'

            RockerForward = 'NextWeapon'
            RockerBack    = 'Reload'

            ThrottleFaceUp    = 'Autohover'
            ThrottleFaceDown  = 'WheelBrake'
            ThrottleFaceLeft  = 'ParkingBrake'
            ThrottleFaceRight = 'SelectAction'
            ThrottleThumb     = 'Free'

            BaseLeft  = 'Free'
            BaseRight = 'Free'
        }
    }
)

function Get-Profile {
    param([string] $Id)
    foreach ($p in $script:Profiles) { if ($p.Id -eq $Id) { return $p } }
    return $null
}

function Copy-Profile {
    <# Deep enough copy that editing a binding cannot mutate the shipped table. #>
    param($Profile)
    $bind = @{}
    foreach ($k in $Profile.Bind.Keys) { $bind[$k] = $Profile.Bind[$k] }
    return @{ Id = $Profile.Id; Label = $Profile.Label; Desc = $Profile.Desc; Bind = $bind }
}

function Import-Profile {
    param([string] $Path)
    if (-not (Test-Path $Path)) { return $null }
    try { $raw = Get-Content -Raw -Path $Path | ConvertFrom-Json } catch { return $null }
    $bind = @{}
    if ($raw.Bind) { foreach ($p in $raw.Bind.PSObject.Properties) { $bind[$p.Name] = [string]$p.Value } }
    return @{ Id = [string]$raw.Id; Label = [string]$raw.Label; Desc = [string]$raw.Desc; Bind = $bind }
}

function Export-Profile {
    param($Profile, [string] $Path)
    $Profile | ConvertTo-Json -Depth 4 | Set-Content -Path $Path -Encoding UTF8
}

function Get-TierBActions {
    <#
        Which Tier B action names are actually in this set of resolved bindings.

        Deliberately driven off the bindings rather than the profile: a profile
        entry for a control the unit does not have never reaches the file, and
        reporting it as unconfirmed would be telling the user to go and verify
        something that is not there.
    #>
    param($Bindings)
    $tierB = @{}
    foreach ($j in $script:Jobs) {
        if ($j.Tier -ne 'B') { continue }
        foreach ($n in (Get-JobActionNames $j)) { $tierB[$n] = $true }
    }
    $out = @()
    foreach ($b in $Bindings) { if ($tierB.ContainsKey($b.Action)) { $out += $b.Action } }
    return ,@($out | Sort-Object -Unique)
}

# -----------------------------------------------------------------------------
# Building the config file
# -----------------------------------------------------------------------------

# Reforger identifies every input source by a 16-hex-digit id. They only have to
# be unique within the file, so a fixed prefix and a counter keeps generated
# files byte-stable and lets you diff two runs. The prefix is ours, not
# Reforger's, so a generated file is recognisable at a glance.
$script:IdPrefix = '7CB1F0A54D'

function New-IdSeries { return [pscustomobject]@{ Next = 1 } }

function Get-NextId {
    param($Series)
    $id = '{0}{1:X6}' -f $script:IdPrefix, $Series.Next
    $Series.Next++
    return $id
}

function Test-InputToken {
    param([string] $Token)
    return $Token -match '^joystick\d+:(button\d+|axis[0-5][+-]|pov_(up|down|left|right))$'
}

$script:ValidPresets = @('left', 'right', 'up', 'down', 'forward', 'back',
                         'hold', 'click', 'pressed', 'select', 'next', 'toggle', 'value')

function Test-FilterPreset { param([string] $Preset) return $script:ValidPresets -contains $Preset }

function New-ActionBlock {
    <#
        One Action { } block. Sources is a list so an action can legitimately be
        driven by more than one input -- the Hotas 4's twist grip and rudder
        rocker feeding the same anti-torque action, for instance.
    #>
    param([string] $Name, $Sources, $Series)
    $lines = @()
    $lines += "  Action $Name {"
    $lines += "   InputSource InputSourceSum `"{$(Get-NextId $Series)}`" {"
    $lines += '    Sources {'
    foreach ($s in $Sources) {
        $lines += "     InputSourceValue `"{$(Get-NextId $Series)}`" {"
        $lines += "      FilterPreset `"$($s.Preset)`""
        $lines += "      Input `"$($s.Token)`""
        if ($s.SingleClick) {
            $lines += "      Filter InputFilterSingleClick `"{$(Get-NextId $Series)}`" {"
            $lines += '      }'
        }
        $lines += '     }'
    }
    $lines += '    }'
    $lines += '   }'
    $lines += '  }'
    return $lines
}

function Resolve-Bindings {
    <#
        Turn (device map + profile) into an ordered list of

            @{ Action = 'HelicopterCyclicLeft'
               Sources = @(@{ Token='joystick0:axis0-'; Preset='left' }) }

        Actions are merged, not overwritten: if two controls drive the same
        action, both end up as sources on it. Anything the device map has no
        entry for is dropped silently, because a control this unit does not
        have is not a missing binding.
    #>
    param($Map, $Profile, [string] $Prefix = 'joystick0')

    # An ordered hashtable keeps first-seen order, so a generated file lists
    # actions in control-catalogue order and two runs diff cleanly.
    $byAction = [ordered]@{}

    foreach ($c in $script:ControlCatalogue) {
        if (-not $Profile.Bind.ContainsKey($c.Id)) { continue }
        $jobId = $Profile.Bind[$c.Id]
        if (-not $jobId -or $jobId -eq 'Free') { continue }
        $job = Get-Job $jobId
        if (-not $job) { continue }

        # (action name, token, preset, single-click) tuples this control adds.
        $adds = @()

        if ($c.Kind -eq 'Button') {
            $idx = Get-MappedButtonIndex -Map $Map -ControlId $c.Id
            if ($null -eq $idx) { continue }
            foreach ($a in $job.Actions) {
                $adds += @{ Action = $a.Name; Token = "${Prefix}:button$idx"; Preset = $a.Preset
                            SingleClick = [bool](Get-Opt $a 'SingleClick' $false) }
            }
        }
        elseif ($c.Kind -eq 'Hat') {
            if (-not $Map.Hat) { continue }
            foreach ($a in $job.Actions) {
                $adds += @{ Action = $a.Name; Token = "${Prefix}:$($a.Pov)"; Preset = $a.Preset
                            SingleClick = $false }
            }
        }
        elseif ($c.Kind -eq 'Axis') {
            if (-not $Map.Axes.ContainsKey($c.Id)) { continue }
            $ax = $Map.Axes[$c.Id]
            # The identify pass recorded which way the control physically went,
            # so an inverted throttle resolves here rather than in the user's head.
            $posSign = $ax.Sign
            $negSign = '+'
            if ($posSign -eq '+') { $negSign = '-' }
            foreach ($a in $job.Pos) {
                $adds += @{ Action = $a.Name; Token = "${Prefix}:axis$($ax.Index)$posSign"; Preset = $a.Preset
                            SingleClick = $false }
            }
            foreach ($a in $job.Neg) {
                $adds += @{ Action = $a.Name; Token = "${Prefix}:axis$($ax.Index)$negSign"; Preset = $a.Preset
                            SingleClick = $false }
            }
        }

        foreach ($add in $adds) {
            if (-not $byAction.Contains($add.Action)) { $byAction[$add.Action] = @() }

            # An InputSourceSum adds its sources together, so the same token
            # listed twice on one action doubles that input. The Hotas 4's twist
            # grip and rudder rocker are one physical axis, and both map to
            # anti-torque, so this is reachable in the shipped profile: full
            # right rudder would ask for two units of right rudder.
            $dupe = $false
            foreach ($existing in @($byAction[$add.Action])) {
                if ($existing.Token -eq $add.Token) { $dupe = $true }
            }
            if ($dupe) { continue }

            $byAction[$add.Action] = @($byAction[$add.Action]) + @{
                Token = $add.Token; Preset = $add.Preset; SingleClick = $add.SingleClick
                ControlId = $c.Id }
        }
    }

    $out = @()
    foreach ($name in $byAction.Keys) { $out += @{ Action = $name; Sources = @($byAction[$name]) } }
    return ,$out
}

function Build-Config {
    <#
        The whole file. $Preserve is a list of raw Action { } blocks read out of
        an existing config whose action names this tool knows nothing about --
        a mod's, usually. They are copied through verbatim rather than dropped,
        because silently deleting someone's binding is worse than not
        understanding it.
    #>
    param($Bindings, [string[]] $Preserve = @())
    $series = New-IdSeries
    $lines = @('ActionManager {', ' Actions {')
    foreach ($b in $Bindings) { $lines += (New-ActionBlock -Name $b.Action -Sources $b.Sources -Series $series) }
    foreach ($raw in $Preserve) { $lines += $raw.TrimEnd("`r", "`n").Split("`n") | ForEach-Object { $_.TrimEnd("`r") } }
    $lines += ' }'
    $lines += '}'
    return (($lines -join "`r`n") + "`r`n")
}

# -----------------------------------------------------------------------------
# Reading an existing config back
# -----------------------------------------------------------------------------

function Read-Config {
    <#
        Pulls action name -> list of (token, preset) out of a config, and keeps
        the raw text of each Action block so unknown ones can be preserved.
        Deliberately a line scanner rather than a real parser: the format is
        one-statement-per-line and generated, and a parser would be more code
        to get wrong.
    #>
    param([string] $Path)
    $result = @{ Actions = [ordered]@{}; Raw = @{}; Text = '' }
    if (-not (Test-Path $Path)) { return $result }

    $text = Get-Content -Raw -Path $Path
    $result.Text = $text
    $lines = $text -split "`r?`n"

    $i = 0
    while ($i -lt $lines.Count) {
        $m = [regex]::Match($lines[$i], '^\s*Action\s+(\w+)\s*\{')
        if (-not $m.Success) { $i++; continue }

        $name = $m.Groups[1].Value
        $depth = 0
        $block = @()
        $sources = @()
        $preset = $null

        while ($i -lt $lines.Count) {
            $line = $lines[$i]
            $block += $line
            $depth += ([regex]::Matches($line, '\{')).Count
            $depth -= ([regex]::Matches($line, '\}')).Count

            $pm = [regex]::Match($line, '^\s*FilterPreset\s+"([^"]*)"')
            if ($pm.Success) { $preset = $pm.Groups[1].Value }
            $im = [regex]::Match($line, '^\s*Input\s+"([^"]*)"')
            if ($im.Success) { $sources += @{ Token = $im.Groups[1].Value; Preset = $preset } }

            $i++
            if ($depth -le 0) { break }
        }

        $result.Actions[$name] = $sources
        $result.Raw[$name] = ($block -join "`r`n")
    }
    return $result
}

function Get-UnknownActionBlock {
    <# Raw blocks for actions no job in this tool produces. #>
    param($Parsed)
    $known = @{}
    foreach ($j in $script:Jobs) { foreach ($n in (Get-JobActionNames $j)) { $known[$n] = $true } }
    $out = @()
    foreach ($name in $Parsed.Actions.Keys) { if (-not $known.ContainsKey($name)) { $out += $Parsed.Raw[$name] } }
    return ,$out
}

# -----------------------------------------------------------------------------
# Validation -- run before anything touches the disk
# -----------------------------------------------------------------------------

function Test-Config {
    <#
        Structural check on generated text. Returns a list of problems; empty
        means it is safe to write. A malformed config is worse than no config:
        Reforger will drop the lot and give you a stick that does nothing, with
        no error you would notice.
    #>
    param([string] $Text)
    $problems = @()

    $open  = ([regex]::Matches($Text, '\{')).Count
    $close = ([regex]::Matches($Text, '\}')).Count
    if ($open -ne $close) { $problems += "brace mismatch: $open '{' against $close '}'" }

    if ($Text -notmatch '(?m)^ActionManager \{') { $problems += 'missing ActionManager block' }
    if ($Text -notmatch '(?m)^ Actions \{')      { $problems += 'missing Actions block' }

    $names = @{}
    foreach ($m in [regex]::Matches($Text, '(?m)^\s*Action\s+(\w+)\s*\{')) {
        $n = $m.Groups[1].Value
        if ($names.ContainsKey($n)) { $problems += "action '$n' declared more than once" }
        $names[$n] = $true
    }
    if ($names.Count -eq 0) { $problems += 'no actions in the file' }

    $ids = @{}
    foreach ($m in [regex]::Matches($Text, '"\{([0-9A-Fa-f]{16})\}"')) {
        $id = $m.Groups[1].Value
        if ($ids.ContainsKey($id)) { $problems += "input source id {$id} used more than once" }
        $ids[$id] = $true
    }

    foreach ($m in [regex]::Matches($Text, '(?m)^\s*Input\s+"([^"]*)"')) {
        $t = $m.Groups[1].Value
        if (-not (Test-InputToken $t)) { $problems += "unrecognised input token '$t'" }
    }

    foreach ($m in [regex]::Matches($Text, '(?m)^\s*FilterPreset\s+"([^"]*)"')) {
        $p = $m.Groups[1].Value
        if (-not (Test-FilterPreset $p)) { $problems += "unrecognised filter preset '$p'" }
    }

    return ,$problems
}

function Get-BindingConflict {
    <#
        Two actions fighting over one input. Three things that look like clashes
        and are not, all of which the shipped profile relies on:

          cyclic and turret aim on the stick   different contexts, different seats
          freelook hold and freelook reset     one job, deliberately stacked
          VON transmit and direct toggle       likewise

        So a conflict is: same context, same token, and coming from two
        different physical controls -- which only happens if a device map has
        been hand-edited into an impossible state, or a profile has been.
    #>
    param($Bindings)

    # action name -> context, built once from the job table
    $context = @{}
    foreach ($j in $script:Jobs) {
        foreach ($key in @('Actions', 'Pos', 'Neg')) {
            foreach ($a in @(Get-Opt $j $key @())) { $context[$a.Name] = $a.Context }
        }
    }

    $seen = @{}
    $out = @()
    foreach ($b in $Bindings) {
        $ctx = 'Global'
        if ($context.ContainsKey($b.Action)) { $ctx = $context[$b.Action] }
        foreach ($s in $b.Sources) {
            $control = Get-Opt $s 'ControlId' ''
            $key = "$ctx|$($s.Token)"
            if ($seen.ContainsKey($key)) {
                if ($seen[$key].Control -eq $control) { continue }
                $out += ("$($seen[$key].Action) and $($b.Action) are both on $($s.Token) " +
                         "in the $ctx context, from different controls")
            } else {
                $seen[$key] = @{ Action = $b.Action; Control = $control }
            }
        }
    }
    return ,$out
}
