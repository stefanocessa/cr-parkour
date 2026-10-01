local Vec = require 'client.core.vec'
local State = require 'client.core.state'
local Cooldown = require 'client.core.cooldowns'
local Movement = require 'client.core.movement'
local Surface = require 'client.detection.surface'
local Animation = require 'client.systems.animation'
local Momentum = require 'client.systems.momentum'
local Precision = require 'client.abilities.precision'
local DebugState = require 'client.debug.state'

local Balance = { name = 'balance', states = { Constants.States.BALANCING } }

local settings = Config.Balance
local input = Config.Input
local reasons = Constants.Reasons
local S = Constants.States
local active = nil

local report = function(ok, reason, surface)
    DebugState.Candidate('balance', ok, reason, surface and {
        surfaceWidth = surface.width,
        leftEdge = surface.left,
        rightEdge = surface.right,
    } or nil)
end

Balance.Evaluate = function(ctx, scan)
    if not settings.enabled then return false, reasons.BALANCE_DENIED_DISABLED end
    if not ctx.grounded or not State.CanTransition(S.BALANCING) then return false, reasons.BALANCE_DENIED_STATE end
    if ctx.speed2d > settings.maxEntrySpeed then return false, reasons.BALANCE_DENIED_TOO_FAST end
    if not Cooldown.CanUse(Balance.name, ctx.now) then return false, reasons.BALANCE_DENIED_STATE end

    local surface = scan.surface
    local reason
    if not surface then
        reason = reasons.BALANCE_DENIED_NO_SURFACE
    elseif surface.wide then
        reason = reasons.BALANCE_DENIED_SURFACE_TOO_WIDE
    elseif not surface.elevated then
        reason = reasons.BALANCE_DENIED_NOT_ELEVATED
    elseif not surface.continues then
        reason = reasons.BALANCE_DENIED_NO_SURFACE
    end
    report(reason == nil, reason or reasons.OK, surface)
    if reason then return false, reason end
    return true, reasons.OK, { forward = scan.surfaceDir, surface = surface }
end

Balance.Enter = function(ctx, payload)
    Momentum.Capture(ctx)
    active = {
        forward = payload.forward,
        surface = payload.surface,
        heading = ctx.heading,
        scannedAt = ctx.now,
        enteredAt = ctx.now,
        animation = nil,
    }
end

local play = function(name)
    if active.animation == name then return end
    active.animation = name
    Animation.CrossFade(name)
end

local rescan = function(ctx)
    if ctx.now - active.scannedAt < settings.scanInterval then return true end
    active.scannedAt = ctx.now
    local surface = Surface.Width(ctx, active.forward, settings.exitWidth)
    report(not surface.wide, surface.wide and reasons.BALANCE_END_WIDE or reasons.OK, surface)
    if surface.wide or not surface.valid then return false end
    active.surface = surface
    return true
end

Balance.CanExit = function(now)
    return active ~= nil and Cooldown.CanExit(Balance.name, now - active.enteredAt)
end

Balance.JumpResult = function(ctx, scan)
    if not active then return nil end
    local ok, _, payload = Precision.Evaluate(ctx, scan, { direction = active.forward, animation = settings.animation.jump })
    if ok then return { next = S.PRECISION, payload = payload } end
    return {
        next = S.PRECISION,
        payload = {
            velocity = active.forward * settings.jumpForward + Vec.Up * settings.jumpUp,
            heading = Vec.Heading(active.forward),
            animation = settings.animation.jump,
        },
    }
end

Balance.Update = function(ctx)
    if ctx.airborne and ctx.groundClearance > Config.Slide.airborneCancel then
        return { next = S.FALLING, velocity = ctx.velocity, reason = reasons.BALANCE_END_FELL }
    end
    if not rescan(ctx) then return { velocity = Vec.Flat(ctx.velocity), motion = true, reason = reasons.BALANCE_END_WIDE } end

    local along = ctx.inputDir and Vec.Dot(ctx.inputDir, active.forward) or 0.0
    if along < -input.deadzone then
        active.forward = Vec.Negate(active.forward)
        along = -along
    end
    local speed = 0.0
    if along > input.deadzone then speed = ctx.sprintHeld and settings.runSpeed or settings.walkSpeed end

    local surface = active.surface
    local correction = surface.lateral * (surface.center * settings.centerGain)
    local velocity = active.forward * speed + correction
    SetEntityVelocity(ctx.ped, velocity.x, velocity.y, ctx.velocity.z)
    active.heading = Movement.TurnHeading(active.heading, Vec.Heading(active.forward), settings.turnGain, ctx.dt)
    SetEntityHeading(ctx.ped, active.heading)
    play(speed > 0.0 and settings.animation.run or settings.animation.idle)
    return nil
end

Balance.Exit = function()
    active = nil
end

Balance.Reset = function()
    active = nil
end

return Balance
