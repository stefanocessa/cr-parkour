# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[Semantic Versioning](https://semver.org/).

## [1.6.0] — unreleased (first public beta)

Version taken from `fxmanifest.lua`. The 1.x number comes from internal development phases; see the release
audit for the open question about renumbering the first public release as `0.x`.

### Added

- Traversal space scanner (`OVER`, `UNDER`, `THROUGH`, `CLIMB`, `LEDGE`, `WALL`, `BALANCE`) and score-based resolver.
- Abilities: vault (9 styles), vault through openings, under slide, manual slide, landing roll, wall climb, ledge
  grab / hang / climb-up, shimmy with corners, ledge jumps, wallrun, walljump, tic-tac, wall flip, precision jump,
  long jump, air trick, balance.
- Hold-to-parkour input (`+parkour`, default E) with Space / Ctrl / trick-key combinations and input buffer.
- Animation registry with custom → native → safe fallback, overrides and per-clip offsets.
- Optional GTA stamina integration, combos, momentum carry, camera effects, damage hooks.
- Safety: watchdog per state, `Recovery.SafeReset`, teleport / respawn / vehicle / ragdoll detection.
- Client exports, local events, rate-limited server fall hook.
- Debug overlay, profiler, snapshot, animation report, ox_lib tuning menu.
- Gameplay presets (`realistic`, `balanced`, `arcade`) and performance presets (`quality`, `balanced`, `performance`).

### Release preparation

- Main loop protected with `pcall`: a Lua error is logged once and the ped is reset instead of staying frozen.
- Debug commands are only registered when `Config.DebugCommands`, `Config.Debug`, `Config.TuningMode` or
  `Config.Profiler.enabled` is true.
- Warning in console for an unknown `Config.Preset` / `Config.Performance.mode`.
- Config grouped by section and commented (values unchanged).
- Custom animation pack excluded from the public repository via `.gitignore` (unclear redistribution license);
  documented as an optional install.
- README, CONTRIBUTING, ROADMAP, release checklist, issue / PR templates, `.gitignore`.
