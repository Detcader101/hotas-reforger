# Arma Reforger — T.Flight Hotas 4 config

Device confirmed on this PC: **VID 0x044F / PID 0xB67C** — T.Flight Hotas 4 in **PC mode**,
reporting **6 axes, 12 buttons, 1 POV hat**. (PID `B67B` also appears in the registry — that's
the same stick in PS4 mode. Keep the base switch on **PC**, or Reforger won't see it properly.)

## Files here

| File | What it is |
|---|---|
| **`Bind-Hotas.ps1`** | **The binding wizard. Start here.** |
| `Check-HotasLog.ps1` | Reads Reforger's log, tells you if the engine accepted every binding. |
| `Test-Hotas.ps1` | Raw live reader — which physical control is which index. |
| `Joystick_TFlightHotas4_0.conf` | Current config. Also installed (see path below). |
| `Joystick_TFlightHotas4_0.STOCK.conf` | Reforger's own auto-generated preset. Revert copy. |
| `backup-<timestamp>-*.conf` | Written automatically every time the wizard saves. |

## The wizard

```powershell
cd C:\Users\jayja\hotas-reforger
powershell -ExecutionPolicy Bypass -File .\Bind-Hotas.ps1
```

**Close Reforger first.** The game rewrites the config on exit, so anything saved
while it's running gets thrown away. The wizard checks and warns you.

Three modes:

- **Change a few bindings** — pick individual actions off a list. This is the one
  you want for a tweak or two.
- **Full wizard** — all 21 steps from the top.
- **Show current bindings** — read-only.

Per step: `Enter` keeps what's there, `s` skips, `b` goes back, `u` unbinds,
`q` quits. Nothing is written to disk until you confirm at the end.

### Things it does for you

**Direction is worked out, not guessed.** It asks you to *raise the collective*, not
to "move an axis". Whichever way the axis actually travels becomes "up", and the
opposite becomes "down". Same for cyclic, rudder and turret. An inverted throttle
is not possible.

**Conflicts are context-aware.** Cyclic and turret aim share the stick and that's
correct — they never apply in the same seat. The wizard only warns when two
actions collide in the *same* context.

**Engine stop is flagged.** It'll bind it if you insist, but it tells you first
why putting an engine cut on a button you might brush is a bad idea.

**Validation before write.** Brace balance, duplicate IDs, duplicate action blocks.
If the generated file is malformed it refuses to write and leaves your config alone.
After writing it reads the file back and re-parses it.

**Bindings it doesn't know about are preserved.** If a mod adds an action and it
ends up in your config, the wizard keeps the block verbatim rather than dropping it.

### Verified vs unconfirmed action names

Reforger doesn't publish a list of bindable actions, and the game data is packed,
so the catalogue is built from two sources:

- **Confirmed** — names the game itself wrote into its own generated preset, or that
  we've watched the engine accept. Everything flight- and gunner-related is here.
- **Unconfirmed** — names pulled out of `ArmaReforgerSteam.exe` that read
  unambiguously as input actions, but which we haven't yet seen Reforger consume.
  Currently just engine start/stop. The wizard marks these in yellow.

After a launch, confirm the unconfirmed ones:

```powershell
powershell -ExecutionPolicy Bypass -File .\Check-HotasLog.ps1
```

"No input errors" means the engine took every binding. It knows to ignore
`ForceFeedback effect failed to create` — that's just the stick having no
force-feedback motor.

### Tests

```powershell
powershell -ExecutionPolicy Bypass -File .\Bind-Hotas.ps1 -SelfTest
```

**92 checks, no joystick required, nothing written.** Run this after any edit.
Exit code is 0 on success, 1 on any failure, so it drops straight into CI later.

Two layers:

**Unit** — catalogue integrity, button bit masks across all 32 bits, axis and
button detection driven with synthetic readings, the input-token grammar, the
structural validator's ability to catch each kind of malformation, config
generation, parse round-tripping, preservation of unknown actions, and config
filename resolution.

**Integration** — the real listen loop fed a fake device (button press, button 0,
axis positive, axis negative, hat, unplugged mid-step, every keyboard escape),
then the whole binding flow with the loop stubbed (full run, skip-all, unbind,
quit, back at the first step, redo, colliding bindings). The last check hashes
your live config before and after and asserts the suite never touched it.

The one thing tests can't cover is the physical read itself — whether *your*
throttle is the axis the driver says it is. That's what the wizard asking you to
move a specific control is for.

## Making this work for other sticks

Most of it is already device-agnostic. What's generic:

- Axis and button detection, and the winmm → Reforger index mapping
- The action catalogue — nothing in it is Thrustmaster-specific
- Direction inference, so any stick's axis polarity sorts itself out
- Config filename: auto-detected from `Joystick_*.conf` in the profile folder,
  so another stick's file is picked up without an argument. Override with
  `-ConfigName`.

What would still need work:

- `Get-Stick` prefers Thrustmaster's vendor ID (`0x044F`) and otherwise takes the
  first stick found. A picker would be needed for someone with a stick *and*
  pedals *and* a throttle quadrant as separate devices.
- Multi-device configs. Reforger writes one file per device and tokens are
  `joystick0:` / `joystick1:`; the wizard assumes `joystick0` throughout.
- The `axis3`/`axis4` (U/V) mapping is inferred, not confirmed. It doesn't matter
  on a Hotas 4 because nothing uses them, but a stick with six live axes would
  want that verified against Reforger's rebinding screen first.

## Installed to

```
C:\Users\jayja\Documents\My Games\ArmaReforger\profile\.save\settings\customInputConfigs\Joystick_TFlightHotas4_0.conf
```

Edit it with the game **closed**. Reforger rewrites this file when you rebind in-game,
so anything you change by hand while it's running will be lost.

**To revert:** copy `Joystick_TFlightHotas4_0.STOCK.conf` over the installed file and rename it.

## Bindings

### Axes

| Axis | Action | Notes |
|---|---|---|
| `axis0` X | Cyclic left/right · Turret aim left/right | Stick roll |
| `axis1` Y | Cyclic forward/back · Turret aim up/down | Stick pitch |
| `axis2` Z | Collective up/down | Throttle lever |
| `axis5` Rz | Anti-torque (tail rotor) · Turret rotate | Stick twist rudder |

`axis3` / `axis4` are unused — the stick reports 6 axes but only these four are flight-relevant.

Cyclic/turret share axes deliberately: they're in different contexts, so the game only
applies whichever seat you're in.

### Buttons

| Button | Action |
|---|---|
| `button0` | Turret fire |
| `button2` | Map |
| `button3` | Freelook (hold) · Freelook reset (single click) |
| `button4` | Autohover toggle |
| `button5` | Wheel brake (+ persistent) |
| `button6` | Turret reload |
| `button7` | Turret next weapon |
| `button8` | **Engine start** |
| `button10` | VON push-to-talk (hold) · Direct channel toggle (click) |
| hat | Freelook up/down/left/right |

`button1`, `button9`, `button11` are left free — bind them in-game to whatever you want.

## Two things I changed from Reforger's stock preset

1. **Added `HelicopterEngineStart` on `button8`.** The stock preset had no engine control at all.
   I deliberately did **not** bind `HelicopterEngineStop` — an accidental brush of a button
   you haven't identified yet means an engine shutdown in the air. Use the keyboard for that.

2. **Dropped `CharacterFire`, `CharacterNextWeapon`, and `SelectAction`.** The stock preset left
   these live, so the stick trigger fires your rifle while you're on foot. This is a flight
   config; door-gunner fire is still on the trigger via `TurretFire`.

To put `CharacterFire` back, add this block inside `Actions { }` (any unique GUIDs will do):

```
  Action CharacterFire {
   InputSource InputSourceSum "{6B0A11E5C0DE0101}" {
    Sources {
     InputSourceValue "{6B0A11E5C0DE0102}" {
      FilterPreset "hold"
      Input "joystick0:button0"
     }
    }
   }
  }
```

## Verify the mapping (worth 2 minutes before you fly)

Two things are assumed rather than measured: **which physical control is `axis2` vs `axis5`**,
and **which physical button is which index**. Both are easy to confirm.

**Buttons and hat — run the reader:**

```powershell
cd C:\Users\jayja\hotas-reforger
powershell -ExecutionPolicy Bypass -File .\Test-Hotas.ps1
```

Press each button; it prints the index and the exact token to use. Ctrl+C to quit.

**Axes — use Reforger itself.** Settings → Controls, pick a helicopter action, then move the
control. The game shows the real token (e.g. `joystick0:axis2+`). This is authoritative;
Windows and Reforger can disagree on the order of the non-X/Y/Z axes.

### If the throttle is backwards

Most likely single problem: collective goes *down* when you push the throttle *forward*.
That's a sign flip. In the config, swap the `+` and `-` on the two collective lines:

```
  HelicopterCollectiveIncrease   ->  Input "joystick0:axis2-"
  HelicopterCollectiveDecrease   ->  Input "joystick0:axis2+"
```

Same trick for anti-torque (`axis5`) or cyclic if either feels inverted.

## Tuning that lives outside this file

The binding config only says *which input drives which action*. Feel is set elsewhere:

- **Deadzone** — Thrustmaster control panel (`joy.cpl` → Properties). Reforger has no
  deadzone setting of its own. The wizard measures resting drift and tells you if you
  need one; as of the last check yours reads 0.00 on every axis, so you don't.
- **Sensitivity curve** — Reforger *does* support this, despite what I said first time.
  `ReforgerEngineSettings.conf` carries an `InputProfileJoystick` block with `Axis00`–`Axis09`,
  each holding a `CurveCubicSplineFloat`. Yours are empty, i.e. linear. Set these through
  the game's controls UI rather than by hand.
- **Inversion** — the wizard handles it by asking for a direction. By hand, swap `+`/`-`
  on the `Input` line.

The action filters the engine ships are `Click`, `DoubleClick`, `Down`, `Hold`, `HoldOnce`,
`Preset`, `Pressed`, `Repeat`, `SingleClick`, `Toggle`, `Up`, `Value` — that's the whole set,
so anything outside it isn't expressible in this file.
