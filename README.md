# hotas-reforger

Bind **every** control on a Thrustmaster T.Flight Hotas 4 in Arma Reforger.

Reforger generates its own joystick preset the first time it sees the stick.
That preset works, and it leaves your trigger, your side thumb button and both
halves of the throttle rocker doing nothing at all. This writes a config where
every button, the hat and all four live axes have a job — or says, in as many
words, which ones you chose to leave alone.

Windows only. Windows PowerShell 5.1 or PowerShell 7. No install, no
dependencies, no drivers beyond Thrustmaster's own.

---

## Quick start

```powershell
cd hotas-reforger
powershell -ExecutionPolicy Bypass -File .\Hotas4.ps1 -Identify   # once, ~1 min
powershell -ExecutionPolicy Bypass -File .\Hotas4.ps1 -Apply
```

Or double-click `Hotas4.cmd` for a menu.

**Close Reforger first.** It rewrites this file when it exits, so anything
written while it is running is silently thrown away. The tool checks and warns.

Set the switch on the throttle base to **PC**, not PS4. In PS4 mode the stick
enumerates as a different device (PID `B67B` instead of `B67C`) and reports a
different control set.

---

## Why it is built control-first

The obvious way to write a binding tool is to walk the game's list of actions
and ask which button you want for each. That is what the previous version of
this did, and it is why the trigger ended up unbound: you can get to the end of
the action list without the tool ever having mentioned a control you own.

So this walks the *hardware*. There are two layers, kept apart:

| Layer | Maps | Where it comes from |
|---|---|---|
| **Device map** | winmm index → physical control | measured on your unit by `-Identify` |
| **Profile** | physical control → game actions | shipped in `lib/Reforger.ps1`, editable |

Because the profile talks about *the trigger* rather than *button 0*, it stays
correct on a unit that enumerates in a different order, and the completeness
check becomes something you can actually assert:

```
COMPLETE -- 17 of 17 controls have a job (0 deliberately free).
```

`-Verify` exits non-zero if that line does not appear, so it works in CI.

---

## Modes

| | |
|---|---|
| `-Identify` | Learn your unit. Press each control when asked; it records the index, and for axes which way they travel. Do this once. |
| `-Apply` | Generate, validate and install the config. Backs up first. |
| `-Show` | The physical layout and what every control currently does. |
| `-Verify` | Coverage audit + structural check of the installed file. Exit 1 on any gap. |
| `-Watch` | Live reader: move something, see the token Reforger would use. |
| `-CheckLog` | Read Reforger's newest log; did the engine accept the bindings? |
| `-Restore` | Put Reforger's own stock preset back. |
| `-SelfTest` | 140 checks. No joystick needed, nothing written. |

Useful flags: `-ProfileName <name>`, `-DryRun` (print instead of write),
`-Force` (skip confirmations), `-ConfigName <file>`.

---

## Profiles

| Name | What it is |
|---|---|
| `helicopter` *(default)* | Everything on the stick flies or shoots. No on-foot actions, so nothing here can fire your rifle while you are walking. |
| `full` | As above, plus the trigger and reload work on foot too. |
| `conservative` | Confirmed actions only — see *Provenance*. Costs you sights and engine start/stop, which become explicitly `Free`. |

The default layout, on a 12-button unit:

| Control | Does |
|---|---|
| Stick roll | Cyclic roll · turret traverse |
| Stick pitch | Cyclic pitch · turret elevation |
| Throttle lever | Collective |
| Stick twist / rudder rocker | Anti-torque · turret rotate |
| Hat | Freelook, four directions |
| **Trigger** | Turret fire |
| **Side face button** | Freelook (hold) · recentre (single click) |
| Stick top, left | Voice — push to talk (hold) · direct channel (click) |
| Stick top, right | Map |
| Stick raised button | Camera view |
| **Rocker forward** | Next weapon |
| **Rocker back** | Reload |
| Throttle face, up | Autohover |
| Throttle face, right | Select action |
| Throttle face, down | Wheel brake |
| Throttle face, left | Parking brake |
| Throttle thumb | Sights / ADS |
| Base buttons | Engine start · engine stop |

The four in bold are the ones Reforger's own preset leaves dead. Engine stop is
on a recessed base button on purpose — an engine cut on something you can brush
is an engine cut in the air.

To change a binding, edit `$script:Profiles` in `lib/Reforger.ps1`. Assign a
job id, or the literal `'Free'` to leave a control alone deliberately. `'Free'`
passes the completeness check; omitting the control entirely does not, which is
the distinction the whole tool turns on.

---

## Provenance of the action names

Reforger publishes no list of bindable actions and ships its game data packed,
so every action name is sourced and carries a tier.

- **Tier A — observed.** The engine wrote this name into the preset it
  generates itself, or into `InputUserSettings.conf` after an in-game rebind.
  Certain.
- **Tier B — extracted.** A plain-text symbol in `ArmaReforgerSteam.exe`, in
  the same string region as the Tier A names, and unambiguously an input action
  rather than a class or a property. Very likely right, not yet watched being
  consumed. Flagged in yellow, listed by `-Verify`, and excluded entirely by
  the `conservative` profile.

A handful of Tier A names (`GadgetMap`, `SelectAction`, `VONChannel`) do not
appear in the binary because they are script-side rather than engine-side. That
is expected, and is why "not in the exe" is not treated as evidence against a
name that has been observed.

To promote Tier B to observed: launch the game once, then

```powershell
powershell -ExecutionPolicy Bypass -File .\Hotas4.ps1 -CheckLog
```

"No input errors" means the engine took every binding in the file. It knows to
ignore `ForceFeedback effect failed to create` — the Hotas 4 has no
force-feedback motor, so that line is always there and never means anything.

---

## What it will not do

**Write a malformed file.** Generated text is checked for brace balance, an
`ActionManager` block, duplicate action names, duplicate input source ids,
unrecognised input tokens and unrecognised filter presets before anything
touches the disk, and read back and re-checked afterwards. A malformed config
is worse than none: Reforger drops the lot and gives you a dead stick with no
error you would notice.

**Drop bindings it does not recognise.** An action from a mod, or from a newer
build, is copied through verbatim rather than deleted.

**Double an input.** The Hotas 4's twist grip and rudder rocker are one
physical axis and both drive anti-torque. An `InputSourceSum` adds its sources,
so listing that token twice would ask for double rudder. Duplicates are merged.

**Guess your button numbers.** It has no built-in index table, because a
plausible-but-wrong one is worse than none. `-Identify` measures.

---

## Things that live outside this file

The binding config only says which input drives which action. Feel is set
elsewhere:

- **Deadzone** — the Thrustmaster control panel (`joy.cpl` → Properties).
  Reforger has no deadzone setting of its own. `-Identify` measures resting
  drift and tells you if you need one.
- **Sensitivity curve** — `ReforgerEngineSettings.conf` carries an
  `InputProfileJoystick` block with `Axis00`–`Axis09`, each holding a
  `CurveCubicSplineFloat`. Set these through the game's controls UI.
- **Inversion** — handled by `-Identify` asking for a direction. By hand, swap
  `+`/`-` on the `Input` line.

The complete set of filter presets the engine ships is `Click`, `DoubleClick`,
`Down`, `Hold`, `HoldOnce`, `Preset`, `Pressed`, `Repeat`, `SingleClick`,
`Toggle`, `Up`, `Value`; anything outside it is not expressible in this file.

---

## Other sticks

Most of this is device-agnostic — the detection, the direction inference, the
generator, the validator, the completeness audit. What is Hotas 4 specific is
`$script:ControlCatalogue` in `lib/Layout.ps1`: the list of physical controls
and how to describe finding each one. Rewrite that list for your stick and the
rest follows. Controls the catalogue has never heard of still get picked up —
`-Identify` asks you to name them and they are audited like any other.

Known limits: the tool assumes `joystick0` throughout, so a stick *and*
separate pedals *and* a throttle quadrant would need work; and the winmm
`U`/`V` → `axis3`/`axis4` mapping is inferred rather than confirmed, which does
not matter on a Hotas 4 because nothing uses them.

---

## Layout

```
Hotas4.ps1            entry point and all the modes
Hotas4.cmd            double-click launcher
lib/Common.ps1        one shared helper
lib/Ui.ps1            console output and key input
lib/Device.ps1        winmm, discovery, live reading, direction inference
lib/Layout.ps1        physical control catalogue, device map, coverage audit
lib/Reforger.ps1      action catalogue, profiles, config generate/parse/validate
tests/Run-Tests.ps1   the suite
reference/            Reforger's stock preset, and the config this replaced
```

Run the tests after any edit:

```powershell
powershell -ExecutionPolicy Bypass -File .\Hotas4.ps1 -SelfTest
```

The one thing tests cannot cover is the physical read — whether *your* throttle
is the axis the driver claims. That is what `-Identify` asking you to move a
named control is for.
