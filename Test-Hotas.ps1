<#
    Test-Hotas.ps1 — identify which physical control is which index
                     on the Thrustmaster T.Flight Hotas 4.

    Move ONE control at a time; the script prints only what changed.
    Use it to confirm the button numbers in the Reforger config.

    Run:   powershell -ExecutionPolicy Bypass -File .\Test-Hotas.ps1
    Quit:  Ctrl+C

    NOTE ON AXES: Windows' winmm API (used here) names axes X, Y, Z, R, U, V.
    Reforger names them axis0..axis5 in DirectInput order (X, Y, Z, Rx, Ry, Rz).
    X/Y/Z line up exactly, so winmm X=axis0, Y=axis1, Z=axis2. R is almost
    always Rz = axis5. If you need certainty for R/U/V, use Reforger's own
    rebinding screen: it prints the real token (e.g. "joystick0:axis5+")
    when you move the control.

    BUTTONS are reported in the same HID order by both, so button numbers
    printed here match the config exactly.
#>

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

    // PowerShell 5.1 cannot cast int -> UIntPtr, so wrap it here.
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

# ---- find the stick ---------------------------------------------------------
$target = $null
Write-Host "`n=== Attached joysticks ===" -ForegroundColor Cyan
foreach ($id in 0..15) {
    $c = New-Object Joy+JOYCAPS
    if ([Joy]::Caps([uint32]$id, [ref]$c) -ne 0) { continue }
    if ([string]::IsNullOrWhiteSpace($c.szPname)) { continue }

    $isTM = ($c.wMid -eq 0x044F)
    "  id={0}  vid=0x{1:X4} pid=0x{2:X4}  axes={3}  buttons={4}  hat={5}  {6}" -f `
        $id, $c.wMid, $c.wPid, $c.wNumAxes, $c.wNumButtons,
        [bool]($c.wCaps -band 0x10), $(if ($isTM) { '<- Thrustmaster' } else { '' }) | Write-Host

    if ($null -eq $target -or $isTM) { $target = [uint32]$id }
    if ($isTM) { break }
}

if ($null -eq $target) {
    Write-Host "`nNo joystick found. Plug the HOTAS in (PC mode, switch on the base) and re-run." -ForegroundColor Red
    exit 1
}

Write-Host "`nWatching id=$target. Move ONE control at a time.  Ctrl+C to quit.`n" -ForegroundColor Yellow

# winmm field -> label. Reforger index is certain for X/Y/Z, inferred for R/U/V.
$axisLabels = [ordered]@{
    dwXpos = 'axis0  (X   - stick left/right)'
    dwYpos = 'axis1  (Y   - stick fwd/back)'
    dwZpos = 'axis2  (Z   - throttle?)'
    dwRpos = 'axis5  (R   - twist rudder?)'
    dwUpos = 'axis3? (U   - extra)'
    dwVpos = 'axis4? (V   - extra)'
}

function Norm([uint32]$v) { [math]::Round((($v / 65535.0) * 2.0) - 1.0, 2) }

$prevAxis = @{}
$prevBtn  = 0
$prevPov  = 65535

while ($true) {
    $i = New-Object Joy+JOYINFOEX
    if ([Joy]::Pos($target, [ref]$i) -ne 0) { Start-Sleep -Milliseconds 250; continue }

    foreach ($f in $axisLabels.Keys) {
        $v = Norm $i.$f
        if (-not $prevAxis.ContainsKey($f)) { $prevAxis[$f] = $v; continue }
        # 0.08 deadband so idle jitter doesn't spam the console
        if ([math]::Abs($v - $prevAxis[$f]) -ge 0.08) {
            $sign = if ($v -ge 0) { '+' } else { '-' }
            "{0,-34} = {1,6}   -> use '{2}'" -f $axisLabels[$f], $v, ($axisLabels[$f].Split(' ')[0] + $sign) | Write-Host
            $prevAxis[$f] = $v
        }
    }

    if ($i.dwButtons -ne $prevBtn) {
        foreach ($b in 0..31) {
            # shift a long: 1 -shl 31 overflows a signed int
            $mask = [uint32](1L -shl $b)
            $now = [bool]($i.dwButtons -band $mask)
            $was = [bool]($prevBtn      -band $mask)
            if ($now -and -not $was) {
                Write-Host ("button{0,-2} PRESSED   -> use 'joystick0:button{0}'" -f $b) -ForegroundColor Green
            }
        }
        $prevBtn = $i.dwButtons
    }

    if ($i.dwPOV -ne $prevPov) {
        if ($i.dwPOV -ne 65535) {
            $dir = switch ($i.dwPOV) {
                0     { 'pov_up' }    4500  { 'pov_up + pov_right' }
                9000  { 'pov_right' } 13500 { 'pov_down + pov_right' }
                18000 { 'pov_down' }  22500 { 'pov_down + pov_left' }
                27000 { 'pov_left' }  31500 { 'pov_up + pov_left' }
                default { "pov $($i.dwPOV / 100) deg" }
            }
            Write-Host ("hat        {0,-22} -> use 'joystick0:{1}'" -f "($($i.dwPOV/100) deg)", $dir) -ForegroundColor Cyan
        }
        $prevPov = $i.dwPOV
    }

    Start-Sleep -Milliseconds 40
}
