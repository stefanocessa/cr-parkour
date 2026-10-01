## What and why

Closes #

## How it was tested

FiveM artifact, map location, steps, video if possible.

## Checklist

- [ ] Tested in FiveM (not only in a simulation)
- [ ] No unrelated refactor / reformatting
- [ ] No new dependency (or explained and agreed in an issue)
- [ ] No framework code in the core
- [ ] No asset without a redistribution license
- [ ] `Config.Debug`, `Config.DebugCommands`, `Config.TuningMode`, `Config.Profiler.enabled` are `false`
- [ ] Existing traversal not broken (vault, wallrun, ledge, slide, under, roll checked)
- [ ] Recovery checked (death / vehicle / `restart cr-parkour` during the changed ability)
- [ ] New config values documented in `shared/config.lua`
- [ ] Only real natives, verified on docs.fivem.net/natives
- [ ] README / CHANGELOG updated if behaviour, controls, exports or events changed
