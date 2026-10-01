local Vec = require 'client.core.vec'
local Movement = require 'client.core.movement'
local Momentum = require 'client.systems.momentum'
local Animation = require 'client.systems.animation'

local Launch = {}

local gravity = Config.Physics.gravity
local breakSpeed = Config.Trajectory.guideBreakSpeed
local S = Constants.States

Launch.Start = function(ctx, velocity, options)
    local launch = Momentum.From(velocity)
    local active = {
        launch = launch,
        options = options,
        startedAt = ctx.now,
        heading = ctx.heading,
        targetHeading = options.heading or ctx.heading,
        guiding = true,
    }
    Momentum.Apply(ctx.ped, launch)
    if options.animation then Animation.CrossFade(options.animation, { duration = options.duration }) end
    return active
end

local guide = function(ctx, active, elapsed)
    local window = math.max(active.options.impulseMs or 0, active.options.guideMs or 0)
    if not active.guiding or elapsed > window then return end
    local expected = active.launch.velocity - Vec.Up * (gravity * elapsed / 1000.0)
    if active.lastCommand and #(ctx.velocity - active.lastCommand) > breakSpeed and elapsed > (active.options.impulseMs or 0) then
        active.guiding = false
        return
    end
    SetEntityVelocity(ctx.ped, expected.x, expected.y, expected.z)
    active.lastCommand = expected
end

Launch.Update = function(ctx, active)
    local options = active.options
    local elapsed = ctx.now - active.startedAt
    active.heading = Movement.TurnHeading(active.heading, active.targetHeading, options.turnGain, ctx.dt)
    SetEntityHeading(ctx.ped, active.heading)
    guide(ctx, active, elapsed)

    if elapsed < options.minDuration then return nil end
    if ctx.grounded then
        return { velocity = Vec.Flat(ctx.velocity) * (options.landingKeep or 1.0), motion = true }
    end
    local waiting = options.endEvent and not Animation.Reached(options.endEvent)
    if waiting and elapsed < (options.maxDuration or options.minDuration) then return nil end
    return { next = S.FALLING }
end

return Launch
