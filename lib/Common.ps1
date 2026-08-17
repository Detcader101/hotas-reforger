<#
    Common.ps1 -- shared helpers. Dot-sourced before everything else.
#>

function Write-TextFile {
    <#
        Write text as UTF-8 with NO byte-order mark.

        This is not a detail. Set-Content -Encoding UTF8 on Windows PowerShell
        5.1 prepends EF BB BF, and Reforger's config parser does not skip it --
        it looks for "ActionManager" at the start of the file, finds the BOM
        instead, and parses the whole thing as empty. The result is a config
        that is valid by every check this tool makes, accepted by the engine
        without a single log error, and completely inert in game. Every file
        Reforger writes itself begins directly with 'A'.

        Every write of a game-facing file goes through here.
    #>
    param([string] $Path, [string] $Text)
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, $Text, $utf8NoBom)
}

function Test-HasBom {
    param([string] $Path)
    if (-not (Test-Path $Path)) { return $false }
    $bytes = [System.IO.File]::ReadAllBytes($Path)
    if ($bytes.Length -lt 3) { return $false }
    return ($bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
}

function Get-Opt {
    <#
        Read an optional key off a hashtable.

        The catalogues in this project are hashtable literals where most entries
        omit most optional keys -- only one job carries SingleClick, only one
        axis carries Optional. Under Set-StrictMode -Version 2.0 reading a key
        that is not there is a terminating error, and the tool runs under strict
        mode deliberately, because the alternative is a typo'd action name
        silently producing an empty binding.

        So optional keys are read through here and nowhere else.
    #>
    param($Table, [string] $Key, $Default = $null)
    if ($null -eq $Table) { return $Default }
    if ($Table -is [System.Collections.IDictionary]) {
        if ($Table.Contains($Key)) { return $Table[$Key] }
        return $Default
    }
    $p = $Table.PSObject.Properties[$Key]
    if ($p) { return $p.Value }
    return $Default
}
