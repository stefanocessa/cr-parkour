local Obstacle = require 'client.detection.obstacle'
local Wall = require 'client.detection.wall'
local Ledge = require 'client.detection.ledge'
local Surface = require 'client.detection.surface'
local Traversal = require 'client.detection.traversal'
local Raycast = require 'client.detection.raycast'
local State = require 'client.core.state'
local Profiler = require 'client.debug.profiler'

local Scanner = {}

local settings = Config.Scan
local detection = Config.Detection
local fanDistance = Config.Obstacle.scanDistance
local sides = Constants.Sides
local reasons = Constants.Reasons
local last = { walls = {}, at = 0, interval = settings.idleInterval }

local needsFrontWall = function(obstacle)
    if not obstacle.hit or obstacle.tall or obstacle.topReason ~= nil or not obstacle.height then return true end
    return obstacle.height >= Config.Wallclimb.minHeight - detection.heightTolerance
end

local groundOrigin = function(ctx)
    if not ctx.grounded then return ctx end
    local groundZ, found = Obstacle.GroundZ(ctx)
    if not found then return ctx end
    return setmetatable({ feetZ = groundZ, groundZ = groundZ }, { __index = ctx })
end

local flush = function()
    Obstacle.Flush()
    Raycast.Flush()
end

State.OnChange(function(current, previous)
    if State.IsLocomotion(current) and State.IsLocomotion(previous) then return end
    flush()
end)

Scanner.Interval = function(ctx)
    if State.IsAbility() then return settings.activeInterval end
    if ctx.airborne then return settings.airInterval end
    if ctx.sprinting then return settings.sprintInterval end
    if ctx.speed2d >= settings.runSpeed then return settings.runInterval end
    if ctx.speed2d > settings.idleSpeed then return settings.moveInterval end
    return settings.idleInterval
end

Scanner.Due = function(ctx)
    local interval = Scanner.Interval(ctx)
    last.interval = interval
    return ctx.now - last.at >= interval
end

Scanner.Run = function(ctx)
    local dir = ctx.approachDir
    Obstacle.SetCaching(ctx.grounded and State.IsLocomotion())
    local origin = groundOrigin(ctx)
    local result = { at = ctx.now, interval = last.interval, walls = {}, origin = origin, groundZ = origin.feetZ, dir = dir, stage = 1 }

    local bodyStarted = Profiler.Start()
    local fan
    fan, result.layers = Traversal.Layers(origin, dir)
    Profiler.Stop('body', bodyStarted)

    if Traversal.AnyHit(result.layers) then
        result.stage = 2
        result.obstacle = Obstacle.Scan(origin, dir, fan, { contact = Traversal.HasContact(result.layers) })
        if result.obstacle.topZ then result.stage = 3 end
    else
        result.obstacle = { hit = false, reason = reasons.NO_OBSTACLE }
    end

    if ctx.airborne or ctx.speed2d >= settings.sideScanSpeed then
        result.walls.left, result.walls.right = Wall.ScanSides(origin, ctx.moveDir)
    end

    if ctx.airborne or needsFrontWall(result.obstacle) then
        result.walls.front = Wall.Scan(origin, sides.front, dir, nil, fan, fanDistance)
    end

    local balance = Config.Balance
    if balance.enabled and ctx.grounded and State.IsLocomotion() and ctx.speed2d <= balance.maxEntrySpeed then
        result.surfaceDir = ctx.speed2d > settings.idleSpeed and ctx.moveDir or ctx.forward
        result.surface = Surface.Width(origin, result.surfaceDir, balance.maxWidth)
    end

    if ctx.airborne then
        result.ledge = Ledge.Find(origin, dir, nil, nil, fan, fanDistance)
    end

    result.profile = Traversal.Build(ctx, result)
    if result.profile.byType.UNDER and result.profile.byType.UNDER.samples or (result.walls.front and result.walls.front.valid) then
        result.stage = 4
    end
    last = result
    return result
end

Scanner.Last = function()
    return last
end

Scanner.Invalidate = function()
    last = { walls = {}, at = 0, interval = settings.idleInterval }
    flush()
end

return Scanner
