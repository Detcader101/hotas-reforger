<#
    Ui.ps1 -- console output and key input.

    Deliberately small. Everything here is presentation; no module in this
    project should make a decision based on what the console can do.
#>

$script:Width = 74

function Write-Rule    { param([string] $Char = '-') Write-Host ('  ' + ($Char * $script:Width)) -ForegroundColor DarkGray }
function Write-Note    { param([string] $Message) Write-Host "    $Message" -ForegroundColor DarkGray }
function Write-Good    { param([string] $Message) Write-Host "    $Message" -ForegroundColor Green }
function Write-Warn    { param([string] $Message) Write-Host "    $Message" -ForegroundColor Yellow }
function Write-Bad     { param([string] $Message) Write-Host "    $Message" -ForegroundColor Red }
function Write-Plain   { param([string] $Message) Write-Host "    $Message" -ForegroundColor Gray }
function Write-Strong  { param([string] $Message) Write-Host "    $Message" -ForegroundColor White }

function Write-Title {
    param([string] $Text, [string] $Subtitle)
    Write-Host ''
    Write-Rule '='
    Write-Host ('    ' + $Text) -ForegroundColor Cyan
    if ($Subtitle) { Write-Host ('    ' + $Subtitle) -ForegroundColor DarkGray }
    Write-Rule '='
    Write-Host ''
}

function Write-Section {
    param([string] $Text)
    Write-Host ''
    Write-Host ('  ' + $Text) -ForegroundColor White
    Write-Rule
}

# Two-column field. Used by every table in the tool so they all line up.
function Write-Field {
    param([string] $Name, [string] $Value, [string] $Colour = 'Gray', [int] $Pad = 26)
    Write-Host ('    ' + $Name.PadRight($Pad) + ' ') -NoNewline -ForegroundColor DarkGray
    Write-Host $Value -ForegroundColor $Colour
}

function Read-KeyChar {
    # Ignore modifier-only keypresses, which arrive as key events with no char.
    while ($true) {
        $k = [Console]::ReadKey($true)
        if ($k.Key -eq 'Enter')     { return "`r" }
        if ($k.Key -eq 'Escape')    { return 'q' }
        if ($k.Key -eq 'Backspace') { return 'b' }
        if ($k.KeyChar) { return ([string]$k.KeyChar).ToLower() }
    }
}

function Test-KeyWaiting { return [Console]::KeyAvailable }

function Clear-KeyBuffer { while ([Console]::KeyAvailable) { [void][Console]::ReadKey($true) } }

# Prompt restricted to a set of single keys. Returns the key that was pressed.
function Read-Choice {
    param([string] $Prompt, [string[]] $Keys)
    Write-Host ''
    Write-Host ('    ' + $Prompt) -ForegroundColor White
    Clear-KeyBuffer
    while ($true) {
        $k = Read-KeyChar
        if ($Keys -contains $k) { return $k }
    }
}

function Confirm-Action {
    param([string] $Prompt)
    return (Read-Choice -Prompt "$Prompt  [y] yes   [n] no" -Keys @('y', 'n')) -eq 'y'
}

function Wait-AnyKey {
    param([string] $Message = 'Press any key to continue.')
    Write-Host ''
    Write-Note $Message
    Clear-KeyBuffer
    [void](Read-KeyChar)
}

# Horizontal bar for an axis reading in the range -1..+1.
function Get-AxisBar {
    param([double] $Value, [int] $Cells = 21)
    $mid = [int](($Cells - 1) / 2)
    $pos = $mid + [int][math]::Round($Value * $mid)
    if ($pos -lt 0) { $pos = 0 }
    if ($pos -ge $Cells) { $pos = $Cells - 1 }
    $chars = @()
    foreach ($i in 0..($Cells - 1)) {
        if ($i -eq $pos)     { $chars += '#' }
        elseif ($i -eq $mid) { $chars += '|' }
        else                 { $chars += '.' }
    }
    return ('[' + ($chars -join '') + ']')
}
