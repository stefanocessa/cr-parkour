local State = require 'client.core.state'
local Context = require 'client.core.context'
local Movement = require 'client.core.movement'
local Scanner = require 'client.core.scanner'
local Input = require 'client.core.input'
local Cooldown = require 'client.core.cooldowns'
local Lifecycle = require 'client.core.lifecycle'
local Recovery = require 'client.core.recovery'
local Animation = require 'client.systems.animation'
local Collision = require 'client.systems.collision'
local Raycast = require 'client.detection.raycast'
local DebugState = require 'client.debug.state'
local Profiler = require 'client.debug.profiler'

local Vault = require 'client.abilities.vault'
local Slide = require 'client.abilities.slide'
local Roll = require 'client.abilities.roll'
local Wallrun = require 'client.abilities.wallrun'
local Walljump = require 'client.abilities.walljump'
local Wallclimb = require 'client.abilities.wallclimb'
local LedgeAbility = require 'client.abilities.ledge'
local Shimmy = require 'client.abilities.shimmy'
local Climb = require 'client.abilities.climb'
local TicTac = require 'client.abilities.tictac'
local WallFlip = require 'client.abilities.wallflip'
local Precision = require 'client.abilities.precision'
local LongJump = require 'client.abilities.longjump'
local Tricks = require 'client.abilities.tricks'
local Balance = require 'client.abilities.balance'
local Rays = require 'client.debug.rays'

local Resolver = {}

local S = Constants.States
local reasons = Constants.Reasons
local scanSettings = Config.Scan
local ledgeSettings = Config.Ledge
local resolverSettings = Config.Resolver
local traversalSettings = Config.Traversal
local detection = Config.Detection
local wallflipSettings = Config.WallFlip
local performance = Config.Performance.active
local blocked = nil
local wasHeld = false
local decision = { candidate = 'NONE', selected = nil, results = {}, order = {}, final = nil, stable = nil }
local entryPool = {}
local noOptions = {}
local found = {}
local priorityIndex = {}
for i = 1, #traversalSettings.priority do priorityIndex[traversalSettings.priority[i]] = i end
local noGeometry = {}
for i = 1, #resolverSettings.noGeometry do noGeometry[reasons[resolverSettings.noGeometry[i]]] = true end
local escalate = {}
for i = 1, #resolverSettings.escalate do escalate[reasons[resolverSettings.escalate[i]]] = true end

Lifecycle.Register({ Vault, Slide, Roll, Wallrun, Walljump, Wallclimb, LedgeAbility, Shimmy, Climb, TicTac, WallFlip, Precision, LongJump, Tricks, Balance })

local groundOptions = {
    OVER = { { Vault, S.VAULTING } },
    THROUGH = { { Vault, S.VAULTING } },
    UNDER = { { Slide, S.SLIDING, 'EvaluateUnder' } },
    CLIMB = { { Wallclimb, S.WALLCLIMBING } },
    LEDGE = { { Wallclimb, S.WALLCLIMBING } },
    WALL = { { Wallrun, S.WALLRUNNING } },
    BALANCE = { { Balance, S.BALANCING } },
}
local airOptions = {
    LEDGE = { { LedgeAbility, S.LEDGE_GRAB } },
    WALL = { { Wallrun, S.WALLRUNNING }, { TicTac, S.TICTAC } },
}

local report = function(ability, ok, reason, detail)
    DebugState.SetReason(ability.name, ok and reasons.OK or reason, detail)
    DebugState.Candidate(ability.name, ok, ok and reasons.OK or reason)
end

local isAir = function(state)
    return Constants.AirAbilities[state] == true
end

local enter = Lifecycle.Enter

local tryStart = function(ctx, ability, target, ...)
    local allowed, gate = Lifecycle.Allowed(ctx, ability)
    if not allowed then
        report(ability, false, gate)
        return false
    end
    local globalOk, globalReason = Cooldown.CanStart(ability.name, ctx.now)
    if not globalOk then
        report(ability, false, globalReason)
        return false
    end
    local ok, reason, payload, detail = ability.Evaluate(ctx, ...)
    report(ability, ok, reason, detail)
    if not ok then return false end
    return enter(ctx, target, payload)
end

local probe = function(ctx, ability, ...)
    local ok, reason = ability.Evaluate(ctx, ...)
    report(ability, ok, reason)
end

local evaluateDebugCandidates = function(ctx, scan)
    if not Rays.IsEnabled() then return end
    if ctx.grounded then
        probe(ctx, Precision, scan)
        probe(ctx, LongJump, scan)
    else
        probe(ctx, TicTac, scan)
        probe(ctx, Tricks, scan)
    end
    probe(ctx, WallFlip, scan)
end

local handleLanding = function(ctx)
    local rolled, reason, payload, category = Roll.Land(ctx)
    DebugState.SetReason('landing', reasons.OK, ('%s %.2fm'):format(category, ctx.landedFall or 0.0))
    if rolled then
        report(Roll, true)
        enter(ctx, S.ROLLING, payload)
        return true
    end
    if category ~= 'small' then report(Roll, false, reason) end
    Collision.Protect(ctx.ped, false)
    return false
end

local autoGrab = function(held)
    return held or (ledgeSettings.autoGrabFromAbility and isAir(State.Current()))
end

local handleAir = function(ctx, scan, held)
    if not ctx.airborne or not Constants.AirChain[State.Current()] or not autoGrab(held) then return false end
    return scan.ledge ~= nil and scan.at == ctx.now and tryStart(ctx, LedgeAbility, S.LEDGE_GRAB, scan)
end

local api = { start = tryStart, enter = enter, apply = Lifecycle.Apply }

local updateAbility = function(ctx, ability)
    local started = Profiler.Start()
    Lifecycle.Update(ctx, ability)
    Profiler.Stop('ability', started)
end

local guard = function(ctx)
    if ctx.teleported then
        Recovery.SafeReset(ctx, reasons.RECOVERY_TELEPORT, { dropVelocity = true })
        Scanner.Invalidate()
        return false
    end
    local ok, reason = Context.CanParkour(ctx)
    if ok then
        blocked = nil
        return true
    end
    if blocked ~= reason then
        blocked = reason
        Recovery.SafeReset(ctx, reason, { state = ctx.ragdoll and S.RAGDOLL or S.IDLE, dropVelocity = ctx.dead })
        DebugState.SetReason('parkour', reason)
    end
    State.SyncLocomotion(ctx)
    return false
end

local jumpReady = function(ctx, scan)
    if not State.IsLocomotion() or (not ctx.grounded and not ctx.coyote) then return false end
    return Precision.Evaluate(ctx, scan) or LongJump.Evaluate(ctx, scan)
end

local scoreOf = function(ability, payload)
    if ability.Score then return ability.Score(payload) end
    return resolverSettings.fallbackScore[ability.name] or resolverSettings.defaultScore
end

local optionsFor = function(kind, airborne)
    local options = airborne and airOptions[kind] or groundOptions[kind]
    return options or noOptions
end

local prepareEntry = function(ctx, index, category)
    local entry = entryPool[index]
    if entry then
        for key in pairs(entry) do entry[key] = nil end
    else
        entry = {}
        entryPool[index] = entry
    end
    entry.type = category.type
    entry.valid = category.valid
    entry.score = category.score
    entry.reason = category.reason
    entry.detail = category.detail
    entry.category = category
    entry.ok = false
    if not category.valid then return entry end
    if category.open then
        entry.reason, entry.passive = reasons.THROUGH_OPEN_PASSAGE, true
        return entry
    end
    local options = optionsFor(category.type, ctx.airborne)
    if #options == 0 then
        entry.reason = reasons.TRAVERSAL_NO_ABILITY
        return entry
    end
    entry.options = options
    entry.deferred = true
    entry.passive = true
    return entry
end

local evaluateEntry = function(ctx, scan, entry)
    if not entry.deferred then return entry end
    entry.deferred, entry.passive = nil, nil
    if entry.suppressed then
        entry.reason = reasons.VAULT_PENDING_APPROACH
        return entry
    end
    local options = entry.options
    local firstReason, firstDetail
    for i = 1, #options do
        local ability, target, method = options[i][1], options[i][2], options[i][3]
        local ok, reason, payload, detail = (method and ability[method] or ability.Evaluate)(ctx, scan)
        report(ability, ok, reason, detail)
        if ok then
            local value = scoreOf(ability, payload)
            if not entry.ok or value > entry.abilityScore then
                entry.ok, entry.ability, entry.target, entry.payload, entry.abilityScore = true, ability, target, payload, value
                entry.name = ability.name
            end
        elseif not firstReason then
            firstReason, firstDetail = reason, detail
        end
    end
    if entry.ok then
        entry.reason, entry.detail = reasons.OK, nil
        entry.variant = entry.payload.clip and entry.payload.clip.name or (entry.payload.plan and entry.payload.plan.name) or nil
    else
        entry.reason, entry.detail = firstReason or reasons.TRAVERSAL_NO_ABILITY, firstDetail
    end
    return entry
end

local rankKey = function(a, b)
    local ka, kb = math.floor(a.score / resolverSettings.tieMargin), math.floor(b.score / resolverSettings.tieMargin)
    if ka ~= kb then return ka > kb end
    return (priorityIndex[a.type] or #traversalSettings.priority + 1) < (priorityIndex[b.type] or #traversalSettings.priority + 1)
end

local clear = function(list)
    for i = #list, 1, -1 do list[i] = nil end
    return list
end

local evaluateCandidates = function(ctx, scan)
    if State.IsAbility() and not isAir(State.Current()) then return end
    evaluateDebugCandidates(ctx, scan)
    local profile = scan.profile
    local results = clear(decision.results)
    local order = clear(decision.order)
    local pending = false
    for i = 1, #profile.candidates do
        local entry = prepareEntry(ctx, i, profile.candidates[i])
        results[i] = entry
        if entry.category.approaching and Vault.Approaching(ctx, scan) then pending = true end
        if entry.deferred then order[#order + 1] = entry end
    end
    for i = 1, #order do
        if pending and order[i].type == 'WALL' then order[i].suppressed = true end
    end
    table.sort(order, rankKey)
    local full = Rays.IsEnabled()
    for key in pairs(found) do found[key] = nil end
    for i = 1, #order do
        local entry = evaluateEntry(ctx, scan, order[i])
        if entry.ok then
            found[entry.name] = true
            if not full then break end
        end
    end
    decision.pending, decision.scanAt = pending, scan.at
    decision.profile = profile
    found.jump = jumpReady(ctx, scan)
    Input.SetCandidates(ctx, found)
end

local finalReason = function(results)
    for i = 1, #results do
        if results[i].ok and results[i].startReason then
            return { code = results[i].startReason, ability = results[i].type }
        end
    end
    for i = 1, #results do
        local entry = results[i]
        if entry.valid and not entry.ok and not entry.passive then
            return { code = entry.reason, detail = entry.detail, ability = entry.type }
        end
    end
    local byType = {}
    for i = 1, #results do byType[results[i].type] = results[i] end
    local chain = nil
    for i = 1, #resolverSettings.reasonOrder do
        local entry = byType[resolverSettings.reasonOrder[i]]
        if entry and not entry.ok and entry.reason and not noGeometry[entry.reason] then
            if not escalate[entry.reason] then
                return { code = entry.reason, detail = entry.detail, ability = entry.type, chain = chain and ('%s %s'):format(chain.type, chain.reason) }
            end
            chain = chain or entry
        end
    end
    if chain then return { code = chain.reason, detail = chain.detail, ability = chain.type } end
    return { code = reasons.NO_GEOMETRY }
end

local gate = function(ctx, ability)
    local allowed, reason = Lifecycle.Allowed(ctx, ability)
    if not allowed then return reason end
    local ok, globalReason = Cooldown.CanStart(ability.name, ctx.now)
    if not ok then return globalReason end
    if not Cooldown.CanUse(ability.name, ctx.now) then return reasons.ABILITY_COOLDOWN end
    return nil
end

local startEntry = function(ctx, entry)
    local blockedBy = gate(ctx, entry.ability)
    if blockedBy then return false, blockedBy end
    local ok, reason = enter(ctx, entry.target, entry.payload)
    if not ok then return false, reason or reasons.INVALID_TRANSITION end
    return true
end

local started = function(entry, persisted)
    decision.selected = entry.type
    decision.variant = entry.variant or entry.name
    decision.final = nil
    decision.stable = nil
    decision.persisted = persisted
    Input.ConsumeTraversal()
    DebugState.SetReason('input', persisted and reasons.CANDIDATE_PERSISTED or reasons.INPUT_AUTO, ('%s %s'):format(entry.type, entry.variant or entry.name))
    return true
end

local persisted = function(ctx)
    local stable = decision.stable
    if not stable or ctx.now - stable.at > detection.candidatePersistMs then return false end
    if not stable.ability.Verify or not stable.ability.Verify(ctx, stable.payload) then return false end
    if not startEntry(ctx, stable) then return false end
    return started(stable, true)
end

local tooHigh = function(profile)
    local ledge = profile and profile.byType.LEDGE
    if not ledge or ledge.valid then return false end
    return ledge.reason == reasons.LEDGE_DENIED_TOO_HIGH
end

local autoWallFlip = function(ctx, scan)
    if not wallflipSettings.autoWhenTooHigh or not ctx.grounded or not tooHigh(decision.profile) then return false end
    if not tryStart(ctx, WallFlip, S.WALLFLIP, scan) then return false end
    decision.selected, decision.variant, decision.final, decision.stable, decision.persisted = 'TRICK', WallFlip.name, nil, nil, false
    decision.candidate = 'TRICK (auto)'
    Input.ConsumeTraversal()
    DebugState.SetReason('input', reasons.INPUT_AUTO, 'wallflip muro troppo alto')
    return true
end

local autoTraverse = function(ctx, scan)
    if scan.at ~= ctx.now or decision.scanAt ~= scan.at then return false end
    local order = decision.order
    local top = nil
    for i = 1, #order do
        local entry = evaluateEntry(ctx, scan, order[i])
        if entry.ok then
            if not top then
                top = entry
                decision.candidate = entry.type
            end
            found[entry.name] = true
            local ok, why = startEntry(ctx, entry)
            if ok then return started(entry, false) end
            entry.startReason = why
        end
    end
    if not top then
        decision.candidate = decision.pending and 'OVER (approach)' or 'NONE'
        if autoWallFlip(ctx, scan) then return true end
    end
    if top and top.ability.Verify then
        decision.stable = { ability = top.ability, target = top.target, type = top.type, name = top.name, variant = top.variant, payload = top.payload, at = ctx.now }
    end
    if persisted(ctx) then return true end
    decision.final = finalReason(decision.results)
    return false
end

local trickTraverse = function(ctx, scan)
    decision.candidate = 'TRICK'
    if scan.at ~= ctx.now or not ctx.grounded then return false end
    if tryStart(ctx, WallFlip, S.WALLFLIP, scan) then
        decision.selected, decision.variant, decision.final, decision.stable, decision.persisted = 'TRICK', WallFlip.name, nil, nil, false
        Input.ConsumeTraversal()
        Context.Consume('trick', Context.BufferWindow('trick'))
        DebugState.SetReason('input', reasons.INPUT_TRICK_WALLFLIP)
        return true
    end
    decision.final = { code = reasons.INPUT_TRICK_NONE, ability = WallFlip.name }
    return false
end

local traverse = function(ctx, scan)
    if Input.TrickHeld() then return trickTraverse(ctx, scan) end
    return autoTraverse(ctx, scan)
end

local trackHold = function(held)
    if held == wasHeld then return end
    wasHeld = held
    if held then return end
    Input.ClearCandidates()
    decision.candidate = 'NONE'
    clear(decision.results)
    clear(decision.order)
    decision.profile = nil
    decision.stable = nil
    if not State.IsAbility() then Scanner.Invalidate() end
end

Resolver.Decision = function()
    return decision
end

Resolver.Tick = function(ctx)
    Raycast.NewTick(ctx.now, ctx.grounded and not ctx.teleported and State.IsLocomotion())
    if not guard(ctx) then return end

    local current = State.Current()
    local ability = Lifecycle.For(current)
    if Recovery.Watchdog(ctx, ability, Roll.IsArmed(ctx)) then return end
    if Movement.IsHeld() and not State.IsKinematic(current) and not (ability and ability.IsKinematic and ability.IsKinematic()) then
        Movement.Release(ctx.ped)
    end
    Animation.Update()

    if not ability then
        State.SyncLocomotion(ctx)
        if ctx.justLanded and handleLanding(ctx) then return end
    end

    local held = Input.IsParkourHeld()
    trackHold(held)
    Cooldown.Track(ctx.coords, ctx.now)
    local air = ability ~= nil and isAir(current) and not (ability.IsKinematic and ability.IsKinematic())
    local scan = Scanner.Last()
    if ((held and not ability) or air) and Scanner.Due(ctx) then
        local scanStarted = Profiler.Start()
        scan = Scanner.Run(ctx)
        evaluateCandidates(ctx, scan)
        Profiler.Stop('scanner', scanStarted)
    end

    Input.Update(ctx)
    if Input.Dispatch(ctx, scan, api) then return end
    local resolverStarted = Profiler.Start()

    if ability and not air then
        decision.final = { code = reasons.ABILITY_ALREADY_ACTIVE, ability = ability.name }
        Profiler.Stop('resolver', resolverStarted)
        updateAbility(ctx, ability)
        return
    end
    if not held then decision.final = { code = reasons.INPUT_NOT_HELD } end

    if ability then
        if ctx.justLanded then
            Lifecycle.Finish(ctx, ability, { motion = true })
            handleLanding(ctx)
            return
        end
        if handleAir(ctx, scan, held) then return end
        if held and autoTraverse(ctx, scan) then return end
        Profiler.Stop('resolver', resolverStarted)
        updateAbility(ctx, ability)
        return
    end

    if handleAir(ctx, scan, held) then return end
    if held then traverse(ctx, scan) end
    Profiler.Stop('resolver', resolverStarted)
end

Resolver.Cancel = function(ctx, reason, options)
    Recovery.SafeReset(ctx, reason, options)
end

Resolver.NextWait = function(ctx)
    if not ctx.coords then return performance.idleTick end
    if State.IsAbility() or Movement.IsHeld() then return 0 end
    if blocked then return performance.idleTick end
    if ctx.airborne or Input.IsParkourHeld() or Input.HasCandidate(ctx) or Context.HasPending() or Roll.IsArmed(ctx) then return 0 end
    if ctx.speed2d > scanSettings.idleSpeed then return performance.moveTick end
    return performance.idleTick
end

return Resolver
