<#
    Common.ps1 -- shared helpers. Dot-sourced before everything else.
#>

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
