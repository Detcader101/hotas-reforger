# hotas-reforger

Bind **every** control on a Thrustmaster T.Flight Hotas 4 in Arma Reforger —
and know which ones actually work before you fly.

Reforger generates its own joystick preset the first time it sees the stick.
That preset flies, and it leaves the trigger, both throttle knob buttons and
several stick buttons doing nothing at all. This writes a config where every
control has a job, or says in as many words why it hasn't.

Windows only. Windows PowerShell 5.1 or PowerShell 7. No install, no
dependencies, no drivers beyond Thrustmaster's own.

```powershell
git clone https://github.com/Detcader101/hotas-reforger
cd hotas-reforger
powershell -ExecutionPolicy Bypass -File .\Hotas4.ps1 -Audit      # what responds?
powershell -ExecutionPolicy Bypass -File .\Hotas4.ps1 -Identify   # which index is what?
powershell -ExecutionPolicy Bypass -File .\Hotas4.ps1 -Apply      # write it
```

Or double-click `Hotas4.cmd` for a menu.

> **Close Reforger first.** It rewrites the input config when it exits, so
> anything written while it's running is silently thrown away. The tool checks.

> Set the switch on the throttle base to **PC**, not PS4. In PS4 mode the stick
> enumerates as a different device (PID `B67B` instead of `B67C`).

---

## The two ideas this is built on

**Walk the hardware, not the action list.** The obvious way to write a binding
tool is to go through the game's actions asking which button you want for each.
Do that and you can reach the end without ever mentioning a control you own —
which is exactly how Reforger's own preset leaves your trigger dead. This walks
the *stick*, so a control with no job is a visible hole:

```
COMPLETE -- 18 of 18 controls have a job (0 deliberately free).
```

`-Verify` exits non-zero if that line doesn't appear, so it works in CI.

**Bound is not the same as working.** Reforger keeps separate input contexts —
`HelicopterContext`, `TurretContext`, `CharacterCompartmentContext` are distinct
symbols in the engine binary. An action bound outside the seat you're sitting in
does nothing, and the config is still perfectly valid. A tool that only checks
"is every control bound" will happily fill your cockpit with turret actions and
report success. So jobs carry the context they live in, profiles declare a seat,
and a test fails if any control in the `pilot` profile is dead in the pilot seat.

Two layers, kept apart:

| Layer | Maps | Where it comes from |
|---|---|---|
| **Device map** | winmm index → physical control | measured on your unit by `-Identify` |
| **Profile** | physical control → game actions | `lib/Reforger.ps1`, editable |

Because the profile says *the trigger* rather than *button 0*, it stays correct
on a unit that enumerates differently.

---

## Modes

| | |
|---|---|
| `-Audit` | Does this control send anything **at all**? Records RESPONDS / DEAD / untested. Every control gets its own letter so you can retest one without walking the list. Writes no game config. |
| `-Identify` | Which index is each control, and which way do its axes travel. Only asks about what it doesn't already know; `-All` forces the full walk. |
| `-Apply` | Generate, validate and install. **Fills gaps by default** — see below. |
| `-Show` | The layout and what every control currently does. |
| `-Verify` | Coverage audit + structural check. Exit 1 on any gap. |
| `-Watch` | Live readout of all six axes, buttons and hat. |
| `-Bind` | Record a token by hand: `-Bind "ThrottleRocker=joystick0:axis4+"`. |
| `-CheckLog` | Read Reforger's newest log; did the engine accept the bindings? |
| `-Restore` | Put Reforger's own stock preset back. |
| `-SelfTest` | 230 checks. No joystick, no game, nothing written. |
| `-KeyTest` | Diagnostic: is this console giving the tool your keystrokes? |

Flags: `-ProfileName <name>`, `-DryRun`, `-Replace`, `-All`, `-Force`,
`-ConfigName <file>`.

### Apply fills, it does not replace

`-Apply` reads your existing config, works out which controls already drive
something, and **adds jobs only to the ones doing nothing**. Existing blocks are
carried through verbatim — same action, same token, same preset, same order.

This is the default because the alternative went badly: asked to bind four dead
controls, an earlier version regenerated the whole layout, and ten working
bindings quietly moved to different buttons. Nothing was corrupt; every piece of
muscle memory was simply wrong. Replacing the layout now needs `-Replace`, which
warns and asks first.

If a control's preferred job is already in your file, it falls back through a
per-control preference list rather than being left dead.

---

## Profiles

| Name | What it is |
|---|---|
| `pilot` *(default)* | Every button live in the helicopter pilot's seat. No turret or on-foot actions, because those do nothing in the cockpit however correctly they're bound. |
| `helicopter` | Flying and door-gunner. Some buttons are inert while piloting. |
| `full` | As above plus on-foot fire, reload and next-weapon. |
| `conservative` | Confirmed actions only — see *Provenance*. |

The `pilot` layout, on a measured unit:

| Control | Token | Does |
|---|---|---|
| Stick roll / pitch | `axis0` `axis1` | Cyclic |
| Throttle lever | `axis2` | Collective |
| Stick twist | `axis5` | Anti-torque |
| **Throttle rocker** | `axis4` | Anti-torque — second rudder, sums with the twist |
| Hat | `pov_*` | Freelook, four directions |
| **Trigger** | `button0` | Perform action |
| L1 face button | `button1` | Voice — push to talk (hold) · direct channel (click) |
| R3 face button | `button2` | Freelook (hold) · recentre (single click) |
| L3 face button | `button3` | Select action |
| Throttle face ◀ ▼ ▶ ▲ | `button4`–`button7` | Map · wheel brake · parking brake · autohover |
| **Throttle R2** | `button8` | Camera view |
| **Throttle L2** | `button9` | Direct speech |
| Base left / right | `button10` `button11` | Engine start · engine stop |

Engine stop is on a recessed base button on purpose — an engine cut on something
you can brush is an engine cut in the air.

To change a binding, edit `$script:Profiles` in `lib/Reforger.ps1`. Assign a job
id, or the literal `'Free'` to leave a control alone deliberately. `'Free'`
passes the completeness check; omitting the control does not, which is the
distinction the whole tool turns on.

---

## Provenance of the action names

Reforger publishes no list of bindable actions and ships its game data packed,
so every action name is sourced and carries a tier.

- **Tier A — observed.** The engine wrote this name into the preset it generates
  itself, or into `InputUserSettings.conf` after an in-game rebind. Certain.
- **Tier B — extracted.** A plain-text symbol in `ArmaReforgerSteam.exe`, in the
  same string region as the Tier A names, and unambiguously an input action
  rather than a class or a property. Very likely right, not yet watched being
  consumed. Flagged in yellow, listed by `-Verify`, excluded by `conservative`.

A few Tier A names (`GadgetMap`, `SelectAction`, `VONChannel`) don't appear in
the binary because they're script-side. That's expected, and why "not in the exe"
isn't treated as evidence against a name that has been observed.

To promote Tier B: launch the game once, then `-CheckLog`. "No input errors"
means the engine took every binding. It ignores `ForceFeedback effect failed to
create` — the Hotas 4 has no force-feedback motor, so that line is always there.

---

## What it will not do

**Write a malformed file.** Brace balance, `ActionManager` block, duplicate
action names, duplicate input-source ids, unrecognised tokens and unrecognised
filter presets are all checked before anything touches disk, then the file is
read back and re-checked. A malformed config is worse than none: Reforger drops
the lot and gives you a dead stick with no error you'd notice.

**Drop bindings it doesn't recognise.** A mod's action, or one from a newer
build, is copied through verbatim.

**Double an input.** An `InputSourceSum` *adds* its sources, so the same token
twice on one action asks for double that input — an axis at full deflection by
half travel. Duplicates are merged.

**Guess your button numbers.** There is no built-in index table, because a
plausible-but-wrong one is worse than none.

---

## Known limits

- **winmm axis mapping.** X, Y, Z and the rudder line up with Reforger's
  `axis0/1/2/5`. U and V are mapped to `axis3`/`axis4` by *inference*. Anything
  landing there is flagged — confirm it in Reforger → Settings → Controls, which
  prints the real token and is authoritative. If it disagrees, `-Bind` it.
- **One device.** Tokens are hard-coded to `joystick0`, so a stick *and*
  separate pedals would need work.
- **Reforger has no deadzone setting.** `-Identify` measures resting drift and
  tells you; fix it in the Thrustmaster control panel (`joy.cpl` → Properties).
  Sensitivity curves live in `ReforgerEngineSettings.conf` and are set through
  the game's UI.

---

## Other sticks

The detection, direction inference, generator, validator, seat-liveness check
and completeness audit are all device-agnostic. What is Hotas 4 specific is
`$script:ControlCatalogue` in `lib/Layout.ps1` — the list of physical controls
and how to describe finding each one. Rewrite that for your stick and the rest
follows. Controls the catalogue has never heard of still get picked up:
`-Identify` asks you to name them and they're audited like any other.

---

## Layout

```
Hotas4.ps1            entry point and all the modes
Hotas4.cmd            double-click launcher
lib/Common.ps1        one shared helper
lib/Ui.ps1            console output and key input
lib/Device.ps1        winmm, discovery, live reading, direction inference
lib/Layout.ps1        physical control catalogue, device map, coverage audit
lib/Audit.ps1         what responds and what does not
lib/Reforger.ps1      action catalogue, profiles, config generate/parse/validate
tests/Run-Tests.ps1   the suite
reference/            Reforger's stock preset, and a measured Hotas 4 layout
```

Run the tests after any edit:

```powershell
powershell -ExecutionPolicy Bypass -File .\Hotas4.ps1 -SelfTest
```

They run on every push against both Windows PowerShell 5.1 and PowerShell 7.

The one thing tests cannot cover is the physical read — whether *your* throttle
is the axis the driver claims. That is what `-Audit` and `-Identify` are for.

---

## Licence

MIT. See [LICENSE](LICENSE).
