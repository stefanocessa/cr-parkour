local Vec = require 'client.core.vec'
local State = require 'client.core.state'
local Combo = require 'client.core.combo'
local Cooldown = require 'client.core.cooldowns'
local Raycast = require 'client.detection.raycast'
local Launch = require 'client.systems.launch'
local Momentum = require 'client.systems.momentum'
local DebugState = require 'client.debug.state'

local TicTac = { name = 'tictac', states = { Constants.States.TICTAC } }

local settings = Config.TicTac
local reasons = Constants.Reasons
local S = Constants.States
local active = nil

local surfaceAngle = function(moveDir, wall)
    return 90.0 - Vec.Angle2d(moveDir, wall.wallDir)
end

local pickWall = function(ctx, scan)
    local best, sawWall
    for _, side in ipairs({ 'left', 'right', 'front' }) do
        local wall = scan.walls[side]
        if wall and wall.valid and wall.distance <= settings.contactDistance and Vec.Dot(ctx.moveDir, wall.wallDir) > 0.0 then
            sawWall = true
            local angle = surfaceAngle(ctx.moveDir, wall)
            if angle >= settings.minAngle and angle <= settings.maxAngle and (not best or wall.distance < best.distance) then
                best = wall
            end
        end
    end
    return best, sawWall
end

local exitVelocity = function(ctx, wall)
    local flat = Vec.Flat(ctx.velocity)
    local normalSpeed = Vec.Dot(flat, wall.normal)
    local tangential = flat - wall.normal * normalSpeed
    local push = math.max(-normalSpeed * settings.normalRestitution, settings.minPush)
    return tangential * settings.tangentKeep + wall.normal * push + Vec.Up * settings.upVelocity
end

TicTac.Evaluate = function(ctx, scan)
    if not settings.enabled then return false, reasons.TICTAC_DENIED_DISABLED end
    if not State.CanTransition(S.TICTAC) then return false, reasons.TICTAC_DENIED_STATE end
    if not ctx.airborne then return false, reasons.TICTAC_DENIED_NOT_AIRBORNE end
    if not Cooldown.CanUse(TicTac.name, ctx.now) then return false, reasons.TICTAC_DENIED_COOLDOWN end
    if ctx.speed2d < Combo.MinSpeed('tictac', settings.minSpeed, ctx.now) then return false, reasons.TICTAC_DENIED_LOW_SPEED end

    local wall, sawWall = pickWall(ctx, scan)
    if not wall then return false, sawWall and reasons.TICTAC_DENIED_BAD_ANGLE or reasons.TICTAC_DENIED_NO_WALL end

    local velocity = exitVelocity(ctx, wall)
    local exitDir = Vec.Normalize2d(velocity) or wall.normal
    if Raycast.Direction(Raycast.AtHeight(ctx, 'chest'), exitDir, settings.exitClearance).hit then
        return false, reasons.TICTAC_DENIED_NO_SPACE
    end

    local side = Vec.Dot(wall.normal, Vec.Right(ctx.moveDir)) < 0.0 and 'right' or 'left'
    DebugState.Candidate('tictac', true, reasons.OK, { side = side, angle = surfaceAngle(ctx.moveDir, wall), wallDistance = wall.distance })
    return true, reasons.OK, { wall = wall, velocity = velocity, side = side, heading = Vec.Heading(exitDir) }
end

TicTac.Enter = function(ctx, payload)
    Momentum.Capture(ctx)
    active = Launch.Start(ctx, payload.velocity, {
        animation = settings.animation[payload.side],
        heading = payload.heading,
        impulseMs = settings.impulseMs,
        minDuration = settings.minDuration,
        turnGain = settings.turnGain,
    })
end

TicTac.Update = function(ctx)
    return Launch.Update(ctx, active)
end

TicTac.Exit = function()
    active = nil
end

return TicTac
