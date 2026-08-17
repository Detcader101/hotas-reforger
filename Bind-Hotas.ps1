<#
    Bind-Hotas.ps1
    Guided binding wizard for a joystick / HOTAS in Arma Reforger.

    Written against a Thrustmaster T.Flight Hotas 4 but nothing here is
    specific to it; any DirectInput stick Windows exposes through winmm works.

    Design notes
      - A live diagnostic panel sits above every step, so you can always see
        which axis is moving and which buttons are down BEFORE you commit.
      - Detection refuses ambiguous readings. If two axes move together it
        says so rather than guessing, which is how a stray hand on the
        throttle ends up bound to the cyclic.
      - A control-discovery pass teaches the tool your hardware once. After
        that it cross-checks every axis binding against what you called that
        control and warns when they disagree.

    Run:   powershell -ExecutionPolicy Bypass -File .\Bind-Hotas.ps1
           (or just double-click Bind-Hotas.cmd)

    Requires Windows PowerShell 5.1 or later. No modules, no install.
#>

[CmdletBinding()]
param(
    [string] $ProfileDir,
    [string] $ConfigName = 'Joystick_TFlightHotas4_0.conf',
    [switch] $SelfTest
)

$ErrorActionPreference = 'Stop'
$script:Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$script:ControlMapPath = Join-Path $script:Root 'hotas-controls.json'

# =============================================================================
# 1. Joystick access (winmm)
# =============================================================================

Add-Type @'
using System;
using System.Runtime.InteropServices;

public static class Joy
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
    private static extern uint _caps(UIntPtr id, ref JOYCAPS c, uint s);
    [DllImport("winmm.dll", EntryPoint = "joyGetPosEx")]
    private static extern uint _pos(uint id, ref JOYINFOEX i);

    // PowerShell 5.1 cannot cast int -> UIntPtr, so do it here.
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

# winmm reports axes as X,Y,Z,R,U,V. Reforger numbers them in DirectInput
# order: X=0, Y=1, Z=2, Rx=3, Ry=4, Rz=5. X/Y/Z line up exactly; R is Rz.
$script:AxisMap = [ordered]@{
    dwXpos = 0
    dwYpos = 1
    dwZpos = 2
    dwRpos = 5
    dwUpos = 3
    dwVpos = 4
}
# Display order, top to bottom, in the diagnostic panel.
$script:AxisRows = @(
    @{ Field='dwXpos'; Index=0; Tag='X' }
    @{ Field='dwYpos'; Index=1; Tag='Y' }
    @{ Field='dwZpos'; Index=2; Tag='Z' }
    @{ Field='dwUpos'; Index=3; Tag='U' }
    @{ Field='dwVpos'; Index=4; Tag='V' }
    @{ Field='dwRpos'; Index=5; Tag='R' }
)

function Get-ButtonMask {
    # "1 -shl 31" is a signed int and comes out as -2147483648, which will not
    # cast to uint32. Shifting a long keeps it positive.
    param([int] $Index)
    return [uint32](1L -shl $Index)
}

function Read-Stick {
    param([uint32] $Id)
    $i = New-Object Joy+JOYINFOEX
    if ([Joy]::Pos($Id, [ref]$i) -ne 0) { return $null }
    return $i
}

function ConvertTo-Unit { param([uint32] $v) return (($v / 65535.0) * 2.0) - 1.0 }

function Get-AxisSnapshot {
    param($Info)
    $h = @{}
    foreach ($f in $script:AxisMap.Keys) { $h[$f] = ConvertTo-Unit $Info.$f }
    return $h
}

function Get-Stick {
    $first = $null
    foreach ($id in 0..15) {
        $c = New-Object Joy+JOYCAPS
        if ([Joy]::Caps([uint32]$id, [ref]$c) -ne 0) { continue }
        if ([string]::IsNullOrWhiteSpace($c.szPname)) { continue }
        $isTM = ($c.wMid -eq 0x044F)
        $stick = [pscustomobject]@{
            Id      = [uint32]$id
            Vid     = $c.wMid
            Pid     = $c.wPid
            Axes    = $c.wNumAxes
            Buttons = $c.wNumButtons
            HasPov  = [bool]($c.wCaps -band 0x10)
            IsTM    = $isTM
        }
        if ($isTM) { return $stick }
        if (-not $first) { $first = $stick }
    }
    return $first
}

function Get-StickName {
    param($Stick)
    if (-not $Stick) { return 'no device' }
    if ($Stick.Vid -eq 0x044F -and $Stick.Pid -eq 0xB67C) { return 'T.Flight Hotas 4 (PC mode)' }
    if ($Stick.Vid -eq 0x044F -and $Stick.Pid -eq 0xB67B) { return 'T.Flight Hotas 4 (PS4 mode)' }
    if ($Stick.IsTM) { return 'Thrustmaster device' }
    return ('joystick vid 0x{0:X4} pid 0x{1:X4}' -f $Stick.Vid, $Stick.Pid)
}

# =============================================================================
# 2. Detection -- pure functions, no hardware, fully testable
# =============================================================================

# Which axis moved furthest from rest, and in which direction?
#
# Returns $null when nothing moved past the threshold, and a result with
# Ambiguous=$true when a second axis moved nearly as much. Guessing in that
# case is how a hand resting on the throttle gets bound to the cyclic.
function Find-MovedAxis {
    param(
        $Base, $Now,
        [double] $Threshold = 0.45,
        [double] $DominanceRatio = 2.0,   # winner must beat runner-up by this factor
        [double] $DominanceFloor = 0.20   # ...or by at least this absolute margin
    )

    $ranked = @()
    foreach ($f in $script:AxisMap.Keys) {
        if (-not $Base.ContainsKey($f) -or -not $Now.ContainsKey($f)) { continue }
        $d = $Now[$f] - $Base[$f]
        $ranked += [pscustomobject]@{ Field=$f; Delta=$d; Abs=[math]::Abs($d) }
    }
    if (-not $ranked.Count) { return $null }

    $ranked = @($ranked | Sort-Object -Property Abs -Descending)
    $win = $ranked[0]
    if ($win.Abs -lt $Threshold) { return $null }

    $runnerUp = if ($ranked.Count -gt 1) { $ranked[1] } else { $null }
    $ambiguous = $false
    $rival = $null
    if ($runnerUp -and $runnerUp.Abs -ge 0.25) {
        $clearByRatio  = ($win.Abs -ge ($runnerUp.Abs * $DominanceRatio))
        $clearByMargin = (($win.Abs - $runnerUp.Abs) -ge $DominanceFloor)
        if (-not ($clearByRatio -or $clearByMargin)) {
            $ambiguous = $true
            $rival = $script:AxisMap[$runnerUp.Field]
        }
    }

    return @{
        Field     = $win.Field
        Index     = $script:AxisMap[$win.Field]
        Sign      = $(if ($win.Delta -ge 0) { '+' } else { '-' })
        Delta     = $win.Delta
        Ambiguous = $ambiguous
        Rival     = $rival
    }
}

# Lowest button down now that was not down at baseline.
# Button 0 is a valid result and is falsy, so callers must test "$null -ne".
function Find-PressedButton {
    param([uint32] $Base, [uint32] $Now, [int] $Max = 32)
    for ($b = 0; $b -lt $Max; $b++) {
        $bit = Get-ButtonMask $b
        if (($Now -band $bit) -and -not ($Base -band $bit)) { return $b }
    }
    return $null
}

# =============================================================================
# 3. Console primitives
# =============================================================================

$script:HasConsole = $true
try { $null = [Console]::KeyAvailable } catch { $script:HasConsole = $false }

function Read-KeyChar {
    if (-not $script:HasConsole) { return 'q' }
    try {
        $k = [Console]::ReadKey($true)
        if ($k.Key -eq 'Enter') { return "`r" }
        return ("$($k.KeyChar)").ToLower()
    } catch { $script:HasConsole = $false; return 'q' }
}

function Test-KeyWaiting {
    if (-not $script:HasConsole) { return $false }
    try { return [Console]::KeyAvailable } catch { $script:HasConsole = $false; return $false }
}

function Write-At {
    param([int] $Row, [int] $Col, [string] $Text, [string] $Colour = 'Gray', [int] $Pad = 0)
    if ($Pad -gt 0 -and $Text.Length -lt $Pad) { $Text = $Text.PadRight($Pad) }
    if (-not $script:HasConsole) { return }
    try { [Console]::SetCursorPosition($Col, $Row) } catch { return }
    Write-Host $Text -NoNewline -ForegroundColor $Colour
}

function Clear-Screen {
    if (-not $script:HasConsole) { return }
    try { Clear-Host } catch { }
}

# A centre-anchored bar. Fill runs from the middle out to the current value,
# so a resting axis is visibly empty and a deflected one is visibly not.
function Get-Bar {
    param([double] $Value, [int] $Width = 21)
    if ($Value -gt 1) { $Value = 1 } elseif ($Value -lt -1) { $Value = -1 }
    $mid = [int](($Width - 1) / 2)
    $pos = [int][math]::Round((($Value + 1) / 2) * ($Width - 1))
    if ($pos -lt 0) { $pos = 0 } elseif ($pos -ge $Width) { $pos = $Width - 1 }

    $out = New-Object char[] $Width
    for ($i = 0; $i -lt $Width; $i++) { $out[$i] = '.' }
    $lo = [math]::Min($mid, $pos); $hi = [math]::Max($mid, $pos)
    for ($i = $lo; $i -le $hi; $i++) { $out[$i] = '=' }
    $out[$mid] = '|'
    $out[$pos] = '#'
    return ('[' + (-join $out) + ']')
}

function Get-BarColour {
    param([double] $Value)
    $a = [math]::Abs($Value)
    if ($a -lt 0.08) { return 'DarkGray' }
    if ($a -lt 0.85) { return 'Cyan' }
    return 'Yellow'
}

# =============================================================================
# 4. The diagnostic panel
# =============================================================================

$script:PanelWidth = 72
$script:Col        = @{ Axis = 3; Bar = 13; Val = 37; Btn = 48 }
$script:PanelRow   = @{
    Title = 1; Rule1 = 2; Head = 3
    Axis0 = 4                       # six axis rows, 4..9
    Btn1  = 4; Btn2  = 5            # buttons live in the right column
    Hat   = 7; Drift = 8
    Rule2 = 10
    Body  = 11                      # step content starts here
}

function Show-PanelChrome {
    param($Stick, [string] $Subtitle = '')
    Clear-Screen
    $name = Get-StickName $Stick
    Write-At $script:PanelRow.Title 2 'ARMA REFORGER - HOTAS BINDING' 'Cyan' 34
    Write-At $script:PanelRow.Title 38 $name 'DarkCyan' 34
    Write-At $script:PanelRow.Rule1 2 ('=' * $script:PanelWidth) 'DarkGray'

    Write-At $script:PanelRow.Head $script:Col.Axis 'AXES' 'White' 10
    Write-At $script:PanelRow.Head $script:Col.Btn  'BUTTONS' 'White' 22

    for ($i = 0; $i -lt $script:AxisRows.Count; $i++) {
        $a = $script:AxisRows[$i]
        Write-At ($script:PanelRow.Axis0 + $i) $script:Col.Axis ('axis{0} {1}' -f $a.Index, $a.Tag) 'DarkGray' 9
    }
    Write-At $script:PanelRow.Rule2 2 ('=' * $script:PanelWidth) 'DarkGray'
    if ($Subtitle) { Write-At $script:PanelRow.Head 22 $Subtitle 'DarkGray' 24 }
}

# Redraw only the live cells. Called every poll, so it must stay cheap.
function Update-Panel {
    param($Info, $Highlight = $null, $Stick = $null)
    if (-not $Info) { return }

    $snap = Get-AxisSnapshot $Info
    for ($i = 0; $i -lt $script:AxisRows.Count; $i++) {
        $a = $script:AxisRows[$i]
        $v = $snap[$a.Field]
        $row = $script:PanelRow.Axis0 + $i
        $col = Get-BarColour $v
        if ($null -ne $Highlight -and $Highlight -eq $a.Index) { $col = 'Green' }
        Write-At $row $script:Col.Bar (Get-Bar $v) $col
        Write-At $row $script:Col.Val ('{0,6:+0.00;-0.00; 0.00}' -f $v) $col 8
    }

    $maxBtn = 12
    if ($Stick -and $Stick.Buttons) { $maxBtn = [int]$Stick.Buttons }
    if ($maxBtn -gt 24) { $maxBtn = 24 }
    for ($half = 0; $half -lt 2; $half++) {
        $row = if ($half -eq 0) { $script:PanelRow.Btn1 } else { $script:PanelRow.Btn2 }
        $x = $script:Col.Btn
        for ($n = 0; $n -lt 6; $n++) {
            $b = ($half * 6) + $n
            if ($b -ge $maxBtn) { Write-At $row $x '   ' 'DarkGray'; $x += 3; continue }
            $down = [bool]($Info.dwButtons -band (Get-ButtonMask $b))
            $col  = if ($down) { 'Green' } else { 'DarkGray' }
            Write-At $row $x ('{0,2} ' -f $b) $col
            $x += 3
        }
    }

    $hat = if ($Info.dwPOV -eq 65535) { 'centre' } else { ('{0} deg' -f ($Info.dwPOV / 100)) }
    $hatCol = if ($Info.dwPOV -eq 65535) { 'DarkGray' } else { 'Green' }
    Write-At $script:PanelRow.Hat $script:Col.Btn ("HAT  $hat") $hatCol 22
}

function Write-PanelStatus {
    param([int] $Row, [string] $Text, [string] $Colour = 'DarkGray')
    Write-At $Row 4 $Text $Colour ($script:PanelWidth - 2)
}

# =============================================================================
# 5. Plain-screen helpers (preflight, review, menus)
# =============================================================================

function Write-Rule  { param([string]$Char='-') Write-Host ('  ' + ($Char * $script:PanelWidth)) -ForegroundColor DarkGray }
function Write-Note  { param([string]$m) Write-Host "    $m" -ForegroundColor DarkGray }
function Write-Good  { param([string]$m) Write-Host "    $m" -ForegroundColor Green }
function Write-Warn  { param([string]$m) Write-Host "    $m" -ForegroundColor Yellow }
function Write-Bad   { param([string]$m) Write-Host "    $m" -ForegroundColor Red }
function Write-Field {
    param([string]$Label, [string]$Value, [string]$Colour='Gray')
    Write-Host ('    {0,-10}' -f $Label) -NoNewline -ForegroundColor DarkGray
    Write-Host $Value -ForegroundColor $Colour
}
function Write-Header {
    Clear-Screen
    Write-Host ''
    Write-Host '  ARMA REFORGER - HOTAS BINDING WIZARD' -ForegroundColor Cyan
    Write-Rule
}
function Pause-Any {
    param([string]$Message = 'press any key to continue')
    Write-Host ''
    Write-Host "    $Message" -ForegroundColor DarkGray
    [void](Read-KeyChar)
}

# =============================================================================
# 6. Paths
# =============================================================================

function Resolve-ProfileDir {
    if ($ProfileDir) { return $ProfileDir }
    $base = Join-Path $env:USERPROFILE 'Documents\My Games\ArmaReforger\profile\.save'
    if (-not (Test-Path $base)) { return $null }
    $shared = Join-Path $base 'settings\customInputConfigs'
    if (Test-Path $shared) { return $shared }
    return $null
}

# Reforger names these files after the device: Joystick_<Name>_<n>.conf.
# Only go looking if the expected name is absent.
function Resolve-ConfigName {
    param([string] $Dir, [string] $Preferred)
    if (-not $Dir) { return $Preferred }
    if (Test-Path (Join-Path $Dir $Preferred)) { return $Preferred }
    $found = @(Get-ChildItem -Path $Dir -Filter 'Joystick_*.conf' -File -ErrorAction SilentlyContinue)
    if ($found.Count -eq 0) { return $Preferred }
    if ($found.Count -eq 1) { return $found[0].Name }
    $zero = $found | Where-Object { $_.Name -match '_0\.conf$' } | Select-Object -First 1
    if ($zero) { return $zero.Name }
    return ($found | Sort-Object Name)[0].Name
}

function Test-GameRunning {
    return [bool](Get-Process -Name 'ArmaReforgerSteam', 'ArmaReforger_BE' -ErrorAction SilentlyContinue)
}

# =============================================================================
# 7. Control map -- what the hardware actually is
# =============================================================================
#
# Learned once, then used to sanity-check every axis binding. If you tell the
# tool that the stick rolls on axis0 and later bind the cyclic to axis4, it
# says so instead of quietly writing a config that will not fly.

$script:ControlProbes = @(
    @{ Key='StickX';   Label='Stick roll';      Prompt='Move the STICK left and right.';        Hint='just the stick, nothing else' }
    @{ Key='StickY';   Label='Stick pitch';     Prompt='Move the STICK forward and back.';      Hint='' }
    @{ Key='Twist';    Label='Twist / rudder';  Prompt='TWIST the stick, or press a pedal.';    Hint='skip if your stick does not twist' }
    @{ Key='Throttle'; Label='Throttle lever';  Prompt='Move the THROTTLE lever.';              Hint='' }
    @{ Key='Rocker';   Label='Throttle rocker'; Prompt='Move the ROCKER on the throttle.';      Hint='skip if you do not have one' }
)

function Import-ControlMap {
    if (-not (Test-Path $script:ControlMapPath)) { return @{} }
    try {
        $raw = Get-Content -Raw $script:ControlMapPath | ConvertFrom-Json
        $h = @{}
        foreach ($p in $raw.PSObject.Properties) { $h[$p.Name] = $p.Value }
        return $h
    } catch { return @{} }
}

function Export-ControlMap {
    param($Map)
    try { ($Map | ConvertTo-Json) | Set-Content -Path $script:ControlMapPath -Encoding UTF8 } catch { }
}

function Get-ControlLabel {
    param($Map, [int] $AxisIndex)
    if (-not $Map) { return $null }
    foreach ($p in $script:ControlProbes) {
        if ($Map.ContainsKey($p.Key) -and $Map[$p.Key] -eq $AxisIndex) { return $p.Label }
    }
    return $null
}

# Find any control already recorded on this axis.
function Find-MapClash {
    param($Map, [int] $AxisIndex, [string] $ExceptKey)
    foreach ($p in $script:ControlProbes) {
        if ($p.Key -eq $ExceptKey) { continue }
        if ($Map.ContainsKey($p.Key) -and $Map[$p.Key] -eq $AxisIndex) { return $p }
    }
    return $null
}

function Invoke-ControlMap {
    param($Stick)

    $map = Import-ControlMap
    $row = $script:PanelRow.Body
    $statusRow = $row + 7
    $keyRow = $row + 10

    $i = 0
    while ($i -lt $script:ControlProbes.Count) {
        $probe = $script:ControlProbes[$i]

        Show-PanelChrome -Stick $Stick -Subtitle ('control {0} of {1}' -f ($i + 1), $script:ControlProbes.Count)
        Write-At $row       3 ('IDENTIFY YOUR CONTROLS    {0}' -f $probe.Label) 'White' ($script:PanelWidth - 2)
        Write-At ($row + 2) 4 $probe.Prompt 'White' ($script:PanelWidth - 2)
        if ($probe.Hint) { Write-At ($row + 3) 4 "($($probe.Hint))" 'DarkGray' ($script:PanelWidth - 2) }

        # running summary, so you can see the map building up
        $done = ($script:ControlProbes | Where-Object { $map.ContainsKey($_.Key) } |
                 ForEach-Object { "$($_.Label)=axis$($map[$_.Key])" }) -join '   '
        Write-At ($row + 5) 4 ("so far: " + $(if ($done) { $done } else { 'nothing yet' })) 'DarkCyan' ($script:PanelWidth - 2)
        Write-At ($row + 9) 2 ('-' * $script:PanelWidth) 'DarkGray'

        $gate = Wait-ForReady -StatusRow $statusRow -HasCurrent $false -KeyRow $keyRow
        if ($gate -eq 'quit') { break }
        if ($gate -eq 'skip') { $i++; continue }
        if ($gate -eq 'back') { if ($i -gt 0) { $i-- }; continue }

        $r = Wait-ForInput -Id $Stick.Id -Want 'Axis' -CurrentToken $null `
                           -StatusRow $statusRow -Stick $Stick -Map $map
        if ($r.Type -eq 'Control') {
            if ($r.Key -eq 'quit') { break }
            if ($r.Key -eq 'back') { if ($i -gt 0) { $i-- }; continue }
            $i++
            continue
        }

        $clash = Find-MapClash -Map $map -AxisIndex $r.Index -ExceptKey $probe.Key
        Write-PanelStatus $statusRow ("read as:  axis$($r.Index)") 'Green'
        if ($clash) {
            Write-At ($statusRow + 1) 4 `
                ("! axis$($r.Index) is already recorded as $($clash.Label) - two controls cannot be the same axis") `
                'Yellow' ($script:PanelWidth - 2)
            Write-At $keyRow 4 'r try again   s skip this control   q done' 'White' ($script:PanelWidth - 2)
            $d = $null
            while (-not $d) {
                switch (Read-KeyChar) { 'r' {$d='redo'} 's' {$d='skip'} 'q' {$d='quit'} }
            }
            if ($d -eq 'quit') { break }
            if ($d -eq 'skip') { $i++ }
            continue
        }

        Write-At ($statusRow + 1) 4 '' 'Gray' ($script:PanelWidth - 2)
        Write-At $keyRow 4 ("ENTER yes, that is my $($probe.Label)   r try again   s skip") 'White' ($script:PanelWidth - 2)
        $d = $null
        while (-not $d) {
            switch (Read-KeyChar) { "`r" {$d='ok'} 'r' {$d='redo'} 's' {$d='skip'} 'q' {$d='quit'} }
        }
        if ($d -eq 'quit') { break }
        if ($d -eq 'redo') { continue }
        if ($d -eq 'skip') { $i++; continue }

        $map[$probe.Key] = $r.Index
        $i++
    }

    # final confirmation before anything is written
    Write-Header
    Write-Host ''
    Write-Host '  YOUR CONTROLS' -ForegroundColor White
    Write-Host ''
    foreach ($p in $script:ControlProbes) {
        $v = if ($map.ContainsKey($p.Key)) { "axis$($map[$p.Key])" } else { 'not set' }
        $c = if ($map.ContainsKey($p.Key)) { 'Gray' } else { 'DarkGray' }
        Write-Host ('    {0,-18} {1}' -f $p.Label, $v) -ForegroundColor $c
    }
    Write-Host ''
    Write-Rule
    Write-Host '    Save this?  [y] yes   [n] discard' -ForegroundColor White
    $ans = $null
    while (-not $ans) { switch (Read-KeyChar) { 'y' {$ans='y'} 'n' {$ans='n'} 'q' {$ans='n'} } }
    if ($ans -eq 'n') { Write-Host ''; Write-Note 'Discarded.'; Pause-Any; return (Import-ControlMap) }

    Export-ControlMap $map
    Write-Host ''
    Write-Good "saved -> $(Split-Path -Leaf $script:ControlMapPath)"
    Pause-Any
    return $map
}

# =============================================================================
# 8. Layout profiles
# =============================================================================

$script:Layouts = @(
    @{ Key='1'; Name='Helicopter focus'
       Desc='Stick and throttle fly the aircraft. Turret rotate goes on the throttle rocker; turret aim stays on the mouse.'
       Exclude=@('TurretAimLeft','TurretAimRight','TurretAimUp','TurretAimDown') }
    @{ Key='2'; Name='Helicopter and door gunner'
       Desc='As above, but the stick also aims the turret when you are in a gunner seat.'
       Exclude=@() }
)

# =============================================================================
# 9. Action catalogue
# =============================================================================
#
# Tier A = the game emitted this action name in its own generated preset, or we
#          have watched the engine accept it.
# Tier B = present in the engine binary and unambiguously an input action, but
#          not yet seen consumed. Flagged in the UI.
#
# Expect  = which physical control this SHOULD be, checked against the control
#           map. Context is used for conflict detection only.

$script:Steps = @(
    @{ Kind='AxisPair'; Group='FLIGHT'; Context='Helicopter'; Tier='A'; Expect='StickX'
       Title='Cyclic - roll'
       Prompt='Roll the cyclic RIGHT and hold it.'
       Hint='the stick only - keep your other hand off the throttle'
       Pos=@{Action='HelicopterCyclicRight'; Preset='right'}
       Neg=@{Action='HelicopterCyclicLeft';  Preset='left'} }

    @{ Kind='AxisPair'; Group='FLIGHT'; Context='Helicopter'; Tier='A'; Expect='StickY'
       Title='Cyclic - pitch'
       Prompt='Push the cyclic FORWARD (nose down) and hold it.'
       Hint='push the stick away from you'
       Pos=@{Action='HelicopterCyclicForward'; Preset='forward'}
       Neg=@{Action='HelicopterCyclicBack';    Preset='back'} }

    @{ Kind='AxisPair'; Group='FLIGHT'; Context='Helicopter'; Tier='A'; Expect='Throttle'
       Title='Collective'
       Prompt='Raise the collective and hold it.'
       Hint='push the throttle lever forward'
       Pos=@{Action='HelicopterCollectiveIncrease'; Preset='up'}
       Neg=@{Action='HelicopterCollectiveDecrease'; Preset='down'} }

    @{ Kind='AxisPair'; Group='FLIGHT'; Context='Helicopter'; Tier='A'; Expect='Twist'
       Title='Anti-torque (tail rotor)'
       Prompt='Yaw RIGHT and hold it.'
       Hint='twist the stick clockwise, or press the right pedal'
       Pos=@{Action='HelicopterAntiTorqueRight'; Preset='right'}
       Neg=@{Action='HelicopterAntiTorqueLeft';  Preset='left'} }

    @{ Kind='Button'; Group='FLIGHT'; Context='Helicopter'; Tier='B'
       Title='Engine start'
       Prompt='Press the button you want for ENGINE START.'
       Actions=@(@{Action='HelicopterEngineStart'; Preset='click'}) }

    @{ Kind='Button'; Group='FLIGHT'; Context='Helicopter'; Tier='B'; Hazard=$true
       Title='Engine stop'
       Prompt='Press the button you want for ENGINE STOP.'
       HazardNote='On an easily-brushed button this is an engine shutdown in the air. Skipping it and using the keyboard is the safe choice.'
       Actions=@(@{Action='HelicopterEngineStop'; Preset='click'}) }

    @{ Kind='Button'; Group='FLIGHT'; Context='Helicopter'; Tier='A'
       Title='Autohover toggle'
       Prompt='Press the button you want for AUTOHOVER.'
       Actions=@(@{Action='HelicopterAutohoverToggle'; Preset='click'}) }

    @{ Kind='Button'; Group='FLIGHT'; Context='Helicopter'; Tier='A'
       Title='Wheel brake'
       Prompt='Press the button you want for WHEEL BRAKE.'
       Note='binds the momentary and the persistent brake together'
       Actions=@(
           @{Action='HelicopterWheelBrake';           Preset='pressed'},
           @{Action='HelicopterWheelBrakePersistent'; Preset='pressed'}) }

    @{ Kind='AxisPair'; Group='GUNNER'; Context='Turret'; Tier='A'; Expect='Rocker'
       Title='Turret rotate'
       Prompt='Push the ROCKER on the throttle to the RIGHT.'
       Hint='the rocker, not the stick - this keeps the stick free for flying'
       Pos=@{Action='TurretRotateRight'; Preset='right'}
       Neg=@{Action='TurretRotateLeft';  Preset='left'} }

    @{ Kind='AxisPair'; Group='GUNNER'; Context='Turret'; Tier='A'; Expect='StickX'
       Title='Turret aim - horizontal'
       Prompt='Aim RIGHT and hold it.'
       Hint='normally the same axis as cyclic roll'
       Pos=@{Action='TurretAimRight'; Preset='right'}
       Neg=@{Action='TurretAimLeft';  Preset='left'} }

    @{ Kind='AxisPair'; Group='GUNNER'; Context='Turret'; Tier='A'; Expect='StickY'
       Title='Turret aim - vertical'
       Prompt='Aim UP and hold it.'
       Hint='pull the stick towards you'
       Pos=@{Action='TurretAimUp';   Preset='up'}
       Neg=@{Action='TurretAimDown'; Preset='down'} }

    @{ Kind='Button'; Group='GUNNER'; Context='Turret'; Tier='A'
       Title='Turret fire'
       Prompt='Press the button you want for TURRET FIRE.'
       Actions=@(@{Action='TurretFire'; Preset='hold'}) }

    @{ Kind='Button'; Group='GUNNER'; Context='Turret'; Tier='A'
       Title='Turret reload'
       Prompt='Press the button you want for TURRET RELOAD.'
       Actions=@(@{Action='TurretReload'; Preset='click'}) }

    @{ Kind='Button'; Group='GUNNER'; Context='Turret'; Tier='A'
       Title='Turret next weapon'
       Prompt='Press the button you want for TURRET NEXT WEAPON.'
       Actions=@(@{Action='TurretNextWeapon'; Preset='click'}) }

    @{ Kind='Button'; Group='VIEW'; Context='Global'; Tier='A'
       Title='Freelook'
       Prompt='Press the button you want for FREELOOK.'
       Note='hold to look around; a single click re-centres'
       Actions=@(
           @{Action='Freelook';      Preset='hold'},
           @{Action='FreelookReset'; Preset='click'; SingleClick=$true}) }

    @{ Kind='Pov'; Group='VIEW'; Context='Global'; Tier='A'
       Title='Freelook hat'
       Prompt='Push the HAT SWITCH in any direction.'
       Hint='binds all four directions at once'
       Actions=@(
           @{Action='FreelookUp';    Preset='up';    Token='pov_up'},
           @{Action='FreelookDown';  Preset='down';  Token='pov_down'},
           @{Action='FreelookLeft';  Preset='left';  Token='pov_left'},
           @{Action='FreelookRight'; Preset='right'; Token='pov_right'}) }

    @{ Kind='Button'; Group='VIEW'; Context='Global'; Tier='A'
       Title='Voice (VON)'
       Prompt='Press the button you want for PUSH TO TALK.'
       Note='hold to transmit; a click toggles direct speech'
       Actions=@(
           @{Action='VONChannel';      Preset='hold'},
           @{Action='VONDirectToggle'; Preset='click'}) }

    @{ Kind='Button'; Group='VIEW'; Context='Global'; Tier='A'
       Title='Map'
       Prompt='Press the button you want for MAP.'
       Actions=@(@{Action='GadgetMap'; Preset='select'}) }

    @{ Kind='Button'; Group='ON FOOT'; Context='Character'; Tier='A'; Optional=$true
       Title='Fire (on foot)'
       Prompt='Press the button you want for FIRE while on foot.'
       Note='leaving this unbound stops the trigger firing your rifle out of the aircraft'
       Actions=@(@{Action='CharacterFire'; Preset='hold'}) }

    @{ Kind='Button'; Group='ON FOOT'; Context='Character'; Tier='A'; Optional=$true
       Title='Next weapon (on foot)'
       Prompt='Press the button you want for NEXT WEAPON on foot.'
       Actions=@(@{Action='CharacterNextWeapon'; Preset='click'}) }

    @{ Kind='Button'; Group='ON FOOT'; Context='Character'; Tier='A'; Optional=$true
       Title='Select action'
       Prompt='Press the button you want for SELECT ACTION.'
       Actions=@(@{Action='SelectAction'; Preset='next'}) }
)

function Get-StepActions {
    param($Step)
    # The leading comma matters. Without it PowerShell unrolls a single-element
    # array on return, so a one-action step hands back a bare hashtable and
    # every [0] index against it silently yields $null.
    switch ($Step.Kind) {
        'AxisPair' { return ,@($Step.Pos, $Step.Neg) }
        default    { return ,@($Step.Actions) }
    }
}

function Get-ActionContext {
    param([string] $Action)
    foreach ($s in $script:Steps) {
        foreach ($a in (Get-StepActions $s)) { if ($a.Action -eq $Action) { return $s.Context } }
    }
    return 'Unknown'
}

# =============================================================================
# 10. Reading and writing the config
# =============================================================================

function Read-ExistingConfig {
    param([string] $Path)
    $result = @{ Bindings = @{}; Raw = ''; Unknown = @() }
    if (-not (Test-Path $Path)) { return $result }

    $text = Get-Content -Path $Path -Raw
    $result.Raw = $text
    $rx = [regex]'(?s)Action\s+(\w+)\s*\{.*?Input\s+"([^"]+)"'
    foreach ($m in $rx.Matches($text)) {
        $name = $m.Groups[1].Value
        if (-not $result.Bindings.ContainsKey($name)) { $result.Bindings[$name] = $m.Groups[2].Value }
    }
    $known = @{}
    foreach ($s in $script:Steps) { foreach ($a in (Get-StepActions $s)) { $known[$a.Action] = $true } }
    foreach ($k in $result.Bindings.Keys) { if (-not $known.ContainsKey($k)) { $result.Unknown += $k } }
    return $result
}

$script:Presets = @{}

function Get-PresetFor {
    param([string] $Action)
    if ($script:Presets.ContainsKey($Action)) { return $script:Presets[$Action] }
    foreach ($s in $script:Steps) {
        foreach ($a in (Get-StepActions $s)) {
            if ($a.Action -eq $Action) { return @{ Preset=$a.Preset; SingleClick=[bool]$a.SingleClick } }
        }
    }
    return @{ Preset = 'click'; SingleClick = $false }
}

function New-GuidSeries {
    $script:GuidHi = '{0:X8}' -f (Get-Random -Minimum 0x10000000 -Maximum 0x7FFFFFFF)
    $script:GuidN = 0
}
function Get-NextGuid {
    $script:GuidN++
    return '{0}{1:X8}' -f $script:GuidHi, $script:GuidN
}

function Test-InputToken {
    param([string] $Token)
    return ($Token -match '^joystick\d+:(axis\d+[+-]|button\d+|pov_(up|down|left|right))$')
}

function Get-RawActionBlock {
    param([string] $Text, [string] $Action)
    $m = [regex]::Match($Text, "(?m)^\s*Action\s+$([regex]::Escape($Action))\s*\{")
    if (-not $m.Success) { return $null }
    $i = $m.Index + $m.Length
    $depth = 1
    while ($i -lt $Text.Length -and $depth -gt 0) {
        $c = $Text[$i]
        if ($c -eq '{') { $depth++ } elseif ($c -eq '}') { $depth-- }
        $i++
    }
    return $Text.Substring($m.Index, $i - $m.Index)
}

function Build-Config {
    param($Bindings, $Existing)
    New-GuidSeries
    $sb = New-Object Text.StringBuilder
    [void]$sb.AppendLine('ActionManager {')
    [void]$sb.AppendLine(' Actions {')

    $written = @{}
    foreach ($step in $script:Steps) {
        foreach ($a in (Get-StepActions $step)) {
            $name = $a.Action
            if (-not $Bindings.ContainsKey($name)) { continue }
            if ($written.ContainsKey($name)) { continue }
            $written[$name] = $true

            $p = Get-PresetFor $name
            $token = $Bindings[$name]
            [void]$sb.AppendLine("  Action $name {")
            [void]$sb.AppendLine("   InputSource InputSourceSum `"{$(Get-NextGuid)}`" {")
            [void]$sb.AppendLine('    Sources {')
            [void]$sb.AppendLine("     InputSourceValue `"{$(Get-NextGuid)}`" {")
            [void]$sb.AppendLine("      FilterPreset `"$($p.Preset)`"")
            [void]$sb.AppendLine("      Input `"$token`"")
            if ($p.SingleClick) {
                [void]$sb.AppendLine("      Filter InputFilterSingleClick `"{$(Get-NextGuid)}`" {")
                [void]$sb.AppendLine('      }')
            }
            [void]$sb.AppendLine('     }')
            [void]$sb.AppendLine('    }')
            [void]$sb.AppendLine('   }')
            [void]$sb.AppendLine('  }')
        }
    }

    foreach ($u in $Existing.Unknown) {
        if (-not $Bindings.ContainsKey($u)) { continue }
        $blk = Get-RawActionBlock -Text $Existing.Raw -Action $u
        if ($blk) { [void]$sb.AppendLine($blk.TrimEnd()) }
    }

    [void]$sb.AppendLine(' }')
    [void]$sb.AppendLine('}')
    return $sb.ToString()
}

function Test-ConfigText {
    param([string] $Text)
    $issues = @()

    $tokens = [regex]::Matches($Text, 'Input\s+"([^"]*)"') | ForEach-Object { $_.Groups[1].Value }
    $badTokens = @($tokens | Where-Object { -not (Test-InputToken $_) })
    if ($badTokens.Count) { $issues += "malformed input tokens: $(($badTokens | Select-Object -Unique) -join ', ')" }

    $stripped = [regex]::Replace($Text, '"\{[0-9A-F]+\}"', 'GUID')
    $open  = ([regex]::Matches($stripped, '\{')).Count
    $close = ([regex]::Matches($stripped, '\}')).Count
    if ($open -ne $close) { $issues += "brace mismatch: $open open, $close close" }

    $guids = [regex]::Matches($Text, '\{([0-9A-F]{16})\}') | ForEach-Object { $_.Groups[1].Value }
    $dupes = $guids | Group-Object | Where-Object Count -gt 1 | ForEach-Object { $_.Name }
    if ($dupes) { $issues += "duplicate ids: $($dupes -join ', ')" }

    $actions = [regex]::Matches($Text, '(?m)^\s*Action\s+(\w+)\s*\{') | ForEach-Object { $_.Groups[1].Value }
    $adupes = $actions | Group-Object | Where-Object Count -gt 1 | ForEach-Object { $_.Name }
    if ($adupes) { $issues += "duplicate action blocks: $($adupes -join ', ')" }

    return [pscustomobject]@{
        Ok = ($issues.Count -eq 0); Issues = $issues
        Actions = $actions.Count; Guids = $guids.Count
    }
}

# =============================================================================
# 11. Listening for an input
# =============================================================================

# Wait until nothing is moving before sampling a baseline.
#
# Without this, a spring-centred stick still recoiling from the previous
# prompt registers a large delta on the OLD axis and wins the next reading --
# which is how five separate controls all get recorded as axis0.
#
# "At rest" means NOT CHANGING, not centred: a throttle legitimately sits
# wherever you left it.
function Wait-ForStillness {
    param(
        [uint32] $Id,
        [int]    $StatusRow = 0,
        [int]    $TimeoutMs = 2500,
        [double] $Tolerance = 0.05,
        [int]    $Window = 6,
        $Stick = $null
    )
    $samples = @()
    $elapsed = 0
    $warned = $false

    while ($elapsed -lt $TimeoutMs) {
        $info = Read-Stick $Id
        if (-not $info) { return $false }
        if ($StatusRow) { Update-Panel -Info $info -Stick $Stick }

        $samples += ,(Get-AxisSnapshot $info)
        if ($samples.Count -gt $Window) { $samples = $samples[($samples.Count - $Window)..($samples.Count - 1)] }

        if ($samples.Count -eq $Window) {
            $spread = 0.0
            foreach ($f in $script:AxisMap.Keys) {
                $st = $samples | ForEach-Object { $_[$f] } | Measure-Object -Maximum -Minimum
                $s = $st.Maximum - $st.Minimum
                if ($s -gt $spread) { $spread = $s }
            }
            if ($spread -le $Tolerance) { return $true }
            if ($StatusRow -and -not $warned) {
                Write-PanelStatus $StatusRow 'let go and let everything settle...' 'DarkGray'
                $warned = $true
            }
        }
        Start-Sleep -Milliseconds 25
        $elapsed += 25
    }
    # A permanently noisy stick must not deadlock the wizard.
    return $true
}

# Nothing starts listening until you say so.
#
# Detection used to begin the instant a screen appeared, so moving your hand
# into position counted as the input. This gate is the difference between a
# demo and something you can actually sit down and use.
function Wait-ForReady {
    param([int] $StatusRow, [bool] $HasCurrent, [int] $KeyRow = 0)
    $msg = if ($HasCurrent) { 'ENTER keep what is there   |   SPACE change it' }
           else             { 'ENTER when you are ready to move the control' }
    Write-PanelStatus $StatusRow $msg 'White'
    if ($KeyRow) {
        $extra = if ($HasCurrent) { 's skip   b back   u unbind   q quit' } else { 's skip   b back   q quit' }
        Write-At $KeyRow 4 $extra 'DarkGray' ($script:PanelWidth - 2)
    }
    while ($true) {
        switch (Read-KeyChar) {
            "`r" { if ($HasCurrent) { return 'keep' } else { return 'go' } }
            ' '  { return 'go' }
            's'  { return 'skip' }
            'b'  { return 'back' }
            'u'  { return 'unbind' }
            'q'  { return 'quit' }
        }
    }
}

function Wait-ForInput {
    param(
        [uint32] $Id,
        [string] $Want,
        [string] $CurrentToken,
        [int]    $StatusRow = 0,
        $Stick = $null,
        $Map = $null
    )

    [void](Wait-ForStillness -Id $Id -StatusRow $StatusRow -Stick $Stick)
    if ($StatusRow) { Write-PanelStatus $StatusRow 'listening...' 'DarkGray' }

    $base = $null
    $baseBtn = [uint32]0
    for ($n = 0; $n -lt 8; $n++) {
        $info = Read-Stick $Id
        if ($info) { $base = Get-AxisSnapshot $info; $baseBtn = $info.dwButtons }
        Start-Sleep -Milliseconds 20
    }
    if (-not $base) {
        if ($StatusRow) { Write-PanelStatus $StatusRow 'Lost contact with the joystick. Is it still plugged in?' 'Red' }
        Start-Sleep -Milliseconds 900
        return @{ Type='Control'; Key='quit' }
    }

    $lastAmbig = $false
    while ($true) {
        if (Test-KeyWaiting) {
            switch (Read-KeyChar) {
                "`r" { if ($CurrentToken) { return @{Type='Control'; Key='keep'} } }
                ' '  { if ($CurrentToken) { return @{Type='Control'; Key='keep'} } }
                's'  { return @{Type='Control'; Key='skip'} }
                'b'  { return @{Type='Control'; Key='back'} }
                'u'  { return @{Type='Control'; Key='unbind'} }
                'q'  { return @{Type='Control'; Key='quit'} }
            }
        }

        $info = Read-Stick $Id
        if (-not $info) { Start-Sleep -Milliseconds 100; continue }
        if ($StatusRow) { Update-Panel -Info $info -Stick $Stick }

        if ($Want -eq 'Button') {
            $pressed = Find-PressedButton -Base $baseBtn -Now $info.dwButtons
            if ($null -ne $pressed) {
                $bit = Get-ButtonMask $pressed
                while ($true) {
                    $r = Read-Stick $Id
                    if (-not $r -or -not ($r.dwButtons -band $bit)) { break }
                    Start-Sleep -Milliseconds 20
                }
                return @{ Type='Button'; Index=$pressed }
            }
        }
        elseif ($Want -eq 'Pov') {
            if ($info.dwPOV -ne 65535) {
                while ($true) {
                    $r = Read-Stick $Id
                    if (-not $r -or $r.dwPOV -eq 65535) { break }
                    Start-Sleep -Milliseconds 20
                }
                return @{ Type='Pov' }
            }
        }
        else {
            $moved = Find-MovedAxis -Base $base -Now (Get-AxisSnapshot $info)
            if ($moved -and $moved.Ambiguous) {
                if ($StatusRow -and -not $lastAmbig) {
                    Write-PanelStatus $StatusRow `
                        ("two axes moving at once (axis$($moved.Index) and axis$($moved.Rival)) - move only one") 'Yellow'
                    $lastAmbig = $true
                }
                Start-Sleep -Milliseconds 40
                continue
            }
            if ($moved) {
                Start-Sleep -Milliseconds 250
                $conf = Read-Stick $Id
                if ($conf) {
                    $c = Get-AxisSnapshot $conf
                    $d2 = $c[$moved.Field] - $base[$moved.Field]
                    if ([math]::Abs($d2) -ge 0.30) { $moved.Sign = $(if ($d2 -ge 0) { '+' } else { '-' }) }
                }
                return @{ Type='Axis'; Index=$moved.Index; Sign=$moved.Sign }
            }
            if ($lastAmbig -and $StatusRow) {
                Write-PanelStatus $StatusRow 'listening...' 'DarkGray'
                $lastAmbig = $false
            }
        }

        Start-Sleep -Milliseconds 25
    }
}

# =============================================================================
# 12. The wizard
# =============================================================================

function Get-Opposite { param([string]$s) if ($s -eq '+') { return '-' } else { return '+' } }

function Show-StepScreen {
    param($Step, [int]$Index, [int]$Total, $Bindings, $Stick, $Map)

    Show-PanelChrome -Stick $Stick -Subtitle ('step {0} of {1}' -f $Index, $Total)
    $row = $script:PanelRow.Body

    Write-At $row 3 ('{0}  /  {1}' -f $Step.Group, $Step.Title) 'White' ($script:PanelWidth - 2)
    if ($Step.Tier -eq 'B') {
        Write-At $row 48 'unconfirmed name' 'DarkYellow' 22
    }

    Write-At ($row + 2) 4 $Step.Prompt 'White' ($script:PanelWidth - 2)
    $r = $row + 3
    if ($Step.Hint) { Write-At $r 4 "($($Step.Hint))" 'DarkGray' ($script:PanelWidth - 2); $r++ }
    if ($Step.Note) { Write-At $r 4 $Step.Note 'DarkGray' ($script:PanelWidth - 2); $r++ }
    if ($Step.Hazard) { Write-At $r 4 ("! " + $Step.HazardNote) 'Yellow' ($script:PanelWidth - 2); $r++ }

    $cur = $null
    $first = @(Get-StepActions $Step)[0].Action
    if ($Bindings.ContainsKey($first)) { $cur = $Bindings[$first] }

    $curText = if ($cur) { "currently: $cur" } else { 'currently: not bound' }
    Write-At ($row + 5) 4 $curText $(if ($cur) { 'Cyan' } else { 'DarkGray' }) ($script:PanelWidth - 2)

    if ($Step.Expect -and $Map -and $Map.ContainsKey($Step.Expect)) {
        $probe = $script:ControlProbes | Where-Object { $_.Key -eq $Step.Expect } | Select-Object -First 1
        Write-At ($row + 6) 4 ("expected control: {0} (axis{1})" -f $probe.Label, $Map[$Step.Expect]) 'DarkGray' ($script:PanelWidth - 2)
    }

    $statusRow = $row + 8
    Write-At ($row + 10) 2 ('-' * $script:PanelWidth) 'DarkGray'

    return @{ Current = $cur; StatusRow = $statusRow; DecisionRow = $row + 9; KeyRow = $row + 11 }
}

function Invoke-Wizard {
    param($Ctx, [int[]] $Only, $Map, $Layout)

    $bindings = @{}
    foreach ($k in $Ctx.Existing.Bindings.Keys) { $bindings[$k] = $Ctx.Existing.Bindings[$k] }

    $excluded = @()
    if ($Layout) { $excluded = @($Layout.Exclude) }

    $candidates = @()
    for ($i = 0; $i -lt $script:Steps.Count; $i++) {
        $acts = @(Get-StepActions $script:Steps[$i] | ForEach-Object { $_.Action })
        $skip = $false
        foreach ($a in $acts) { if ($excluded -contains $a) { $skip = $true } }
        if (-not $skip) { $candidates += $i }
    }
    # a layout that drops actions must also clear them from the config
    foreach ($a in $excluded) { $bindings.Remove($a) | Out-Null }

    # "if ($Only)" is wrong here: @(0) unrolls to the integer 0, which is falsy,
    # so picking only the FIRST item in the list silently walked every step.
    $order = if ($null -ne $Only -and @($Only).Count -gt 0) {
        @($Only | Where-Object { $candidates -contains $_ })
    } else { $candidates }
    $pos = 0

    while ($pos -lt $order.Count) {
        $si   = $order[$pos]
        $step = $script:Steps[$si]

        $ui = Show-StepScreen -Step $step -Index ($pos + 1) -Total $order.Count `
                              -Bindings $bindings -Stick $Ctx.Stick -Map $Map
        $cur = $ui.Current

        # gate 1: nothing is read until you ask for it
        $gate = Wait-ForReady -StatusRow $ui.StatusRow -HasCurrent ([bool]$cur) -KeyRow $ui.KeyRow
        if ($gate -eq 'quit') { return $null }
        if ($gate -eq 'back') { if ($pos -gt 0) { $pos-- }; continue }
        if ($gate -eq 'unbind') {
            foreach ($a in (Get-StepActions $step)) { $bindings.Remove($a.Action) | Out-Null }
            Write-PanelStatus $ui.StatusRow 'unbound' 'Yellow'
            Start-Sleep -Milliseconds 700
            $pos++
            continue
        }
        if ($gate -eq 'skip' -or $gate -eq 'keep') { $pos++; continue }

        $want = switch ($step.Kind) { 'AxisPair' {'Axis'} 'Pov' {'Pov'} default {'Button'} }
        $r = Wait-ForInput -Id $Ctx.Stick.Id -Want $want -CurrentToken $cur `
                           -StatusRow $ui.StatusRow -Stick $Ctx.Stick -Map $Map

        # if/elseif, NOT switch: "continue" inside a PowerShell switch exits the
        # switch, not the loop, and execution would fall into the token builder.
        if ($r.Type -eq 'Control') {
            if ($r.Key -eq 'quit') { return $null }
            if ($r.Key -eq 'back') { if ($pos -gt 0) { $pos-- }; continue }
            if ($r.Key -eq 'unbind') {
                foreach ($a in (Get-StepActions $step)) { $bindings.Remove($a.Action) | Out-Null }
                Write-PanelStatus $ui.StatusRow 'unbound' 'Yellow'
                Start-Sleep -Milliseconds 700
                $pos++
                continue
            }
            $pos++
            continue
        }

        $assign = @{}
        $summary = ''
        $warnings = @()

        if ($step.Kind -eq 'AxisPair') {
            $posTok = 'joystick0:axis{0}{1}' -f $r.Index, $r.Sign
            $negTok = 'joystick0:axis{0}{1}' -f $r.Index, (Get-Opposite $r.Sign)
            $assign[$step.Pos.Action] = @{ Token=$posTok; Preset=$step.Pos.Preset }
            $assign[$step.Neg.Action] = @{ Token=$negTok; Preset=$step.Neg.Preset }
            $label = Get-ControlLabel -Map $Map -AxisIndex $r.Index
            $summary = "axis$($r.Index)$($r.Sign)" + $(if ($label) { "  ($label)" } else { '' })

            # cross-check against what this control was said to be
            if ($step.Expect -and $Map -and $Map.ContainsKey($step.Expect) -and $Map[$step.Expect] -ne $r.Index) {
                $probe = $script:ControlProbes | Where-Object { $_.Key -eq $step.Expect } | Select-Object -First 1
                $warnings += ("that is axis$($r.Index), but you called $($probe.Label) axis$($Map[$step.Expect])")
            }
        }
        elseif ($step.Kind -eq 'Pov') {
            foreach ($a in $step.Actions) {
                $assign[$a.Action] = @{ Token=('joystick0:{0}' -f $a.Token); Preset=$a.Preset }
            }
            $summary = 'hat (all four directions)'
        }
        else {
            $tok = 'joystick0:button{0}' -f $r.Index
            foreach ($a in $step.Actions) {
                $assign[$a.Action] = @{ Token=$tok; Preset=$a.Preset; SingleClick=[bool]$a.SingleClick }
            }
            $summary = "button$($r.Index)"
        }

        foreach ($an in $assign.Keys) {
            $tok = $assign[$an].Token
            foreach ($other in $bindings.Keys) {
                if ($assign.ContainsKey($other)) { continue }
                if ($bindings[$other] -ne $tok) { continue }
                if ((Get-ActionContext $other) -eq $step.Context) { $warnings += "$tok already used by $other" }
            }
        }

        # gate 2: nothing is recorded until you confirm the reading
        Write-PanelStatus $ui.StatusRow ("read as:  $summary") 'Green'
        $wr = $ui.StatusRow + 1
        $shown = @($warnings | Select-Object -Unique)
        if ($shown.Count) {
            Write-At $wr 4 ('! ' + $shown[0]) 'Yellow' ($script:PanelWidth - 2)
            if ($shown.Count -gt 1) { Write-At ($wr + 1) 4 ('! ' + $shown[1]) 'Yellow' ($script:PanelWidth - 2) }
        } else {
            Write-At $wr 4 '' 'Gray' ($script:PanelWidth - 2)
            Write-At ($wr + 1) 4 '' 'Gray' ($script:PanelWidth - 2)
        }

        # a reading that contradicts your control map has to be confirmed twice
        $needsExtra = ($shown.Count -gt 0)
        $prompt = if ($needsExtra) { 'y accept anyway   r try again   s skip' }
                  else             { 'ENTER accept   r try again   s skip' }
        Write-At $ui.KeyRow 4 $prompt 'White' ($script:PanelWidth - 2)

        $decision = $null
        while (-not $decision) {
            $k = Read-KeyChar
            if ($k -eq 'r') { $decision = 'redo' }
            elseif ($k -eq 's') { $decision = 'skip' }
            elseif ($k -eq 'q') { return $null }
            elseif ($needsExtra -and $k -eq 'y') { $decision = 'accept' }
            elseif (-not $needsExtra -and $k -eq "`r") { $decision = 'accept' }
        }
        if ($decision -eq 'redo') { continue }
        if ($decision -eq 'skip') { $pos++; continue }

        foreach ($an in $assign.Keys) {
            $bindings[$an] = $assign[$an].Token
            $script:Presets[$an] = $assign[$an]
        }
        $pos++
    }

    return $bindings
}

# =============================================================================
# 13. Preflight, review, save
# =============================================================================

function Invoke-Preflight {
    Write-Header
    Write-Host ''
    Write-Host '  PREFLIGHT' -ForegroundColor White
    Write-Host ''

    $problems = @(); $warnings = @()

    $stick = Get-Stick
    if (-not $stick) {
        Write-Bad 'No joystick detected.'
        Write-Note 'Plug it in, set the base switch to PC mode, then re-run.'
        Pause-Any 'press any key to exit'
        return $null
    }
    if ($stick.Vid -eq 0x044F -and $stick.Pid -eq 0xB67B) {
        $warnings += 'Stick is in PS4 mode. Reforger wants PC mode - flip the switch on the base.'
    }

    Write-Field 'Device' (Get-StickName $stick) 'White'
    Write-Field 'Layout' ("{0} axes   {1} buttons   hat {2}" -f $stick.Axes, $stick.Buttons, $(if ($stick.HasPov) {'yes'} else {'no'}))

    if (Test-GameRunning) {
        Write-Field 'Reforger' 'RUNNING' 'Yellow'
        $warnings += 'Reforger is running. It rewrites this file on exit - close it before saving.'
    } else {
        Write-Field 'Reforger' 'not running' 'Green'
    }

    $dir = Resolve-ProfileDir
    if (-not $dir) {
        Write-Field 'Profile' 'NOT FOUND' 'Red'
        $problems += 'Could not find the Reforger profile folder. Pass -ProfileDir.'
    } else {
        Write-Field 'Profile' $dir
        try {
            $probe = Join-Path $dir '.writetest'
            [IO.File]::WriteAllText($probe, 'x'); Remove-Item $probe -Force
        } catch { $problems += 'The profile folder is not writable by this account.' }
    }

    if (-not $PSBoundParameters.ContainsKey('ConfigName')) {
        $script:ConfigName = Resolve-ConfigName -Dir $dir -Preferred $ConfigName
    }
    $cfgPath = if ($dir) { Join-Path $dir $ConfigName } else { $null }
    $existing = if ($cfgPath) { Read-ExistingConfig $cfgPath } else { @{ Bindings=@{}; Unknown=@(); Raw='' } }
    if ($cfgPath -and (Test-Path $cfgPath)) {
        Write-Field 'Config' ("{0}  ({1} bound)" -f $ConfigName, $existing.Bindings.Count)
        if ($existing.Unknown.Count) {
            $warnings += ("Config has {0} action(s) this tool does not know ({1}). They will be preserved." -f $existing.Unknown.Count, ($existing.Unknown -join ', '))
        }
    } else {
        Write-Field 'Config' 'none yet - will create one'
    }

    $map = Import-ControlMap
    if ($map.Count) {
        $desc = ($script:ControlProbes | Where-Object { $map.ContainsKey($_.Key) } |
                 ForEach-Object { "$($_.Label)=axis$($map[$_.Key])" }) -join ', '
        Write-Field 'Controls' $desc 'DarkCyan'
    } else {
        Write-Field 'Controls' 'not mapped yet - run option 3' 'DarkYellow'
    }

    Write-Host ''
    Write-Host '  RESTING DRIFT' -ForegroundColor White
    Write-Note 'Hands off the stick...'
    Start-Sleep -Milliseconds 400
    $samples = @()
    for ($n = 0; $n -lt 25; $n++) {
        $info = Read-Stick $stick.Id
        if ($info) { $samples += ,(Get-AxisSnapshot $info) }
        Start-Sleep -Milliseconds 20
    }
    if ($samples.Count) {
        $drift = @{}
        foreach ($f in $script:AxisMap.Keys) {
            $stats = $samples | ForEach-Object { $_[$f] } | Measure-Object -Maximum -Minimum
            $drift[$f] = $stats.Maximum - $stats.Minimum
        }
        $line = ($script:AxisRows | ForEach-Object { 'axis{0} {1:0.00}' -f $_.Index, $drift[$_.Field] }) -join '   '
        $worst = ($drift.Values | Measure-Object -Maximum).Maximum
        Write-Host "    $line" -ForegroundColor $(if ($worst -gt 0.06) { 'Yellow' } else { 'Green' })
        if ($worst -gt 0.06) {
            $warnings += ('An axis jitters by {0:0.00} at rest. Set a deadzone in joy.cpl.' -f $worst)
        }
    }

    Write-Host ''
    Write-Rule
    foreach ($w in $warnings) { Write-Warn "!  $w" }
    foreach ($p in $problems) { Write-Bad  "X  $p" }
    if (-not $warnings.Count -and -not $problems.Count) { Write-Good 'All clear.' }
    if ($problems.Count) { Pause-Any 'press any key to exit'; return $null }

    Pause-Any
    return [pscustomobject]@{ Stick=$stick; Dir=$dir; CfgPath=$cfgPath; Existing=$existing; Map=$map }
}

function Show-Review {
    param($Bindings, $Map)
    Write-Header
    Write-Host ''
    Write-Host '  REVIEW' -ForegroundColor White
    Write-Host ''

    foreach ($group in @('FLIGHT','GUNNER','VIEW','ON FOOT')) {
        $rows = @()
        foreach ($step in ($script:Steps | Where-Object { $_.Group -eq $group })) {
            $first = @(Get-StepActions $step)[0].Action
            if ($Bindings.ContainsKey($first)) {
                $t = $Bindings[$first]
                if ($step.Kind -eq 'AxisPair') {
                    $ax = $t -replace '^joystick0:axis','' -replace '[+-]$',''
                    $lbl = Get-ControlLabel -Map $Map -AxisIndex ([int]$ax)
                    $t = "axis$ax both ways" + $(if ($lbl) { "  ($lbl)" } else { '' })
                } elseif ($step.Kind -eq 'Pov') { $t = 'hat' }
                else { $t = $t -replace '^joystick0:','' }
                $rows += [pscustomobject]@{ Title=$step.Title; Token=$t; Tier=$step.Tier }
            } else {
                $rows += [pscustomobject]@{ Title=$step.Title; Token='-'; Tier=$step.Tier }
            }
        }
        if (-not $rows.Count) { continue }
        Write-Host "  $group" -ForegroundColor DarkCyan
        foreach ($r in $rows) {
            $col = if ($r.Token -eq '-') { 'DarkGray' } elseif ($r.Tier -eq 'B') { 'DarkYellow' } else { 'Gray' }
            Write-Host ('    {0,-28} {1}' -f $r.Title, $r.Token) -ForegroundColor $col
        }
        Write-Host ''
    }

    $tierB = @()
    foreach ($step in $script:Steps) {
        if ($step.Tier -ne 'B') { continue }
        $first = @(Get-StepActions $step)[0].Action
        if ($Bindings.ContainsKey($first)) { $tierB += $first }
    }
    if ($tierB.Count) {
        Write-Rule
        Write-Warn "Unconfirmed action names: $($tierB -join ', ')"
        Write-Note 'After your next launch run  .\Check-HotasLog.ps1  to see if the engine took them.'
        Write-Host ''
    }
}

function Save-Config {
    param($Bindings, $Ctx)

    $text = Build-Config -Bindings $Bindings -Existing $Ctx.Existing
    $check = Test-ConfigText $text

    Write-Rule
    Write-Host ''
    Write-Host '  VALIDATION' -ForegroundColor White
    Write-Field 'Actions' $check.Actions
    Write-Field 'Ids' ("{0}, all unique" -f $check.Guids)
    if (-not $check.Ok) {
        Write-Field 'Structure' 'INVALID' 'Red'
        foreach ($i in $check.Issues) { Write-Bad "  $i" }
        Write-Host ''
        Write-Bad 'Refusing to write a malformed config. Nothing changed.'
        Pause-Any 'press any key to exit'
        return $false
    }
    Write-Field 'Structure' 'valid' 'Green'

    if (Test-GameRunning) {
        Write-Host ''
        Write-Warn '!  Reforger is running and will overwrite this file when it exits. Close it first.'
    }

    Write-Host ''
    Write-Host '    Write this to your profile?  [y] yes   [n] no' -ForegroundColor White
    $ans = $null
    while (-not $ans) { switch (Read-KeyChar) { 'y' {$ans='y'} 'n' {$ans='n'} 'q' {$ans='n'} } }
    if ($ans -eq 'n') { Write-Host ''; Write-Note 'Nothing written.'; Pause-Any; return $false }

    if (Test-Path $Ctx.CfgPath) {
        $backup = Join-Path $script:Root ("backup-{0}-{1}" -f (Get-Date -Format 'yyyyMMdd-HHmmss'), $ConfigName)
        Copy-Item $Ctx.CfgPath $backup -Force
        Write-Host ''
        Write-Good "backed up -> $(Split-Path -Leaf $backup)"
    }

    [IO.File]::WriteAllText($Ctx.CfgPath, $text, (New-Object Text.UTF8Encoding($false)))
    Write-Good "written    -> $($Ctx.CfgPath)"

    $back = Get-Content -Raw $Ctx.CfgPath
    if ((Test-ConfigText $back).Ok -and $back.TrimEnd() -eq $text.TrimEnd()) {
        Write-Good 'verified   -> re-parses cleanly from disk'
    } else {
        Write-Bad 'WARNING: the file on disk did not re-validate. Restore the backup.'
    }

    Write-Host ''
    Write-Rule
    Write-Note 'Next: launch Reforger, then run  .\Check-HotasLog.ps1'
    Pause-Any
    return $true
}

# =============================================================================
# 14. Menus
# =============================================================================

function Select-Layout {
    Write-Header
    Write-Host ''
    Write-Host '  WHAT IS THE STICK FOR?' -ForegroundColor White
    Write-Host ''
    foreach ($l in $script:Layouts) {
        Write-Host ("    [$($l.Key)]  $($l.Name)") -ForegroundColor Gray
        Write-Note "       $($l.Desc)"
        Write-Host ''
    }
    Write-Rule
    while ($true) {
        $k = Read-KeyChar
        if ($k -eq 'q') { return $null }
        $hit = $script:Layouts | Where-Object { $_.Key -eq $k } | Select-Object -First 1
        if ($hit) { return $hit }
    }
}

function Select-Steps {
    param($Ctx, $Map)
    $picked = @()
    while ($true) {
        Write-Header
        Write-Host ''
        Write-Host '  PICK WHAT TO CHANGE' -ForegroundColor White
        Write-Note 'type a number and press enter; blank line when done'
        Write-Host ''
        $lastGroup = ''
        for ($i = 0; $i -lt $script:Steps.Count; $i++) {
            $s = $script:Steps[$i]
            if ($s.Group -ne $lastGroup) { Write-Host ''; Write-Host "  $($s.Group)" -ForegroundColor DarkCyan; $lastGroup = $s.Group }
            $first = @(Get-StepActions $s)[0].Action
            $cur = if ($Ctx.Existing.Bindings.ContainsKey($first)) { $Ctx.Existing.Bindings[$first] -replace '^joystick0:','' } else { '-' }
            $mark = if ($picked -contains $i) { '*' } else { ' ' }
            $col  = if ($picked -contains $i) { 'Cyan' } else { 'Gray' }
            Write-Host ('   {0}{1,3}. {2,-28} {3}' -f $mark, ($i + 1), $s.Title, $cur) -ForegroundColor $col
        }
        Write-Host ''
        Write-Rule
        Write-Host '    number = toggle    [enter] = start    [q] = back' -ForegroundColor DarkGray
        Write-Host '    > ' -NoNewline
        $inp = Read-Host
        if ($inp -eq 'q') { return $null }
        if ([string]::IsNullOrWhiteSpace($inp)) { if ($picked.Count) { return ($picked | Sort-Object) }; continue }
        $n = 0
        if ([int]::TryParse($inp.Trim(), [ref]$n) -and $n -ge 1 -and $n -le $script:Steps.Count) {
            $idx = $n - 1
            if ($picked -contains $idx) { $picked = @($picked | Where-Object { $_ -ne $idx }) }
            else { $picked += $idx }
        }
    }
}

function Show-Menu {
    param($Ctx)
    while ($true) {
        Write-Header
        Write-Host ''
        Write-Host '  WHAT DO YOU WANT TO DO?' -ForegroundColor White
        Write-Host ''
        Write-Host '    [1]  Change a few bindings' -ForegroundColor Gray
        Write-Note  '       pick individual actions from a list'
        Write-Host ''
        Write-Host '    [2]  Full wizard' -ForegroundColor Gray
        Write-Note  '       choose a layout, then walk every binding'
        Write-Host ''
        Write-Host '    [3]  Identify my controls' -ForegroundColor Gray
        Write-Note  '       teach the tool which axis is the stick, throttle, rocker'
        Write-Host ''
        Write-Host '    [4]  Show current bindings' -ForegroundColor Gray
        Write-Host ''
        Write-Host '    [q]  Quit' -ForegroundColor Gray
        Write-Host ''
        Write-Rule
        switch (Read-KeyChar) {
            '1' { return 'few' }
            '2' { return 'full' }
            '3' { return 'map' }
            '4' {
                $b = @{}
                foreach ($x in $Ctx.Existing.Bindings.Keys) { $b[$x] = $Ctx.Existing.Bindings[$x] }
                Show-Review -Bindings $b -Map $Ctx.Map
                Pause-Any
            }
            'q' { return 'quit' }
        }
    }
}

# =============================================================================
# 15. Tests
# =============================================================================

$script:_p = 0
$script:_f = 0

function T {
    param([string]$Name, [bool]$Ok, [string]$Detail = '')
    if ($Ok) { Write-Host "  PASS  $Name" -ForegroundColor Green; $script:_p++ }
    else     { Write-Host "  FAIL  $Name  $Detail" -ForegroundColor Red; $script:_f++ }
}

function New-FakeInfo {
    param(
        [int] $x = 32767, [int] $y = 32767, [int] $z = 32767,
        [int] $r = 32767, [int] $u = 32767, [int] $v = 32767,
        [uint32] $buttons = 0, [uint32] $pov = 65535
    )
    return [pscustomobject]@{
        dwXpos=[uint32]$x; dwYpos=[uint32]$y; dwZpos=[uint32]$z
        dwRpos=[uint32]$r; dwUpos=[uint32]$u; dwVpos=[uint32]$v
        dwButtons=$buttons; dwPOV=$pov
    }
}

function Invoke-SelfTest {
    Write-Host ''
    Write-Host '  UNIT TESTS' -ForegroundColor Cyan
    Write-Host ''

    # --- catalogue ---------------------------------------------------------
    $all = @()
    foreach ($s in $script:Steps) { foreach ($a in (Get-StepActions $s)) { $all += $a.Action } }
    $dupes = $all | Group-Object | Where-Object Count -gt 1 | ForEach-Object { $_.Name }
    T 'no duplicate action names' ($dupes.Count -eq 0) ($dupes -join ',')

    $missing = @()
    foreach ($s in $script:Steps) {
        if (-not $s.Title -or -not $s.Prompt -or -not $s.Kind -or -not $s.Context) { $missing += $s.Title }
        foreach ($a in (Get-StepActions $s)) { if (-not $a.Preset) { $missing += "$($s.Title):$($a.Action)" } }
    }
    T 'every step fully specified' ($missing.Count -eq 0) ($missing -join ',')
    T 'catalogue has 21 steps' ($script:Steps.Count -eq 21) "got $($script:Steps.Count)"

    $badIndex = @(); $badCount = @()
    foreach ($s in $script:Steps) {
        $acts = Get-StepActions $s
        if (-not ($acts -is [array])) { $badIndex += "$($s.Title): not an array"; continue }
        if ($null -eq @($acts)[0].Action) { $badIndex += "$($s.Title): [0].Action null" }
        $want = if ($s.Kind -eq 'AxisPair') { 2 } else { @($s.Actions).Count }
        if (@($acts).Count -ne $want) { $badCount += "$($s.Title): $(@($acts).Count) vs $want" }
    }
    T 'Get-StepActions[0].Action resolves everywhere' ($badIndex.Count -eq 0) ($badIndex -join '; ')
    T 'Get-StepActions counts are right' ($badCount.Count -eq 0) ($badCount -join '; ')
    $single = $script:Steps | Where-Object { $_.Kind -eq 'Button' -and @($_.Actions).Count -eq 1 } | Select-Object -First 1
    T 'a one-action step still returns an array' ((Get-StepActions $single) -is [array])

    # every AxisPair declares which control it should be
    $noExpect = @($script:Steps | Where-Object { $_.Kind -eq 'AxisPair' -and -not $_.Expect } | ForEach-Object { $_.Title })
    T 'every axis step declares an expected control' ($noExpect.Count -eq 0) ($noExpect -join ',')
    $probeKeys = $script:ControlProbes | ForEach-Object { $_.Key }
    $badExpect = @($script:Steps | Where-Object { $_.Expect -and ($probeKeys -notcontains $_.Expect) } | ForEach-Object { $_.Title })
    T 'expected controls all exist as probes' ($badExpect.Count -eq 0) ($badExpect -join ',')
    T 'turret rotate expects the rocker' `
        ((($script:Steps | Where-Object { $_.Title -eq 'Turret rotate' }).Expect) -eq 'Rocker')

    # --- button masks ------------------------------------------------------
    $maskErr = @()
    for ($b = 0; $b -lt 32; $b++) {
        try { if ((Get-ButtonMask $b) -ne [uint32][math]::Pow(2, $b)) { $maskErr += "bit $b" } }
        catch { $maskErr += "bit $b threw" }
    }
    T 'button masks correct for all 32 bits' ($maskErr.Count -eq 0) ($maskErr -join ';')
    T 'button mask 31 does not overflow' ((Get-ButtonMask 31) -eq [uint32]2147483648)

    # --- axis detection ----------------------------------------------------
    function Snap { param([double]$x=0,[double]$y=0,[double]$z=0,[double]$r=0,[double]$u=0,[double]$v=0)
        return @{ dwXpos=$x; dwYpos=$y; dwZpos=$z; dwRpos=$r; dwUpos=$u; dwVpos=$v } }
    $idle = Snap
    T 'idle reports nothing'  ($null -eq (Find-MovedAxis -Base $idle -Now $idle))
    T 'jitter is ignored'     ($null -eq (Find-MovedAxis -Base $idle -Now (Snap -x 0.2)))
    $m = Find-MovedAxis -Base $idle -Now (Snap -x 0.9);  T 'stick right = axis0+' ($m.Index -eq 0 -and $m.Sign -eq '+')
    $m = Find-MovedAxis -Base $idle -Now (Snap -x -0.9); T 'stick left = axis0-'  ($m.Index -eq 0 -and $m.Sign -eq '-')
    $m = Find-MovedAxis -Base $idle -Now (Snap -z 0.9);  T 'throttle = axis2'     ($m.Index -eq 2)
    $m = Find-MovedAxis -Base $idle -Now (Snap -r -0.9); T 'twist = axis5'        ($m.Index -eq 5)
    $m = Find-MovedAxis -Base $idle -Now (Snap -u 0.9);  T 'U = axis3'            ($m.Index -eq 3)
    $m = Find-MovedAxis -Base $idle -Now (Snap -v 0.9);  T 'V = axis4'            ($m.Index -eq 4)
    $m = Find-MovedAxis -Base (Snap -z -1.0) -Now (Snap -z 1.0)
    T 'axis resting at an extreme still reads' ($m.Index -eq 2 -and $m.Sign -eq '+')

    # --- ambiguity: the bug that bound the cyclic to the rocker ------------
    $m = Find-MovedAxis -Base $idle -Now (Snap -x 0.9 -v 0.8)
    T 'two axes moving together is flagged ambiguous' ($m -and $m.Ambiguous) "amb=$($m.Ambiguous)"
    $m = Find-MovedAxis -Base $idle -Now (Snap -x 0.95 -v 0.30)
    T 'a clear winner is not flagged ambiguous' ($m -and -not $m.Ambiguous -and $m.Index -eq 0)
    $m = Find-MovedAxis -Base $idle -Now (Snap -x 0.9 -v 0.15)
    T 'small secondary movement is tolerated' ($m -and -not $m.Ambiguous -and $m.Index -eq 0)
    $m = Find-MovedAxis -Base $idle -Now (Snap -x 0.60 -v 0.55)
    T 'near-tie names the rival axis' ($m.Ambiguous -and $m.Rival -eq 4) "rival=$($m.Rival)"

    # --- buttons -----------------------------------------------------------
    T 'no press reads null'   ($null -eq (Find-PressedButton -Base 0 -Now 0))
    T 'button 0 detected'     (0  -eq (Find-PressedButton -Base 0 -Now (Get-ButtonMask 0)))
    T 'button 11 detected'    (11 -eq (Find-PressedButton -Base 0 -Now (Get-ButtonMask 11)))
    T 'button 31 detected'    (31 -eq (Find-PressedButton -Base 0 -Now (Get-ButtonMask 31)))
    T 'held button not re-detected' ($null -eq (Find-PressedButton -Base (Get-ButtonMask 5) -Now (Get-ButtonMask 5)))
    T 'new press beside a held one'  (7 -eq (Find-PressedButton -Base (Get-ButtonMask 5) -Now ((Get-ButtonMask 5) -bor (Get-ButtonMask 7))))

    # --- bar rendering -----------------------------------------------------
    T 'bar has the right width'      ((Get-Bar 0).Length -eq 23)
    T 'centred bar marks the middle' ((Get-Bar 0)[11] -eq '#')
    T 'full right puts marker last'  ((Get-Bar 1)[21] -eq '#')
    T 'full left puts marker first'  ((Get-Bar -1)[1] -eq '#')
    T 'out of range values clamp'    ((Get-Bar 9).Length -eq 23 -and (Get-Bar -9).Length -eq 23)

    # --- tokens ------------------------------------------------------------
    foreach ($good in @('joystick0:axis0+','joystick0:axis5-','joystick0:button0','joystick0:pov_up')) {
        T "token '$good' accepted" (Test-InputToken $good)
    }
    foreach ($bad in @('joystick0:button','joystick0:axis','joystick0:axis2','', 'keyboard:KC_A')) {
        T "token '$bad' rejected" (-not (Test-InputToken $bad))
    }

    # --- validator ---------------------------------------------------------
    T 'catches brace mismatch' (-not (Test-ConfigText "ActionManager {`n Actions {`n").Ok)
    $dupId = 'ActionManager { Actions { Action A { InputSource InputSourceSum "{AAAAAAAAAAAAAAAA}" { } } Action B { InputSource InputSourceSum "{AAAAAAAAAAAAAAAA}" { } } } }'
    T 'catches duplicate ids' (-not (Test-ConfigText $dupId).Ok)

    # --- generation and round trip ----------------------------------------
    $script:Presets = @{}
    $fake = @{}
    foreach ($s in $script:Steps) {
        if ($s.Kind -eq 'AxisPair') { $fake[$s.Pos.Action]='joystick0:axis0+'; $fake[$s.Neg.Action]='joystick0:axis0-' }
        elseif ($s.Kind -eq 'Pov')  { foreach ($a in $s.Actions) { $fake[$a.Action]="joystick0:$($a.Token)" } }
        else { foreach ($a in $s.Actions) { $fake[$a.Action]='joystick0:button0' } }
    }
    $gen = Build-Config -Bindings $fake -Existing @{ Unknown=@(); Raw='' }
    $chk = Test-ConfigText $gen
    T 'generated config valid' $chk.Ok ($chk.Issues -join '; ')
    T 'generated config complete' ($chk.Actions -eq $fake.Count)
    T 'emits SingleClick filter' ($gen -match 'InputFilterSingleClick')

    $tmp = Join-Path $env:TEMP ('hotas-st-{0}.conf' -f $PID)
    [IO.File]::WriteAllText($tmp, $gen, (New-Object Text.UTF8Encoding($false)))
    $rt = Read-ExistingConfig $tmp
    T 'round trip recovers every binding' ($rt.Bindings.Count -eq $fake.Count)
    $ok = $true; foreach ($k in $fake.Keys) { if ($rt.Bindings[$k] -ne $fake[$k]) { $ok = $false } }
    T 'round trip recovers exact tokens' $ok

    $withUnknown = $gen -replace '(?m)^ \}\r?\n\}\r?\n?$', @'
  Action SomeModAction {
   InputSource InputSourceSum "{1234567890ABCDEF}" {
    Sources {
     InputSourceValue "{1234567890ABCDE0}" {
      FilterPreset "click"
      Input "joystick0:button11"
     }
    }
   }
  }
 }
}
'@
    [IO.File]::WriteAllText($tmp, $withUnknown, (New-Object Text.UTF8Encoding($false)))
    $ru = Read-ExistingConfig $tmp
    T 'unknown action detected' ($ru.Unknown -contains 'SomeModAction')
    T 'unknown action survives a rewrite' ((Build-Config -Bindings $ru.Bindings -Existing $ru) -match 'SomeModAction')
    Remove-Item $tmp -Force -ErrorAction SilentlyContinue

    # --- control map -------------------------------------------------------
    $map = @{ StickX=0; StickY=1; Throttle=2; Twist=5; Rocker=4 }
    T 'control map labels a known axis' ((Get-ControlLabel -Map $map -AxisIndex 4) -eq 'Throttle rocker')
    T 'control map returns null for unknown' ($null -eq (Get-ControlLabel -Map $map -AxisIndex 3))
    T 'control map survives a null map' ($null -eq (Get-ControlLabel -Map $null -AxisIndex 0))

    # --- filename resolution ----------------------------------------------
    $tdir = Join-Path $env:TEMP ('hotas-cfg-{0}' -f $PID)
    New-Item -ItemType Directory -Path $tdir -Force | Out-Null
    T 'empty folder keeps the preferred name' ((Resolve-ConfigName -Dir $tdir -Preferred 'A.conf') -eq 'A.conf')
    Set-Content (Join-Path $tdir 'Joystick_Other_0.conf') 'x'
    T 'a single unfamiliar config is found' ((Resolve-ConfigName -Dir $tdir -Preferred 'A.conf') -eq 'Joystick_Other_0.conf')
    Remove-Item $tdir -Recurse -Force -ErrorAction SilentlyContinue

    # --- live config -------------------------------------------------------
    $dir = Resolve-ProfileDir
    if ($dir) {
        $p = Join-Path $dir $ConfigName
        if (Test-Path $p) {
            $real = Read-ExistingConfig $p
            T 'live config parses' ($real.Bindings.Count -gt 0)
            T 'live config is valid' (Test-ConfigText $real.Raw).Ok
        }
    }
    Write-Host ''
}

function Invoke-IntegrationTest {
    Write-Host '  INTEGRATION TESTS' -ForegroundColor Cyan
    Write-Host ''

    $livePath = $null; $before = $null
    $dir = Resolve-ProfileDir
    if ($dir) {
        $livePath = Join-Path $dir $ConfigName
        if (Test-Path $livePath) { $before = (Get-FileHash $livePath -Algorithm SHA256).Hash }
    }
    $stick = [pscustomobject]@{ Id=[uint32]0; Vid=0x044F; Pid=0xB67C; Axes=6; Buttons=12; HasPov=$true; IsTM=$true }

    # ---- the real listen loop, fed a fake device ----
    # IDLE covers the stillness check (6 reads) plus the baseline (8 reads).
    $IDLE = 20
    & {
        function Start-Sleep { param($Milliseconds, $Seconds) }
        function Test-KeyWaiting { return $false }

        $script:_r = 0
        function Read-Stick { param($Id)
            $script:_r++
            if ($script:_r -le 20) { return New-FakeInfo }
            if ($script:_r -le 24) { return New-FakeInfo -buttons (Get-ButtonMask 8) }
            return New-FakeInfo }
        $r = Wait-ForInput -Id 0 -Want 'Button' -CurrentToken $null -Stick $stick
        T 'loop detects a button press' ($r.Type -eq 'Button' -and $r.Index -eq 8)

        $script:_r = 0
        function Read-Stick { param($Id)
            $script:_r++
            if ($script:_r -le 20) { return New-FakeInfo }
            if ($script:_r -le 24) { return New-FakeInfo -buttons (Get-ButtonMask 0) }
            return New-FakeInfo }
        $r = Wait-ForInput -Id 0 -Want 'Button' -CurrentToken $null -Stick $stick
        T 'loop detects button 0 (falsy index)' ($r.Type -eq 'Button' -and $r.Index -eq 0)

        $script:_r = 0
        function Read-Stick { param($Id)
            $script:_r++
            if ($script:_r -le 20) { return New-FakeInfo }
            return New-FakeInfo -z 65535 }
        $r = Wait-ForInput -Id 0 -Want 'Axis' -CurrentToken $null -Stick $stick
        T 'loop detects throttle forward as axis2+' ($r.Type -eq 'Axis' -and $r.Index -eq 2 -and $r.Sign -eq '+')

        $script:_r = 0
        function Read-Stick { param($Id)
            $script:_r++
            if ($script:_r -le 20) { return New-FakeInfo }
            return New-FakeInfo -v 65535 }
        $r = Wait-ForInput -Id 0 -Want 'Axis' -CurrentToken $null -Stick $stick
        T 'loop detects the rocker as axis4+' ($r.Type -eq 'Axis' -and $r.Index -eq 4 -and $r.Sign -eq '+')

        # THE REGRESSION: a stick still recoiling from the previous prompt must
        # not poison the baseline. Reads 1..12 show X springing back to centre;
        # only after it settles should the baseline be taken, so the throttle
        # that moves afterwards is what gets detected -- not axis0.
        $script:_r = 0
        function Read-Stick { param($Id)
            $script:_r++
            if ($script:_r -le 4)  { return New-FakeInfo -x 65535 }
            if ($script:_r -le 8)  { return New-FakeInfo -x 55000 }
            if ($script:_r -le 12) { return New-FakeInfo -x 40000 }
            if ($script:_r -le 30) { return New-FakeInfo }
            return New-FakeInfo -z 65535 }
        $r = Wait-ForInput -Id 0 -Want 'Axis' -CurrentToken $null -Stick $stick
        T 'a recoiling axis does not poison the next reading' `
            ($r.Type -eq 'Axis' -and $r.Index -eq 2) "got axis$($r.Index)"

        # stick and rocker together must NOT resolve
        $script:_r = 0
        function Read-Stick { param($Id)
            $script:_r++
            if ($script:_r -le 20) { return New-FakeInfo }
            if ($script:_r -le 60) { return New-FakeInfo -x 62000 -v 60000 }
            return New-FakeInfo -x 65535 }
        $r = Wait-ForInput -Id 0 -Want 'Axis' -CurrentToken $null -Stick $stick
        T 'loop refuses to resolve two axes moving together' `
            ($r.Type -eq 'Axis' -and $r.Index -eq 0) "got $($r.Type)/$($r.Index)"

        $script:_r = 0
        function Read-Stick { param($Id)
            $script:_r++
            if ($script:_r -le 20) { return New-FakeInfo }
            if ($script:_r -le 24) { return New-FakeInfo -pov 9000 }
            return New-FakeInfo }
        $r = Wait-ForInput -Id 0 -Want 'Pov' -CurrentToken $null -Stick $stick
        T 'loop detects the hat' ($r.Type -eq 'Pov')

        function Read-Stick { param($Id) return $null }
        $r = Wait-ForInput -Id 0 -Want 'Button' -CurrentToken $null -Stick $stick
        T 'dead device aborts rather than skipping' ($r.Type -eq 'Control' -and $r.Key -eq 'quit')
    }

    # ---- stillness gate ----
    & {
        function Start-Sleep { param($Milliseconds, $Seconds) }
        function Read-Stick { param($Id) return New-FakeInfo -x 40000 }
        T 'a steady stick is still even when off centre' (Wait-ForStillness -Id 0)

        $script:_r = 0
        function Read-Stick { param($Id)
            $script:_r++
            if ($script:_r -le 30) { return New-FakeInfo -x (20000 + ($script:_r * 900)) }
            return New-FakeInfo -x 47000 }
        T 'a moving stick is not still until it stops' (Wait-ForStillness -Id 0)
        T 'stillness waited for the movement to stop' ($script:_r -gt 30) "stopped at $($script:_r)"

        function Read-Stick { param($Id) return $null }
        T 'stillness reports failure on a dead device' (-not (Wait-ForStillness -Id 0))

        # a permanently noisy device must time out rather than deadlock
        $script:_n = 0
        function Read-Stick { param($Id)
            $script:_n++
            return New-FakeInfo -x $(if ($script:_n % 2) { 10000 } else { 60000 }) }
        T 'a permanently noisy stick times out instead of hanging' (Wait-ForStillness -Id 0 -TimeoutMs 300)
    }

    # ---- the ready gate ----
    & {
        function Test-KeyWaiting { return $true }
        $script:_key = "`r"
        function Read-KeyChar { return $script:_key }
        T 'Enter keeps the existing binding'   ((Wait-ForReady -StatusRow 0 -HasCurrent $true)  -eq 'keep')
        T 'Enter starts listening when unbound'((Wait-ForReady -StatusRow 0 -HasCurrent $false) -eq 'go')
        $script:_key = ' '
        T 'Space always starts listening'      ((Wait-ForReady -StatusRow 0 -HasCurrent $true)  -eq 'go')
        foreach ($p in @(@('s','skip'), @('b','back'), @('u','unbind'), @('q','quit'))) {
            $script:_key = $p[0]
            T "gate honours '$($p[0])' as $($p[1])" ((Wait-ForReady -StatusRow 0 -HasCurrent $true) -eq $p[1])
        }
    }

    & {
        function Start-Sleep { param($Milliseconds, $Seconds) }
        function Read-Stick { param($Id) return New-FakeInfo }
        function Test-KeyWaiting { return $true }
        foreach ($pair in @(@('s','skip'), @('b','back'), @('u','unbind'), @('q','quit'))) {
            $script:_key = $pair[0]
            function Read-KeyChar { return $script:_key }
            $r = Wait-ForInput -Id 0 -Want 'Button' -CurrentToken 'joystick0:button1' -Stick $stick
            T "loop honours '$($pair[0])' as $($pair[1])" ($r.Key -eq $pair[1])
        }
        $script:_key = "`r"
        function Read-KeyChar { return $script:_key }
        $r = Wait-ForInput -Id 0 -Want 'Button' -CurrentToken 'joystick0:button1' -Stick $stick
        T 'loop honours Enter as keep' ($r.Key -eq 'keep')
    }

    # ---- the whole flow, listen loop stubbed ----
    $map = @{ StickX=0; StickY=1; Throttle=2; Twist=5; Rocker=4 }
    $ctx = [pscustomobject]@{
        Stick=$stick; Dir=$env:TEMP
        CfgPath=(Join-Path $env:TEMP ('hotas-it-{0}.conf' -f $PID))
        Existing=@{ Bindings=@{}; Raw=''; Unknown=@() }; Map=$map
    }

    $flow = & {
        function Clear-Host { }
        function Start-Sleep { param($Milliseconds, $Seconds) }
        function Read-KeyChar { return "`r" }
        $script:_a = 0; $script:_b = 0
        function Wait-ForInput { param($Id,$Want,$CurrentToken,$StatusRow,$Stick,$Map)
            if ($Want -eq 'Axis') { $i = $script:_a; $script:_a++; return @{Type='Axis'; Index=($i % 6); Sign='+'} }
            if ($Want -eq 'Pov')  { return @{Type='Pov'} }
            $i = $script:_b; $script:_b++; return @{Type='Button'; Index=($i % 12)} }
        # no control map here: this test is about the walk, not the cross-check
        Invoke-Wizard -Ctx $ctx -Only $null -Map $null -Layout $null 6>$null
    }
    T 'full run returns a binding set' ($null -ne $flow)
    $allA = @(); foreach ($s in $script:Steps) { foreach ($a in (Get-StepActions $s)) { $allA += $a.Action } }
    T 'full run binds everything' (@($allA | Where-Object { -not $flow.ContainsKey($_) }).Count -eq 0)
    T 'config from a full run is valid' (Test-ConfigText (Build-Config -Bindings $flow -Existing $ctx.Existing)).Ok

    # layout exclusion must drop turret aim from the stick
    $focus = $script:Layouts | Where-Object { $_.Name -eq 'Helicopter focus' } | Select-Object -First 1
    $ctx3 = [pscustomobject]@{
        Stick=$stick; Dir=$env:TEMP; CfgPath=$ctx.CfgPath; Map=$map
        Existing=@{ Bindings=@{ 'TurretAimLeft'='joystick0:axis0-'; 'TurretAimRight'='joystick0:axis0+' }; Raw=''; Unknown=@() }
    }
    $focused = & {
        function Clear-Host { }
        function Start-Sleep { param($Milliseconds, $Seconds) }
        function Read-KeyChar { return "`r" }
        function Wait-ForInput { param($Id,$Want,$CurrentToken,$StatusRow,$Stick,$Map) return @{Type='Control'; Key='skip'} }
        Invoke-Wizard -Ctx $ctx3 -Only $null -Map $map -Layout $focus 6>$null
    }
    T 'helicopter-focus layout removes turret aim from the stick' `
        (-not $focused.ContainsKey('TurretAimLeft') -and -not $focused.ContainsKey('TurretAimRight'))
    T 'helicopter-focus layout keeps turret rotate available' `
        (($script:Layouts | Where-Object { $_.Name -eq 'Helicopter focus' }).Exclude -notcontains 'TurretRotateRight')

    $ctx2 = [pscustomobject]@{
        Stick=$stick; Dir=$env:TEMP; CfgPath=$ctx.CfgPath; Map=$map
        Existing=@{ Bindings=@{ 'TurretFire'='joystick0:button3' }; Raw=''; Unknown=@() }
    }
    $skipped = & {
        function Clear-Host { }
        function Start-Sleep { param($Milliseconds, $Seconds) }
        function Read-KeyChar { return "`r" }
        function Wait-ForInput { param($Id,$Want,$CurrentToken,$StatusRow,$Stick,$Map) return @{Type='Control'; Key='skip'} }
        Invoke-Wizard -Ctx $ctx2 -Only $null -Map $map -Layout $null 6>$null
    }
    T 'skipping everything preserves existing bindings' ($skipped.Count -eq 1 -and $skipped['TurretFire'] -eq 'joystick0:button3')

    # 'u' is answered at the ready gate now, before anything is read
    $unbound = & {
        function Clear-Host { }
        function Start-Sleep { param($Milliseconds, $Seconds) }
        function Read-KeyChar { return 'u' }
        function Wait-ForInput { param($Id,$Want,$CurrentToken,$StatusRow,$Stick,$Map) return @{Type='Control'; Key='skip'} }
        Invoke-Wizard -Ctx $ctx2 -Only @(11) -Map $map -Layout $null 6>$null
    }
    T 'unbind at the gate clears the action' (-not $unbound.ContainsKey('TurretFire'))

    # Enter on a bound step keeps it without ever listening
    $kept = & {
        function Clear-Host { }
        function Start-Sleep { param($Milliseconds, $Seconds) }
        function Read-KeyChar { return "`r" }
        $script:_listened = $false
        function Wait-ForInput { param($Id,$Want,$CurrentToken,$StatusRow,$Stick,$Map)
            $script:_listened = $true; return @{Type='Button'; Index=9} }
        $out = Invoke-Wizard -Ctx $ctx2 -Only @(11) -Map $map -Layout $null 6>$null
        @{ Bindings = $out; Listened = $script:_listened }
    }
    T 'Enter on a bound step keeps it'            ($kept.Bindings['TurretFire'] -eq 'joystick0:button3')
    T 'Enter on a bound step never starts listening' (-not $kept.Listened)

    $quit = & {
        function Clear-Host { }
        function Start-Sleep { param($Milliseconds, $Seconds) }
        function Read-KeyChar { return 'q' }
        function Wait-ForInput { param($Id,$Want,$CurrentToken,$StatusRow,$Stick,$Map) return @{Type='Control'; Key='quit'} }
        Invoke-Wizard -Ctx $ctx2 -Only $null -Map $map -Layout $null 6>$null
    }
    T 'quit returns nothing' ($null -eq $quit)

    $backed = & {
        function Clear-Host { }
        function Start-Sleep { param($Milliseconds, $Seconds) }
        function Read-KeyChar { return "`r" }
        $script:_n = 0
        function Wait-ForInput { param($Id,$Want,$CurrentToken,$StatusRow,$Stick,$Map)
            $script:_n++
            if ($script:_n -le 4) { return @{Type='Control'; Key='back'} }
            return @{Type='Control'; Key='skip'} }
        Invoke-Wizard -Ctx $ctx2 -Only @(0,1) -Map $map -Layout $null 6>$null
    }
    T 'back at the first step does not run off the list' ($null -ne $backed)

    # space (change it) -> read 1 -> r (try again) -> space -> read 2 -> Enter (accept)
    $redone = & {
        function Clear-Host { }
        function Start-Sleep { param($Milliseconds, $Seconds) }
        $script:_keys = @(' ', 'r', ' ', "`r")
        $script:_k = -1
        function Read-KeyChar {
            $script:_k++
            if ($script:_k -lt $script:_keys.Count) { return $script:_keys[$script:_k] }
            return "`r" }
        $script:_w = 0
        function Wait-ForInput { param($Id,$Want,$CurrentToken,$StatusRow,$Stick,$Map)
            $script:_w++; return @{Type='Button'; Index=$script:_w} }
        Invoke-Wizard -Ctx $ctx2 -Only @(11) -Map $map -Layout $null 6>$null
    }
    T 'redo discards the first reading' ($redone['TurretFire'] -eq 'joystick0:button2') "got $($redone['TurretFire'])"

    # a reading that contradicts the control map needs 'y', not Enter
    $ctx4 = [pscustomobject]@{
        Stick=$stick; Dir=$env:TEMP; CfgPath=$ctx.CfgPath; Map=$map
        Existing=@{ Bindings=@{}; Raw=''; Unknown=@() }
    }
    $contradiction = & {
        function Clear-Host { }
        function Start-Sleep { param($Milliseconds, $Seconds) }
        # Enter must NOT accept a contradicted reading. Press it several times,
        # then quit -- a null result proves Enter never committed anything.
        $script:_k = 0
        function Read-KeyChar { $script:_k++; if ($script:_k -le 6) { return "`r" }; return 'q' }
        function Wait-ForInput { param($Id,$Want,$CurrentToken,$StatusRow,$Stick,$Map)
            return @{Type='Axis'; Index=4; Sign='+'} }     # rocker, but step expects StickX
        Invoke-Wizard -Ctx $ctx4 -Only @(0) -Map $map -Layout $null 6>$null
    }
    T 'a contradicted reading is not accepted with Enter' ($null -eq $contradiction)

    $overridden = & {
        function Clear-Host { }
        function Start-Sleep { param($Milliseconds, $Seconds) }
        $script:_k = 0
        function Read-KeyChar {
            $script:_k++
            if ($script:_k -eq 1)  { return ' ' }    # gate: change it
            if ($script:_k -le 20) { return 'y' }    # confirm the override
            return 'q' }                             # backstop, never reached
        function Wait-ForInput { param($Id,$Want,$CurrentToken,$StatusRow,$Stick,$Map) return @{Type='Axis'; Index=4; Sign='+'} }
        Invoke-Wizard -Ctx $ctx4 -Only @(0) -Map $map -Layout $null 6>$null
    }
    $overrideKeys = $script:_k
    T "a contradicted reading can be forced with 'y'" `
        ($null -ne $overridden -and $overridden['HelicopterCyclicRight'] -eq 'joystick0:axis4+') `
        ("keys=$overrideKeys result=" + $(if ($null -eq $overridden) { 'NULL' } else { (($overridden.Keys | Sort-Object) -join ',') }))

    # --- selecting a subset must walk exactly that subset ------------------
    function Measure-Walk {
        param($Only)
        return & {
            function Clear-Host { }
            function Start-Sleep { param($Milliseconds, $Seconds) }
            function Read-KeyChar { return ' ' }        # always "start listening"
            $script:_steps = 0
            function Wait-ForInput { param($Id,$Want,$CurrentToken,$StatusRow,$Stick,$Map)
                $script:_steps++; return @{Type='Control'; Key='skip'} }
            [void](Invoke-Wizard -Ctx $ctx4 -Only $Only -Map $null -Layout $null 6>$null)
            $script:_steps
        }
    }
    T 'picking step 0 alone walks one step'   ((Measure-Walk @(0))   -eq 1)  "got $(Measure-Walk @(0))"
    T 'picking step 5 alone walks one step'   ((Measure-Walk @(5))   -eq 1)
    T 'picking three steps walks three'       ((Measure-Walk @(0,3,7)) -eq 3)
    T 'passing no selection walks everything' ((Measure-Walk $null)  -eq $script:Steps.Count)

    # --- control map clash detection ---
    T 'clash found when two controls share an axis' `
        ((Find-MapClash -Map @{StickX=0; StickY=1} -AxisIndex 0 -ExceptKey 'StickY').Key -eq 'StickX')
    T 'no clash against itself' `
        ($null -eq (Find-MapClash -Map @{StickX=0} -AxisIndex 0 -ExceptKey 'StickX'))
    T 'no clash on a free axis' `
        ($null -eq (Find-MapClash -Map @{StickX=0; StickY=1} -AxisIndex 5 -ExceptKey 'Twist'))

    # ---- screens render ----
    $renderErr = @()
    & {
        function Clear-Host { }
        $full = @{}
        foreach ($s in $script:Steps) { foreach ($a in (Get-StepActions $s)) { $full[$a.Action] = 'joystick0:button0' } }
        for ($i = 0; $i -lt $script:Steps.Count; $i++) {
            foreach ($set in @(@{}, $full)) {
                try { Show-StepScreen -Step $script:Steps[$i] -Index ($i+1) -Total 21 -Bindings $set -Stick $stick -Map $map 6>$null | Out-Null }
                catch { $renderErr += "step $($i+1): $($_.Exception.Message)" }
            }
        }
        try { Show-Review -Bindings $full -Map $map 6>$null | Out-Null } catch { $renderErr += "review: $($_.Exception.Message)" }
        try { Show-Review -Bindings @{} -Map $null 6>$null | Out-Null } catch { $renderErr += "review empty: $($_.Exception.Message)" }
        try { Update-Panel -Info (New-FakeInfo -x 60000 -buttons 5 -pov 0) -Stick $stick 6>$null | Out-Null }
        catch { $renderErr += "panel: $($_.Exception.Message)" }
    }
    T 'every screen renders without error' ($renderErr.Count -eq 0) ($renderErr -join ' | ')

    Remove-Item $ctx.CfgPath -Force -ErrorAction SilentlyContinue

    if ($before) {
        T 'tests did not touch the live config' ((Get-FileHash $livePath -Algorithm SHA256).Hash -eq $before)
    }
    Write-Host ''
}

if ($SelfTest) {
    Invoke-SelfTest
    Invoke-IntegrationTest
    $col = if ($script:_f -eq 0) { 'Green' } else { 'Red' }
    Write-Host ("  {0} passed, {1} failed" -f $script:_p, $script:_f) -ForegroundColor $col
    Write-Host ''
    if ($script:_f -ne 0) { exit 1 }
    exit 0
}

# =============================================================================
# 16. Main
# =============================================================================

try { [Console]::CursorVisible = $false } catch { }

try {
    $ctx = Invoke-Preflight
    if (-not $ctx) { return }

    while ($true) {
        $mode = Show-Menu -Ctx $ctx
        if ($mode -eq 'quit') { break }

        if ($mode -eq 'map') {
            $ctx.Map = Invoke-ControlMap -Stick $ctx.Stick
            continue
        }

        $layout = $null
        $only = $null
        if ($mode -eq 'few') {
            $only = Select-Steps -Ctx $ctx -Map $ctx.Map
            if ($null -eq $only) { continue }
        } else {
            $layout = Select-Layout
            if ($null -eq $layout) { continue }
        }

        $script:Presets = @{}
        $result = Invoke-Wizard -Ctx $ctx -Only $only -Map $ctx.Map -Layout $layout
        if ($null -eq $result) { continue }

        Show-Review -Bindings $result -Map $ctx.Map
        if (Save-Config -Bindings $result -Ctx $ctx) {
            $ctx.Existing = Read-ExistingConfig $ctx.CfgPath
        }
    }
}
finally {
    try { [Console]::CursorVisible = $true } catch { }
    Write-Host ''
}
