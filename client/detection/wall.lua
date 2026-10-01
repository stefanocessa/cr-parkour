local Vec = require 'client.core.vec'
local Raycast = require 'client.detection.raycast'

local Wall = {}

local settings = Config.Wall
local sides = Constants.Sides

local directionFor = function(side, forward)
    if side == sides.right then return Vec.Right(forward) end
    if side == sides.left then return Vec.Negate(Vec.Right(forward)) end
    return forward
end

local distanceFor = function(side)
    return side == sides.front and settings.frontDistance or settings.sideDistance
end

Wall.Scan = function(origin, side, forward, distance, fan, fanDistance)
    local dir = directionFor(side, forward)
    local reach = distance or distanceFor(side)
    local results
    if Raycast.Covers(fan, settings.heights, reach, fanDistance or 0.0) then
        results = Raycast.Clip(fan, settings.heights, reach)
    else
        results = Raycast.FanUntil(origin, dir, reach, settings.heights, settings.minHits, Raycast.IsWall)
    end
    local count, normalSum, pointSum, nearest, rejected = 0, Vec.Zero, Vec.Zero, nil, nil
    local normals = {}

    for i = 1, #results do
        local result = results[i]
        if Raycast.IsWall(result) then
            count = count + 1
            local flatNormal = Vec.Flat(result.normal)
            normals[#normals + 1] = flatNormal
            normalSum = normalSum + flatNormal
            pointSum = pointSum + result.coords
            local flat = Vec.Distance2d(origin.coords, result.coords)
            if not nearest or flat < nearest then nearest = flat end
        elseif result.hit then
            rejected = rejected or result.rejected
        end
    end

    if count < settings.minHits then return { valid = false, side = side, hits = count, reason = rejected } end

    local normal = Vec.Normalize2d(normalSum)
    if not normal then return { valid = false, side = side, hits = count } end
    for i = 1, #normals do
        if Vec.Angle2d(normals[i], normal) > settings.maxNormalSpread then
            return { valid = false, side = side, hits = count, reason = Constants.Reasons.WALL_AMBIGUOUS }
        end
    end

    local wallDir = Vec.Negate(normal)
    local tangent = Vec.Normalize2d(Vec.ProjectOnPlane(Vec.Flat(forward), normal)) or Vec.Right(wallDir)
    local angle = side == sides.front and Vec.Angle2d(forward, wallDir) or Vec.Angle2d(forward, tangent)

    return {
        valid = true,
        side = side,
        hits = count,
        normal = normal,
        wallDir = wallDir,
        tangent = tangent,
        point = pointSum / count,
        distance = nearest,
        angle = angle,
    }
end

Wall.ScanSides = function(origin, forward)
    return Wall.Scan(origin, sides.left, forward), Wall.Scan(origin, sides.right, forward)
end

Wall.Nearest = function(left, right)
    if left.valid and right.valid then return left.distance <= right.distance and left or right end
    if left.valid then return left end
    if right.valid then return right end
    return nil
end

return Wall
