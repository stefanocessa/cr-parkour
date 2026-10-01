local Vec = require 'client.core.vec'
local State = require 'client.core.state'
local Combo = require 'client.core.combo'
local Cooldown = require 'client.core.cooldowns'
local Raycast = require 'client.detection.raycast'
local Landing = require 'client.detection.landing'
local Trajectory = require 'client.detection.trajectory'
local Launch = require 'client.systems.launch'
local Momentum = require 'client.systems.momentum'
local Collision = require 'client.systems.collision'
local Rays = require 'client.debug.rays'
local DebugState = require 'client.debug.state'

local Precision = { name = 'precision', states = { Constants.States.PRECISION } }

local settings = Config.Precision
local reasons = Constants.Reasons
local S = Constants.States
local active = nil

local groundAt = function(point, feetZ)
    local result = Raycast.Cast(Vec.WithZ(point, feetZ + settings.maxRise + settings.probeAbove), Vec.WithZ(point, feetZ - settings.maxDrop))
    if not Raycast.IsFloor(result) then return nil end
    return result
end

local sameLevel = function(point, z, feetZ)
    local result = groundAt(point, feetZ)
    return result ~= nil and math.abs(result.coords.z - z) <= settings.heightTolerance
end

local findTarget = function(ctx, dir)
    local sawGap = false
    local distance = settings.step
    while distance <= settings.maxDistance do
        local ground = groundAt(ctx.coords + dir * distance, ctx.feetZ)
        if not ground or ground.coords.z < ctx.feetZ - settings.gapDepth then
            sawGap = true
        elseif sawGap and distance >= settings.minDistance then
            return ground, distance
        end
        distance = distance + settings.step
    end
    return nil, sawGap and reasons.PRECISION_DENIED_NO_TARGET or reasons.PRECISION_DENIED_NO_GAP
end

local measureWidth = function(point, z, lateral, feetZ)
    local width = 0.0
    for _, sign in ipairs({ -1.0, 1.0 }) do
        local offset = settings.widthStep
        while offset <= settings.widthProbe and sameLevel(point + lateral * (offset * sign), z, feetZ) do
            offset = offset + settings.widthStep
        end
        width = width + offset - settings.widthStep
    end
    return width
end

local classify = function(distance)
    for i = 1, #settings.classes do
        if distance <= settings.classes[i].maxDistance then return settings.classes[i] end
    end
    return settings.classes[#settings.classes]
end

local deny = function(reason, info)
    DebugState.Candidate('precision', false, reason, info)
    return false, reason
end

Precision.Evaluate = function(ctx, scan, options)
    if not settings.enabled then return false, reasons.PRECISION_DENIED_DISABLED end
    if not State.CanTransition(S.PRECISION) then return false, reasons.PRECISION_DENIED_STATE end
    if not Cooldown.CanUse(Precision.name, ctx.now) then return false, reasons.PRECISION_DENIED_COOLDOWN end
    if not ctx.grounded and not ctx.coyote then return false, reasons.PRECISION_DENIED_STATE end

    local dir = options and options.direction or ctx.approachDir
    local edge, found = findTarget(ctx, dir)
    if not edge then return deny(found) end

    local target = edge.coords + dir * settings.landingInset
    local landing = groundAt(target, ctx.feetZ)
    if not landing or math.abs(landing.coords.z - edge.coords.z) > settings.heightTolerance then return deny(reasons.PRECISION_DENIED_BAD_LANDING) end
    target = landing.coords
    Rays.Point(target, 'landing')

    local info = {
        target = target,
        distance = Vec.Distance2d(ctx.coords, target),
        heightDelta = target.z - ctx.feetZ,
    }
    if info.heightDelta > settings.maxRise then return deny(reasons.PRECISION_DENIED_TOO_HIGH, info) end
    if not sameLevel(target + dir * settings.minLandingDepth, target.z, ctx.feetZ) then return deny(reasons.PRECISION_DENIED_BAD_LANDING, info) end
    info.landingWidth = measureWidth(target, target.z, Vec.Right(dir), ctx.feetZ)
    info.landingNormal = landing.normal
    if info.landingWidth < settings.minLandingWidth then return deny(reasons.PRECISION_DENIED_NARROW_LANDING, info) end
    local _, clear = Landing.Clearance(target)
    if not clear then return deny(reasons.PRECISION_DENIED_BAD_LANDING, info) end

    local ballistic = Trajectory.Ballistic(info.distance, info.heightDelta, settings.arcHeight)
    info.requiredSpeed = ballistic.horizontal
    if Collision.HeadRoom(ctx.coords, settings.arcHeight).hit then return deny(reasons.PRECISION_DENIED_HEAD_BLOCKED, info) end

    local available = math.max(ctx.speed2d, settings.standingSpeed) * settings.speedFactor
    available = math.min(available / Combo.MinSpeed('precision', 1.0, ctx.now), settings.maxHorizontalSpeed)
    info.availableSpeed = available
    if ballistic.horizontal > available then return deny(reasons.PRECISION_DENIED_TOO_FAR, info) end
    if ballistic.vertical > settings.maxVerticalSpeed then return deny(reasons.PRECISION_DENIED_TOO_HIGH, info) end

    local flat = Vec.Normalize2d(target - ctx.coords) or dir
    local velocity = flat * ballistic.horizontal + Vec.Up * ballistic.vertical
    local path = Trajectory.Predict(ctx.coords, velocity, ballistic.time + settings.step)
    if not path.hit or not path.floor or #(path.point - target) > settings.pathTolerance then
        return deny(reasons.PRECISION_DENIED_PATH_BLOCKED, info)
    end

    local class = classify(info.distance)
    info.class = class.name
    info.landingValid = true
    DebugState.Candidate('precision', true, reasons.OK, info)
    return true, reasons.OK, {
        velocity = velocity,
        time = ballistic.time,
        heading = Vec.Heading(flat),
        animation = options and options.animation or class.animation,
        info = info,
    }
end

Precision.Enter = function(ctx, payload)
    Momentum.Capture(ctx)
    active = Launch.Start(ctx, payload.velocity, {
        animation = payload.animation,
        heading = payload.heading,
        impulseMs = settings.minDuration,
        guideMs = payload.time and payload.time * 1000.0 or 0,
        minDuration = settings.minDuration,
        turnGain = settings.turnGain,
    })
end

Precision.Update = function(ctx)
    return Launch.Update(ctx, active)
end

Precision.Exit = function()
    active = nil
end

return Precision
