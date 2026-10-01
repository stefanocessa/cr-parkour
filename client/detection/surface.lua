local Vec = require 'client.core.vec'
local Raycast = require 'client.detection.raycast'

local Surface = {}

local settings = Config.Balance

local sample = function(point, groundZ)
    local result = Raycast.Down(Vec.WithZ(point, groundZ + settings.probeAbove), settings.probeAbove + settings.minDrop)
    if not Raycast.IsFloor(result) then return false, true end
    local drop = groundZ - result.coords.z
    if drop > settings.heightTolerance then return false, false end
    return true, false
end

local edge = function(origin, groundZ, dir)
    local distance = settings.probeStep
    while distance <= settings.probeRange do
        local solid, elevated = sample(origin + dir * distance, groundZ)
        if not solid then return distance, elevated end
        distance = distance + settings.probeStep
    end
    return settings.probeRange, false
end

Surface.Width = function(origin, forward, limit)
    local groundZ = origin.feetZ
    local lateral = Vec.Right(forward)
    local coords = origin.coords
    local half = limit * 0.5 + settings.probeStep
    local leftSolid = sample(coords - lateral * half, groundZ)
    local rightSolid = sample(coords + lateral * half, groundZ)
    if leftSolid or rightSolid then
        return { valid = false, wide = true, width = limit, lateral = lateral }
    end

    local left, leftElevated = edge(coords, groundZ, Vec.Negate(lateral))
    local right, rightElevated = edge(coords, groundZ, lateral)
    local ahead = sample(coords + forward * settings.minForward, groundZ)
    return {
        valid = true,
        wide = left + right > limit,
        width = left + right,
        left = left,
        right = right,
        elevated = leftElevated and rightElevated,
        continues = ahead,
        lateral = lateral,
        center = (right - left) * 0.5,
    }
end

return Surface
