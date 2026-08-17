<#
    Device.ps1 -- reading the stick.

    Uses winmm (joyGetDevCaps / joyGetPosEx) rather than DirectInput because it
    needs no SDK, no extra assembly and no window handle, and it reports button
    and POV state in the same order DirectInput does.

    AXIS ORDER. winmm names axes X, Y, Z, R, U, V. Arma Reforger names them
    axis0..axis5 in DirectInput order: X, Y, Z, Rx, Ry, Rz. X/Y/Z line up
    exactly. R is the rudder, which on every stick this tool targets is Rz, so
    R -> axis5. U and V fall through to axis3/axis4; nothing on a T.Flight
    Hotas 4 uses them, and if a device does, confirm the token in Reforger's own
    rebinding screen before trusting it.
#>

$script:WinmmLoaded = $false

# winmm axis field order, in the Reforger axis index each one maps to.
$script:AxisOrder = @(
    @{ Field = 'dwXpos'; Index = 0; Winmm = 'X' }
    @{ Field = 'dwYpos'; Index = 1; Winmm = 'Y' }
    @{ Field = 'dwZpos'; Index = 2; Winmm = 'Z' }
    @{ Field = 'dwUpos'; Index = 3; Winmm = 'U' }
    @{ Field = 'dwVpos'; Index = 4; Winmm = 'V' }
    @{ Field = 'dwRpos'; Index = 5; Winmm = 'R' }
)

$script:HatDirections = @(
    @{ Degrees =     0; Names = @('up') }
    @{ Degrees =  4500; Names = @('up', 'right') }
    @{ Degrees =  9000; Names = @('right') }
    @{ Degrees = 13500; Names = @('down', 'right') }
    @{ Degrees = 18000; Names = @('down') }
    @{ Degrees = 22500; Names = @('down', 'left') }
    @{ Degrees = 27000; Names = @('left') }
    @{ Degrees = 31500; Names = @('up', 'left') }
)

function Initialize-Device {
    if ($script:WinmmLoaded) { return }
    Add-Type @'
using System;
using System.Runtime.InteropServices;

public static class Winmm
{
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Ansi)]
    public struct JOYCAPS
    {
        public ushort wMid, wPid;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string szPname;
        public uint wXmin, wXmax, wYmin, wYmax, wZmin, wZmax;
        public uint wNumButtons, wPeriodMin, wPeriodMax;
        public uint wRmin, wRmax, wUmin, wUmax, wVmin, wVmax;
        public uint wCaps, wMaxAxes, wNumAxes, wMaxButtons;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)]  public string szRegKey;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 260)] public string szOEMVxD;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct JOYINFOEX
    {
        public uint dwSize, dwFlags;
        public uint dwXpos, dwYpos, dwZpos, dwRpos, dwUpos, dwVpos;
        public uint dwButtons, dwButtonNumber, dwPOV, dwReserved1, dwReserved2;
    }

    [DllImport("winmm.dll", EntryPoint = "joyGetDevCapsA")]
    private static extern uint _caps(UIntPtr id, ref JOYCAPS c, uint size);
    [DllImport("winmm.dll", EntryPoint = "joyGetPosEx")]
    private static extern uint _pos(uint id, ref JOYINFOEX info);

    // Windows PowerShell 5.1 will not cast int -> UIntPtr, so the shim is here.
    public static uint Caps(uint id, ref JOYCAPS c) {
        return _caps((UIntPtr)id, ref c, (uint)Marshal.SizeOf(typeof(JOYCAPS)));
    }
    public static uint Pos(uint id, ref JOYINFOEX i) {
        i.dwSize  = (uint)Marshal.SizeOf(typeof(JOYINFOEX));
        i.dwFlags = 0xFF;   // JOY_RETURNALL
        return _pos(id, ref i);
    }
}
'@
    $script:WinmmLoaded = $true
}

function ConvertTo-Unit {
    param([uint32] $Raw)
    # winmm reports 0..65535 regardless of the device's own range.
    return [math]::Round((($Raw / 65535.0) * 2.0) - 1.0, 4)
}

function Get-Joystick {
    <# Every joystick winmm can see, in winmm id order. #>
    Initialize-Device
    $found = @()
    foreach ($id in 0..15) {
        $caps = New-Object Winmm+JOYCAPS
        if ([Winmm]::Caps([uint32]$id, [ref]$caps) -ne 0) { continue }
        if ([string]::IsNullOrWhiteSpace($caps.szPname)) { continue }
        $found += @{
            Id          = [uint32]$id
            Vid         = [int]$caps.wMid
            Pid         = [int]$caps.wPid
            Name        = $caps.szPname.Trim()
            AxisCount   = [int]$caps.wNumAxes
            ButtonCount = [int]$caps.wNumButtons
            HasHat      = [bool]($caps.wCaps -band 0x10)   # JOYCAPS_HASPOV
        }
    }
    return ,$found
}

# 0x044F Thrustmaster; 0xB67C is the Hotas 4 in PC mode, 0xB67B the same unit
# left in PS4 mode -- which enumerates but reports a different control set.
$script:ThrustmasterVid = 0x044F
$script:Hotas4PcPid     = 0xB67C
$script:Hotas4Ps4Pid    = 0xB67B

function Select-Hotas {
    <#
        Pick the stick to work with. A Hotas 4 in PC mode wins outright; failing
        that any Thrustmaster; failing that the first stick attached, which the
        caller is expected to warn about.
    #>
    param($Sticks)
    if (-not $Sticks -or $Sticks.Count -eq 0) { return $null }
    foreach ($s in $Sticks) {
        if ($s.Vid -eq $script:ThrustmasterVid -and $s.Pid -eq $script:Hotas4PcPid) { return $s }
    }
    foreach ($s in $Sticks) { if ($s.Vid -eq $script:ThrustmasterVid) { return $s } }
    return $Sticks[0]
}

function Get-DeviceWarning {
    <# Things about the attached device that will bite later. #>
    param($Stick)
    $out = @()
    if (-not $Stick) { return ,$out }
    if ($Stick.Vid -eq $script:ThrustmasterVid -and $Stick.Pid -eq $script:Hotas4Ps4Pid) {
        $out += 'This is a T.Flight Hotas 4 in PS4 mode. Slide the switch on the base to PC and replug, or Reforger will see the wrong control set.'
    }
    elseif ($Stick.Vid -ne $script:ThrustmasterVid) {
        $out += "This is not a Thrustmaster device ($($Stick.Name)). The tool will still work, but run -Identify first: none of the shipped layout applies."
    }
    if ($Stick.ButtonCount -lt 12) {
        $out += "Only $($Stick.ButtonCount) buttons reported; a Hotas 4 in PC mode reports 12."
    }
    if (-not $Stick.HasHat) { $out += 'No hat switch reported.' }
    return ,$out
}

function Read-Device {
    <#
        One snapshot. Axes come back as a 6-element array indexed by Reforger
        axis number, so $r.Axes[5] is what "joystick0:axis5" refers to.
    #>
    param([uint32] $Id)
    Initialize-Device
    $info = New-Object Winmm+JOYINFOEX
    if ([Winmm]::Pos($Id, [ref]$info) -ne 0) { return $null }

    $axes = New-Object double[] 6
    foreach ($a in $script:AxisOrder) { $axes[$a.Index] = ConvertTo-Unit $info.$($a.Field) }

    return @{
        Axes    = $axes
        Buttons = [uint32]$info.dwButtons
        Hat     = [int]$info.dwPOV        # 65535 = centred
    }
}

function Test-ButtonDown {
    param([uint32] $Mask, [int] $Index)
    # 1 -shl 31 overflows a signed int, so shift a long and narrow afterwards.
    return [bool]($Mask -band [uint32](1L -shl $Index))
}

function Get-PressedButton {
    <# Indices newly down in $Now that were up in $Before. #>
    param([uint32] $Before, [uint32] $Now, [int] $Count = 32)
    $out = @()
    foreach ($i in 0..($Count - 1)) {
        if ((Test-ButtonDown $Now $i) -and -not (Test-ButtonDown $Before $i)) { $out += $i }
    }
    return ,$out
}

function Get-HatNames {
    <# Reforger token suffixes for a POV reading; empty when centred. #>
    param([int] $Degrees)
    if ($Degrees -lt 0 -or $Degrees -ge 36000) { return ,@() }
    foreach ($d in $script:HatDirections) { if ($d.Degrees -eq $Degrees) { return ,$d.Names } }
    return ,@()
}

function Find-MovedAxis {
    <#
        The axis that moved furthest from its resting value, if any moved past
        $Threshold. Returns the axis index and which way it went, so the caller
        never has to ask the user "was that positive or negative".
    #>
    param($Baseline, $Current, [double] $Threshold = 0.45)
    $best = $null
    foreach ($i in 0..5) {
        $delta = $Current[$i] - $Baseline[$i]
        $size = [math]::Abs($delta)
        if ($size -lt $Threshold) { continue }
        if ($null -eq $best -or $size -gt $best.Size) {
            $sign = '+'
            if ($delta -lt 0) { $sign = '-' }
            $best = @{ Index = $i; Sign = $sign; Size = $size; Value = $Current[$i] }
        }
    }
    return $best
}

function Wait-DeviceStill {
    <#
        Block until nothing has moved for $StillMs, then return the resting axis
        values. Called before every read so that a stick still springing back
        from the last step is not mistaken for the next input.
    #>
    param([uint32] $Id, [int] $StillMs = 350, [int] $TimeoutMs = 6000)
    $last = Read-Device $Id
    if (-not $last) { return $null }
    $still = 0
    $spent = 0
    while ($spent -lt $TimeoutMs) {
        Start-Sleep -Milliseconds 40
        $spent += 40
        $now = Read-Device $Id
        if (-not $now) { return $null }
        $moved = $false
        foreach ($i in 0..5) { if ([math]::Abs($now.Axes[$i] - $last.Axes[$i]) -gt 0.06) { $moved = $true } }
        if ($now.Buttons -ne $last.Buttons -or $now.Hat -ne $last.Hat) { $moved = $true }
        $last = $now
        if ($moved) { $still = 0 } else { $still += 40 }
        if ($still -ge $StillMs) { break }
    }
    return $last
}

<#
    Wait for the user to actuate one control and report what it actually was.

    The caller says what it expects ('Button', 'Axis', 'Hat', or 'Any'); this
    reports what the hardware did. Those two disagreeing is information, not an
    error -- it is how the tool discovers that a rocker some other stick exposes
    as an axis is two buttons on this one.

    Returns a hashtable with Kind = Button | Axis | Hat | Key.
#>
function Wait-Control {
    param(
        [uint32]   $Id,
        [string]   $Accept = 'Any',
        [string[]] $Keys = @('s', 'b', 'q'),
        [int]      $TimeoutMs = 60000,
        [scriptblock] $OnTick
    )
    $rest = Wait-DeviceStill $Id
    if (-not $rest) { return @{ Kind = 'Gone' } }

    Clear-KeyBuffer
    $baselineButtons = $rest.Buttons
    $spent = 0
    while ($spent -lt $TimeoutMs) {
        if (Test-KeyWaiting) {
            $k = Read-KeyChar
            if ($Keys -contains $k) { return @{ Kind = 'Key'; Key = $k } }
        }

        $now = Read-Device $Id
        if (-not $now) { return @{ Kind = 'Gone' } }
        if ($OnTick) { & $OnTick $now }

        if ($Accept -eq 'Any' -or $Accept -eq 'Button') {
            $pressed = Get-PressedButton -Before $baselineButtons -Now $now.Buttons
            if ($pressed.Count -gt 0) { return @{ Kind = 'Button'; Index = $pressed[0] } }
            # Let go of a button held over from the last step and it stops
            # counting as "already down" -- otherwise it can never be read.
            $baselineButtons = $baselineButtons -band $now.Buttons
        }

        if ($Accept -eq 'Any' -or $Accept -eq 'Hat') {
            $names = Get-HatNames $now.Hat
            if ($names.Count -gt 0) { return @{ Kind = 'Hat'; Directions = $names } }
        }

        if ($Accept -eq 'Any' -or $Accept -eq 'Axis') {
            $moved = Find-MovedAxis -Baseline $rest.Axes -Current $now.Axes
            if ($moved) { return @{ Kind = 'Axis'; Index = $moved.Index; Sign = $moved.Sign; Value = $moved.Value } }
        }

        Start-Sleep -Milliseconds 25
        $spent += 25
    }
    return @{ Kind = 'Timeout' }
}

function Get-RestingDrift {
    <#
        How far each axis wanders while untouched. Reforger has no deadzone
        setting, so anything much above zero here has to be fixed in the
        Thrustmaster control panel, not in the config this tool writes.
    #>
    param([uint32] $Id, [int] $SampleMs = 1200)
    $min = New-Object double[] 6
    $max = New-Object double[] 6
    $first = Read-Device $Id
    if (-not $first) { return $null }
    foreach ($i in 0..5) { $min[$i] = $first.Axes[$i]; $max[$i] = $first.Axes[$i] }
    $spent = 0
    while ($spent -lt $SampleMs) {
        $r = Read-Device $Id
        if ($r) {
            foreach ($i in 0..5) {
                if ($r.Axes[$i] -lt $min[$i]) { $min[$i] = $r.Axes[$i] }
                if ($r.Axes[$i] -gt $max[$i]) { $max[$i] = $r.Axes[$i] }
            }
        }
        Start-Sleep -Milliseconds 30
        $spent += 30
    }
    $drift = New-Object double[] 6
    foreach ($i in 0..5) { $drift[$i] = [math]::Round($max[$i] - $min[$i], 3) }
    return $drift
}
