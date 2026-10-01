local Vec = require 'client.core.vec'
local Movement = require 'client.core.movement'
local Momentum = require 'client.systems.momentum'
local Animation = require 'client.systems.animation'
local Camera = require 'client.systems.camera'

local Walljump = { name = 'walljump', states = { Constants.States.WALLJUMPING } }

local settings = Config.Walljump
local gravity = Config.Physics.gravity
local S = Constants.States
local active = nil

Walljump.Enter = function(ctx, payload)
    local along = payload.tangent and payload.tangent * ((payload.speed or 0.0) * settings.alongKeep) or Vec.Zero
    local launch = Momentum.From(payload.normal * settings.pushOut + along + Vec.Up * settings.upVelocity)
    local direction = launch.direction or payload.normal
    active = {
        launch = launch,
        targetHeading = Vec.Heading(direction),
        heading = ctx.heading,
        startedAt = ctx.now,
    }
    Momentum.Apply(ctx.ped, launch)
    Animation.CrossFade(settings.animation[payload.side] or settings.animation.back)
    Camera.Shake('walljump')
end

Walljump.Update = function(ctx)
    local elapsed = ctx.now - active.startedAt
    active.heading = Movement.TurnHeading(active.heading, active.targetHeading, settings.turnGain, ctx.dt)
    SetEntityHeading(ctx.ped, active.heading)
    if elapsed <= settings.impulseMs then
        local velocity = active.launch.velocity - Vec.Up * (gravity * elapsed / 1000.0)
        SetEntityVelocity(ctx.ped, velocity.x, velocity.y, velocity.z)
        return nil
    end
    if elapsed < settings.minDuration then return nil end
    if ctx.grounded then return { motion = true } end
    return { next = S.FALLING }
end

Walljump.Exit = function()
    active = nil
end

return Walljump
