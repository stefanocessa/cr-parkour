local Vec = require 'client.core.vec'
local Raycast = require 'client.detection.raycast'
local Landing = require 'client.detection.landing'
local Rays = require 'client.debug.rays'
local Profiler = require 'client.debug.profiler'

local Obstacle = {}

local settings = Config.Obstacle
local capsule = Config.TraversalCapsule
local detection = Config.Detection
local vault = Config.Vault
local body = Config.Body
local heights = Config.Heights
local cacheSettings = Config.Cache
local reasons = Constants.Reasons
local geometry = { enabled = false, entry = nil }

local findFace = function(results)
    local lowest, lastHit, firstFree
    for i = 1, #results do
        local result = results[i]
        if result.hit and not lowest then
            lowest, lastHit = result, result
        elseif result.hit and not firstFree then
            lastHit = result
        elseif not result.hit and lowest and not firstFree then
            firstFree = result
        elseif result.hit and firstFree and result.distance <= lowest.distance + settings.ambiguousMargin then
            return lowest, lastHit, firstFree, result
        end
    end
    return lowest, lastHit, firstFree, nil
end

local pathClear = function(from, to, topZ, ceilingZ)
    for i = 1, #vault.pathHeights do
        local z = topZ + vault.bodyClearance + vault.pathHeights[i]
        if z < ceilingZ - settings.ceilingMargin and not Landing.PathClear(Vec.WithZ(from, z), Vec.WithZ(to, z)) then return false end
    end
    return true
end

local exitClear = function(point, dir)
    for i = 1, #vault.exitHeights do
        local from = Vec.WithZ(point, point.z + heights[vault.exitHeights[i]])
        if Raycast.Direction(from, dir, vault.exitClearance).hit then return false end
    end
    return true
end

local describe = function(result)
    if not result or not result.hit then return nil end
    if result.rejected then return result.rejected end
    return Raycast.Classify(result)
end

local surfaceAt = function(point, topZ)
    local result = Raycast.Cast(Vec.WithZ(point, topZ + settings.depthProbeAbove), Vec.WithZ(point, topZ - settings.depthTolerance))
    return result.hit and result or nil
end

Obstacle.MaxVaultHeight = function()
    return vault.maxHeight + detection.heightTolerance
end

Obstacle.GroundZ = function(origin)
    local result = Raycast.Down(origin.coords, body.rootHeight + settings.groundProbe)
    if result.hit then return result.coords.z, true end
    return origin.feetZ, false
end

Obstacle.FindBase = function(origin, face, normal)
    local point = face.coords + normal * settings.baseInset
    local result = Raycast.Cast(Vec.WithZ(point, origin.feetZ + heights.knees), Vec.WithZ(point, origin.feetZ - settings.groundProbe))
    return result.hit and result.coords.z or nil
end

Obstacle.FindEdge = function(origin, dir, lastHit, firstFree, distance)
    local low, high = origin.feetZ + lastHit.height, origin.feetZ + firstFree.height
    local point = lastHit.coords
    for _ = 1, settings.edgeRefine do
        local mid = (low + high) * 0.5
        local result = Raycast.Direction(Vec.WithZ(origin.coords, mid), dir, distance)
        if result.hit then
            low, point = mid, result.coords
        else
            high = mid
        end
    end
    return low, point
end

Obstacle.GetTopSurface = function(edgePoint, intoDir, edgeZ)
    local top, minZ, maxZ
    for i = 1, #settings.topSamples do
        local xy = edgePoint + intoDir * settings.topSamples[i]
        local result = Raycast.Cast(Vec.WithZ(xy, edgeZ + settings.topProbeAbove), Vec.WithZ(xy, edgeZ - settings.topProbeBelow))
        if result.hit then
            top = top or result
            minZ = math.min(minZ or result.coords.z, result.coords.z)
            maxZ = math.max(maxZ or result.coords.z, result.coords.z)
        end
    end
    if not top then return { reason = reasons.OBSTACLE_NO_TOP } end
    local data = { point = top.coords, z = top.coords.z, normal = top.normal, rejected = top.rejected, variance = maxZ - minZ }
    if not Raycast.IsFloor(top) then
        data.reason = top.rejected or reasons.OBSTACLE_TOP_TOO_STEEP
    elseif data.variance > settings.maxTopVariance then
        data.reason = reasons.OBSTACLE_IRREGULAR_TOP
    end
    return data
end

Obstacle.GetDepth = function(edgePoint, intoDir, topZ)
    local inside = settings.topSamples[1]
    local outside = nil
    local minZ, maxZ = topZ, topZ
    local distance = inside + settings.depthStep
    while distance <= settings.maxDepth do
        local hit = surfaceAt(edgePoint + intoDir * distance, topZ)
        if not hit then
            outside = distance
            break
        end
        inside = distance
        minZ, maxZ = math.min(minZ, hit.coords.z), math.max(maxZ, hit.coords.z)
        distance = distance + settings.depthStep
    end
    if not outside then return { depth = settings.maxDepth, deep = true, variance = maxZ - minZ } end
    for _ = 1, settings.depthRefine do
        local mid = (inside + outside) * 0.5
        if surfaceAt(edgePoint + intoDir * mid, topZ) then inside = mid else outside = mid end
    end
    return { depth = inside, deep = false, back = edgePoint + intoDir * inside, variance = maxZ - minZ }
end

Obstacle.SetCaching = function(value)
    geometry.enabled = value == true
    if not geometry.enabled then geometry.entry = nil end
end

Obstacle.Flush = function()
    geometry.entry = nil
end

local reusable = function(face, normal, dir, groundZ, now)
    local entry = geometry.entry
    if not geometry.enabled or not entry then return nil end
    if now - entry.at > cacheSettings.geometryTTL then return nil end
    if face.entity and face.entity ~= 0 then return nil end
    local delta = face.coords - entry.face
    local tolerance = cacheSettings.positionTolerance
    if delta.x * delta.x + delta.y * delta.y + delta.z * delta.z > tolerance * tolerance then return nil end
    if Vec.Dot(normal, entry.normal) < cacheSettings.normalDot then return nil end
    if Vec.Angle2d(dir, entry.dir) > cacheSettings.headingTolerance then return nil end
    if math.abs(groundZ - entry.groundZ) > detection.heightTolerance then return nil end
    return entry.data
end

local remember = function(face, normal, dir, data, now)
    if not geometry.enabled or (face.entity and face.entity ~= 0) or data.groundZ == nil then return end
    geometry.entry = { at = now, face = face.coords, normal = normal, dir = dir, groundZ = data.groundZ, data = data }
end

local reuse = function(origin, base, cached)
    local data = {}
    for key, value in pairs(cached) do data[key] = value end
    for key, value in pairs(base) do data[key] = value end
    data.groundZ, data.groundFound = Obstacle.GroundZ(origin)
    if data.topZ then data.height = data.topZ - data.groundZ end
    data.baseHeight = data.baseZ and data.topZ and data.topZ - data.baseZ or nil
    if cached.headClearance then
        local head = Raycast.Up(Raycast.AtHeight(origin, 'head'), Config.Scan.upDistance)
        data.headClearance = head.hit and head.distance or Config.Scan.upDistance
    end
    data.cached = true
    return data
end

Obstacle.Scan = function(origin, dir, fan, options)
    local results = fan or Raycast.Fan(origin, dir, settings.scanDistance, settings.heights)
    local face, lastHit, firstFree, upper = findFace(results)
    if not face then return { hit = false, reason = reasons.NO_OBSTACLE } end

    local normal = Vec.Normalize2d(face.normal) or Vec.Negate(dir)
    local intoDir = Vec.Negate(normal)
    local data = {
        hit = true,
        face = face.coords,
        normal = normal,
        intoDir = intoDir,
        distance = Vec.Distance2d(origin.coords, face.coords),
        approachAngle = Vec.Angle2d(dir, intoDir),
        tall = firstFree == nil,
        ambiguous = upper ~= nil,
        upperHit = upper and upper.coords or nil,
        surface = describe(face),
    }
    Rays.Point(face.coords, 'face')

    if not Raycast.IsWall(face) then
        data.reason = Raycast.Reject(face, reasons.OBSTACLE_BAD_SURFACE)
        return data
    end
    if data.tall then
        data.reason = reasons.OBSTACLE_TALL
        return data
    end
    if options and options.contact == false then
        data.reason = reasons.OVER_NO_LOWER_CONTACT
        data.lazy = true
        return data
    end

    local now = GetGameTimer()
    local groundZ, groundFound = Obstacle.GroundZ(origin)
    local cached = reusable(face, normal, dir, groundZ, now)
    if cached then return reuse(origin, data, cached) end

    local detailStarted = Profiler.Start()
    data.groundZ, data.groundFound = groundZ, groundFound
    data.baseZ = Obstacle.FindBase(origin, face, normal)

    local edgeZ, edgePoint = Obstacle.FindEdge(origin, dir, lastHit, firstFree, face.distance + settings.faceMargin)
    data.edgeZ = edgeZ
    data.frontEdge = Vec.WithZ(edgePoint, edgeZ)
    Rays.Point(data.frontEdge, 'face')

    local top = Obstacle.GetTopSurface(edgePoint, intoDir, edgeZ)
    if not top.z then
        data.reason = top.reason
        remember(face, normal, dir, data, now)
        Profiler.Stop('top', detailStarted)
        return data
    end
    data.top = top.point
    data.topZ = top.z
    data.topNormal = top.normal
    data.topRejected = top.rejected
    data.topVariance = top.variance
    data.topReason = top.reason
    data.height = data.topZ - data.groundZ
    data.baseHeight = data.baseZ and data.topZ - data.baseZ or nil
    Rays.Point(top.point, 'top')

    if data.topReason or data.height > Obstacle.MaxVaultHeight() then
        data.reason = data.topReason or reasons.OK
        remember(face, normal, dir, data, now)
        Profiler.Stop('top', detailStarted)
        return data
    end

    local above = Raycast.Up(top.point + Vec.Up * Constants.SurfaceOffset, capsule.standingHeight)
    data.topClearance = above.hit and above.distance + Constants.SurfaceOffset or capsule.standingHeight
    data.ceiling = above.hit and above.coords or nil

    local head = Raycast.Up(Raycast.AtHeight(origin, 'head'), Config.Scan.upDistance)
    data.headClearance = head.hit and head.distance or Config.Scan.upDistance

    local depth = Obstacle.GetDepth(edgePoint, intoDir, data.topZ)
    data.depth = depth.depth
    data.deep = depth.deep
    data.topVariance = math.max(data.topVariance, depth.variance)
    if data.topVariance > settings.maxTopVariance then data.topReason = reasons.OBSTACLE_IRREGULAR_TOP end
    data.center = Vec.WithZ(edgePoint + intoDir * (data.depth * 0.5), data.topZ)

    if depth.back then
        data.backEdge = Vec.WithZ(depth.back, data.topZ)
        Rays.Point(data.backEdge, 'top')
        local landingXY = depth.back + intoDir * vault.landingOffset
        local landing = Landing.Validate(landingXY, data.topZ, data.height + vault.maxDrop)
        data.landing = landing
        data.landingPoint = landing and landing.point
        data.landingZ = landing and landing.point.z
        data.landingClearance = landing and landing.clearance or 0.0
        data.pathClear = pathClear(edgePoint - intoDir * body.radius, landingXY, data.topZ, data.topZ + data.topClearance)
        data.exitClear = landing ~= nil and exitClear(landing.point, intoDir)
    end

    data.reason = data.topReason or reasons.OK
    remember(face, normal, dir, data, now)
    Profiler.Stop('top', detailStarted)
    return data
end

return Obstacle
