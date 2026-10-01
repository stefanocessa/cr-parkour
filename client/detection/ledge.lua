local Vec = require 'client.core.vec'
local Raycast = require 'client.detection.raycast'
local Landing = require 'client.detection.landing'
local Rays = require 'client.debug.rays'

local Ledge = {}

local settings = Config.Ledge
local detection = Config.Detection
local jump = Config.Ledge.jump
local body = Config.Body
local reasons = Constants.Reasons
local corner = Config.Shimmy.corner

local denied = function(reason, extra)
    local result = extra or {}
    result.valid = false
    result.reason = reason
    return result
end

local findFace = function(origin, dir, fan, fanDistance)
    local results
    if Raycast.Covers(fan, settings.faceHeights, settings.faceDistance, fanDistance or 0.0) then
        results = Raycast.Clip(fan, settings.faceHeights, settings.faceDistance)
    else
        results = Raycast.Fan(origin, dir, settings.faceDistance, settings.faceHeights)
    end
    local best, rejected
    for i = 1, #results do
        local result = results[i]
        if Raycast.IsWall(result) then
            local distance = Vec.Distance2d(origin.coords, result.coords)
            if not best or distance < best.distance then
                best = { coords = result.coords, normal = Vec.Normalize2d(result.normal), distance = distance }
            end
        elseif result.hit then
            rejected = rejected or result.rejected
        end
    end
    return best, rejected
end

local scanTop = function(face, wallDir, fromZ, toZ)
    local backoff = settings.scanBackoff
    local lastHitZ
    local z = fromZ
    while z <= toZ do
        local from = Vec.WithZ(face.coords - wallDir * backoff, z)
        local result = Raycast.Direction(from, wallDir, backoff + settings.topInset)
        if result.hit then
            lastHitZ = z
        elseif lastHitZ then
            return z
        end
        z = z + settings.scanStep
    end
    return nil
end

local probeSurface = function(edgeXY, wallDir, aboveZ, belowZ)
    local point = edgeXY + wallDir * settings.topInset
    return Raycast.Cast(Vec.WithZ(point, aboveZ), Vec.WithZ(point, belowZ))
end

local build = function(origin, face, normal, top)
    local wallDir = Vec.Negate(normal)
    local edge = Vec.WithZ(face, top.coords.z)
    local hang = edge + normal * settings.hangDistance + Vec.Up * settings.verticalOffset
    Rays.Point(edge, 'ledge')
    local mark = Vec.Right(wallDir) * Config.DebugPanel.ledgeMarkWidth
    Rays.Line(edge + mark, edge - mark, 'ledge')
    return {
        valid = true,
        reason = reasons.OK,
        edge = edge,
        topZ = top.coords.z,
        topNormal = top.normal,
        normal = normal,
        wallDir = wallDir,
        tangent = Vec.Right(wallDir),
        hang = hang,
        heading = Vec.Heading(wallDir),
        height = top.coords.z - origin.feetZ,
        distance = Vec.Distance2d(origin.coords, face),
    }
end

Ledge.Inspect = function(result)
    local head = Raycast.Up(result.edge + result.wallDir * settings.topInset + Vec.Up * Constants.SurfaceOffset, settings.headClearance)
    result.headClear = not head.hit
    local landingXY = result.edge + result.wallDir * settings.landingDepth
    local landing = Landing.FindGround(landingXY, result.topZ + settings.topProbeAbove, result.topZ - settings.topTolerance)
    result.landing = landing and landing.coords
    result.landingClearance, result.climbable = 0.0, false
    if landing then
        local clearance, clear = Landing.Clearance(landing.coords, settings.climbClearance)
        result.landingClearance = clearance
        result.climbable = clear and result.headClear
    end
    return result
end

Ledge.Find = function(origin, dir, minHeight, maxHeight, fan, fanDistance)
    local face, rejected = findFace(origin, dir, fan, fanDistance)
    if not face or not face.normal then return denied(rejected or reasons.LEDGE_DENIED_NO_WALL) end
    if face.distance > settings.reach + detection.distanceTolerance then return denied(reasons.LEDGE_DENIED_TOO_FAR, { distance = face.distance }) end

    local wallDir = Vec.Negate(face.normal)
    local freeZ = scanTop(face, wallDir, face.coords.z, origin.feetZ + (maxHeight or settings.maxHeight) + detection.heightTolerance + settings.scanStep)
    if not freeZ then return denied(reasons.LEDGE_DENIED_TOO_HIGH, { distance = face.distance }) end

    local top = probeSurface(face.coords, wallDir, freeZ + settings.topProbeAbove, freeZ - settings.scanStep - settings.topTolerance)
    if not top.hit then return denied(reasons.LEDGE_DENIED_NO_TOP, { distance = face.distance }) end
    if not Raycast.IsFloor(top) then return denied(Raycast.Reject(top, reasons.LEDGE_DENIED_BAD_SURFACE), { distance = face.distance }) end
    Rays.Point(top.coords, 'top')

    local result = build(origin, face.coords, face.normal, top)
    if result.height < (minHeight or settings.minHeight) - detection.heightTolerance then return denied(reasons.LEDGE_DENIED_TOO_LOW, result) end
    if result.height > (maxHeight or settings.maxHeight) + detection.heightTolerance then return denied(reasons.LEDGE_DENIED_TOO_HIGH, result) end
    Ledge.Inspect(result)
    if not result.headClear then return denied(reasons.LEDGE_DENIED_HEAD_BLOCKED, result) end
    if not result.landing then return denied(reasons.LEDGE_DENIED_NO_LANDING, result) end
    return result
end

Ledge.AtFace = function(ledge, facePoint, normal)
    local step = Config.Shimmy.maxStep
    local top = probeSurface(facePoint, Vec.Negate(normal), ledge.topZ + step, ledge.topZ - step)
    if not Raycast.IsFloor(top) then return denied(reasons.SHIMMY_DENIED_NO_EDGE) end
    return build({ coords = facePoint, feetZ = ledge.topZ - ledge.height }, facePoint, normal, top)
end

Ledge.Follow = function(ledge, edgeXY)
    local wallDir = ledge.wallDir
    local from = Vec.WithZ(edgeXY - wallDir * settings.scanBackoff, ledge.topZ - settings.topInset)
    local wall = Raycast.Direction(from, wallDir, settings.scanBackoff * 2.0)
    if not Raycast.IsWall(wall) then return denied(reasons.SHIMMY_DENIED_NO_EDGE) end
    return Ledge.AtFace(ledge, wall.coords, Vec.Normalize2d(wall.normal) or ledge.normal)
end

local cornerFrom = function(ledge, hit, kind)
    if not Raycast.IsWall(hit) then return denied(reasons.SHIMMY_DENIED_CORNER) end
    local normal = Vec.Normalize2d(hit.normal)
    if not normal then return denied(reasons.SHIMMY_DENIED_CORNER) end
    local angle = Vec.Angle2d(ledge.normal, normal)
    if angle < corner.minAngle or angle > corner.maxAngle then return denied(reasons.SHIMMY_DENIED_CORNER) end
    local result = Ledge.AtFace(ledge, hit.coords, normal)
    if not result.valid then return denied(reasons.SHIMMY_DENIED_CORNER) end
    result.corner = kind
    result.cornerAngle = angle
    return result
end

Ledge.OuterCorner = function(ledge, direction)
    local origin = Vec.WithZ(ledge.edge + direction * corner.reach + ledge.wallDir * corner.depth, ledge.topZ - settings.topInset)
    return cornerFrom(ledge, Raycast.Direction(origin, Vec.Negate(direction), corner.reach), 'outer')
end

Ledge.InnerCorner = function(ledge, direction)
    local origin = Vec.WithZ(ledge.edge + ledge.normal * corner.inset, ledge.topZ - settings.topInset)
    return cornerFrom(ledge, Raycast.Direction(origin, direction, corner.reach), 'inner')
end

Ledge.FindUp = function(ledge, minRise, maxRise)
    local face = { coords = ledge.edge }
    local probe = Vec.WithZ(ledge.edge - ledge.wallDir * settings.scanBackoff, ledge.topZ + jump.wallProbe)
    if not Raycast.IsWall(Raycast.Direction(probe, ledge.wallDir, settings.scanBackoff + settings.topInset)) then
        return denied(reasons.LEDGE_JUMP_DENIED_NO_TARGET)
    end
    local freeZ = scanTop(face, ledge.wallDir, ledge.topZ + jump.wallProbe, ledge.topZ + maxRise + settings.scanStep)
    if not freeZ then return denied(reasons.LEDGE_DENIED_TOO_HIGH) end
    local top = probeSurface(ledge.edge, ledge.wallDir, freeZ + settings.topProbeAbove, freeZ - settings.scanStep - settings.topTolerance)
    if not Raycast.IsFloor(top) then return denied(Raycast.Reject(top, reasons.LEDGE_DENIED_NO_TOP)) end
    local rise = top.coords.z - ledge.topZ
    if rise < minRise - detection.heightTolerance then return denied(reasons.LEDGE_DENIED_TOO_LOW) end
    if rise > maxRise + detection.heightTolerance then return denied(reasons.LEDGE_DENIED_TOO_HIGH) end
    local result = build({ coords = ledge.edge, feetZ = ledge.topZ - ledge.height }, ledge.edge, ledge.normal, top)
    result.rise = rise
    return Ledge.Inspect(result)
end

Ledge.FindSide = function(ledge, sign, preferred)
    local best, bestError, bestOffset
    local distance = jump.sideMin
    while distance <= jump.sideMax + Constants.Epsilon do
        local target = Ledge.Follow(ledge, ledge.edge + ledge.tangent * (sign * distance))
        if target.valid and math.abs(target.topZ - ledge.topZ) <= jump.sideTolerance then
            local err = math.abs(distance - preferred)
            if not best or err < bestError then best, bestError, bestOffset = target, err, distance end
        end
        distance = distance + jump.sideStep
    end
    if not best then return denied(reasons.LEDGE_JUMP_DENIED_NO_TARGET) end
    best.offset = bestOffset
    return Ledge.Inspect(best)
end

Ledge.CanGrab = function(origin, ledge, verticalSpeed)
    if not ledge or not ledge.valid then return false, ledge and ledge.reason or reasons.LEDGE_DENIED_NO_WALL end
    if ledge.distance > settings.reach + detection.distanceTolerance then return false, reasons.LEDGE_DENIED_TOO_FAR end
    local offset = ledge.topZ - (origin.feetZ + body.handReach)
    if offset < settings.grabMinOffset then return false, reasons.LEDGE_DENIED_TOO_LOW end
    if offset > settings.grabMaxOffset then return false, reasons.LEDGE_DENIED_TOO_HIGH end
    if verticalSpeed and -verticalSpeed > settings.maxFallSpeed then return false, reasons.LEDGE_DENIED_TOO_FAST end
    return true, reasons.OK
end

return Ledge
