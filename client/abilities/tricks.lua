local Vec = require 'client.core.vec'
local State = require 'client.core.state'
local Cooldown = require 'client.core.cooldowns'
local Raycast = require 'client.detection.raycast'
local Trajectory = require 'client.detection.trajectory'
local Launch = require 'client.systems.launch'
local Animation = require 'client.systems.animation'
local Collision = require 'client.systems.collision'
local DebugState = require 'client.debug.state'

local Tricks = { name = 'trick', states = { Constants.States.TRICK } }

local settings = Config.Tricks
local input = Config.Input
local reasons = Constants.Reasons
local S = Constants.States
local active = nil

local pickAnimation = function(ctx)
    local forward, side = ctx.input.forward, ctx.input.side
    if math.abs(forward) <= input.deadzone and math.abs(side) <= input.deadzone then return settings.animations.none end
    if math.abs(forward) >= math.abs(side) then
        return forward > 0.0 and settings.animations.forward or settings.animations.back
    end
    return side > 0.0 and settings.animations.right or settings.animations.left
end

local deny = function(reason, info)
    DebugState.Candidate('trick', false, reason, info)
    return false, reason
end

Tricks.Evaluate = function(ctx)
    if not settings.enabled then return false, reasons.TRICK_DENIED_DISABLED end
    if not ctx.airborne or not State.CanTransition(S.TRICK) then return false, reasons.TRICK_DENIED_STATE end
    if not Cooldown.CanUse(Tricks.name, ctx.now) then return false, reasons.TRICK_DENIED_COOLDOWN end

    local animation = pickAnimation(ctx)
    local info = { animation = animation, verticalSpeed = ctx.velocity.z }
    if not Animation.Resolve(animation) then return deny(reasons.TRICK_DENIED_NO_ANIMATION, info) end
    if ctx.velocity.z < settings.minVerticalSpeed then return deny(reasons.TRICK_DENIED_LOW_CLEARANCE, info) end
    if Collision.HeadRoom(ctx.coords, settings.headClearance).hit then return deny(reasons.TRICK_DENIED_HEAD_BLOCKED, info) end

    local ground = Raycast.Down(ctx.coords, Config.Roll.predictDistance)
    info.groundDistance = ground.hit and ctx.feetZ - ground.coords.z or nil
    if info.groundDistance and info.groundDistance < settings.minGroundDistance then return deny(reasons.TRICK_DENIED_LOW_CLEARANCE, info) end

    local velocity = ctx.velocity + Vec.Up * settings.pop
    local landing = Trajectory.Predict(ctx.coords, velocity)
    info.airTime = landing.time
    if not landing.hit or not landing.floor then return deny(reasons.TRICK_DENIED_NO_LANDING, info) end
    if landing.time < settings.minAirTime then return deny(reasons.TRICK_DENIED_LOW_CLEARANCE, info) end

    DebugState.Candidate('trick', true, reasons.OK, info)
    return true, reasons.OK, { velocity = velocity, animation = animation, airTime = landing.time }
end

Tricks.Enter = function(ctx, payload)
    active = Launch.Start(ctx, payload.velocity, {
        animation = payload.animation,
        heading = ctx.heading,
        impulseMs = 0,
        minDuration = 0,
        endEvent = settings.endEvent,
        maxDuration = payload.airTime * 1000.0,
        turnGain = 0.0,
    })
end

Tricks.Update = function(ctx)
    return Launch.Update(ctx, active)
end

Tricks.Exit = function()
    active = nil
end

return Tricks
