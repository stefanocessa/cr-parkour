# CR-Parkour

Contextual parkour and traversal system for FiveM. Hold the parkour key and the script reads the geometry in
front of you with raycasts (no zones, no coordinates) and picks the traversal that fits: vault over, slide
under, climb up, grab a ledge, run along a wall.

Standalone: the only dependency is [ox_lib](https://github.com/overextended/ox_lib). No ESX / QBCore / QBox code.

> **Status: public beta.** Every system has been checked statically (syntax, native signatures, logic review),
> but **none of it has been validated in game yet**. Expect bugs and tuning issues. Reports and pull requests are
> welcome — see [Contributing](#contributing).

## Features

Everything listed here exists in the code today. "Needs custom pack" means the feature needs the optional
animation pack (see [Custom animations](#custom-animations)).

| Category | What it does |
| --- | --- |
| Traversal scanner | Body-layer raycasts (feet → overhead) classify the space ahead as `OVER`, `UNDER`, `THROUGH`, `CLIMB`, `LEDGE`, `WALL` or `BALANCE`, each with a score or a reason code |
| Resolver | Scores every compatible ability and starts the best one; falls back to the next candidate if the best cannot start |
| Vault (OVER) | Obstacles 0.5–1.35 m. 9 styles chosen by height, depth, speed and angle. Advanced styles (kash, monkey, safety, reverse, slide, roll) need the custom pack; generic jump-over styles fall back to native GTA clips |
| Vault through (THROUGH) | Window-like openings with a lintel; full-height openings are left to normal GTA running |
| Under slide (UNDER) | Cinematic slide under low obstacles along a validated corridor (passages from ~0.85 m) |
| Manual slide | Parkour key + crouch while running |
| Wall climb | Run-up on walls 1.3–4.4 m, continues into a ledge grab |
| Ledge grab / hang | From a wall climb, a wallrun or mid-air; periodic re-validation, drop, climb-up |
| Shimmy | Left / right along the ledge, outer and inner corners |
| Ledge jumps | Jump up or sideways to another ledge |
| Wallrun | Left / right, from the ground or the air, with wall following and ledge detection |
| Walljump | From a wallrun or a wall climb |
| Tic-tac | Kick off a wall at an angle |
| Wall flip | Back flip off a wall — **needs custom pack** |
| Precision jump | Ballistic jump to a validated landing across a gap |
| Long jump | Sprint jump with a boosted trajectory |
| Air trick | **Needs custom pack**, only the front twist has a clip |
| Balance | Walk / run / jump on narrow elevated surfaces |
| Landing roll | Press crouch just before (or just after) landing from 2.2 m+ |
| Combos | Shorter speed requirements when chaining abilities (`Config.Combo`) |
| Stamina | Optional, uses GTA player stamina (`Config.Stamina.enabled = false` by default) |
| Safety & recovery | Watchdog per state, teleport / respawn / vehicle / ragdoll / death detection, `SafeReset` on resource stop |
| Animation registry | custom → native GTA → safe (no clip) fallback per entry, overrides and per-clip offsets |
| Debug tools | Raycast overlay, state / pipeline panels, reason codes, profiler, snapshot, animation report, tuning menu |

## Requirements

Required:
- [ox_lib](https://github.com/overextended/ox_lib) (developed against **3.39.0**; uses `lib.addKeybind`, `lib.onCache`,
  `cache`, `lib.callback`, `lib.notify`, `lib.print`, context menus)

Optional:
- A custom parkour animation pack (`.ycd`), **not included** — see [Custom animations](#custom-animations)

No framework, no database, no OneSync requirement.

## Installation

1. Install and start `ox_lib`.
2. Put `cr-parkour` in your `resources` folder.
3. In `server.cfg`, after ox_lib:
   ```cfg
   ensure ox_lib
   ensure cr-parkour
   ```
4. (Optional) add a custom animation pack, see below.

If ox_lib is missing, FiveM refuses to start the resource because of the `dependency 'ox_lib'` declaration in
`fxmanifest.lua`.

## Controls

"Parkour key" is the `+parkour` keybind, default **E**. Players can rebind it (and the trick key) in
*Settings → Key Bindings → FiveM*. When the parkour key is **not** held, GTA behaves normally.

| Input | Action |
| --- | --- |
| Hold **parkour key** | Contextual traversal on the ground: vault, under slide, wall climb, wallrun, balance. In the air: ledge grab, wallrun, tic-tac |
| Parkour + **Jump** (Space) | Precision jump if there is a gap with a valid landing, otherwise long jump (needs sprint speed). Plain GTA jump if neither is valid |
| Parkour + **Crouch** (Ctrl) | Slide while running; landing roll when pressed shortly before / after landing |
| Parkour + **Trick key** (default **X**, `+parkourtrick`) | Wall flip in front of a high wall, air trick while airborne |
| Hanging: **Jump** or press parkour again, or hold **Forward** | Climb up |
| Hanging: **Left / Right** | Shimmy, corners included |
| Hanging: **Jump** + Left / Right | Ledge jump sideways (jump without side input = jump up when climb-up is blocked) |
| Hanging: **Crouch** | Drop (works without the parkour key) |
| Wallrun / wall climb: **Jump** or press parkour again | Walljump |
| Balancing: **Forward / Back**, **Sprint**, **Jump** | Walk, run, jump off |

## Configuration

Everything is in [`shared/config.lua`](shared/config.lua), grouped and commented by section (General, Input,
Performance, Detection, Traversal, each ability, Gameplay rules, Animations, Camera, Debug).

- `Config.Preset` — gameplay preset `'realistic' | 'balanced' | 'arcade'` ([`shared/presets.lua`](shared/presets.lua)).
  `balanced` (default) = the values in the config, unchanged.
- `Config.Performance.mode` — `'quality' | 'balanced' | 'performance'`, only changes loop / scan intervals.
- Every ability has `enabled = true/false`.
- `Config.Weapons` — parkour while armed (only "simple" abilities by default).
- `Config.DynamicSurfaces`, `Config.Materials` — vehicles, moving props, blacklisted models / materials.
- `Config.Stamina` — optional GTA stamina costs.
- `Config.Fall` — fall categories, optional built-in damage (`damagePerMeter = 0` = off), server hook.

Unknown preset / performance mode names fall back to `balanced` with a console warning.

## Custom animations

Animations are resolved through a registry ([`shared/animations.lua`](shared/animations.lua)). Each entry can
have a `custom` clip, a `native` GTA clip, or both; a string value is an alias to another entry.

Resolution order: **custom → native GTA clip → safe** (no clip: the ability still runs on a virtual timeline).
A missing animation never blocks an ability by itself, except where noted below.

**No custom animations are distributed with this repository.** The registry is written for a third-party pack
whose redistribution license is unclear, so you have to obtain a pack yourself:

1. Obtain a parkour animation pack separately (respect its license).
2. Place the `.ycd` files in `cr-parkour/stream/` (or in any other streamed resource — dictionaries are global).
3. If the dictionary / clip names differ from the registry (`parkour@anims`, `parkour_part_2@anim`), map them with
   `Config.AnimationOverrides` or by editing `shared/animations.lua`.
4. Optional: list the clips as `dict clip` lines in a `.txt` file and point `Config.AnimationPack.manifests` to it;
   `/parkouranims` then checks the files against the registry.

What changes without the custom pack:

| Ability | Without custom clips |
| --- | --- |
| Vault | Only the 3 generic styles, played with native `move_climb` vault clips. Timing metadata was measured on the custom clips, so the native fallback needs visual tuning |
| Under slide / manual slide | Native `rubble_slide_gunman`; the kip-up variant is unavailable |
| Roll, wallrun, ledge hang / shimmy / corners, long jump, precision | Native GTA clips |
| Ledge jumps, tic-tac, balance | Work, but with no animation (safe timeline) |
| Wall flip, air tricks | **Disabled** (`WALLFLIP_DENIED_NO_ANIMATION`, `TRICK_DENIED_NO_ANIMATION`) |
| Wall climb, climb-up, walljump | Native only (no custom clip used) |

Per-clip fields (`blendIn`, `flags`, `playbackRate`, `headingOffset`, `positionOffset`, `rootMotion`, `meta`...) are
documented in [`docs/DEVELOPMENT_NOTES.md`](docs/DEVELOPMENT_NOTES.md). `meta` values (lift, cross phase, distances)
describe a specific clip: if you use a different pack, these numbers must be measured again.

## Debug

All debug output is off by default and stays off unless you enable it.

| Setting / command | Effect |
| --- | --- |
| `Config.Debug = true` | Overlay: raycasts (green free, red hit, blue top, yellow landing, purple ledge / target), state panel, pipeline panel with the reason code of every stage |
| `Config.DebugCommands = true` | Registers the debug commands below without turning debug on at start |
| `/parkourdebug` | Toggle the overlay (opens the tuning menu when `Config.TuningMode = true`) |
| `/parkoursnapshot` | Print the current state to F8 and copy it to the clipboard — attach it to bug reports |
| `/parkourperf` | Profiler overlay (`Config.Profiler`) |
| `/parkouranims`, `/parkouranim <entry>` | Animation pack report / play one registry entry and measure root motion |

The debug commands are only registered when at least one of `Config.DebugCommands`, `Config.Debug`,
`Config.TuningMode` or `Config.Profiler.enabled` is true. They only affect the local client.

In-game test protocol: [TESTING.md](TESTING.md) (Italian). Tuning log: [TUNING.md](TUNING.md) (Italian).

## Exports

Client-side only.

```lua
exports['cr-parkour']:IsParkouring()            -- boolean: an ability is running (alias: IsBusy)
exports['cr-parkour']:GetParkourState()         -- string: current state, e.g. 'IDLE', 'VAULTING', 'LEDGE_HANG' (alias: GetState)
exports['cr-parkour']:GetCurrentAbility()       -- string|nil: 'vault', 'slide', 'roll', 'wallrun', 'walljump', 'wallclimb',
                                                --   'ledge', 'shimmy', 'climb', 'tictac', 'wallflip', 'precision',
                                                --   'longjump', 'trick', 'balance'
exports['cr-parkour']:IsParkourEnabled()        -- boolean
exports['cr-parkour']:SetParkourEnabled(false)  -- disables parkour; a running ability is safely cancelled
exports['cr-parkour']:CanParkour()              -- boolean, reason: e.g. false, 'PARKOUR_DENIED_VEHICLE'
exports['cr-parkour']:CancelParkour(force)      -- boolean: false if nothing runs, or the clip is not cancelable and force ~= true

-- Damage hooks. kind: 'hardLanding' | 'failedRoll' | 'largeFall' | 'collision'. Returns false for an unknown kind.
-- Return true from the handler to replace the built-in behaviour (only 'largeFall' has one: damage + ragdoll).
exports['cr-parkour']:SetDamageHandler('largeFall', function(data) return true end)
exports['cr-parkour']:SetLandingDamageHandler(function(data) end) -- same handler for hardLanding, largeFall, failedRoll
```

States: `IDLE`, `RUNNING`, `SPRINTING`, `JUMPING`, `FALLING`, `VAULTING`, `SLIDING`, `ROLLING`, `WALLRUNNING`,
`WALLCLIMBING`, `WALLJUMPING`, `LEDGE_GRAB`, `LEDGE_HANG`, `LEDGE_MOVE`, `CLIMBING`, `TICTAC`, `WALLFLIP`,
`PRECISION`, `LONGJUMP`, `TRICK`, `BALANCING`, `RAGDOLL`.

## Events

Client, local (`AddEventHandler`). Fired on transitions only, never per frame.

| Event | Payload |
| --- | --- |
| `cr-parkour:abilityStarted` | `{ ability, state }` |
| `cr-parkour:abilityEnded` | `{ ability, state, next, reason }` (`reason` may be nil) |
| `cr-parkour:abilityCancelled` | `{ ability, state, reason }` |
| `cr-parkour:stateChanged` | `{ state, previous }` (not fired for locomotion → locomotion, e.g. RUNNING → SPRINTING) |
| `cr-parkour:damage` | `kind, data` — `largeFall { distance, rolled, reduction }`, `hardLanding { distance, heavy }`, `failedRoll { distance, reason }`, `collision { ability, speed }`; `data.kind` is set too. Disable with `Config.Damage.events = false` |
| `cr-parkour:fallImpact` | `distance, rolled` (falls of `Config.Fall.veryLarge`+ meters) |

Server, local:

| Event | Payload |
| --- | --- |
| `cr-parkour:fallImpact` | `source, distance, rolled` — **reported by the client**: rate limited (`Config.Fall.reportCooldown`) and clamped, but spoofable. Use it for cosmetics / logging, never for rewards or anticheat. Disable with `Config.Fall.serverHook = false` |

`cr-parkour:server:fallImpact` (net event) and the `cr-parkour:animationManifest` callback are internal.

## Performance

The client loop sleeps when the parkour key is not held: `idleTick` (250 ms) standing, `moveTick` (120 ms)
moving, and wakes up immediately when the key is pressed. Raycasts only run while the key is held, during an
air ability, or while an ability is active. The server does nothing per tick.

**No in-game measurements exist yet.** Use `/parkourperf` + `resmon 1` and fill the table in
[TUNING.md](TUNING.md) (scenarios A–J) — numbers from real servers are a very welcome contribution.

## Known limitations

- **Not tested in game.** All systems were verified statically only; tuning values are first guesses.
- No custom animations are shipped; with native fallbacks, vault timing / heights were measured on the custom
  clips and will look off until tuned. Wall flip and air tricks are disabled without the pack.
- `meta` values in the registry are tied to one specific pack; another pack needs new measurements.
- Detection is raycast based: thin props, irregular collision meshes, fences and stairs can produce false
  negatives or odd candidates.
- Vehicles and moving props are not parkour surfaces (`Config.DynamicSurfaces`); moving platforms are not supported.
- Restarting the resource during an under slide unfreezes the ped wherever it is, possibly under a low obstacle.
- Debug, notifications and keybind descriptions are in Italian; there is no locale system yet.
- Keyboard focused: controller input goes through the same GTA controls but has not been tested.
- Single-player feel only: other players see the result of the local ped's animations / movement through normal
  GTA sync, nothing is synced explicitly.

## Roadmap

See [ROADMAP.md](ROADMAP.md).

## Contributing

Contributions are welcome, especially:

- in-game test reports (with `/parkoursnapshot` output and a video)
- performance measurements
- animation mappings for packs you are allowed to use
- detection improvements and edge case fixes
- controller support, translations, documentation

Read [CONTRIBUTING.md](CONTRIBUTING.md) before opening a pull request.

## License

No license has been chosen yet. Until a `LICENSE` file is added, all rights are reserved by the author.
