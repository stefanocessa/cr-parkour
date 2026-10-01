local Vec = require 'client.core.vec'
local State = require 'client.core.state'
local Movement = require 'client.core.movement'
local Cooldown = require 'client.core.cooldowns'
local Raycast = require 'client.detection.raycast'
local Landing = require 'client.detection.landing'
local Trajectory = require 'client.detection.trajectory'
local Launch = require 'client.systems.launch'
local Momentum = require 'client.systems.momentum'
local Animation = require 'client.systems.animation'
local Collision = require 'client.systems.collision'
local Wallrun = require 'client.abilities.wallrun'
local DebugState = require 'client.debug.state'

local WallFlip = { name = 'wallflip', states = { Constants.States.WALLFLIP } }

local settings = Config.WallFlip
local reasons = Constants.Reasons
local S = Constants.States
local active = nil

local pickWall = function(ctx, scan)
    if State.Is(S.WALLRUNNING) then return Wallrun.Current(), true end
    return scan.walls.front, false
end

local backBlocked = function(ctx, normal)
    local results = Raycast.Fan(ctx, normal, settings.backClearance, settings.backHeights)
    local nearest = settings.backClearance
    local blocked = false
    for i = 1, #results do
        if results[i].hit then
            blocked = true
            nearest = math.min(nearest, results[i].distance)
        end
    end
    return blocked, nearest
end

local deny = function(reason, info)
    DebugState.Candidate('wallflip', false, reason, info)
    return false, reason
end

local curveAt = function(meta, phase)
    local curve = meta.curve
    local x = Vec.Clamp(phase, 0.0, 1.0) * (#curve - 1)
    local i = math.floor(x)
    if i >= #curve - 1 then return curve[#curve] end
    local f = x - i
    return curve[i + 1] * (1.0 - f) + curve[i + 2] * f
end

local phaseFor = function(meta, value)
    local low, high = 0.0, meta.contact
    if value <= curveAt(meta, low) then return low end
    if value >= curveAt(meta, high) then return high end
    for _ = 1, settings.phaseRefine do
        local mid = (low + high) * 0.5
        if curveAt(meta, mid) < value then low = mid else high = mid end
    end
    return (low + high) * 0.5
end

local planGround = function(ctx, wall, info)
    local meta = Animation.Meta(settings.animation)
    if not meta or not meta.curve then return nil, reasons.WALLFLIP_DENIED_NO_ANIMATION end
    local reach = curveAt(meta, meta.contact)
    local travel = Vec.Clamp(wall.distance - settings.wallGap, 0.0, reach - curveAt(meta, 0.0))
    local startPhase = phaseFor(meta, reach - travel)
    local start = Vec.WithZ(ctx.coords, ctx.coords.z)
    local landingXY = start + wall.wallDir * (curveAt(meta, meta.settle) - curveAt(meta, startPhase))
    local ground = Landing.FindGround(landingXY, ctx.feetZ + settings.landingTolerance, ctx.feetZ - settings.landingTolerance)
    info.startPhase, info.travel = startPhase, travel
    if not ground then return nil, reasons.WALLFLIP_DENIED_BAD_LANDING end
    local _, clear = Landing.Clearance(ground.coords)
    if not clear then return nil, reasons.WALLFLIP_DENIED_LOW_CLEARANCE end
    return {
        kinematic = true,
        meta = meta,
        startPhase = startPhase,
        start = start,
        wallDir = wall.wallDir,
        heading = Vec.Heading(wall.wallDir),
        rise = ground.coords.z - ctx.feetZ,
        duration = (meta.settle - startPhase) * meta.duration * 1000.0,
    }
end

WallFlip.Evaluate = function(ctx, scan)
    if not settings.enabled then return false, reasons.WALLFLIP_DENIED_DISABLED end
    if not State.CanTransition(S.WALLFLIP) then return false, reasons.WALLFLIP_DENIED_STATE end
    if not Cooldown.CanUse(WallFlip.name, ctx.now) then return false, reasons.WALLFLIP_DENIED_COOLDOWN end
    if not Animation.Resolve(settings.animation) then return false, reasons.WALLFLIP_DENIED_NO_ANIMATION end

    local wall, fromWallrun = pickWall(ctx, scan)
    if not wall or not wall.valid then return deny(wall and wall.reason or reasons.WALLFLIP_DENIED_NO_WALL) end
    local info = { wallDistance = wall.distance, wallAngle = wall.angle }
    if not fromWallrun then
        if wall.distance > settings.maxDistance then return deny(reasons.WALLFLIP_DENIED_TOO_FAR, info) end
        if wall.angle > settings.maxApproachAngle then return deny(reasons.WALLFLIP_DENIED_BAD_ANGLE, info) end
        if ctx.grounded and ctx.speed2d < settings.minSpeed then return deny(reasons.WALLFLIP_DENIED_LOW_SPEED, info) end
        local top = Raycast.Direction(Vec.WithZ(ctx.coords, ctx.feetZ + settings.minWallHeight), wall.wallDir, settings.maxDistance + Config.Body.radius)
        if not Raycast.IsWall(top) then return deny(reasons.WALLFLIP_DENIED_WALL_TOO_LOW, info) end
    end

    if Collision.HeadRoom(ctx.coords, settings.headClearance).hit then return deny(reasons.WALLFLIP_DENIED_LOW_CLEARANCE, info) end
    local blocked, clearance = backBlocked(ctx, wall.normal)
    info.backClearance = clearance
    if blocked then return deny(reasons.WALLFLIP_DENIED_BACK_BLOCKED, info) end

    if not fromWallrun and ctx.grounded then
        local plan, reason = planGround(ctx, wall, info)
        if not plan then return deny(reason, info) end
        DebugState.Candidate('wallflip', true, reasons.OK, info)
        return true, reasons.OK, plan
    end

    local velocity = wall.normal * settings.backSpeed + Vec.Up * settings.upVelocity
    local landing = Trajectory.Predict(ctx.coords, velocity)
    if not landing.hit or not landing.floor or landing.time < settings.minLandingTime
        or ctx.feetZ - landing.point.z > settings.maxDrop then
        return deny(reasons.WALLFLIP_DENIED_BAD_LANDING, info)
    end
    local _, clear = Landing.Clearance(landing.point)
    if not clear then return deny(reasons.WALLFLIP_DENIED_LOW_CLEARANCE, info) end

    DebugState.Candidate('wallflip', true, reasons.OK, info)
    return true, reasons.OK, { velocity = velocity, heading = Vec.Heading(wall.wallDir), landing = landing }
end

local enterGround = function(ctx, plan)
    Movement.Hold(ctx.ped)
    active = { kinematic = true, plan = plan, startedAt = ctx.now }
    Animation.Play(settings.animation, { duration = plan.duration, startPhase = plan.startPhase, restart = true })
    Movement.Place(ctx.ped, Animation.Apply(plan.start, plan.heading))
end

WallFlip.Enter = function(ctx, payload)
    Momentum.Capture(ctx)
    if payload.kinematic then return enterGround(ctx, payload) end
    active = Launch.Start(ctx, payload.velocity, {
        animation = settings.animation,
        heading = payload.heading,
        impulseMs = settings.impulseMs,
        minDuration = settings.impulseMs,
        endEvent = settings.endEvent,
        maxDuration = settings.maxDuration,
        turnGain = settings.turnGain,
    })
end

local updateGround = function(ctx)
    local plan = active.plan
    local meta = plan.meta
    local phase = plan.startPhase + (ctx.now - active.startedAt) / (meta.duration * 1000.0)
    local offset = curveAt(meta, phase) - curveAt(meta, plan.startPhase)
    local blend = Vec.Clamp((phase - meta.contact) / (meta.land - meta.contact), 0.0, 1.0)
    local position = plan.start + plan.wallDir * offset + Vec.Up * (plan.rise * blend)
    Movement.Place(ctx.ped, Animation.Apply(position, plan.heading))
    if phase < meta.settle then return nil end
    return { velocity = Vec.Zero, motion = true }
end

WallFlip.Update = function(ctx)
    if active.kinematic then return updateGround(ctx) end
    return Launch.Update(ctx, active)
end

WallFlip.IsKinematic = function()
    return active ~= nil and active.kinematic == true
end

WallFlip.Exit = function()
    active = nil
end

return WallFlip
