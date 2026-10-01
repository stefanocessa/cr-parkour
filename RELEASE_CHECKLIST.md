# Release checklist

Run on a clean server (ox_lib + cr-parkour only) before tagging a release. Mark a line only after checking it in
FiveM, not by reading the code.

## Repository

- [ ] LICENSE decided and added
- [ ] Third-party assets reviewed: `git ls-files stream/` lists no `.ycd` / `.txt` from the custom pack
- [ ] No `.DS_Store`, logs, screenshots, videos, zips, backups, `test-config.lua` (`git status` clean, `.gitignore` respected)
- [ ] `fxmanifest.lua` version = CHANGELOG version
- [ ] README updated (features, controls, exports, events, known limitations)
- [ ] CHANGELOG updated

## Default config

- [ ] `Config.Debug = false`
- [ ] `Config.DebugCommands = false`
- [ ] `Config.TuningMode = false`
- [ ] `Config.Profiler.enabled = false`
- [ ] `Config.Preset = 'balanced'`, `Config.Performance.mode = 'balanced'`

## Start-up

- [ ] Fresh install works (copy folder, `ensure ox_lib`, `ensure cr-parkour`)
- [ ] ox_lib dependency works; without ox_lib FiveM refuses to start the resource with a clear message
- [ ] Default config works
- [ ] No console errors (server console and F8) at start, during play and at stop
- [ ] No debug overlay, markers, prints or commands visible with the default config

## Gameplay

- [ ] Parkour hold works (nothing happens without the key, GTA jump / crouch untouched)
- [ ] Vault works (low, medium, high)
- [ ] Same obstacle reusable (vault → step away → vault, three times)
- [ ] Wallrun works (left and right)
- [ ] Ledge works (grab, hang, shimmy, corner, climb-up, drop)
- [ ] Slide works (parkour + crouch)
- [ ] Under traversal works
- [ ] Landing roll works
- [ ] Precision jump / long jump work
- [ ] Stamina enabled tested
- [ ] Stamina disabled tested

## Robustness

- [ ] Resource restart tested while idle, vaulting, wallrunning, ledge hanging, sliding, under sliding
- [ ] Death, vehicle entry, teleport and ragdoll during an ability leave the ped free (no freeze, camera normal)
- [ ] Missing custom animation tested (pack removed: abilities fall back, wall flip / tricks denied, no errors)
- [ ] `SetParkourEnabled(false)` during an ability cancels it cleanly

## Performance

- [ ] `/parkourperf` + `resmon 1` measured for idle, moving without parkour, parkour held in open area,
      parkour held in a complex area, active traversal — numbers written in TUNING.md / release notes
