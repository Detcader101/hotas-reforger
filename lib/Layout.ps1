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

# MEASURED, NOT GUESSED. An earlier version of this list was assembled from
# product photographs and reviews, and got the unit wrong in three ways: it
# invented a raised button on the grip and a thumb button on the throttle
# handle that do not exist, and it described the throttle rocker as a
# fore-and-aft paddle when it is a small two-way switch that Thrustmaster
# labels L2 and R2. The list below is what a T.Flight Hotas 4 in PC mode
# actually reports -- twelve buttons, one hat, four live axes -- confirmed by
# an -Identify run against real hardware.

$script:ControlCatalogue = @(
    # --- stick ---------------------------------------------------------------
    @{ Id = 'StickTrigger';   Zone = 'Stick'; Kind = 'Button'
       Label = 'Trigger'
       Fill  = @('TurretFireOnly', 'Fire')
       Where = 'the trigger on the front of the grip, under your index finger' }

    # The stick carries FOUR buttons and one hat. That is the whole of it.
    # Earlier versions of this file invented a "stick top - left", a "stick top -
    # right" and a "side face button" from product photographs, none of which
    # exist under those names. The buttons are labelled L1, L3 and R3.
    @{ Id = 'StickL1'; Zone = 'Stick'; Kind = 'Button'; Ps4 = 'L1'
       Label = 'L1 face button'
       Fill  = @('Von', 'SelectAction')
       Where = 'the button marked L1 on the stick' }

    @{ Id = 'StickL3'; Zone = 'Stick'; Kind = 'Button'; Ps4 = 'L3'
       Label = 'L3 face button'
       Fill  = @('SelectAction', 'CameraType')
       Where = 'the button marked L3 on the stick' }

    @{ Id = 'StickR3'; Zone = 'Stick'; Kind = 'Button'; Ps4 = 'R3'
       Label = 'R3 face button'
       Fill  = @('Freelook', 'CameraType')
       Where = 'the button marked R3 on the stick' }

    # One hat, on the stick head. There is no second hat on this unit.
    @{ Id = 'StickHat';       Zone = 'Stick'; Kind = 'Hat'
       Label = 'Hat switch'
       Where = 'the multi-direction hat on the top of the stick head' }

    # --- throttle ------------------------------------------------------------
    # The four face buttons sit in a diamond under the left thumb.
    @{ Id = 'ThrottleFaceLeft';  Zone = 'Throttle'; Kind = 'Button'; Ps4 = 'Square'
       Label = 'Throttle face - left'
       Where = 'the left-hand button of the four in a diamond on the throttle' }

    @{ Id = 'ThrottleFaceDown';  Zone = 'Throttle'; Kind = 'Button'; Ps4 = 'Cross'
       Label = 'Throttle face - down'
       Where = 'the bottom button of the four in a diamond on the throttle' }

    @{ Id = 'ThrottleFaceRight'; Zone = 'Throttle'; Kind = 'Button'; Ps4 = 'Circle'
       Label = 'Throttle face - right'
       Where = 'the right-hand button of the four in a diamond on the throttle' }

    @{ Id = 'ThrottleFaceUp';    Zone = 'Throttle'; Kind = 'Button'; Ps4 = 'Triangle'
       Label = 'Throttle face - up'
       Fill  = @('Autohover', 'Sights')
       Where = 'the top button of the four in a diamond on the throttle' }

    # L2 and R2 are DEDICATED BUTTONS on the throttle knob. They are not the
    # rocker. An earlier version of this file conflated the two -- it labelled
    # these as the rocker's two ends -- which meant the rocker was never
    # actually tested and these two were described as something they are not.
    @{ Id = 'ThrottleL2'; Zone = 'Throttle'; Kind = 'Button'; Ps4 = 'L2'
       Label = 'Throttle L2 button'
       Fill  = @('VonDirectHold', 'FreelookToggle')
       Where = 'the button marked L2 on the throttle knob' }

    @{ Id = 'ThrottleR2'; Zone = 'Throttle'; Kind = 'Button'; Ps4 = 'R2'
       Label = 'Throttle R2 button'
       Fill  = @('SightsToggle', 'FreelookToggle', 'VonDirectHold')
       Where = 'the button marked R2 on the throttle knob' }

    # The two-way rocker is an ANALOGUE SLIDER, not a pair of buttons. Two wrong
    # calls were made about it before it was measured: first that it was two
    # buttons (so the audit only watched for presses and reported it dead), then
    # that winmm could not read it at all. It reports on winmm's V, which this
    # tool maps to Reforger axis4 -- an inferred index, so worth confirming.
    @{ Id = 'ThrottleRocker'; Zone = 'Throttle'; Kind = 'Axis'
       Label = 'Throttle rocker'
       Where = 'the small two-way rocker on the throttle knob'
       Probe = 'Push the throttle ROCKER fully one way and hold it.'
       Note  = 'Thrustmaster wire this as a second rudder alongside the twist grip' }

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
    @{ Id = 'AxisRoll';     Zone = 'Stick'; Kind = 'Axis'
       Label = 'Stick roll'
       Where = 'move the STICK left and right'
       Probe = 'Move the STICK fully to the RIGHT and hold it.' }

    @{ Id = 'AxisPitch';    Zone = 'Stick'; Kind = 'Axis'
       Label = 'Stick pitch'
       Where = 'move the STICK forward and back'
       Probe = 'Push the STICK fully FORWARD, away from you, and hold it.' }

    @{ Id = 'AxisTwist';    Zone = 'Stick'; Kind = 'Axis'
       Label = 'Stick twist'
       Where = 'twist the grip'
       Probe = 'TWIST the grip CLOCKWISE and hold it.'
       Note  = 'the twist lock on the base has to be released' }

    @{ Id = 'AxisThrottle'; Zone = 'Throttle'; Kind = 'Axis'
       Label = 'Throttle lever'
       Where = 'slide the throttle lever'
       Probe = 'Push the THROTTLE lever fully FORWARD and hold it.' }
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
          NoInput     -Audit found it sends nothing; not bindable by anything
          Unassigned  named but nothing was ever decided about it
          Unnamed     the device reports it and -Identify has never seen it

        NoInput is why $Audit is here. The throttle rocker on a Hotas 4 sends
        no input at all, so demanding a job for it would leave the completeness
        check permanently unsatisfiable -- and the honest report is "this cannot
        be bound", not "you forgot to bind this".
    #>
    param($Map, $Profile, [int] $ButtonCount, [bool] $HasHat, $Audit)

    $rows = @()

    # Controls the audit found to be electrically dead.
    $noInput = @{}
    if ($Audit) {
        foreach ($c in $script:ControlCatalogue) {
            if ((Get-AuditStatus -State $Audit -Id $c.Id) -eq 'Dead') { $noInput[$c.Id] = $true }
        }
    }
    foreach ($id in $noInput.Keys) {
        $c = Get-Control $id
        $rows += @{ Token = '-'; ControlId = $id; Label = $c.Label; Zone = $c.Zone
                    Kind = $c.Kind; Status = 'NoInput'; JobId = $null }
    }

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
            if (Get-Opt $c 'Optional' $false) { continue }

            # A control winmm cannot read is not an oversight and not a dead
            # control -- it is one this tool has no way to measure. Reforger may
            # well see it. The honest status is "tell me its token", not
            # "you forgot this".
            if (Get-Opt $c 'Unreadable' $false) {
                $rows += @{ Token = '-'; ControlId = $c.Id; Label = $c.Label; Zone = $c.Zone
                            Kind = 'Axis'; Status = 'NeedsBind'; JobId = $null }
                continue
            }
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
    <#
        NoInput and Free both pass. Free is a decision; NoInput is a fact about
        the hardware. Neither is an oversight, which is the only thing this is
        looking for.
    #>
    param($Rows)
    foreach ($r in $Rows) { if ($r.Status -eq 'Unnamed' -or $r.Status -eq 'Unassigned') { return $false } }
    return $true
}
