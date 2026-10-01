# Roadmap

Real next steps, roughly in priority order. Nothing here is promised for a date — pick something and open an
issue to discuss it before starting.

## Before a stable release

- [ ] Full in-game pass of [TESTING.md](TESTING.md) and fixes for every P0 / P1 finding
- [ ] Performance measurements (scenarios A–J in [TUNING.md](TUNING.md)) on at least two machines
- [ ] Tune the native animation fallbacks (vault heights / timing without the custom pack)
- [ ] Decide and add a license
- [ ] Resource restart during a kinematic traversal (under slide, vault) should leave the ped in a free spot

## Detection

- [ ] Better handling of irregular collision meshes and thin props (fences, railings, stairs)
- [ ] Moving platforms / vehicles as optional parkour surfaces
- [ ] Improved corner ledge transitions (inner corners, short edges)

## Animations

- [ ] Mappings for more animation packs (only packs whose license allows it)
- [ ] Tool to measure `meta` values (lift, cross phase, distances) from a clip in game, instead of offline
- [ ] Clips for the air tricks that are registered but empty (front / back / side flip)

## Input & UX

- [ ] Controller testing and default bindings
- [ ] Locale system (ox_lib locales) for notifications, keybind descriptions and debug text — currently Italian
- [ ] Optional on-screen hints for the available action

## Integrations

- [ ] Optional framework bridges (stamina / damage / job restrictions) as separate files, never in the core

## Code health

- [ ] Remove unused helpers left from earlier phases (list in the release audit)
- [ ] Split `client/debug/state.lua` (~27 KB) and `client/detection/traversal.lua` (~25 KB) into smaller modules
