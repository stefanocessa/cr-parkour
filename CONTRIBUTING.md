# Contributing to CR-Parkour

Thanks for helping. The project is in public beta: the most useful contributions right now are honest in-game
test reports and small, focused fixes.

## Opening an issue

- **Bug**: use the *Bug report* template. Always include the FiveM artifact, the cr-parkour and ox_lib versions,
  exact steps, and the output of `/parkoursnapshot` (enable `Config.DebugCommands = true` or `Config.Debug = true`).
  A short video is worth more than a long description.
- **Feature**: use the *Feature request* template and explain the gameplay problem first, then the idea.
- Search existing issues before opening a new one.

## Proposing a fix

1. Open (or comment on) an issue so we agree on the problem and the approach.
2. Fork the repository and create a branch: `fix/ledge-drop-push`, `feat/controller-bindings`...
3. Keep the change focused on that one problem.
4. Test it in FiveM (see below).
5. Open a pull request with the template filled in.

## Pull request rules

- **No unrelated refactors.** Do not reformat, rename or move code you are not fixing.
- **No rewrites** of a module unless the issue explicitly agreed on it.
- **No new dependency** without a clear reason discussed in an issue. The core depends on ox_lib only.
- **No framework code in the core** (ESX, QBCore, QBox...). Optional integrations go in separate, clearly named
  files that the core does not require.
- **No assets without a license.** Never commit `.ycd` / `.ydr` / other game assets unless you made them or their
  license explicitly allows redistribution — state the source and license in the PR.
- **Debug off.** `Config.Debug`, `Config.DebugCommands`, `Config.TuningMode` and `Config.Profiler.enabled` must
  stay `false` in the committed config.
- **Config first.** New numbers go in `shared/config.lua`, in the right section, with a short comment. Keep the
  default behaviour unchanged unless the PR is about changing it.
- Update the README / CHANGELOG when you change behaviour, controls, exports or events.

## Code style

- Follow the existing code: modules are local tables returned by `require`, functions are
  `Module.Name = function(...) end`, private helpers are `local name = function(...) end`.
- Config sections are `Config.PascalCase`, fields are `camelCase`.
- No comments in Lua logic — use clear names instead. Config comments are welcome.
- Keep modules focused; no giant `client.lua`.
- No magic numbers in logic: read them from `Config` or `Constants`.
- Avoid polling when an event / state based approach is possible (`lib.onCache`, `State.OnChange`, keybind callbacks).
- Use only real FiveM / GTA natives. Verify every native against <https://docs.fivem.net/natives/>
  (sources: `citizenfx/natives` and `citizenfx/fivem/ext/native-decls`). Do not guess names or parameters.
- Prefer the GTA engine (tasks, natives) over simulating behaviour by hand.
- Every denial path returns a reason code from `Constants.Reasons` so the debug panel can explain it.

## Project structure

```text
fxmanifest.lua
shared/
  config.lua          all settings, grouped by section
  presets.lua         gameplay presets + performance presets
  animations.lua      animation registry (custom / native / meta)
  constants.lua       states, reason codes, flags
client/
  main.lua            wiring: main loop, commands, exports, resource stop
  core/               state machine (state), input, context, scanner, resolver, lifecycle,
                      recovery (SafeReset + watchdog), cooldowns, combo, movement, vec
  detection/          raycast, traversal (space scanner), obstacle, wall, ledge, surface, landing, trajectory
  abilities/          one file per ability: Evaluate / Enter / Update / Exit (+ Score, Verify, Recover)
  systems/            animation, camera, collision, damage, launch, momentum, stamina
  debug/              rays, state panels, profiler, snapshot, tuning menu, animation report
server/
  main.lua            fall impact hook (rate limited) + animation manifest callback
stream/               optional custom animation pack (not distributed)
docs/                 development notes
```

Where to look:

| Topic | File |
| --- | --- |
| Config | `shared/config.lua` |
| Input / keybinds | `client/core/input.lua` |
| State machine | `client/core/state.lua`, `client/core/lifecycle.lua` |
| Scanner | `client/core/scanner.lua`, `client/detection/traversal.lua` |
| Resolver | `client/core/resolver.lua` |
| Abilities | `client/abilities/*.lua` |
| Animations | `shared/animations.lua`, `client/systems/animation.lua` |
| Debug | `client/debug/*.lua` |
| Recovery | `client/core/recovery.lua` |
| Performance | `Config.Performance`, `client/debug/profiler.lua` |

## Testing in FiveM

There is no automated test suite. **A Python / Lua simulation is not a substitute for an in-game test**: every
PR that touches gameplay must be tested in FiveM.

1. Use a local server with ox_lib and cr-parkour only (or a minimal setup).
2. Set `Config.Debug = true` (or `Config.TuningMode = true` for the tuning menu) **locally**, do not commit it.
3. Run the relevant sections of [TESTING.md](TESTING.md), plus the recovery checks (death, vehicle, teleport,
   `restart cr-parkour` during the ability).
4. Check F8 for errors and warnings.
5. For performance changes: `/parkourperf` + `resmon 1`, before and after, same spot.
6. Put the results in the PR: what you tested, where, artifact version, video if possible.
