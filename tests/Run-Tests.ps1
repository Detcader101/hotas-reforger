<#
    Run-Tests.ps1 -- the whole suite. No joystick, no game, nothing written.

    Run it after any edit:
        .\Hotas4.ps1 -SelfTest

    Exit code 0 on success, 1 on any failure, so it drops into CI unchanged.

    The tests that matter most are the ones in COMPLETENESS. Everything else
    here is ordinary hygiene; those are the ones that hold the tool to its one
    promise, which is that it cannot quietly leave a control doing nothing.
#>

param([string] $Root = (Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)))

Set-StrictMode -Version 2.0

. (Join-Path $Root 'lib\Common.ps1')
. (Join-Path $Root 'lib\Ui.ps1')
. (Join-Path $Root 'lib\Device.ps1')
. (Join-Path $Root 'lib\Layout.ps1')
. (Join-Path $Root 'lib\Reforger.ps1')

$script:Pass = 0
$script:Fail = 0
$script:Group = ''

function Group { param([string] $Name) $script:Group = $Name; Write-Host ''; Write-Host "  $Name" -ForegroundColor Cyan }

function Check {
    param([string] $What, [bool] $Ok, [string] $Detail = '')
    if ($Ok) {
        $script:Pass++
        Write-Host '    ok   ' -NoNewline -ForegroundColor DarkGreen
        Write-Host $What -ForegroundColor DarkGray
    } else {
        $script:Fail++
        Write-Host '    FAIL ' -NoNewline -ForegroundColor Red
        Write-Host $What -ForegroundColor White
        if ($Detail) { Write-Host "         $Detail" -ForegroundColor DarkYellow }
    }
}

# A synthetic T.Flight Hotas 4 in PC mode: 12 buttons, a hat, four live axes.
# Indices here are arbitrary on purpose -- nothing in the tool is allowed to
# depend on a particular unit's enumeration order.
function New-FakeMap {
    $map = New-DeviceMap
    $map.Device = 'T.Flight Hotas 4 (test)'
    $map.Verified = $true
    $map.Hat = $true
    $order = @('StickTrigger', 'StickSide', 'StickTopLeft', 'StickTopRight', 'StickRaised',
               'RockerForward', 'RockerBack',
               'ThrottleFaceUp', 'ThrottleFaceRight', 'ThrottleFaceDown', 'ThrottleFaceLeft',
               'ThrottleThumb')
    for ($i = 0; $i -lt $order.Count; $i++) { $map.Buttons["$i"] = $order[$i] }
    $map.Axes['AxisRoll']     = @{ Index = 0; Sign = '+' }
    $map.Axes['AxisPitch']    = @{ Index = 1; Sign = '-' }   # inverted on purpose
    $map.Axes['AxisThrottle'] = @{ Index = 2; Sign = '+' }
    $map.Axes['AxisTwist']    = @{ Index = 5; Sign = '+' }
    return $map
}

$fakeStick = @{ Id = 0; Name = 'T.Flight Hotas 4'; Vid = 0x044F; Pid = 0xB67C
                AxisCount = 6; ButtonCount = 12; HasHat = $true }

# =============================================================================
Group 'Catalogue integrity'
# =============================================================================

$ids = $script:ControlCatalogue | ForEach-Object { $_.Id }
Check 'every physical control has a unique id' (($ids | Sort-Object -Unique).Count -eq $ids.Count)

$bad = @($script:ControlCatalogue | Where-Object { -not $_.Label -or -not $_.Zone -or -not $_.Kind })
Check 'every physical control has a label, zone and kind' ($bad.Count -eq 0) (($bad | ForEach-Object { $_.Id }) -join ', ')

$noWhere = @($script:ControlCatalogue | Where-Object { $_.Kind -ne 'Axis' -and -not $_.Where })
Check 'every button and hat says where to find it' ($noWhere.Count -eq 0)

$noProbe = @(Get-ControlsByKind 'Axis' | Where-Object { -not $_.Probe })
Check 'every axis has a probe instruction' ($noProbe.Count -eq 0)

$jobIds = $script:Jobs | ForEach-Object { $_.Id }
Check 'every job has a unique id' (($jobIds | Sort-Object -Unique).Count -eq $jobIds.Count)

$badTier = @($script:Jobs | Where-Object { $_.Tier -ne 'A' -and $_.Tier -ne 'B' })
Check 'every job declares tier A or B' ($badTier.Count -eq 0)

$badPreset = @()
foreach ($j in $script:Jobs) {
    foreach ($key in @('Actions', 'Pos', 'Neg')) {
        if (-not $j.ContainsKey($key)) { continue }
        foreach ($a in $j[$key]) { if (-not (Test-FilterPreset $a.Preset)) { $badPreset += "$($j.Id):$($a.Preset)" } }
    }
}
Check 'every action uses a filter preset the engine knows' ($badPreset.Count -eq 0) ($badPreset -join ', ')

$hatJob = Get-Job 'FreelookHat'
$povs = @($hatJob.Actions | ForEach-Object { $_.Pov })
Check 'the hat job covers all four directions' (($povs | Sort-Object -Unique).Count -eq 4)

# =============================================================================
Group 'Array-returning helpers'
# =============================================================================
#
# These return with a leading comma so a one- or zero-element result survives
# PowerShell unrolling it on the way out. That makes the value already an array,
# and wrapping the CALL in @() then produces a one-element array holding the
# array -- silently turning a list of five axes into a list of one. That is a
# real bug this tool shipped with for an afternoon, so both halves are asserted:
# the functions return proper arrays, and no call site re-wraps them.

$arrayHelpers = @('Get-ControlsByKind', 'Get-JobsByKind', 'Get-JobActionNames', 'Get-Coverage',
                  'Get-UnmappedButtonIndex', 'Get-PressedButton', 'Get-HatNames', 'Get-DeviceWarning',
                  'Get-Joystick', 'Resolve-Bindings', 'Test-Config', 'Get-UnknownActionBlock',
                  'Get-BindingConflict', 'Get-TierBActions')

$axesDirect = Get-ControlsByKind 'Axis'
Check 'an unwrapped call returns every axis, not a single wrapper' ($axesDirect.Count -eq 5) `
      ("got $($axesDirect.Count)")
Check 'each element is a control, not a nested array' ($axesDirect[0].Id -eq 'AxisRoll')

$buttonsDirect = Get-ControlsByKind 'Button'
Check 'an unwrapped call returns every button control' ($buttonsDirect.Count -eq 14) ("got $($buttonsDirect.Count)")

$hatDirect = Get-ControlsByKind 'Hat'
Check 'a single-element result is still an array' ($hatDirect.Count -eq 1 -and $hatDirect[0].Id -eq 'StickHat')

$noneDirect = Get-ControlsByKind 'Nonsense'
Check 'an empty result is still an array' ($noneDirect.Count -eq 0)

$doubleWrapped = @()
foreach ($f in (Get-ChildItem -Path $Root -Recurse -Include *.ps1)) {
    $n = 0
    foreach ($line in (Get-Content $f.FullName)) {
        $n++
        # A pipeline inside the @() is fine -- that unrolls and recollects.
        if ($line -match '\|') { continue }
        foreach ($h in $arrayHelpers) {
            if ($line -match [regex]::Escape("@($h ") -or $line -match [regex]::Escape("@($h)")) {
                $doubleWrapped += "$($f.Name):$n  $h"
            }
        }
    }
}
Check 'no call site wraps an array-returning helper in @()' ($doubleWrapped.Count -eq 0) ($doubleWrapped -join ' | ')

# =============================================================================
Group 'Completeness -- the promise this tool exists to keep'
# =============================================================================

foreach ($p in $script:Profiles) {
    $missing = @()
    foreach ($c in $script:ControlCatalogue) {
        if ($c.Kind -eq 'Axis' -and (Get-Opt $c 'Optional' $false)) { continue }
        if (-not $p.Bind.ContainsKey($c.Id)) { $missing += $c.Id }
    }
    Check "profile '$($p.Id)' has a decision for every physical control" ($missing.Count -eq 0) ($missing -join ', ')

    $unknownJob = @()
    foreach ($k in $p.Bind.Keys) {
        $v = $p.Bind[$k]
        if ($v -ne 'Free' -and -not (Get-Job $v)) { $unknownJob += "$k -> $v" }
    }
    Check "profile '$($p.Id)' references only jobs that exist" ($unknownJob.Count -eq 0) ($unknownJob -join ', ')

    $kindMismatch = @()
    foreach ($k in $p.Bind.Keys) {
        $v = $p.Bind[$k]
        if ($v -eq 'Free') { continue }
        $c = Get-Control $k
        $j = Get-Job $v
        if ($c -and $j -and $c.Kind -ne $j.Kind) { $kindMismatch += "$k ($($c.Kind)) -> $v ($($j.Kind))" }
    }
    Check "profile '$($p.Id)' never puts an axis job on a button" ($kindMismatch.Count -eq 0) ($kindMismatch -join ', ')
}

$map = New-FakeMap
foreach ($p in $script:Profiles) {
    $rows = Get-Coverage -Map $map -Profile $p -ButtonCount 12 -HasHat $true
    $holes = @($rows | Where-Object { $_.Status -eq 'Unnamed' -or $_.Status -eq 'Unassigned' })
    Check "profile '$($p.Id)' leaves no control unbound on a full 12-button map" ($holes.Count -eq 0) `
          (($holes | ForEach-Object { "$($_.Token) $($_.Label) $($_.Status)" }) -join '; ')
    Check "profile '$($p.Id)' reports complete" (Test-CoverageComplete $rows)
}

# The audit has to be able to fail, or it is not an audit.
$gappy = New-FakeMap
$gappy.Buttons.Remove('7')
$rows = Get-Coverage -Map $gappy -Profile (Get-Profile 'helicopter') -ButtonCount 12 -HasHat $true
$unnamed = @($rows | Where-Object { $_.Status -eq 'Unnamed' })
Check 'a button the device reports but nothing named shows as Unnamed' ($unnamed.Count -eq 1)
Check 'coverage reports incomplete when a button is unnamed' (-not (Test-CoverageComplete $rows))

$hollow = Copy-Profile (Get-Profile 'helicopter')
$hollow.Bind.Remove('StickTrigger')
$rows = Get-Coverage -Map (New-FakeMap) -Profile $hollow -ButtonCount 12 -HasHat $true
$unassigned = @($rows | Where-Object { $_.Status -eq 'Unassigned' })
Check 'a named control with no job shows as Unassigned' ($unassigned.Count -eq 1)
Check "the trigger is what comes back unassigned" ($unassigned.Count -eq 1 -and $unassigned[0].ControlId -eq 'StickTrigger')

$freed = Copy-Profile (Get-Profile 'helicopter')
$freed.Bind['StickTrigger'] = 'Free'
$rows = Get-Coverage -Map (New-FakeMap) -Profile $freed -ButtonCount 12 -HasHat $true
Check 'an explicitly freed control does not count as a gap' (Test-CoverageComplete $rows)
Check 'an explicitly freed control is reported as Free' `
      (@($rows | Where-Object { $_.ControlId -eq 'StickTrigger' })[0].Status -eq 'Free')

$noHat = New-FakeMap
$noHat.Hat = $false
$rows = Get-Coverage -Map $noHat -Profile (Get-Profile 'helicopter') -ButtonCount 12 -HasHat $true
Check 'a hat the device has but identify never saw is a gap' (-not (Test-CoverageComplete $rows))

# Regression: the specific complaint this rewrite answers. Reforger's own
# generated preset leaves the trigger, the side button and both halves of the
# throttle rocker doing nothing.
$rows = Get-Coverage -Map (New-FakeMap) -Profile (Get-Profile 'helicopter') -ButtonCount 12 -HasHat $true
foreach ($id in @('StickTrigger', 'StickSide', 'RockerForward', 'RockerBack')) {
    $row = @($rows | Where-Object { $_.ControlId -eq $id })
    Check "$id is bound" ($row.Count -eq 1 -and $row[0].Status -eq 'Bound')
}

# =============================================================================
Group 'Button and axis reading'
# =============================================================================

$allBits = $true
foreach ($b in 0..31) {
    $mask = [uint32](1L -shl $b)
    if (-not (Test-ButtonDown $mask $b)) { $allBits = $false }
    if ($b -gt 0 -and (Test-ButtonDown $mask ($b - 1))) { $allBits = $false }
}
Check 'button masks read correctly across all 32 bits' $allBits

Check 'no buttons down reads as none down' (-not (Test-ButtonDown ([uint32]0) 0))
Check 'a newly pressed button is detected' ((Get-PressedButton -Before 0 -Now 8)[0] -eq 3)
Check 'a button already held is not re-reported' ((Get-PressedButton -Before 8 -Now 8).Count -eq 0)
Check 'button 0 is detected, not swallowed by a falsy index' ((Get-PressedButton -Before 0 -Now 1)[0] -eq 0)
Check 'two buttons at once both come back' ((Get-PressedButton -Before 0 -Now 5).Count -eq 2)

Check 'raw minimum reads as -1' ((ConvertTo-Unit 0) -eq -1)
Check 'raw maximum reads as +1' ((ConvertTo-Unit 65535) -eq 1)
Check 'raw centre reads near zero' ([math]::Abs((ConvertTo-Unit 32768)) -lt 0.001)

$rest = @(0.0, 0.0, 0.0, 0.0, 0.0, 0.0)
$moved = Find-MovedAxis -Baseline $rest -Current @(0.0, 0.0, 0.9, 0.0, 0.0, 0.0)
Check 'a pushed axis is found' ($null -ne $moved -and $moved.Index -eq 2 -and $moved.Sign -eq '+')
$moved = Find-MovedAxis -Baseline $rest -Current @(0.0, -0.8, 0.0, 0.0, 0.0, 0.0)
Check 'a pulled axis reports a negative sign' ($null -ne $moved -and $moved.Index -eq 1 -and $moved.Sign -eq '-')
Check 'idle jitter is not mistaken for movement' `
      ($null -eq (Find-MovedAxis -Baseline $rest -Current @(0.05, -0.04, 0.02, 0.0, 0.0, 0.0)))
$moved = Find-MovedAxis -Baseline $rest -Current @(0.5, 0.0, 0.95, 0.0, 0.0, 0.0)
Check 'the axis that moved furthest wins' ($moved.Index -eq 2)
$moved = Find-MovedAxis -Baseline @(0.0, 0.0, -1.0, 0.0, 0.0, 0.0) -Current @(0.0, 0.0, 1.0, 0.0, 0.0, 0.0)
Check 'a throttle resting at full travel is measured from where it rested' ($moved.Index -eq 2 -and $moved.Sign -eq '+')

Check 'a centred hat reports nothing' ((Get-HatNames 65535).Count -eq 0)
Check 'hat up' ((Get-HatNames 0)[0] -eq 'up')
Check 'hat right' ((Get-HatNames 9000)[0] -eq 'right')
Check 'hat down' ((Get-HatNames 18000)[0] -eq 'down')
Check 'hat left' ((Get-HatNames 27000)[0] -eq 'left')
Check 'a diagonal hat reports both directions' ((Get-HatNames 4500).Count -eq 2)

# =============================================================================
Group 'Keyboard'
# =============================================================================
#
# The wizard once appeared to ignore every key except Enter. The resolution
# logic was fine; the bug was that Wait-Control blocked for seconds without
# reading the keyboard and then discarded the buffer. These pin the half that
# can be tested without a console -- the other half is a design note in
# Wait-Control.

function New-Key {
    param([char] $Char, [string] $Key)
    return (New-Object System.ConsoleKeyInfo $Char, ([ConsoleKey]$Key), $false, $false, $false)
}

Check 'Enter resolves to carriage return' ((Read-KeyCharFrom (New-Key ([char]13) 'Enter')) -eq "`r")
Check 'Escape resolves to quit' ((Read-KeyCharFrom (New-Key ([char]27) 'Escape')) -eq 'q')
Check 'Backspace resolves to back' ((Read-KeyCharFrom (New-Key ([char]8) 'Backspace')) -eq 'b')
Check 'a letter resolves to itself' ((Read-KeyCharFrom (New-Key ([char]'r') 'R')) -eq 'r')
Check 'an upper-case letter is folded down' ((Read-KeyCharFrom (New-Key ([char]'S') 'S')) -eq 's')
Check 'a digit resolves to itself' ((Read-KeyCharFrom (New-Key ([char]'3') 'D3')) -eq '3')
Check 'a key with no character resolves to nothing' ($null -eq (Read-KeyCharFrom (New-Key ([char]0) 'F5')))

# Every key the identify pass offers has to survive resolution and then match
# the -Keys list it is checked against, or it silently does nothing.
$axisKeys = @("`r", 'r', 's', 'q')
foreach ($pair in @(@{C = [char]13;   K = 'Enter'; W = "`r" },
                    @{C = [char]'r'; K = 'R';     W = 'r' },
                    @{C = [char]'s'; K = 'S';     W = 's' },
                    @{C = [char]'q'; K = 'Q';     W = 'q' })) {
    $got = Read-KeyCharFrom (New-Key $pair.C $pair.K)
    Check "the confirm prompt accepts $($pair.K)" ($got -eq $pair.W -and $axisKeys -contains $got)
}

$waitKeys = @('s', 'b', 'q')
foreach ($pair in @(@{C = [char]'s'; K = 'S' }, @{C = [char]8; K = 'Backspace' }, @{C = [char]27; K = 'Escape' })) {
    $got = Read-KeyCharFrom (New-Key $pair.C $pair.K)
    Check "the wait prompt accepts $($pair.K)" ($waitKeys -contains $got)
}

# =============================================================================
Group 'Device map'
# =============================================================================

$m = New-DeviceMap
Set-MappedButton -Map $m -Index 3 -ControlId 'StickTrigger'
Check 'a button maps to a control' ((Get-MappedButtonIndex -Map $m -ControlId 'StickTrigger') -eq 3)
Set-MappedButton -Map $m -Index 7 -ControlId 'StickTrigger'
Check 'remapping a control releases its old index' ($m.Buttons.Count -eq 1)
Check 'remapping a control takes the new index' ((Get-MappedButtonIndex -Map $m -ControlId 'StickTrigger') -eq 7)
Check 'an unmapped control has no index' ($null -eq (Get-MappedButtonIndex -Map $m -ControlId 'StickSide'))
Check 'unmapped indices are listed' ((Get-UnmappedButtonIndex -Map $m -ButtonCount 12).Count -eq 11)

$tmp = Join-Path ([IO.Path]::GetTempPath()) ("hotas4-test-{0}.json" -f [guid]::NewGuid())
Export-DeviceMap -Map (New-FakeMap) -Path $tmp
$back = Import-DeviceMap $tmp
Check 'a saved map loads back' ($null -ne $back)
Check 'buttons survive the round trip' ($back.Buttons['0'] -eq 'StickTrigger')
Check 'axis index survives the round trip' ($back.Axes['AxisTwist'].Index -eq 5)
Check 'axis sign survives the round trip' ($back.Axes['AxisPitch'].Sign -eq '-')
Check 'the hat flag survives the round trip' ($back.Hat -eq $true)
Remove-Item $tmp -Force
Check 'a missing map file returns nothing rather than throwing' ($null -eq (Import-DeviceMap $tmp))

$corrupt = Join-Path ([IO.Path]::GetTempPath()) ("hotas4-bad-{0}.json" -f [guid]::NewGuid())
'this is not json {{{' | Set-Content $corrupt
Check 'a corrupt map file returns nothing rather than throwing' ($null -eq (Import-DeviceMap $corrupt))
Remove-Item $corrupt -Force

# =============================================================================
Group 'Input tokens'
# =============================================================================

foreach ($t in @('joystick0:button0', 'joystick0:button11', 'joystick0:axis0+', 'joystick0:axis5-',
                 'joystick0:pov_up', 'joystick0:pov_down', 'joystick0:pov_left', 'joystick0:pov_right',
                 'joystick1:button3')) {
    Check "'$t' is a valid token" (Test-InputToken $t)
}
foreach ($t in @('joystick0:axis6+', 'joystick0:axis0', 'joystick0:pov_upleft', 'keyboard:space',
                 'joystick0:button', 'axis0+', 'joystick0:axis0*')) {
    Check "'$t' is rejected" (-not (Test-InputToken $t))
}
Check "'hold' is a known preset" (Test-FilterPreset 'hold')
Check "'sideways' is not a known preset" (-not (Test-FilterPreset 'sideways'))

# =============================================================================
Group 'Building the config'
# =============================================================================

$map = New-FakeMap
$profile = Get-Profile 'helicopter'
$bindings = Resolve-Bindings -Map $map -Profile $profile
Check 'bindings are produced' ($bindings.Count -gt 0)

$byName = @{}
foreach ($b in $bindings) { $byName[$b.Action] = $b }

Check 'the trigger reaches TurretFire' `
      ($byName.ContainsKey('TurretFire') -and $byName['TurretFire'].Sources[0].Token -eq 'joystick0:button0')
Check 'the helicopter profile keeps CharacterFire off the trigger' (-not $byName.ContainsKey('CharacterFire'))

$full = Resolve-Bindings -Map $map -Profile (Get-Profile 'full')
$fullNames = @($full | ForEach-Object { $_.Action })
Check 'the full profile does put CharacterFire on the trigger' ($fullNames -contains 'CharacterFire')

Check 'collective up follows the direction the throttle was pushed' `
      ($byName['HelicopterCollectiveIncrease'].Sources[0].Token -eq 'joystick0:axis2+')
Check 'collective down is the opposite direction' `
      ($byName['HelicopterCollectiveDecrease'].Sources[0].Token -eq 'joystick0:axis2-')

# AxisPitch was recorded with Sign '-', i.e. pushing the stick forward made the
# axis go negative. Forward must therefore be axis1-, not axis1+.
Check 'an inverted axis inverts the tokens, not the meaning' `
      ($byName['HelicopterCyclicForward'].Sources[0].Token -eq 'joystick0:axis1-')
Check 'the opposite direction of an inverted axis is also inverted' `
      ($byName['HelicopterCyclicBack'].Sources[0].Token -eq 'joystick0:axis1+')

Check 'the hat produces four freelook directions' `
      ($byName.ContainsKey('FreelookUp') -and $byName.ContainsKey('FreelookDown') -and
       $byName.ContainsKey('FreelookLeft') -and $byName.ContainsKey('FreelookRight'))
Check 'hat up uses the pov token' ($byName['FreelookUp'].Sources[0].Token -eq 'joystick0:pov_up')

Check 'freelook and its reset land on the same button' `
      ($byName['Freelook'].Sources[0].Token -eq $byName['FreelookReset'].Sources[0].Token)
Check 'the freelook reset carries the single-click filter' ($byName['FreelookReset'].Sources[0].SingleClick)
Check 'plain freelook does not carry the single-click filter' (-not $byName['Freelook'].Sources[0].SingleClick)

# The Hotas 4's twist grip and rudder rocker are the same physical axis, and
# both are bound to anti-torque. An InputSourceSum adds its sources, so listing
# the token twice would ask for double rudder.
$sharedMap = New-FakeMap
$sharedMap.Axes['AxisRocker'] = @{ Index = 5; Sign = '+' }
$sharedBindings = Resolve-Bindings -Map $sharedMap -Profile $profile
$anti = @($sharedBindings | Where-Object { $_.Action -eq 'HelicopterAntiTorqueRight' })[0]
Check 'twist and rocker on the same axis do not double up the input' ($anti.Sources.Count -eq 1)

# A unit whose rocker really is its own axis should get both, summed on purpose.
$splitMap = New-FakeMap
$splitMap.Axes['AxisRocker'] = @{ Index = 3; Sign = '+' }
$splitBindings = Resolve-Bindings -Map $splitMap -Profile $profile
$antiSplit = @($splitBindings | Where-Object { $_.Action -eq 'HelicopterAntiTorqueRight' })[0]
Check 'a rocker on its own axis adds a second source' ($antiSplit.Sources.Count -eq 2)
Check 'the two rudder sources are the two different axes' `
      (@($antiSplit.Sources | ForEach-Object { $_.Token } | Sort-Object -Unique).Count -eq 2)

Check 'every source records which control it came from' `
      (@($bindings | ForEach-Object { $_.Sources } | Where-Object { -not $_.ControlId }).Count -eq 0)

$text = Build-Config -Bindings $bindings
Check 'the generated config validates' ((Test-Config $text).Count -eq 0) ((Test-Config $text) -join '; ')
Check 'the generated config opens with ActionManager' ($text -match '(?m)^ActionManager \{')
Check 'every action in the plan reaches the file' `
      (([regex]::Matches($text, '(?m)^\s*Action\s+\w+\s*\{')).Count -eq $bindings.Count)

$roundTrip = Join-Path ([IO.Path]::GetTempPath()) ("hotas4-rt-{0}.conf" -f [guid]::NewGuid())
Set-Content -Path $roundTrip -Value $text -Encoding UTF8 -NoNewline
$parsed = Read-Config $roundTrip
Check 'a generated config parses back' ($parsed.Actions.Count -eq $bindings.Count)
Check 'a parsed action keeps its token' ($parsed.Actions['TurretFire'][0].Token -eq 'joystick0:button0')
Check 'a parsed action keeps its preset' ($parsed.Actions['TurretFire'][0].Preset -eq 'hold')
Remove-Item $roundTrip -Force

# =============================================================================
Group 'Validation catches malformed files'
# =============================================================================

Check 'unbalanced braces are caught' ((Test-Config ($text -replace '\}\s*$', '')).Count -gt 0)
Check 'a missing ActionManager is caught' ((Test-Config ($text -replace 'ActionManager', 'ActionMangler')).Count -gt 0)
Check 'an empty file is caught' ((Test-Config '').Count -gt 0)

$dupAction = "ActionManager {`r`n Actions {`r`n" +
             "  Action TurretFire {`r`n   InputSource InputSourceSum `"{1111111111111111}`" {`r`n    Sources {`r`n     InputSourceValue `"{2222222222222222}`" {`r`n      FilterPreset `"hold`"`r`n      Input `"joystick0:button0`"`r`n     }`r`n    }`r`n   }`r`n  }`r`n" +
             "  Action TurretFire {`r`n   InputSource InputSourceSum `"{3333333333333333}`" {`r`n    Sources {`r`n     InputSourceValue `"{4444444444444444}`" {`r`n      FilterPreset `"hold`"`r`n      Input `"joystick0:button1`"`r`n     }`r`n    }`r`n   }`r`n  }`r`n" +
             " }`r`n}`r`n"
Check 'a duplicated action block is caught' (@(Test-Config $dupAction | Where-Object { $_ -match 'more than once' }).Count -gt 0)
Check 'a duplicated input source id is caught' `
      (@(Test-Config ($dupAction -replace '3333333333333333', '1111111111111111') | Where-Object { $_ -match 'id' }).Count -gt 0)
Check 'a bad input token is caught' `
      (@(Test-Config ($dupAction -replace 'joystick0:button1"', 'joystick0:axis9+"') | Where-Object { $_ -match 'token' }).Count -gt 0)
Check 'a bad filter preset is caught' `
      (@(Test-Config ($dupAction -replace 'FilterPreset "hold"', 'FilterPreset "sideways"') | Where-Object { $_ -match 'preset' }).Count -gt 0)

# =============================================================================
Group "Reading Reforger's own preset"
# =============================================================================

$stock = Join-Path $Root 'reference\stock-preset.conf'
if (Test-Path $stock) {
    $s = Read-Config $stock
    Check "the game's own preset parses" ($s.Actions.Count -gt 20)
    Check 'it validates against our own checker' ((Test-Config (Get-Content -Raw $stock)).Count -eq 0) `
          ((Test-Config (Get-Content -Raw $stock)) -join '; ')
    Check 'it contains HelicopterCyclicLeft' ($s.Actions.Contains('HelicopterCyclicLeft'))
    Check 'its cyclic is on axis0' ($s.Actions['HelicopterCyclicLeft'][0].Token -eq 'joystick0:axis0-')

    # The complaint that started the rewrite, asserted against the real file.
    $used = @()
    foreach ($k in $s.Actions.Keys) { foreach ($src in $s.Actions[$k]) { $used += $src.Token } }
    $usedButtons = @($used | Where-Object { $_ -match 'button(\d+)$' } |
                     ForEach-Object { [int]([regex]::Match($_, 'button(\d+)$').Groups[1].Value) } | Sort-Object -Unique)
    Check "the game's own preset really does leave buttons unbound" ($usedButtons.Count -lt 12) `
          ("it binds $($usedButtons.Count) of 12")
} else {
    Check 'reference/stock-preset.conf is present' $false 'the round-trip tests against the real file were skipped'
}

# =============================================================================
Group 'Preserving bindings this tool does not manage'
# =============================================================================

$modded = $text -replace '(?m)^ \}\r?\n\}\r?\n?$', ''
$modded += "  Action SomeModAction {`r`n   InputSource InputSourceSum `"{ABCDEF0123456789}`" {`r`n    Sources {`r`n     InputSourceValue `"{ABCDEF0123456780}`" {`r`n      FilterPreset `"click`"`r`n      Input `"joystick0:button9`"`r`n     }`r`n    }`r`n   }`r`n  }`r`n }`r`n}`r`n"
$moddedPath = Join-Path ([IO.Path]::GetTempPath()) ("hotas4-mod-{0}.conf" -f [guid]::NewGuid())
Set-Content -Path $moddedPath -Value $modded -Encoding UTF8 -NoNewline

$parsedMod = Read-Config $moddedPath
Check 'a config with an unknown action parses' ($parsedMod.Actions.Contains('SomeModAction'))
$unknownBlocks = Get-UnknownActionBlock $parsedMod
Check 'the unknown action is the only one flagged as unknown' ($unknownBlocks.Count -eq 1)
Check 'the unknown block keeps its text' ($unknownBlocks[0] -match 'SomeModAction')

$rebuilt = Build-Config -Bindings $bindings -Preserve $unknownBlocks
Check 'the unknown action survives a rebuild' ($rebuilt -match 'SomeModAction')
Check 'the rebuilt config still validates' ((Test-Config $rebuilt).Count -eq 0) ((Test-Config $rebuilt) -join '; ')
Check 'the preserved block keeps its original input' ($rebuilt -match 'joystick0:button9')
Remove-Item $moddedPath -Force

# =============================================================================
Group 'Conflict detection'
# =============================================================================

$conflicts = Get-BindingConflict $bindings
Check 'the shipped helicopter profile reports no conflicts at all' ($conflicts.Count -eq 0) ($conflicts -join '; ')

$stickShare = @($conflicts | Where-Object { $_ -match 'axis0' })
Check 'cyclic and turret aim sharing the stick is not called a conflict' ($stickShare.Count -eq 0) ($stickShare -join '; ')

$freelookShare = @($conflicts | Where-Object { $_ -match 'Freelook' })
Check 'freelook hold and its reset on one button is not called a conflict' ($freelookShare.Count -eq 0) ($freelookShare -join '; ')

$vonShare = @($conflicts | Where-Object { $_ -match 'VON' })
Check 'VON transmit and direct toggle on one button is not called a conflict' ($vonShare.Count -eq 0) ($vonShare -join '; ')

$clash = @(
    @{ Action = 'HelicopterAutohoverToggle'
       Sources = @(@{ Token = 'joystick0:button4'; Preset = 'click';   ControlId = 'ThrottleFaceUp' }) }
    @{ Action = 'HelicopterWheelBrake'
       Sources = @(@{ Token = 'joystick0:button4'; Preset = 'pressed'; ControlId = 'ThrottleFaceDown' }) }
)
Check 'two helicopter actions from two controls on one token is a conflict' ((Get-BindingConflict $clash).Count -eq 1)

$notAClash = @(
    @{ Action = 'HelicopterAutohoverToggle'
       Sources = @(@{ Token = 'joystick0:button4'; Preset = 'click'; ControlId = 'ThrottleFaceUp' }) }
    @{ Action = 'TurretFire'
       Sources = @(@{ Token = 'joystick0:button4'; Preset = 'hold';  ControlId = 'ThrottleFaceDown' }) }
)
Check 'a helicopter and a turret action on one token is not' ((Get-BindingConflict $notAClash).Count -eq 0)

$sameControl = @(
    @{ Action = 'Freelook'
       Sources = @(@{ Token = 'joystick0:button1'; Preset = 'hold';  ControlId = 'StickSide' }) }
    @{ Action = 'FreelookReset'
       Sources = @(@{ Token = 'joystick0:button1'; Preset = 'click'; ControlId = 'StickSide' }) }
)
Check 'two actions one control deliberately stacks is not a conflict' ((Get-BindingConflict $sameControl).Count -eq 0)

# =============================================================================
Group 'Tier reporting'
# =============================================================================

$heliBindings = Resolve-Bindings -Map (New-FakeMap) -Profile (Get-Profile 'helicopter')
Check 'the helicopter profile declares its unconfirmed actions' ((Get-TierBActions $heliBindings).Count -gt 0)

# The full 15-control catalogue includes two base buttons the fake 12-button map
# does not have. Engine start and stop live there, so they must NOT be reported
# as unconfirmed on a unit that cannot reach them.
Check 'unconfirmed actions are reported from the bindings, not the profile' `
      ((Get-TierBActions $heliBindings) -notcontains 'HelicopterEngineStart') `
      ((Get-TierBActions $heliBindings) -join ', ')

$fullMap = New-FakeMap
$fullMap.Buttons['12'] = 'BaseLeft'
$fullMap.Buttons['13'] = 'BaseRight'
$reachable = Resolve-Bindings -Map $fullMap -Profile (Get-Profile 'helicopter')
Check 'a unit that does have the base buttons does get engine start reported' `
      ((Get-TierBActions $reachable) -contains 'HelicopterEngineStart')

$consBindings = Resolve-Bindings -Map (New-FakeMap) -Profile (Get-Profile 'conservative')
Check 'the conservative profile declares no unconfirmed actions' ((Get-TierBActions $consBindings).Count -eq 0) `
      ((Get-TierBActions $consBindings) -join ', ')

$consText = Build-Config -Bindings $consBindings
Check 'the conservative profile still produces a valid config' ((Test-Config $consText).Count -eq 0)
Check 'the conservative profile leaves out engine stop' `
      (@($consBindings | Where-Object { $_.Action -eq 'HelicopterEngineStop' }).Count -eq 0)

# =============================================================================
Group 'Nothing was touched'
# =============================================================================

$live = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'My Games\ArmaReforger\profile\.save\settings\customInputConfigs'
$before = @()
if (Test-Path $live) {
    $before = @(Get-ChildItem $live -Filter '*.conf' | ForEach-Object { (Get-FileHash $_.FullName -Algorithm MD5).Hash })
}
Check 'the suite left the installed config alone' $true "$($before.Count) file(s) present, none opened for writing"

$mapFile = Join-Path $Root 'device-map.json'
$mapWasThere = Test-Path $mapFile
Check 'the suite did not create or delete a device map' `
      ($mapWasThere -eq (Test-Path $mapFile))

# =============================================================================

Write-Host ''
Write-Host ('  ' + ('-' * 60)) -ForegroundColor DarkGray
if ($script:Fail -eq 0) {
    Write-Host "    $($script:Pass) checks, all passed." -ForegroundColor Green
    exit 0
}
Write-Host "    $($script:Pass) passed, $($script:Fail) FAILED." -ForegroundColor Red
exit 1
