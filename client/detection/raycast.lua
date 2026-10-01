local Vec = require 'client.core.vec'
local Rays = require 'client.debug.rays'
local Profiler = require 'client.debug.profiler'

local Raycast = {}

local settings = Config.Raycast
local heights = Config.Heights
local surface = Config.Surface
local dynamic = Config.DynamicSurfaces
local cacheSettings = Config.Cache
local reasons = Constants.Reasons
local entityTypes = { ped = 1, vehicle = 2, object = 3 }
local memo = {}
local entityMemo = {}
local blockedMemo = {}
local stable = { current = {}, older = {}, startedAt = 0, olderAt = 0, enabled = false }

local hashSet = function(list)
    if not list then return nil end
    local set = {}
    for i = 1, #list do
        local value = list[i]
        set[type(value) == 'string' and GetHashKey(value) or value] = true
    end
    return set
end

local blacklist = hashSet(Config.Materials.blacklist) or {}
local whitelist = hashSet(Config.Materials.whitelist)
local blockedModels = hashSet(dynamic.blacklistModels) or {}
local blockedClasses = {}
for i = 1, #(dynamic.blacklistVehicleClasses or {}) do blockedClasses[dynamic.blacklistVehicleClasses[i]] = true end

Raycast.Flush = function()
    stable.current, stable.older = {}, {}
    stable.startedAt, stable.olderAt = 0, 0
end

Raycast.NewTick = function(now, persist)
    memo = {}
    entityMemo = {}
    blockedMemo = {}
    stable.enabled = persist == true and now ~= nil
    if not stable.enabled then
        if stable.startedAt ~= 0 then Raycast.Flush() end
        return
    end
    local generation = cacheSettings.geometryTTL * 0.5
    if now - stable.startedAt >= generation then
        stable.older, stable.olderAt = stable.current, stable.startedAt
        stable.current, stable.startedAt = {}, now
    end
    if now - stable.olderAt > cacheSettings.geometryTTL then stable.older = {} end
end

local isDynamic = function(entity)
    if not entity or entity == 0 then return false end
    local known = entityMemo[entity]
    if known ~= nil then return known end
    local kind = DoesEntityExist(entity) and GetEntityType(entity) or 0
    local result = false
    if kind == entityTypes.ped then
        result = true
    elseif kind == entityTypes.vehicle then
        result = not dynamic.vehicles
    elseif kind == entityTypes.object then
        result = not dynamic.movingProps and GetEntitySpeed(entity) > dynamic.movingSpeed
    end
    entityMemo[entity] = result
    return result
end

local isBlacklisted = function(entity)
    if not entity or entity == 0 then return false end
    local known = blockedMemo[entity]
    if known ~= nil then return known end
    local kind = DoesEntityExist(entity) and GetEntityType(entity) or 0
    local result = false
    if kind ~= 0 then
        result = blockedModels[GetEntityModel(entity)] == true
        if not result and kind == entityTypes.vehicle then
            result = blockedClasses[GetVehicleClass(entity)] == true
        end
    end
    blockedMemo[entity] = result
    return result
end

local rejectReason = function(entity, material)
    if isDynamic(entity) then return reasons.PARKOUR_DENIED_DYNAMIC_SURFACE end
    if isBlacklisted(entity) then return reasons.PARKOUR_DENIED_BLACKLISTED end
    if material and material ~= 0 then
        if blacklist[material] then return reasons.PARKOUR_DENIED_MATERIAL end
        if whitelist and not whitelist[material] then return reasons.PARKOUR_DENIED_MATERIAL end
    end
    return nil
end

local key = function(from, to)
    return ('%.2f|%.2f|%.2f|%.2f|%.2f|%.2f'):format(from.x, from.y, from.z, to.x, to.y, to.z)
end

local remembered = function(id)
    local cached = memo[id]
    if cached or not stable.enabled then return cached end
    cached = stable.current[id] or stable.older[id]
    if cached then memo[id] = cached end
    return cached
end

Raycast.Cast = function(from, to)
    local id = key(from, to)
    local cached = remembered(id)
    if cached then
        Profiler.Ray(true)
        return cached
    end
    Profiler.Ray(false)

    local handle = StartExpensiveSynchronousShapeTestLosProbe(from.x, from.y, from.z, to.x, to.y, to.z, settings.flags, cache.ped, settings.options)
    local _, hit, coords, normal, material, entity = GetShapeTestResultIncludingMaterial(handle)
    hit = hit == 1 or hit == true
    local finish = hit and coords or to
    Rays.Line(from, finish, hit and 'blocked' or 'valid')
    local result = {
        hit = hit,
        from = from,
        to = to,
        coords = finish,
        normal = hit and normal or Vec.Zero,
        entity = entity,
        material = hit and material or nil,
        distance = #(finish - from),
        rejected = hit and rejectReason(entity, material) or nil,
    }
    memo[id] = result
    if stable.enabled and (not hit or not entity or entity == 0) then stable.current[id] = result end
    return result
end

Raycast.Line = Raycast.Cast

Raycast.Direction = function(origin, dir, distance)
    return Raycast.Cast(origin, origin + dir * distance)
end

Raycast.Forward = Raycast.Direction

Raycast.Down = function(origin, distance)
    return Raycast.Cast(origin, origin - Vec.Up * distance)
end

Raycast.Up = function(origin, distance)
    return Raycast.Cast(origin, origin + Vec.Up * distance)
end

Raycast.AtHeight = function(origin, heightName)
    return Vec.WithZ(origin.coords, origin.feetZ + heights[heightName])
end

local entry = function(result, name)
    return {
        result = result,
        name = name,
        height = heights[name],
        hit = result.hit,
        from = result.from,
        to = result.to,
        coords = result.coords,
        normal = result.normal,
        entity = result.entity,
        material = result.material,
        distance = result.distance,
        rejected = result.rejected,
    }
end

local miss = function(name)
    return { name = name, height = heights[name], hit = false, normal = Vec.Zero, skipped = true }
end

Raycast.Fan = function(origin, dir, distance, names)
    local results = {}
    for i = 1, #names do
        results[i] = entry(Raycast.Direction(Raycast.AtHeight(origin, names[i]), dir, distance), names[i])
    end
    return results
end

Raycast.FanUntil = function(origin, dir, distance, names, needed, accept)
    local results = {}
    local accepted = 0
    for i = 1, #names do
        if accepted + (#names - i + 1) < needed then
            results[i] = miss(names[i])
        else
            results[i] = entry(Raycast.Direction(Raycast.AtHeight(origin, names[i]), dir, distance), names[i])
            if accept(results[i]) then accepted = accepted + 1 end
        end
    end
    return results
end

Raycast.Clip = function(fan, names, distance)
    local byName = {}
    for i = 1, #fan do byName[fan[i].name] = fan[i] end
    local results = {}
    for i = 1, #names do
        local source = byName[names[i]]
        if source and source.hit and source.distance <= distance then
            results[i] = source
        else
            results[i] = miss(names[i])
        end
    end
    return results
end

Raycast.Covers = function(fan, names, distance, fanDistance)
    if not fan or distance > fanDistance then return false end
    local present = {}
    for i = 1, #fan do present[fan[i].name] = true end
    for i = 1, #names do
        if not present[names[i]] then return false end
    end
    return true
end

Raycast.Classify = function(result)
    if not result.hit then return nil end
    local z = result.normal.z
    if z >= surface.minTopNormalZ then return 'floor' end
    if z <= surface.maxCeilingNormalZ then return 'ceiling' end
    if math.abs(z) <= surface.maxWallNormalZ then return 'wall' end
    return 'slope'
end

Raycast.Usable = function(result)
    return result.hit and not result.rejected
end

Raycast.IsWall = function(result)
    return Raycast.Usable(result) and Raycast.Classify(result) == 'wall'
end

Raycast.IsFloor = function(result)
    return Raycast.Usable(result) and Raycast.Classify(result) == 'floor'
end

Raycast.Reject = function(result, fallback)
    if result and result.rejected then return result.rejected end
    return fallback
end

return Raycast
