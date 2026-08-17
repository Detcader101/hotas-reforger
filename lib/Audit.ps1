<#
    Audit.ps1 -- which controls physically send anything.

    Separate from -Identify on purpose. Identify asks "which index is this
    control", and assumes every control it names exists and works. Audit asks
    the prior question: does this control produce ANY reading at all? A switch
    that sends nothing is invisible to identify -- you press it, nothing is
    read, and the step looks like you simply did not press hard enough.

    Every control gets its own letter, so a control can be retested on its own
    without walking the whole list again, and the running state is on screen the
    whole time. Three outcomes:

      RESPONDS   a reading arrived, and the token it produced is recorded
      DEAD       you pressed it and told the tool nothing was read
      untested   not yet checked

    DEAD is a real result, not a failure to record. It is the difference
    between "this stick has twelve buttons" and "twelve buttons reach the PC".
#>

function New-AuditState {
    param($Stick)
    $s = @{
        Device      = ''
        Vid         = 0
        Pid         = 0
        ButtonCount = 0
        Results     = @{}
    }
    if ($Stick) {
        $s.Device = $Stick.Name
        $s.Vid = $Stick.Vid
        $s.Pid = $Stick.Pid
        $s.ButtonCount = $Stick.ButtonCount
    }
    return $s
}

function Import-AuditState {
    param([string] $Path)
    if (-not (Test-Path $Path)) { return $null }
    try { $raw = Get-Content -Raw -Path $Path | ConvertFrom-Json } catch { return $null }
    $s = New-AuditState $null
    foreach ($k in @('Device', 'Vid', 'Pid', 'ButtonCount')) { if ($null -ne $raw.$k) { $s[$k] = $raw.$k } }
    if ($raw.Results) {
        foreach ($p in $raw.Results.PSObject.Properties) {
            $s.Results[$p.Name] = @{ Status = [string]$p.Value.Status; Token = [string]$p.Value.Token }
        }
    }
    return $s
}

function Export-AuditState {
    param($State, [string] $Path)
    Write-TextFile -Path $Path -Text ($State | ConvertTo-Json -Depth 5)
}

function Get-AuditStatus {
    param($State, [string] $Id)
    if ($State.Results.ContainsKey($Id)) { return $State.Results[$Id].Status }
    return 'untested'
}

function Get-AuditToken {
    param($State, [string] $Id)
    if ($State.Results.ContainsKey($Id)) { return $State.Results[$Id].Token }
    return ''
}

function Set-AuditResult {
    param($State, [string] $Id, [string] $Status, [string] $Token = '')
    $State.Results[$Id] = @{ Status = $Status; Token = $Token }
}

# Keys the audit menu itself uses. A control must never be given one of these:
# assigning 'q' to an axis meant pressing it quit the program instead of testing
# that axis, because the menu checks its own commands first.
$script:AuditReservedKeys = @('q', 'r', 't', 'w', 'x')

function Get-AuditKeyMap {
    <# A letter per control, skipping the menu's own commands. #>
    $map = [ordered]@{}
    $pool = @()
    foreach ($ch in 'abcdefghijklmnopqrstuvwxyz'.ToCharArray()) {
        if ($script:AuditReservedKeys -notcontains "$ch") { $pool += "$ch" }
    }
    $i = 0
    foreach ($c in $script:ControlCatalogue) {
        if ($i -lt $pool.Count) { $map[$pool[$i]] = $c.Id }
        $i++
    }
    return $map
}

function Get-AuditSummary {
    <# Counts, plus the driver-reported button indices nothing has claimed. #>
    param($State)
    $responds = @()
    $dead = @()
    $untested = @()
    foreach ($c in $script:ControlCatalogue) {
        switch (Get-AuditStatus -State $State -Id $c.Id) {
            'Responds' { $responds += $c.Id }
            'Dead'     { $dead += $c.Id }
            default    { $untested += $c.Id }
        }
    }

    $seen = @{}
    foreach ($id in $responds) {
        $t = Get-AuditToken -State $State -Id $id
        if ($t -match '^button(\d+)$') { $seen[[int]$Matches[1]] = $true }
    }
    $unseen = @()
    if ($State.ButtonCount -gt 0) {
        foreach ($i in 0..($State.ButtonCount - 1)) { if (-not $seen.ContainsKey($i)) { $unseen += $i } }
    }

    return @{ Responds = $responds; Dead = $dead; Untested = $untested; UnseenIndices = $unseen }
}
