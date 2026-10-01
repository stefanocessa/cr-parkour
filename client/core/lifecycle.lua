local State = require 'client.core.state'
local Context = require 'client.core.context'
local Movement = require 'client.core.movement'
local Combo = require 'client.core.combo'
local Cooldown = require 'client.core.cooldowns'
local Momentum = require 'client.systems.momentum'
local Animation = require 'client.systems.animation'
local Collision = require 'client.systems.collision'
local Camera = require 'client.systems.camera'
local Stamina = require 'client.systems.stamina'
local DebugState = require 'client.debug.state'

local Lifecycle = {}

local S = Constants.States
local reasons = Constants.Reasons
local momentumSettings = Config.Momentum
local weapons = Config.Weapons
local abilities = {}
local unique = {}
local registry = {}
local simple = {}
local run = nil

for i = 1, #weapons.simpleAbilities do simple[weapons.simpleAbilities[i]] = true end

local emit = function(event, payload)
    TriggerEvent(('cr-parkour:%s'):format(event), payload)
end

Lifecycle.Register = function(list)
    for _, ability in ipairs(list) do
        unique[#unique + 1] = ability
        registry[ability.name] = ability
        for i = 1, #ability.states do abilities[ability.states[i]] = ability end
    end
end

Lifecycle.For = function(state)
    return abilities[state]
end

Lifecycle.Get = function(name)
    return registry[name]
end

Lifecycle.Registry = function()
    return registry
end

Lifecycle.Active = function()
    return abilities[State.Current()]
end

Lifecycle.Run = function()
    return run
end

Lifecycle.Allowed = function(ctx, ability)
    if ctx.armed then
        if not weapons.allowParkour then return false, reasons.PARKOUR_DENIED_WEAPON end
        if not simple[ability.name] and not weapons.allowAdvancedTricks then return false, reasons.PARKOUR_DENIED_WEAPON end
    end
    return Stamina.CanPerform(ability.name)
end

Lifecycle.MarkActive = function()
    if run and run.phase == 'enter' then run.phase = 'active' end
end

Lifecycle.Elapsed = function(now)
    return run and (now or GetGameTimer()) - run.startedAt or 0
end

local motionFor = function(ctx, velocity)
    if not ctx.input.active then return nil end
    local speed = velocity and math.sqrt(velocity.x * velocity.x + velocity.y * velocity.y) or 0.0
    if speed < momentumSettings.forceMotionSpeed then return nil end
    return ctx.sprintHeld and Constants.MotionStates.sprint or Constants.MotionStates.run
end

local release = function(ctx, result)
    Movement.Release(ctx.ped)
    if result.velocity then Momentum.Apply(ctx.ped, Momentum.From(result.velocity)) end
    if result.motion then
        local motion = motionFor(ctx, result.velocity)
        if motion then ForcePedMotionState(ctx.ped, motion, false, 0, false) end
    end
end

local begin = function(ctx, ability, target, payload)
    run = { ability = ability.name, state = target, phase = 'enter', startedAt = ctx.now }
    Cooldown.Start(ability.name, ctx.now)
    Stamina.Consume(ability.name)
    ability.Enter(ctx, payload, target)
    Combo.Enter(ability.name, target, ctx.now)
    Camera.OnAbility(ability.name, target, payload)
    emit('abilityStarted', { ability = ability.name, state = target })
end

local close = function(ctx, ability, velocity, event, detail)
    Combo.Exit(ability.name, ctx.now, velocity)
    Cooldown.End(ability.name, ctx.now)
    Camera.OnAbilityEnd(ability.name)
    emit(event, detail)
end

Lifecycle.Enter = function(ctx, target, payload)
    if not State.CanTransition(target) then return false, reasons.INVALID_TRANSITION end
    local ability = abilities[target]
    local previous = abilities[State.Current()]
    local from = State.Current()
    if previous and previous ~= ability then
        if run then run.phase = 'exit' end
        previous.Exit(target)
        close(ctx, previous, ctx.velocity, 'abilityEnded', { ability = previous.name, state = from, next = target })
    end
    if not State.IsKinematic(target) then Movement.Release(ctx.ped) end
    State.Set(target, payload)
    Context.ResetAir()
    Collision.Protect(ctx.ped, true)
    if previous == ability then
        ability.Enter(ctx, payload, target)
        if run then run.state = target end
    else
        begin(ctx, ability, target, payload)
    end
    return true
end

Lifecycle.Finish = function(ctx, ability, result)
    local current = State.Current()
    local target = result.next or State.Derive(ctx)
    if not State.CanTransition(target) then
        DebugState.SetReason(ability.name, reasons.INVALID_TRANSITION, ('%s>%s'):format(current, target))
        target = State.Derive(ctx)
        if not State.CanTransition(target) then target = S.FALLING end
    end
    if result.reason then DebugState.SetReason(ability.name, result.reason) end

    if run then run.phase = 'exit' end
    ability.Exit(target)
    local nextAbility = abilities[target]
    if nextAbility ~= ability then
        close(ctx, ability, result.velocity, 'abilityEnded', { ability = ability.name, state = current, next = target, reason = result.reason })
    end

    if not State.IsKinematic(target) then release(ctx, result) end

    if nextAbility then
        State.Set(target, result.payload)
        if nextAbility ~= ability then
            begin(ctx, nextAbility, target, result.payload)
        else
            nextAbility.Enter(ctx, result.payload, target)
            if run then run.state = target end
        end
        return
    end

    run = nil
    State.Set(target)
    Animation.Stop()
    Context.ResetAir()
    Collision.Protect(ctx.ped, false)
end

Lifecycle.Cancel = function(ctx, reason)
    local current = State.Current()
    local ability = abilities[current]
    if not ability then
        run = nil
        return nil
    end
    if run then run.phase = 'recovery' end
    local velocity = ability.Recover and ability.Recover(ctx) or nil
    ability.Exit(nil)
    close(ctx, ability, velocity, 'abilityCancelled', { ability = ability.name, state = current, reason = reason })
    run = nil
    return velocity
end

Lifecycle.Start = function(ctx, name, payload, target)
    local ability = registry[name]
    if not ability then return false, reasons.TRAVERSAL_NO_ABILITY end
    return Lifecycle.Enter(ctx, target or ability.states[1], payload)
end

Lifecycle.Apply = function(ctx, ability, result)
    if result.hold then
        DebugState.SetReason(ability.name, result.reason)
        return false
    end
    Lifecycle.Finish(ctx, ability, result)
    return true
end

local exhausted = function(ctx, ability)
    return {
        next = S.FALLING,
        velocity = ability.Recover and ability.Recover(ctx) or ctx.velocity,
        reason = reasons.PARKOUR_END_LOW_STAMINA,
    }
end

Lifecycle.Update = function(ctx, ability)
    ability = ability or abilities[State.Current()]
    if not ability then return false end
    if not Stamina.Drain(ability.name, ctx.dt) then
        Lifecycle.Apply(ctx, ability, exhausted(ctx, ability))
        return true
    end
    local result = ability.Update(ctx, State.Current())
    Lifecycle.MarkActive()
    if result then Lifecycle.Apply(ctx, ability, result) end
    return true
end

Lifecycle.Stop = function(ctx, reason)
    return Lifecycle.Cancel(ctx, reason)
end

Lifecycle.ResetAll = function()
    for i = 1, #unique do
        if unique[i].Reset then unique[i].Reset() end
    end
end

return Lifecycle
