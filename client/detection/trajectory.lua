local Vec = require 'client.core.vec'
local Raycast = require 'client.detection.raycast'
local Landing = require 'client.detection.landing'
local Rays = require 'client.debug.rays'

local Trajectory = {}

local settings = Config.Trajectory
local gravity = Config.Physics.gravity
local body = Config.Body

Trajectory.Position = function(origin, velocity, t)
    return origin + velocity * t - Vec.Up * (0.5 * gravity * t * t)
end

Trajectory.Velocity = function(velocity, t)
    return velocity - Vec.Up * (gravity * t)
end

Trajectory.Predict = function(root, velocity, maxTime)
    local limit = maxTime or settings.maxTime
    local feetOffset = Vec.Up * (body.rootHeight - settings.feetProbe)
    local headOffset = Vec.Up * (body.headHeight - body.rootHeight)
    local previousFeet, previousHead = root - feetOffset, root + headOffset
    local t = 0.0
    while t < limit do
        t = t + settings.step
        local position = Trajectory.Position(root, velocity, t)
        local feet, head = position - feetOffset, position + headOffset
        local hit = Raycast.Cast(previousFeet, feet)
        if not hit.hit then hit = Raycast.Cast(previousHead, head) end
        if hit.hit then
            Rays.Point(hit.coords, Raycast.IsFloor(hit) and 'landing' or 'blocked')
            return {
                hit = true,
                point = hit.coords,
                normal = hit.normal,
                time = t,
                floor = Raycast.IsFloor(hit),
                wall = Raycast.IsWall(hit),
            }
        end
        previousFeet, previousHead = feet, head
    end
    return { hit = false, point = previousFeet, time = limit, floor = false, wall = false }
end

Trajectory.Ballistic = function(horizontalDistance, heightDelta, arcHeight)
    local apex = math.max(heightDelta, 0.0) + arcHeight
    local vertical = math.sqrt(2.0 * gravity * apex)
    local fall = math.sqrt(2.0 * math.max(apex - heightDelta, 0.0) / gravity)
    local time = vertical / gravity + fall
    return { vertical = vertical, horizontal = horizontalDistance / time, time = time }
end

Trajectory.TimeToGround = function(ctx, maxDistance)
    return Landing.TimeToImpact(ctx, maxDistance)
end

return Trajectory
