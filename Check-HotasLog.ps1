<#
    Check-HotasLog.ps1
    Reads Reforger's newest log and reports whether the joystick config
    was accepted, so you can tell a bad binding from a bad habit.

    Run after launching (and quitting) the game:
        powershell -ExecutionPolicy Bypass -File .\Check-HotasLog.ps1
#>

[CmdletBinding()]
param(
    # Look at the Nth most recent log folder (1 = newest).
    [int] $Recent = 1,
    # Show every input-related line, not just the interesting ones.
    [switch] $All
)

$ErrorActionPreference = 'Stop'

$logRoot = Join-Path $env:USERPROFILE 'Documents\My Games\ArmaReforger\logs'
if (-not (Test-Path $logRoot)) {
    Write-Host "No Reforger log folder at $logRoot" -ForegroundColor Red
    return
}

$dirs = Get-ChildItem $logRoot -Directory | Sort-Object LastWriteTime -Descending
if (-not $dirs) { Write-Host 'No logs yet - launch the game once.' -ForegroundColor Yellow; return }
if ($Recent -gt $dirs.Count) { $Recent = $dirs.Count }
$dir = $dirs[$Recent - 1]

Write-Host ''
Write-Host '  REFORGER INPUT LOG CHECK' -ForegroundColor Cyan
Write-Host ('  ' + ('-' * 66)) -ForegroundColor DarkGray
Write-Host ("    log     {0}" -f $dir.Name)
Write-Host ("    when    {0}" -f $dir.LastWriteTime)
Write-Host ''

$console = Join-Path $dir.FullName 'console.log'
if (-not (Test-Path $console)) { Write-Host '    console.log missing' -ForegroundColor Red; return }

$lines = Get-Content $console

# Lines we already understand and do not want to alarm anyone with.
$benign = @(
    'ForceFeedback effect failed to create'   # stick has no FFB motor; harmless
)

# Word boundaries matter here. Without them "FactionManager" matches
# "ActionManager" and "SCR_InputButtonComponent" matches "INPUT", which buries
# a real fault under UI noise.
$inputLines = $lines | Where-Object {
    $_ -match '\bINPUT\b' -or
    $_ -match 'joystick' -or
    $_ -match '\bFilterPreset\b' -or
    $_ -match '\bInputSource\w*\b' -or
    $_ -match '\bActionManager\b' -or
    $_ -match 'customInputConfigs'
}

$problems = @()
$noted    = @()

foreach ($l in $inputLines) {
    $isBenign = $false
    foreach ($b in $benign) { if ($l -match [regex]::Escape($b)) { $isBenign = $true; break } }
    if ($isBenign) { $noted += $l; continue }
    if ($l -match '\(E\)|\(W\)|error|warn|unknown|invalid|fail|cannot|could not') { $problems += $l }
    elseif ($All) { $noted += $l }
}

if ($problems.Count -eq 0) {
    Write-Host '    No input errors. Every binding in your config was accepted.' -ForegroundColor Green
} else {
    Write-Host ('    {0} input problem(s):' -f $problems.Count) -ForegroundColor Yellow
    Write-Host ''
    foreach ($p in $problems) { Write-Host "      $($p.Trim())" -ForegroundColor Yellow }
}

if ($noted.Count) {
    Write-Host ''
    Write-Host '    Known-harmless:' -ForegroundColor DarkGray
    foreach ($n in ($noted | Select-Object -First 6)) { Write-Host "      $($n.Trim())" -ForegroundColor DarkGray }
    if (-not $All -and $noted.Count -gt 6) {
        Write-Host ("      ... and {0} more (-All to see them)" -f ($noted.Count - 6)) -ForegroundColor DarkGray
    }
}

# Cross-check: is every action in the config one the engine never complained about?
$cfg = Join-Path $env:USERPROFILE 'Documents\My Games\ArmaReforger\profile\.save\settings\customInputConfigs\Joystick_TFlightHotas4_0.conf'
if (Test-Path $cfg) {
    $text = Get-Content -Raw $cfg
    $actions = [regex]::Matches($text, '(?m)^\s*Action\s+(\w+)\s*\{') | ForEach-Object { $_.Groups[1].Value }
    Write-Host ''
    Write-Host ('    Config has {0} actions bound.' -f $actions.Count) -ForegroundColor DarkGray
    $named = $actions | Where-Object { $a = $_; @($lines | Where-Object { $_ -match "\b$([regex]::Escape($a))\b" }).Count -gt 0 }
    if ($named) {
        Write-Host '    Actions mentioned by name in the log (check these first if something misbehaves):' -ForegroundColor DarkGray
        foreach ($a in ($named | Select-Object -Unique)) { Write-Host "      $a" -ForegroundColor Yellow }
    }
}

Write-Host ''
