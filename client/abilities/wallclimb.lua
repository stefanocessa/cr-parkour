local Vec = require 'client.core.vec'
local State = require 'client.core.state'
local Context = require 'client.core.context'
local Movement = require 'client.core.movement'
local Cooldown = require 'client.core.cooldowns'
local Raycast = require 'client.detection.raycast'
local Ledge = require 'client.detection.ledge'
local Momentum = require 'client.systems.momentum'
local Animation = require 'client.systems.animation'
local Collision = require 'client.systems.collision'

local Wallclimb = { name = 'wallclimb', states = { Constants.States.WALLCLIMBING } }

local settings = Config.Wallclimb
local detection = Config.Detection
local ledgeSettings = Config.Ledge
local body = Config.Body
local reasons = Constants.Reasons
local S = Constants.States
local active = nil
local lastLedge = nil

Wallclimb.Evaluate = function(ctx, scan)
    if not settings.enabled then return false, reasons.WALLCLIMB_DENIED_DISABLED end
    if not State.CanTransition(S.WALLCLIMBING) then return false, reasons.WALLCLIMB_DENIED_STATE end
    if not Cooldown.CanUse(Wallclimb.name, ctx.now) then return false, reasons.WALLCLIMB_DENIED_COOLDOWN end

    lastLedge = nil
    local wall = scan.walls.front
    if not wall or not wall.valid then return false, wall and wall.reason or reasons.WALLCLIMB_DENIED_NO_WALL end
    if ctx.speed2d < settings.minSpeed then return false, reasons.WALLCLIMB_DENIED_LOW_SPEED end
    if wall.distance > settings.maxDistance + detection.distanceTolerance then return false, reasons.WALLCLIMB_DENIED_TOO_FAR, nil, ('%.2f'):format(wall.distance) end
    if wall.angle > settings.maxApproachAngle + detection.angleTolerance then return false, reasons.WALLCLIMB_DENIED_BAD_ANGLE, nil, ('%.0f'):format(wall.angle) end
    if not Context.HasIntent(ctx, wall.wallDir, settings.intentSpeed, settings.intentDot) then return false, reasons.PARKOUR_DENIED_NO_INTENT end
    if Cooldown.SameTarget(Wallclimb.name, wall.point, wall.normal, ctx.now) then return false, reasons.SAME_OBSTACLE_BLOCKED end
    if Collision.HeadRoom(ctx.coords, settings.headClearance).hit then return false, reasons.WALLCLIMB_DENIED_HEAD_BLOCKED end

    local ledge = scan.profile and scan.profile.frontLedge or Ledge.Find(scan.origin or ctx, wall.wallDir, settings.minHeight, settings.maxHeight)
    lastLedge = ledge
    if not ledge.valid then return false, reasons.WALLCLIMB_DENIED_NO_LEDGE, nil, ledge.reason end
    if ctx.speed2d < settings.runSpeed and ledge.height > settings.slowMaxHeight + detection.heightTolerance then
        return false, reasons.WALLCLIMB_DENIED_TOO_HIGH, nil, ('slow %.2f'):format(ledge.height)
    end
    local weights = Config.Resolver.weights.wallclimb
    local ideal = (settings.minHeight + settings.slowMaxHeight) * 0.5
    local score = weights.base + weights.height * Vec.Clamp(1.0 - math.abs(ledge.height - ideal) / settings.maxHeight, 0.0, 1.0)
        + weights.angle * Vec.Clamp(1.0 - wall.angle / settings.maxApproachAngle, 0.0, 1.0)
    return true, reasons.OK, { wall = wall, ledge = ledge, score = score }
end

Wallclimb.LastLedge = function()
    return lastLedge
end

Wallclimb.Score = function(payload)
    return payload.score
end

Wallclimb.Verify = function(ctx, payload)
    local wall = payload.wall
    if not ctx.grounded or Cooldown.SameTarget(Wallclimb.name, wall.point, wall.normal, ctx.now) then return false end
    local distance = Vec.Distance2d(ctx.coords, wall.point)
    if distance > settings.maxDistance + detection.distanceTolerance + detection.persistDistance then return false end
    local probe = Raycast.Direction(Raycast.AtHeight(ctx, 'chest'), wall.wallDir, distance + detection.persistDistance)
    if not Raycast.IsWall(probe) then return false end
    local normal = Vec.Normalize2d(probe.normal)
    return normal ~= nil and Vec.Dot(normal, wall.normal) >= detection.persistDot
end

Wallclimb.Enter = function(ctx, payload)
    local entry = Momentum.Capture(ctx)
    Cooldown.Remember(Wallclimb.name, payload.wall.point, payload.wall.normal, ctx.now)
    Movement.Hold(ctx.ped)
    Collision.BeginTraversal(ctx.ped, 'LEDGE', settings.maxDuration)
    active = {
        wall = payload.wall,
        ledge = payload.ledge,
        speed = settings.climbSpeed + entry.speed2d * settings.speedFromEntry,
        position = ctx.coords,
        startZ = ctx.coords.z,
        startedAt = ctx.now,
        heading = ctx.heading,
    }
    Animation.Play(settings.animation)
end

local pushOff = function(reason)
    return { next = S.FALLING, velocity = active.ledge.normal * settings.pushOffVelocity, reason = reason }
end

Wallclimb.Update = function(ctx)
    local ledge = active.ledge
    local handZ = active.position.z - body.rootHeight + body.handReach
    if ledge.topZ - handZ <= ledgeSettings.grabMaxOffset then
        return { next = S.LEDGE_GRAB, payload = ledge }
    end

    active.speed = active.speed - settings.deceleration * ctx.dt
    local risen = active.position.z - active.startZ
    if active.speed <= 0.0 or risen >= settings.maxRise or ctx.now - active.startedAt >= settings.maxDuration then
        return pushOff(reasons.WALLCLIMB_END_NO_LEDGE)
    end
    if Collision.HeadRoom(active.position, active.speed * ctx.dt + body.radius).hit then
        return pushOff(reasons.WALLCLIMB_END_HEAD_BLOCKED)
    end

    local anchor = ledge.edge + ledge.normal * settings.wallDistance
    local settled = Movement.Approach(active.position, Vec.WithZ(anchor, active.position.z), settings.settleGain, ctx.dt)
    active.position = settled + Vec.Up * (active.speed * ctx.dt)
    active.heading = Movement.TurnHeading(active.heading, ledge.heading, settings.turnGain, ctx.dt)
    Movement.Place(ctx.ped, Animation.Apply(active.position, active.heading))
    return nil
end

Wallclimb.JumpResult = function()
    if not Config.Walljump.fromWallclimb or not active then return nil end
    return { next = S.WALLJUMPING, payload = { normal = active.ledge.normal, side = 'back' } }
end

Wallclimb.CanExit = function(now)
    return active ~= nil and Cooldown.CanExit(Wallclimb.name, now - active.startedAt)
end

Wallclimb.Recover = function()
    if not active then return nil end
    return active.ledge.normal * settings.pushOffVelocity
end

Wallclimb.Exit = function()
    active = nil
    Collision.EndTraversal()
end

return Wallclimb
