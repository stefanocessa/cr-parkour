local Vec = require 'client.core.vec'
local State = require 'client.core.state'
local Context = require 'client.core.context'
local Movement = require 'client.core.movement'
local Cooldown = require 'client.core.cooldowns'
local Raycast = require 'client.detection.raycast'
local Wall = require 'client.detection.wall'
local Ledge = require 'client.detection.ledge'
local Momentum = require 'client.systems.momentum'
local Animation = require 'client.systems.animation'
local Collision = require 'client.systems.collision'
local Damage = require 'client.systems.damage'

local Wallrun = { name = 'wallrun', states = { Constants.States.WALLRUNNING } }

local settings = Config.Wallrun
local gravity = Config.Physics.gravity
local body = Config.Body
local reasons = Constants.Reasons
local S = Constants.States
local lastEnd, lastNormal = 0, nil
local active = nil

Wallrun.Evaluate = function(ctx, scan)
    if not settings.enabled then return false, reasons.WALLRUN_DENIED_DISABLED end
    if not State.CanTransition(S.WALLRUNNING) then return false, reasons.WALLRUN_DENIED_STATE end
    if not ctx.airborne and not settings.allowGroundStart then return false, reasons.WALLRUN_DENIED_NOT_AIRBORNE end
    if not Cooldown.CanUse(Wallrun.name, ctx.now) then return false, reasons.WALLRUN_DENIED_COOLDOWN end

    local left, right = scan.walls.left or {}, scan.walls.right or {}
    local wall = Wall.Nearest(left, right)
    if not wall then
        local reason = left.reason or right.reason
        if reason == reasons.WALL_AMBIGUOUS then return false, reasons.WALLRUN_DENIED_AMBIGUOUS end
        return false, reason or reasons.WALLRUN_DENIED_NO_WALL
    end
    if ctx.speed2d < settings.minSpeed then return false, reasons.WALLRUN_DENIED_LOW_SPEED end
    if wall.angle > settings.maxApproachAngle then return false, reasons.WALLRUN_DENIED_BAD_ANGLE end
    if ctx.airborne and ctx.groundClearance < settings.minGroundClearance then return false, reasons.WALLRUN_DENIED_TOO_LOW end
    if lastNormal and ctx.now - lastEnd < settings.sameWallCooldown and Vec.Dot(lastNormal, wall.normal) >= settings.sameWallDot then
        return false, reasons.WALLRUN_DENIED_SAME_WALL
    end
    if Raycast.Direction(Raycast.AtHeight(ctx, 'chest'), wall.tangent, settings.forwardClearance).hit then
        return false, reasons.WALLRUN_DENIED_NO_SPACE
    end
    local weights = Config.Resolver.weights.wallrun
    return true, reasons.OK, { wall = wall, score = weights.base + weights.angle * Vec.Clamp(1.0 - wall.angle / settings.maxApproachAngle, 0.0, 1.0) }
end

Wallrun.Score = function(payload)
    return payload.score
end

Wallrun.Enter = function(ctx, payload)
    local wall = payload.wall
    local entry = Momentum.Capture(ctx)
    local along = Momentum.ProjectOnDirection(entry, wall.tangent)
    Movement.Hold(ctx.ped)
    active = {
        side = wall.side,
        normal = wall.normal,
        tangent = wall.tangent,
        startTangent = wall.tangent,
        speed = math.max(along.speed2d * settings.speedKeep, settings.minSpeed),
        vertical = Vec.Clamp(math.max(ctx.velocity.z, settings.initialLift), settings.initialLift, settings.maxEntryLift),
        position = ctx.coords,
        heading = ctx.heading,
        startedAt = ctx.now,
        lostAt = nil,
        ledgeAt = 0,
        wallAt = 0,
        wallPoint = wall.point,
    }
    Animation.Play(settings.animation[wall.side])
end

local carried = function()
    return active.tangent * active.speed + Vec.Up * active.vertical
end

local finish = function(reason, nextState, velocity)
    return {
        reason = reason,
        next = nextState or S.FALLING,
        velocity = velocity or carried(),
    }
end

local keepDistance = function(ctx)
    local target = active.wallPoint + active.normal * settings.wallDistance
    local offset = Vec.Dot(Vec.Flat(target - active.position), active.normal)
    if math.abs(offset) <= settings.distanceTolerance then return end
    local step = offset * Vec.Clamp(settings.stickGain * ctx.dt, 0.0, 1.0)
    active.position = active.position + active.normal * step
end

local refreshWall = function(ctx, origin)
    if ctx.now - active.wallAt < settings.wallCheckInterval then return true end
    active.wallAt = ctx.now
    local wall = Wall.Scan(origin, active.side, active.tangent)
    if not wall.valid then
        active.lostAt = active.lostAt or ctx.now
        return ctx.now - active.lostAt <= settings.lostGraceMs
    end
    active.lostAt = nil
    active.normal = wall.normal
    active.wallPoint = wall.point
    local tangent = Vec.Normalize2d(Vec.ProjectOnPlane(active.tangent, wall.normal))
    if tangent then active.tangent = tangent end
    return true
end

local findLedge = function(ctx, origin)
    if ctx.now - active.ledgeAt < settings.ledgeScanInterval then return nil end
    active.ledgeAt = ctx.now
    local ahead = Ledge.Find(origin, active.tangent)
    if Ledge.CanGrab(origin, ahead, active.vertical) then return ahead end
    if ctx.inputDir and Vec.Dot(ctx.inputDir, Vec.Negate(active.normal)) >= settings.towardWallDot then
        local side = Ledge.Find(origin, Vec.Negate(active.normal))
        if Ledge.CanGrab(origin, side, active.vertical) then return side end
    end
    return nil
end

Wallrun.Update = function(ctx)
    if ctx.now - active.startedAt >= settings.maxDuration then return finish(reasons.WALLRUN_END_DURATION) end

    active.speed = active.speed - (settings.speedDecay + active.speed * settings.drag) * ctx.dt
    if active.speed < settings.endSpeed then return finish(reasons.WALLRUN_END_LOW_SPEED) end
    active.vertical = active.vertical - gravity * settings.gravityScale * ctx.dt

    local origin = Context.Origin(active.position)
    if not refreshWall(ctx, origin) then return finish(reasons.WALLRUN_END_WALL_LOST) end
    if Vec.Angle2d(active.tangent, active.startTangent) > settings.maxCurve then
        return finish(reasons.WALLRUN_END_BAD_ANGLE, S.FALLING, active.startTangent * active.speed + Vec.Up * active.vertical)
    end

    local ledge = findLedge(ctx, origin)
    if ledge then return { next = S.LEDGE_GRAB, payload = ledge } end

    local step = active.speed * ctx.dt
    if Collision.BodyBlocked(active.position, active.tangent, step) then
        Damage.Emit('collision', { ability = Wallrun.name, speed = active.speed })
        return finish(reasons.WALLRUN_END_BLOCKED, S.FALLING, active.normal * settings.blockedPush + Vec.Up * math.min(active.vertical, 0.0))
    end
    if active.vertical > 0.0 and Collision.HeadRoom(active.position, active.vertical * ctx.dt + body.radius).hit then
        active.vertical = 0.0
    end

    keepDistance(ctx)
    local nextPosition = active.position + active.tangent * step + Vec.Up * (active.vertical * ctx.dt)
    if active.vertical <= 0.0 and Collision.Ground(nextPosition, 0.0) then
        return { velocity = active.tangent * active.speed, motion = true, reason = reasons.WALLRUN_END_LANDED }
    end

    active.position = nextPosition
    active.heading = Movement.TurnHeading(active.heading, Vec.Heading(active.tangent), settings.turnGain, ctx.dt)
    local offset = settings.Offsets[active.side]
    local visual = offset and nextPosition + active.normal * offset.wallOffset or nextPosition
    Movement.Place(ctx.ped, Animation.Apply(visual, active.heading))
    return nil
end

Wallrun.Current = function()
    if not active then return nil end
    return { valid = true, normal = active.normal, wallDir = Vec.Negate(active.normal), distance = 0.0, angle = 0.0 }
end

Wallrun.CanExit = function(now)
    return active ~= nil and Cooldown.CanExit(Wallrun.name, now - active.startedAt)
end

Wallrun.JumpResult = function()
    if not Config.Walljump.enabled or not active then return nil end
    return {
        next = S.WALLJUMPING,
        payload = { normal = active.normal, tangent = active.tangent, speed = active.speed, side = active.side },
    }
end

Wallrun.Recover = function()
    if not active then return nil end
    return active.tangent * (active.speed * settings.speedKeep) + active.normal * settings.blockedPush
end

Wallrun.Exit = function()
    lastEnd = GetGameTimer()
    lastNormal = active and active.normal
    active = nil
end

return Wallrun
