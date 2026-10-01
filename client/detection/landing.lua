local Vec = require 'client.core.vec'
local Raycast = require 'client.detection.raycast'
local Rays = require 'client.debug.rays'

local Landing = {}

local settings = Config.Landing
local gravity = Config.Physics.gravity

Landing.FindGround = function(point, fromZ, toZ)
    local result = Raycast.Cast(Vec.WithZ(point, fromZ), Vec.WithZ(point, toZ))
    if not Raycast.IsFloor(result) then return nil end
    Rays.Point(result.coords, 'landing')
    return result
end

Landing.Clearance = function(point, height)
    local result = Raycast.Up(point + Vec.Up * Constants.SurfaceOffset, height or settings.clearanceHeight)
    return result.hit and result.distance or (height or settings.clearanceHeight), not result.hit
end

Landing.PathClear = function(from, to)
    return not Raycast.Cast(from, to).hit
end

Landing.Validate = function(point, topZ, dropLimit)
    local ground = Landing.FindGround(point, topZ + settings.probeAbove, topZ - dropLimit)
    if not ground then return nil end
    local clearance, clear = Landing.Clearance(ground.coords)
    return {
        point = ground.coords,
        normal = ground.normal,
        clearance = clearance,
        clear = clear,
    }
end

Landing.TimeToImpact = function(ctx, maxDistance)
    local result = Raycast.Down(ctx.coords, maxDistance)
    if not result.hit then return nil, nil end
    local height = math.max(0.0, ctx.feetZ - result.coords.z)
    local descent = -ctx.velocity.z
    local time = (-descent + math.sqrt(descent * descent + 2.0 * gravity * height)) / gravity
    return time * 1000.0, result.coords.z
end

return Landing
