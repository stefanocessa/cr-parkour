local Vec = require 'client.core.vec'
local State = require 'client.core.state'
local Context = require 'client.core.context'
local Movement = require 'client.core.movement'
local Cooldown = require 'client.core.cooldowns'
local Landing = require 'client.detection.landing'
local Momentum = require 'client.systems.momentum'
local Animation = require 'client.systems.animation'
local Camera = require 'client.systems.camera'
local Collision = require 'client.systems.collision'
local Damage = require 'client.systems.damage'
local DebugState = require 'client.debug.state'

local Roll = { name = 'roll', states = { Constants.States.ROLLING } }

local settings = Config.Roll
local fall = Config.Fall
local reasons = Constants.Reasons
local S = Constants.States
local armed = nil
local recentLanding = nil
local active = nil

Roll.InWindow = function(ctx)
    if not settings.enabled or not ctx.airborne or ctx.velocity.z >= 0.0 then return false end
    local timeToImpact = Landing.TimeToImpact(ctx, settings.predictDistance)
    return timeToImpact ~= nil and timeToImpact <= settings.windowMs
end

Roll.Approaching = function(ctx, lead)
    if not settings.enabled or not ctx.airborne or ctx.velocity.z >= 0.0 then return false end
    local timeToImpact = Landing.TimeToImpact(ctx, settings.predictDistance)
    return timeToImpact ~= nil and timeToImpact <= settings.windowMs + lead
end

Roll.HasLateWindow = function(ctx)
    return recentLanding ~= nil and ctx.now - recentLanding.at <= settings.lateGraceMs
end

Roll.Arm = function(ctx)
    if not settings.enabled then return false, reasons.ROLL_DENIED_DISABLED end
    if ctx.velocity.z >= 0.0 then return false, reasons.ROLL_DENIED_NOT_FALLING end
    if not Roll.InWindow(ctx) then return false, reasons.ROLL_DENIED_TOO_EARLY end
    armed = ctx.now
    Collision.Protect(ctx.ped, true)
    return true, reasons.ROLL_ARMED
end

Roll.IsArmed = function(ctx)
    return armed ~= nil and ctx.now - armed <= settings.windowMs + settings.lateGraceMs
end

Roll.Disarm = function()
    armed = nil
end

Roll.Classify = function(distance)
    if distance >= fall.veryLarge then return 'veryLarge' end
    if distance >= fall.large then return 'large' end
    if distance >= fall.medium then return 'medium' end
    return 'small'
end

local landingDirection = function(ctx)
    return Vec.Normalize2d(Context.AirVelocity()) or ctx.moveDir
end

Roll.Evaluate = function(ctx, distance)
    if not settings.enabled then return false, reasons.ROLL_DENIED_DISABLED end
    if not State.CanTransition(S.ROLLING) then return false, reasons.ROLL_DENIED_NOT_FALLING end
    if not Cooldown.CanUse(Roll.name, ctx.now) then return false, reasons.ROLL_DENIED_COOLDOWN end
    if distance < settings.minFall then return false, reasons.ROLL_DENIED_FALL_TOO_SHORT end
    if distance > settings.maxFall then return false, reasons.ROLL_DENIED_FALL_TOO_HIGH end
    if not Roll.IsArmed(ctx) then return false, reasons.ROLL_DENIED_TOO_EARLY end
    if Collision.BodyBlocked(ctx.coords, landingDirection(ctx), settings.frontClearance, settings.frontHeights) then
        return false, reasons.ROLL_DENIED_FRONT_BLOCKED
    end
    return true, reasons.OK, { distance = distance, category = Roll.Classify(distance) }
end

local impact = function(ctx, distance, rolled)
    TriggerEvent('cr-parkour:fallImpact', distance, rolled)
    if fall.serverHook then TriggerServerEvent('cr-parkour:server:fallImpact', distance, rolled) end
    if not rolled then Collision.Protect(ctx.ped, false) end
    Damage.Emit('largeFall', { distance = distance, rolled = rolled, reduction = rolled and settings.largeFallReduction or 1.0 })
end

local hardLanding = function(ctx, shake, distance)
    local velocity = Vec.Flat(ctx.velocity) * fall.hardLandingKeep
    SetEntityVelocity(ctx.ped, velocity.x, velocity.y, ctx.velocity.z)
    Animation.Play('land.hard')
    Camera.Shake(shake)
    Damage.Emit('hardLanding', { distance = distance, heavy = shake == 'heavyLanding' })
end

Roll.Land = function(ctx)
    local distance = ctx.landedFall or 0.0
    local category = Roll.Classify(distance)
    local wasArmed = Roll.IsArmed(ctx)
    local canRoll, reason, payload = Roll.Evaluate(ctx, distance)
    Roll.Disarm()
    recentLanding = reason == reasons.ROLL_DENIED_TOO_EARLY and { at = ctx.now, distance = distance } or nil

    if canRoll then
        if category == 'veryLarge' then impact(ctx, distance, true) end
        return true, reason, payload, category
    end

    if wasArmed and category ~= 'small' then
        Damage.Emit('failedRoll', { distance = distance, reason = reason })
    end
    if category == 'veryLarge' then
        impact(ctx, distance, false)
    elseif category == 'large' then
        hardLanding(ctx, 'heavyLanding', distance)
    elseif category == 'medium' then
        hardLanding(ctx, 'hardLanding', distance)
    end
    return false, reason, nil, category
end

Roll.EvaluateLate = function(ctx)
    if not recentLanding then return nil end
    local landing = recentLanding
    recentLanding = nil
    if ctx.now - landing.at > settings.lateGraceMs then return false, reasons.ROLL_DENIED_TOO_EARLY end
    armed = ctx.now
    return Roll.Evaluate(ctx, landing.distance)
end

local pickVariant = function(ctx, direction)
    local lateral = ctx.input.active and ctx.input.side or Vec.Dot(direction, ctx.camRight)
    if lateral >= settings.sideThreshold then return settings.animations.right end
    if lateral <= -settings.sideThreshold then return settings.animations.left end
    return settings.animations.forward
end

Roll.Enter = function(ctx, payload)
    Roll.Disarm()
    local entry = Momentum.Capture(ctx, Context.AirVelocity())
    local direction = entry.direction or ctx.forward
    local animation = pickVariant(ctx, direction)
    local duration = Animation.SyncedDuration(animation, settings.duration)
    local keep = payload.category == 'veryLarge' and settings.veryLargeKeep or settings.momentumKeep
    active = {
        direction = direction,
        heading = ctx.heading,
        targetHeading = Vec.Heading(direction),
        speed = math.max(entry.speed2d * keep, settings.minSpeed),
        startedAt = ctx.now,
        duration = duration,
        distance = payload.distance,
    }
    Animation.Play(animation, { duration = duration })
    Camera.Shake(payload.category == 'veryLarge' and 'heavyLanding' or 'roll')
end

Roll.Update = function(ctx)
    active.speed = math.max(0.0, active.speed - settings.deceleration * ctx.dt)
    local dir = active.direction
    if active.speed > 0.0 and Collision.BodyBlocked(ctx.coords, dir, active.speed * ctx.dt, settings.frontHeights) then
        active.speed = 0.0
        DebugState.SetReason('roll', reasons.ROLL_END_BLOCKED)
    end
    local exit = { velocity = dir * active.speed, motion = true }
    if ctx.now - active.startedAt >= active.duration then return exit end
    if ctx.input.active and Animation.Reached('control') then return exit end
    Momentum.Drive(ctx.ped, ctx.velocity, Vec.WithZ(dir * active.speed, ctx.velocity.z), Animation.Assist())
    active.heading = Movement.TurnHeading(active.heading, active.targetHeading, settings.turnGain, ctx.dt)
    SetEntityHeading(ctx.ped, active.heading)
    return nil
end

Roll.Exit = function()
    active = nil
end

Roll.Reset = function()
    armed = nil
    recentLanding = nil
    active = nil
end

return Roll
