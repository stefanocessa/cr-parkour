local Vec = require 'client.core.vec'
local State = require 'client.core.state'
local Combo = require 'client.core.combo'
local Cooldown = require 'client.core.cooldowns'
local Trajectory = require 'client.detection.trajectory'
local Launch = require 'client.systems.launch'
local Momentum = require 'client.systems.momentum'
local Collision = require 'client.systems.collision'
local DebugState = require 'client.debug.state'

local LongJump = { name = 'longjump', states = { Constants.States.LONGJUMP } }

local settings = Config.LongJump
local reasons = Constants.Reasons
local S = Constants.States
local active = nil

local deny = function(reason, info)
    DebugState.Candidate('longjump', false, reason, info)
    return false, reason
end

LongJump.Evaluate = function(ctx, scan)
    if not settings.enabled then return false, reasons.LONGJUMP_DENIED_DISABLED end
    if not State.CanTransition(S.LONGJUMP) then return false, reasons.LONGJUMP_DENIED_STATE end
    if not ctx.grounded and not ctx.coyote then return false, reasons.LONGJUMP_DENIED_STATE end
    if not Cooldown.CanUse(LongJump.name, ctx.now) then return false, reasons.LONGJUMP_DENIED_COOLDOWN end
    if ctx.speed2d < Combo.MinSpeed('longjump', settings.minSpeed, ctx.now) then return deny(reasons.LONGJUMP_DENIED_LOW_SPEED) end
    local obstacle = scan.obstacle
    if obstacle and obstacle.hit and obstacle.distance < settings.clearDistance then return deny(reasons.LONGJUMP_DENIED_OBSTACLE) end
    if Collision.HeadRoom(ctx.coords, settings.headClearance).hit then return deny(reasons.LONGJUMP_DENIED_HEAD_BLOCKED) end

    local entry = Momentum.Peek(ctx)
    local dir = entry.direction or ctx.moveDir
    local horizontal = math.min(entry.speed2d * settings.forwardMultiplier, settings.maxHorizontalSpeed)
    local velocity = dir * horizontal + Vec.Up * settings.verticalBoost
    local path = Trajectory.Predict(ctx.coords, velocity)
    local info = { speed = horizontal, airTime = path.time, landing = path.hit and path.floor }
    if path.hit and path.time < settings.minAirTime then return deny(reasons.LONGJUMP_DENIED_BAD_TRAJECTORY, info) end

    DebugState.Candidate('longjump', true, reasons.OK, info)
    return true, reasons.OK, { velocity = velocity, heading = Vec.Heading(dir) }
end

LongJump.Enter = function(ctx, payload)
    Momentum.Capture(ctx)
    active = Launch.Start(ctx, payload.velocity, {
        animation = settings.animation,
        heading = payload.heading,
        impulseMs = settings.impulseMs,
        minDuration = settings.minDuration,
        turnGain = settings.turnGain,
    })
end

LongJump.Update = function(ctx)
    return Launch.Update(ctx, active)
end

LongJump.Exit = function()
    active = nil
end

return LongJump
