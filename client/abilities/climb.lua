local Vec = require 'client.core.vec'
local Movement = require 'client.core.movement'
local Momentum = require 'client.systems.momentum'
local Animation = require 'client.systems.animation'
local LedgeAbility = require 'client.abilities.ledge'
local DebugState = require 'client.debug.state'

local Climb = { name = 'climb', states = { Constants.States.CLIMBING } }

local settings = Config.Climb
local ledgeSettings = Config.Ledge
local body = Config.Body
local active = nil

Climb.Enter = function(ctx, ledge)
    local target = ledge.landing + Vec.Up * body.rootHeight
    local peakZ = ledge.topZ + body.rootHeight + settings.arc
    local control = Vec.WithZ(ledge.edge + ledge.normal * body.radius, peakZ)
    local duration = Animation.SyncedDuration(ledgeSettings.animation.climb, settings.duration)
    Movement.Hold(ctx.ped)
    active = {
        ledge = ledge,
        startHeading = ledge.heading,
        tween = Movement.Tween(ctx.coords, target, control, duration, Movement.EaseInOut),
    }
    LedgeAbility.Play(ledgeSettings.animation.climb, { duration = duration })
end

Climb.Update = function(ctx)
    local ledge = active.ledge
    local position, t = Movement.Sample(active.tween)
    LedgeAbility.Place(ctx, ledge, position, Movement.LerpHeading(active.startHeading, ledge.heading, t))
    if t < 1.0 then return nil end

    if not ctx.input.active or ctx.input.forward <= 0.0 then
        return { velocity = Vec.Zero }
    end
    local speed = ctx.sprintHeld and settings.exitSprintSpeed or settings.exitSpeed
    speed = math.max(speed, (ledge.entrySpeed or 0.0) * settings.momentumKeep)
    return { velocity = Momentum.WithSpeed(ctx.inputDir or ledge.wallDir, speed).velocity, motion = true }
end

Climb.Recover = function()
    if not active then return nil end
    return active.ledge.wallDir * settings.exitSpeed + Vec.Up * settings.recoverLift
end

Climb.Exit = function()
    active = nil
    DebugState.Ledge(nil)
end

return Climb
