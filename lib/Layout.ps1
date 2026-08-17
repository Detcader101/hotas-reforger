<#
    Layout.ps1 -- what is physically on the stick, and where.

    The point of this file is the thing the old wizard got wrong. That one
    walked the list of game actions and asked "which button do you want for
    this?", so it could finish having never once mentioned the trigger. This
    one walks the list of physical controls and asks what each should do, so a
    control that has no job is a visible hole rather than an omission.

    Two layers, kept apart on purpose:

      device map   winmm index  ->  physical control id     (per unit, learned)
      profile      physical control id -> Reforger actions  (shipped, editable)

    Splitting them is what lets the shipped profile talk about "the trigger"
    instead of "button 0", and survive Thrustmaster shipping a revision that
    enumerates in a different order.
#>

# -----------------------------------------------------------------------------
# The physical control catalogue
# -----------------------------------------------------------------------------
#
# Zone     which hand is on it
# Kind     Button | Hat | Axis
# Where    how to find it without looking it up -- read out during -Identify
# Ps4      the DualShock button this control emulates, where it is known. The
#          Hotas 4 presents itself as a DS4, so these are useful cross-checks,
#          but they are NOT the winmm index and must not be used as one.

$script:ControlCatalogue = @(
    # --- stick ---------------------------------------------------------------
    @{ Id = 'StickTrigger';   Zone = 'Stick';    Kind = 'Button'
       Label = 'Trigger'
       Where = 'the trigger on the front of the grip, under your index finger' }

    @{ Id = 'StickSide';      Zone = 'Stick';    Kind = 'Button'
       Label = 'Side face button'
       Where = 'the large button on the side face of the grip, under your thumb' }

    @{ Id = 'StickTopLeft';   Zone = 'Stick';    Kind = 'Button'
       Label = 'Stick top - left'
       Where = 'the left-hand button on the top of the stick head' }

    @{ Id = 'StickTopRight';  Zone = 'Stick';    Kind = 'Button'
       Label = 'Stick top - right'
       Where = 'the right-hand button on the top of the stick head' }

    @{ Id = 'StickRaised';    Zone = 'Stick';    Kind = 'Button'
       Label = 'Stick raised button'
       Where = 'the raised button on the upper front of the grip, clear of the trigger' }

    @{ Id = 'StickHat';       Zone = 'Stick';    Kind = 'Hat'
       Label = 'Hat switch'
       Where = 'the multi-direction hat on the top of the stick head' }

    # --- throttle ------------------------------------------------------------
    @{ Id = 'ThrottleFaceUp';    Zone = 'Throttle'; Kind = 'Button'
       Label = 'Throttle face - up';    Ps4 = 'Triangle'
       Where = 'the top button of the four in a diamond on the throttle' }

    @{ Id = 'ThrottleFaceRight'; Zone = 'Throttle'; Kind = 'Button'
       Label = 'Throttle face - right'; Ps4 = 'Circle'
       Where = 'the right-hand button of the four in a diamond on the throttle' }

    @{ Id = 'ThrottleFaceDown';  Zone = 'Throttle'; Kind = 'Button'
       Label = 'Throttle face - down';  Ps4 = 'Cross'
       Where = 'the bottom button of the four in a diamond on the throttle' }

    @{ Id = 'ThrottleFaceLeft';  Zone = 'Throttle'; Kind = 'Button'
       Label = 'Throttle face - left';  Ps4 = 'Square'
       Where = 'the left-hand button of the four in a diamond on the throttle' }

    @{ Id = 'ThrottleThumb';     Zone = 'Throttle'; Kind = 'Button'
       Label = 'Throttle thumb button'
       Where = 'the button on the throttle handle itself, under your thumb' }

    @{ Id = 'RockerForward';     Zone = 'Throttle'; Kind = 'Button'
       Label = 'Throttle rocker - forward'
       Where = 'the rocker on the throttle knob, pushed AWAY from you' }

    @{ Id = 'RockerBack';        Zone = 'Throttle'; Kind = 'Button'
       Label = 'Throttle rocker - back'
       Where = 'the same rocker, pulled TOWARDS you' }

    # --- base ----------------------------------------------------------------
    @{ Id = 'BaseLeft';  Zone = 'Base'; Kind = 'Button'; Ps4 = 'Share'
       Label = 'Base button - left'
       Where = 'the left of the small buttons on the throttle base' }

    @{ Id = 'BaseRight'; Zone = 'Base'; Kind = 'Button'; Ps4 = 'Options'
       Label = 'Base button - right'
       Where = 'the right of the small buttons on the throttle base' }

    # --- axes ----------------------------------------------------------------
    # Identified by what they do, not where they are, because that is the only
    # thing that can actually be measured about an axis.
    @{ Id = 'AxisRoll';     Zone = 'Stick';    Kind = 'Axis'
       Label = 'Stick roll'
       Where = 'move the STICK left and right'
       Probe = 'Move the STICK fully to the RIGHT and hold it.' }

    @{ Id = 'AxisPitch';    Zone = 'Stick';    Kind = 'Axis'
       Label = 'Stick pitch'
       Where = 'move the STICK forward and back'
       Probe = 'Push the STICK fully FORWARD, away from you, and hold it.' }

    @{ Id = 'AxisTwist';    Zone = 'Stick';    Kind = 'Axis'
       Label = 'Stick twist'
       Where = 'twist the grip'
       Probe = 'TWIST the grip CLOCKWISE and hold it.'
       Note  = 'the twist lock on the base has to be released' }

    @{ Id = 'AxisThrottle'; Zone = 'Throttle'; Kind = 'Axis'
       Label = 'Throttle lever'
       Where = 'slide the throttle lever'
       Probe = 'Push the THROTTLE lever fully FORWARD and hold it.' }

    @{ Id = 'AxisRocker';   Zone = 'Throttle'; Kind = 'Axis'; Optional = $true
       Label = 'Throttle rocker (as an axis)'
       Where = 'the rocker, if this unit reports it as an analogue axis'
       Probe = 'Push the throttle ROCKER fully AWAY from you and hold it.'
       Note  = 'on most Hotas 4 units the rocker is two buttons, not an axis -- the tool works out which' }
)

function Get-Control {
    param([string] $Id)
    foreach ($c in $script:ControlCatalogue) { if ($c.Id -eq $Id) { return $c } }
    return $null
}

function Get-ControlsByKind {
    param([string] $Kind)
    return ,@($script:ControlCatalogue | Where-Object { $_.Kind -eq $Kind })
}

function Get-ControlLabel {
    param([string] $Id)
    $c = Get-Control $Id
    if ($c) { return $c.Label }
    if ($Id -like 'custom:*') { return $Id.Substring(7) }
    return $Id
}

function Get-ControlZone {
    param([string] $Id)
    $c = Get-Control $Id
    if ($c) { return $c.Zone }
    return 'Other'
}

# -----------------------------------------------------------------------------
# The device map
# -----------------------------------------------------------------------------
#
#   Buttons  @{ '0' = 'StickTrigger'; ... }   winmm button index -> control id
#   Axes     @{ 'AxisRoll' = @{ Index = 0; Sign = '+' }; ... }
#   Hat      $true once seen
#
# Axes store the sign that the probe direction produced, so "push the throttle
# forward" ends up meaning collective up whichever way the hardware counts.

function New-DeviceMap {
    return @{
        Device   = ''
        Vid      = 0
        Pid      = 0
        Verified = $false
        Buttons  = @{}
        Axes     = @{}
        Hat      = $false
    }
}

function Import-DeviceMap {
    param([string] $Path)
    if (-not (Test-Path $Path)) { return $null }
    try { $raw = Get-Content -Raw -Path $Path | ConvertFrom-Json } catch { return $null }

    $map = New-DeviceMap
    foreach ($k in @('Device', 'Vid', 'Pid', 'Verified', 'Hat')) {
        if ($null -ne $raw.$k) { $map[$k] = $raw.$k }
    }
    if ($raw.Buttons) {
        foreach ($p in $raw.Buttons.PSObject.Properties) { $map.Buttons[$p.Name] = [string]$p.Value }
    }
    if ($raw.Axes) {
        foreach ($p in $raw.Axes.PSObject.Properties) {
            $map.Axes[$p.Name] = @{ Index = [int]$p.Value.Index; Sign = [string]$p.Value.Sign }
        }
    }
    return $map
}

function Export-DeviceMap {
    param($Map, [string] $Path)
    $Map | ConvertTo-Json -Depth 5 | Set-Content -Path $Path -Encoding UTF8
}

function Set-MappedButton {
    <# Record index -> control, clearing any earlier claim on either side. #>
    param($Map, [int] $Index, [string] $ControlId)
    foreach ($k in @($Map.Buttons.Keys)) { if ($Map.Buttons[$k] -eq $ControlId) { $Map.Buttons.Remove($k) } }
    $Map.Buttons["$Index"] = $ControlId
}

function Get-MappedButtonIndex {
    param($Map, [string] $ControlId)
    foreach ($k in $Map.Buttons.Keys) { if ($Map.Buttons[$k] -eq $ControlId) { return [int]$k } }
    return $null
}

function Get-UnmappedButtonIndex {
    <# Button indices the device reports that nothing has been said about. #>
    param($Map, [int] $ButtonCount)
    $out = @()
    foreach ($i in 0..($ButtonCount - 1)) { if (-not $Map.Buttons.ContainsKey("$i")) { $out += $i } }
    return ,$out
}

# -----------------------------------------------------------------------------
# Coverage
# -----------------------------------------------------------------------------

function Get-Coverage {
    <#
        The audit the whole tool exists to pass: one row per physical control
        the device actually reports, saying whether it is named and whether it
        does anything.

        Status is one of
          Bound       named and has at least one action
          Free        named and deliberately left with no action
          Unassigned  named but nothing was ever decided about it
          Unnamed     the device reports it and -Identify has never seen it
    #>
    param($Map, $Profile, [int] $ButtonCount, [bool] $HasHat)

    $rows = @()

    foreach ($i in 0..($ButtonCount - 1)) {
        $id = $null
        if ($Map.Buttons.ContainsKey("$i")) { $id = $Map.Buttons["$i"] }
        if (-not $id) {
            $rows += @{ Token = "button$i"; ControlId = $null; Label = "button$i"; Zone = 'Unknown'
                        Kind = 'Button'; Status = 'Unnamed'; JobId = $null }
            continue
        }
        $rows += (New-CoverageRow -Token "button$i" -ControlId $id -Kind 'Button' -Profile $Profile)
    }

    if ($HasHat) {
        if ($Map.Hat) {
            $rows += (New-CoverageRow -Token 'pov' -ControlId 'StickHat' -Kind 'Hat' -Profile $Profile)
        } else {
            $rows += @{ Token = 'pov'; ControlId = 'StickHat'; Label = 'Hat switch'; Zone = 'Stick'
                        Kind = 'Hat'; Status = 'Unnamed'; JobId = $null }
        }
    }

    foreach ($c in (Get-ControlsByKind 'Axis')) {
        if (-not $Map.Axes.ContainsKey($c.Id)) {
            # An optional axis this unit does not have is not a gap. The rocker
            # is the reason: on most Hotas 4 units it is two buttons, and those
            # buttons are audited on their own rows.
            if (Get-Opt $c 'Optional' $false) { continue }
            $rows += @{ Token = '-'; ControlId = $c.Id; Label = $c.Label; Zone = $c.Zone
                        Kind = 'Axis'; Status = 'Unnamed'; JobId = $null }
            continue
        }
        $a = $Map.Axes[$c.Id]
        $rows += (New-CoverageRow -Token ("axis" + $a.Index) -ControlId $c.Id -Kind 'Axis' -Profile $Profile)
    }

    return ,$rows
}

function New-CoverageRow {
    param([string] $Token, [string] $ControlId, [string] $Kind, $Profile)

    $jobId = $null
    if ($Profile -and $Profile.Bind.ContainsKey($ControlId)) { $jobId = $Profile.Bind[$ControlId] }

    $status = 'Unassigned'
    if ($jobId -eq 'Free')      { $status = 'Free' }
    elseif (-not [string]::IsNullOrEmpty($jobId)) { $status = 'Bound' }

    return @{
        Token     = $Token
        ControlId = $ControlId
        Label     = (Get-ControlLabel $ControlId)
        Zone      = (Get-ControlZone $ControlId)
        Kind      = $Kind
        Status    = $status
        JobId     = $jobId
    }
}

function Test-CoverageComplete {
    param($Rows)
    foreach ($r in $Rows) { if ($r.Status -eq 'Unnamed' -or $r.Status -eq 'Unassigned') { return $false } }
    return $true
}
