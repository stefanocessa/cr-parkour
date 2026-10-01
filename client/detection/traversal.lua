local Vec = require 'client.core.vec'
local Raycast = require 'client.detection.raycast'
local Ledge = require 'client.detection.ledge'
local Animation = require 'client.systems.animation'
local Rays = require 'client.debug.rays'
local Profiler = require 'client.debug.profiler'

local Traversal = {}

local settings = Config.Traversal
local capsule = Config.TraversalCapsule
local under = Config.Under
local through = Config.Through
local vault = Config.Vault
local wallclimb = Config.Wallclimb
local wallrun = Config.Wallrun
local detection = Config.Detection
local heights = Config.Heights
local reasons = Constants.Reasons

local minimum = function(pool, field, fallback, onlyGeneric)
    local value
    for i = 1, #pool do
        local meta = Animation.Meta(pool[i])
        if meta and meta[field] and (not onlyGeneric or meta.generic) then value = math.min(value or meta[field], meta[field]) end
    end
    return value or fallback
end

local candidate = function(kind, valid, reason, detail)
    return { type = kind, valid = valid, reason = valid and reasons.OK or reason, detail = detail, score = nil, path = nil }
end

local score = function(kind, quality)
    return settings.scores[kind] * (1.0 - settings.quality + settings.quality * Vec.Clamp(quality, 0.0, 1.0))
end

local path = function(entry, cross, exit)
    return { entry = entry, cross = cross, exit = exit, valid = entry ~= nil and cross ~= nil and exit ~= nil }
end

local lateral = function(point, dir, distance)
    local right = Vec.Right(dir)
    local left = Raycast.Direction(point, Vec.Negate(right), distance)
    local rightHit = Raycast.Direction(point, right, distance)
    return left.hit and left.distance or distance, rightHit.hit and rightHit.distance or distance
end

Traversal.Layers = function(origin, dir)
    local fan = Raycast.Fan(origin, dir, Config.Obstacle.scanDistance, settings.layers)
    local layers = {}
    for i = 1, #fan do
        local layer = fan[i]
        layers[layer.name] = {
            name = layer.name,
            height = layer.height,
            hit = layer.hit,
            distance = layer.hit and Vec.Distance2d(origin.coords, layer.coords) or nil,
            coords = layer.hit and layer.coords or nil,
            normal = layer.hit and layer.normal or nil,
            entity = layer.entity,
            material = layer.material,
        }
    end
    return fan, layers
end

local blocked = function(layers, names, distance)
    for i = 1, #names do
        local layer = layers[names[i]]
        if layer and layer.hit and (not distance or layer.distance <= distance) then return true, layer end
    end
    return false, nil
end

Traversal.HasContact = function(layers)
    return (blocked(layers, settings.contactLayers, Config.Obstacle.scanDistance))
end

Traversal.AnyHit = function(layers)
    for i = 1, #settings.layers do
        local layer = layers[settings.layers[i]]
        if layer and layer.hit then return true end
    end
    return false
end

local nearestBlock = function(layers, names, distance)
    local best
    for i = 1, #names do
        local layer = layers[names[i]]
        if layer and layer.hit and layer.distance <= distance and (not best or layer.distance < best.distance) then best = layer end
    end
    return best
end

local classifyOver = function(profile, obstacle)
    if not obstacle or not obstacle.hit then return candidate('OVER', false, reasons.VAULT_DENIED_NO_OBSTACLE) end
    if not blocked(profile.layers, settings.contactLayers, Config.Obstacle.scanDistance) then return candidate('OVER', false, reasons.OVER_NO_LOWER_CONTACT) end
    if obstacle.reason == reasons.OBSTACLE_BAD_SURFACE then return candidate('OVER', false, reasons.VAULT_DENIED_BAD_SURFACE) end
    if obstacle.reason == reasons.PARKOUR_DENIED_DYNAMIC_SURFACE or obstacle.reason == reasons.PARKOUR_DENIED_MATERIAL
        or obstacle.reason == reasons.PARKOUR_DENIED_BLACKLISTED then
        return candidate('OVER', false, obstacle.reason)
    end
    if obstacle.tall then return candidate('OVER', false, reasons.OBSTACLE_TALL) end
    if not obstacle.topZ then return candidate('OVER', false, obstacle.reason or reasons.OBSTACLE_NO_TOP) end
    if obstacle.topRejected then return candidate('OVER', false, obstacle.topRejected) end
    if obstacle.topReason then return candidate('OVER', false, obstacle.topReason) end
    local tolerance = detection.heightTolerance
    local measured = ('%.2f'):format(obstacle.height)
    if obstacle.height < vault.minHeight - tolerance then return candidate('OVER', false, reasons.OBSTACLE_TOO_LOW, measured) end
    if obstacle.height > vault.maxHeight + tolerance then return candidate('OVER', false, reasons.OBSTACLE_TOO_HIGH, measured) end
    if obstacle.deep or obstacle.depth > vault.maxDepth + detection.distanceTolerance then
        return candidate('OVER', false, reasons.OBSTACLE_TOO_DEEP, obstacle.deep and 'deep' or ('%.2f'):format(obstacle.depth))
    end
    local clearance = minimum(vault.pool, 'clearanceRequired', vault.topClearance, true)
    if obstacle.topClearance < clearance - tolerance then return candidate('OVER', false, reasons.OBSTACLE_TOP_BLOCKED, ('%.2f'):format(obstacle.topClearance)) end
    if obstacle.headClearance < vault.headClearance then return candidate('OVER', false, reasons.VAULT_DENIED_HEAD_BLOCKED, 'start') end
    if not obstacle.landing then return candidate('OVER', false, reasons.VAULT_DENIED_NO_LANDING) end
    if not obstacle.landing.clear then return candidate('OVER', false, reasons.VAULT_DENIED_LANDING_BLOCKED, 'clearance') end
    if obstacle.landingZ > obstacle.topZ - vault.minLandingDrop then return candidate('OVER', false, reasons.VAULT_DENIED_LANDING_BLOCKED, 'second_object') end
    if not obstacle.pathClear then return candidate('OVER', false, reasons.VAULT_DENIED_PATH_BLOCKED) end
    if not obstacle.exitClear then return candidate('OVER', false, reasons.VAULT_DENIED_EXIT_BLOCKED) end

    local kind = obstacle.topClearance < capsule.standingHeight - tolerance and 'THROUGH' or 'OVER'
    local result = candidate(kind, true)
    result.window = kind == 'THROUGH'
    result.path = path(Vec.WithZ(obstacle.frontEdge - obstacle.intoDir * Config.Body.radius, obstacle.groundZ), Vec.WithZ(obstacle.center, obstacle.topZ), obstacle.landingPoint)
    if obstacle.approachAngle > vault.maxApproachAngle + detection.angleTolerance then
        result.valid, result.reason, result.detail = false, reasons.VAULT_DENIED_BAD_ANGLE, ('%.0f'):format(obstacle.approachAngle)
        return result
    end
    if obstacle.distance > vault.maxDistance + detection.distanceTolerance then
        result.valid, result.reason, result.detail = false, reasons.VAULT_DENIED_TOO_FAR, ('%.2f'):format(obstacle.distance)
        result.approaching = true
        return result
    end
    local fit = 1.0 - obstacle.approachAngle / (vault.maxApproachAngle + detection.angleTolerance)
    result.floating = not blocked(profile.layers, settings.lowerLayers, Config.Obstacle.scanDistance)
    result.score = score(kind, fit) * (result.floating and settings.floatingPenalty or 1.0)
    if result.window then
        result.opening = { height = obstacle.topClearance, bottom = obstacle.topZ }
    end
    return result
end

local sampleGround = function(point, lastZ)
    local result = Raycast.Cast(Vec.WithZ(point, lastZ + under.stepUp), Vec.WithZ(point, lastZ - under.stepDown))
    if not Raycast.IsFloor(result) then return nil end
    return result.coords.z
end

local corridorClear = function(from, to, dir)
    local right = Vec.Right(dir) * (capsule.width * 0.5)
    for i = 1, #under.corridorHeights do
        local h = heights[under.corridorHeights[i]]
        if Raycast.Cast(from + Vec.Up * h, to + Vec.Up * h).hit then return false end
    end
    local h = heights[under.shoulderHeight]
    if Raycast.Cast(from + right + Vec.Up * h, to + right + Vec.Up * h).hit then return false end
    if Raycast.Cast(from - right + Vec.Up * h, to - right + Vec.Up * h).hit then return false end
    return true
end

Traversal.Corridor = function(origin, dir)
    local samples = {}
    local previous = Vec.WithZ(origin.coords, origin.feetZ)
    local groundZ = origin.feetZ
    local distance = under.step
    local passageEnd = nil
    local broken = nil
    while distance <= under.maxLength + Constants.Epsilon do
        local point = origin.coords + dir * distance
        local z = sampleGround(point, groundZ)
        if not z then
            broken = reasons.UNDER_NO_GROUND
            break
        end
        local floor = Vec.WithZ(point, z)
        if not corridorClear(previous, floor, dir) then
            broken = reasons.UNDER_CORRIDOR_BLOCKED
            break
        end
        local up = Raycast.Up(floor + Vec.Up * heights.feet, capsule.standingHeight - heights.feet)
        local clearance = up.hit and (up.coords.z - z) or capsule.standingHeight
        samples[#samples + 1] = { distance = distance, point = floor, ground = z, clearance = clearance, underside = up.hit and up.coords or nil }
        if clearance < capsule.standingHeight - under.headroomTolerance then
            passageEnd = distance
        elseif passageEnd and distance - passageEnd >= under.exitScan then
            break
        elseif not passageEnd and distance > under.triggerDistance + under.step then
            break
        end
        previous, groundZ = floor, z
        distance = distance + under.step
    end
    return samples, broken
end

local classifyUnder = function(origin, dir, layers, profile)
    if not under.enabled then return candidate('UNDER', false, reasons.VAULT_DENIED_DISABLED) end
    if blocked(layers, settings.lowerLayers, under.triggerDistance) then return candidate('UNDER', false, reasons.UNDER_LOWER_BLOCKED) end
    local blocker = nearestBlock(layers, settings.upperLayers, under.triggerDistance)
    if not blocker then return candidate('UNDER', false, reasons.UNDER_NO_BLOCKER) end

    local samples, broken = Traversal.Corridor(origin, dir)
    local first, last, lowest, lowestZ
    for i = 1, #samples do
        local sample = samples[i]
        if sample.clearance < capsule.standingHeight - under.headroomTolerance then
            if not first then first = i end
            if not last or i == last + 1 then
                last = i
                if not lowest or sample.clearance < lowest then lowest = sample.clearance end
                if sample.underside and (not lowestZ or sample.underside.z < lowestZ) then lowestZ = sample.underside.z end
            end
        end
    end
    local result = candidate('UNDER', false, reasons.UNDER_NO_BLOCKER)
    result.samples = samples
    if not first then
        result.reason = broken or reasons.UNDER_NO_BLOCKER
        return result
    end
    result.passageStart = samples[first].distance
    result.passageEnd = samples[last].distance
    result.passageHeight = lowest
    result.passageDepth = samples[last].distance - samples[first].distance + under.step
    result.lowestBlockingZ = lowestZ
    result.groundZ = samples[first].ground
    local exit
    for i = last + 1, #samples do
        if samples[i].clearance >= capsule.standingHeight - under.headroomTolerance then
            exit = samples[i]
            break
        end
    end
    result.exitLength = exit and (samples[#samples].distance - exit.distance) or 0.0
    result.exitClear = exit ~= nil and result.exitLength >= under.minExitLength - Constants.Epsilon
    result.path = path(samples[first].point, samples[math.floor((first + last) * 0.5)].point, exit and exit.point or nil)
    if result.passageStart > under.triggerDistance + under.step then
        result.reason = reasons.UNDER_TOO_FAR
        return result
    end
    if lowest < minimum(under.pool, 'minPassage', capsule.slideHeight) - detection.heightTolerance then
        result.reason, result.detail = reasons.UNDER_PASSAGE_TOO_LOW, ('%.2f'):format(lowest)
        return result
    end
    if not exit then
        result.reason = broken or reasons.UNDER_EXIT_BLOCKED
        return result
    end
    if not result.exitClear then
        result.reason, result.detail = reasons.UNDER_EXIT_BLOCKED, ('%.2f'):format(result.exitLength)
        return result
    end
    result.valid, result.reason = true, reasons.OK
    result.score = score('UNDER', (lowest - minimum(under.pool, 'minPassage', capsule.slideHeight)) / under.score.passageSpan)
    return result
end

local classifyOpening = function(origin, dir, layers)
    if not through.enabled then return candidate('THROUGH', false, reasons.THROUGH_NO_FRAME) end
    if blocked(layers, { 'knees', 'waist', 'chest', 'head' }, through.probeDistance) then return candidate('THROUGH', false, reasons.THROUGH_NO_FRAME, 'center_blocked') end
    local right = Vec.Right(dir) * (capsule.width * 0.5 + through.frameMargin)
    local frame
    for i = 1, #capsule.shoulderHeights do
        local h = heights[capsule.shoulderHeights[i]]
        local base = Vec.WithZ(origin.coords, origin.feetZ + h)
        for _, side in ipairs({ right, Vec.Negate(right) }) do
            local hit = Raycast.Direction(base + side, dir, through.probeDistance)
            if hit.hit and (not frame or hit.distance < frame) then frame = hit.distance end
        end
    end
    local overhead = layers.overhead
    if overhead and overhead.hit and overhead.distance <= through.probeDistance and (not frame or overhead.distance < frame) then frame = overhead.distance end
    if not frame then return candidate('THROUGH', false, reasons.THROUGH_NO_FRAME) end

    local crossXY = origin.coords + dir * (frame + through.frameMargin)
    local cross = Vec.WithZ(crossXY, origin.feetZ + heights.waist)
    local left, rightClear = lateral(cross, dir, settings.lateralProbe)
    local up = Raycast.Up(Vec.WithZ(crossXY, origin.feetZ + heights.feet), capsule.standingHeight + through.frameMargin)
    local result = candidate('THROUGH', false, reasons.THROUGH_TOO_NARROW)
    result.open = true
    result.opening = { width = left + rightClear, height = up.hit and (up.coords.z - origin.feetZ) or capsule.standingHeight + through.frameMargin, left = left, right = rightClear }
    local exitXY = crossXY + dir * (through.frameDepth + through.exitDistance)
    local ground = sampleGround(exitXY, origin.feetZ)
    result.path = path(Vec.WithZ(origin.coords + dir * frame, origin.feetZ), Vec.WithZ(crossXY, origin.feetZ), ground and Vec.WithZ(exitXY, ground) or nil)
    if result.opening.width < capsule.width then
        result.detail = ('%.2f'):format(result.opening.width)
        return result
    end
    if result.opening.height < capsule.standingHeight then
        result.reason, result.detail = reasons.THROUGH_TOO_LOW, ('%.2f'):format(result.opening.height)
        return result
    end
    if not ground then
        result.reason = reasons.THROUGH_NO_EXIT
        return result
    end
    result.valid, result.reason = true, reasons.OK
    result.score = settings.scores.OPEN
    return result
end

local classifyFront = function(origin, profile, front, airborne)
    local climb = candidate('CLIMB', false, reasons.WALLCLIMB_DENIED_NO_WALL)
    local ledgeCandidate = candidate('LEDGE', false, reasons.LEDGE_DENIED_NO_WALL)
    if airborne then
        local ledge = profile.airLedge
        if not ledge then return climb, ledgeCandidate end
        ledgeCandidate.ledge = ledge
        if not ledge.valid then
            ledgeCandidate.reason = ledge.reason
            return climb, ledgeCandidate
        end
        local ok, reason = Ledge.CanGrab(origin, ledge, origin.velocity and origin.velocity.z)
        ledgeCandidate.path = path(ledge.edge - ledge.wallDir * ledge.distance, ledge.edge, ledge.hang)
        if not ok then
            ledgeCandidate.reason = reason
            return climb, ledgeCandidate
        end
        ledgeCandidate.valid, ledgeCandidate.reason = true, reasons.OK
        ledgeCandidate.score = score('LEDGE', 1.0)
        climb.reason = reasons.LEDGE_DENIED_STATE
        return climb, ledgeCandidate
    end
    if not front or not front.valid then return climb, ledgeCandidate end
    local ledge = Ledge.Find(origin, front.wallDir, wallclimb.minHeight, wallclimb.maxHeight)
    profile.frontLedge = ledge
    climb.ledge, ledgeCandidate.ledge = ledge, ledge
    if front.distance > wallclimb.maxDistance + detection.distanceTolerance then
        climb.reason, climb.detail = reasons.WALLCLIMB_DENIED_TOO_FAR, ('%.2f'):format(front.distance)
        ledgeCandidate.reason, ledgeCandidate.detail = climb.reason, climb.detail
        return climb, ledgeCandidate
    end
    if front.angle > wallclimb.maxApproachAngle + detection.angleTolerance then
        climb.reason, climb.detail = reasons.WALLCLIMB_DENIED_BAD_ANGLE, ('%.0f'):format(front.angle)
        ledgeCandidate.reason, ledgeCandidate.detail = climb.reason, climb.detail
        return climb, ledgeCandidate
    end
    if not ledge.valid then
        climb.reason, climb.detail = reasons.WALLCLIMB_DENIED_NO_LEDGE, ledge.reason
        ledgeCandidate.reason, ledgeCandidate.detail = ledge.reason, nil
        return climb, ledgeCandidate
    end
    local entry = Vec.WithZ(front.point, origin.feetZ)
    local quality = 1.0 - math.abs(ledge.height - (wallclimb.minHeight + wallclimb.slowMaxHeight) * 0.5) / wallclimb.maxHeight
    if ledge.climbable then
        climb.valid, climb.reason = true, reasons.OK
        climb.path = path(entry, ledge.edge, ledge.landing)
        climb.score = score('CLIMB', quality)
        ledgeCandidate.reason = reasons.CLIMB_PREFERRED
    else
        climb.reason = reasons.CLIMB_NOT_CLIMBABLE
        ledgeCandidate.valid, ledgeCandidate.reason = true, reasons.OK
        ledgeCandidate.path = path(entry, ledge.edge, ledge.hang)
        ledgeCandidate.score = score('LEDGE', quality)
    end
    return climb, ledgeCandidate
end

local classifyWall = function(scan, airborne)
    local left, right = scan.walls.left, scan.walls.right
    local side
    if left and left.valid and right and right.valid then
        side = left.distance <= right.distance and left or right
    else
        side = (left and left.valid and left) or (right and right.valid and right) or nil
    end
    local front = scan.walls.front
    local wall = side or (airborne and front and front.valid and front) or nil
    if not wall then return candidate('WALL', false, reasons.WALL_NONE) end
    local result = candidate('WALL', true)
    result.wall = wall
    result.path = path(wall.point, wall.point + wall.tangent, wall.point + wall.tangent * 2.0)
    result.score = score('WALL', 1.0 - Vec.Clamp(wall.angle / wallrun.maxApproachAngle, 0.0, 1.0))
    return result
end

local classifyBalance = function(scan)
    local surface = scan.surface
    if not surface or not surface.valid or surface.wide or not surface.elevated then return candidate('BALANCE', false, reasons.BALANCE_DENIED_NO_SURFACE) end
    local result = candidate('BALANCE', true)
    result.score = settings.scores.BALANCE
    return result
end

local priorityIndex = {}
for i = 1, #settings.priority do priorityIndex[settings.priority[i]] = i end

Traversal.Rank = function(list, margin)
    local valid = {}
    for i = 1, #list do
        if list[i].valid and list[i].score then valid[#valid + 1] = list[i] end
    end
    table.sort(valid, function(a, b)
        local ka, kb = math.floor(a.score / margin), math.floor(b.score / margin)
        if ka ~= kb then return ka > kb end
        return (priorityIndex[a.type] or #settings.priority + 1) < (priorityIndex[b.type] or #settings.priority + 1)
    end)
    return valid
end

local draw = function(profile)
    if not Rays.IsEnabled() then return end
    local lines = {}
    local underCandidate = profile.byType.UNDER
    if underCandidate and underCandidate.samples then
        local previous
        for i = 1, #underCandidate.samples do
            local sample = underCandidate.samples[i]
            local knee = sample.point + Vec.Up * heights.knees
            if previous then lines[#lines + 1] = { previous, knee, 'path' } end
            previous = knee
            if sample.underside then Rays.Cross(lines, sample.underside, 'face') end
        end
        if underCandidate.path and underCandidate.path.exit then Rays.Cross(lines, underCandidate.path.exit, 'landing') end
    end
    local throughCandidate = profile.byType.THROUGH
    if throughCandidate and throughCandidate.open and throughCandidate.path and throughCandidate.path.cross then
        local cross = throughCandidate.path.cross + Vec.Up * heights.waist
        local right = Vec.Right(profile.dir)
        lines[#lines + 1] = { cross - right * throughCandidate.opening.left, cross + right * throughCandidate.opening.right, 'target' }
        if throughCandidate.path.exit then Rays.Cross(lines, throughCandidate.path.exit, 'landing') end
    end
    Rays.Shape('traversal', lines)
end

Traversal.Build = function(ctx, scan)
    local origin = scan.origin or ctx
    local layers = scan.layers or {}
    local obstacle = scan.obstacle or {}
    local front = scan.walls.front
    local profile = {
        valid = false,
        dir = scan.dir,
        layers = layers,
        frontDistance = obstacle.hit and obstacle.distance or nil,
        feetBlocked = layers.feet and layers.feet.hit or false,
        kneeBlocked = layers.knees and layers.knees.hit or false,
        waistBlocked = layers.waist and layers.waist.hit or false,
        chestBlocked = layers.chest and layers.chest.hit or false,
        headBlocked = layers.head and layers.head.hit or false,
        aboveHeadBlocked = layers.overhead and layers.overhead.hit or false,
        topFound = obstacle.topZ ~= nil,
        topZ = obstacle.topZ,
        topNormal = obstacle.topNormal,
        topSlope = obstacle.topNormal and math.deg(math.acos(Vec.Clamp(obstacle.topNormal.z, -1.0, 1.0))) or nil,
        obstacleHeight = obstacle.height,
        obstacleDepth = obstacle.depth,
        upperClearance = obstacle.topClearance,
        lowerClearance = nil,
        passageHeight = nil,
        passageDepth = nil,
        landingFound = obstacle.landing ~= nil,
        landingCoords = obstacle.landingPoint,
        landingClear = obstacle.landing ~= nil and obstacle.landing.clear == true,
        ledgeFound = false,
        ledgeCoords = nil,
        ledgeHeight = nil,
        wallNormal = front and front.valid and front.normal or obstacle.normal,
        wallDistance = front and front.valid and front.distance or obstacle.distance,
        airLedge = scan.ledge,
        traversalType = 'NONE',
        byType = {},
    }
    local detailed = Rays.IsEnabled()
    if ctx.grounded and detailed then
        profile.leftClearance, profile.rightClearance = lateral(Raycast.AtHeight(origin, 'waist'), scan.dir, settings.lateralProbe)
    end

    local list = {}
    local add = function(entry)
        list[#list + 1] = entry
        profile.byType[entry.type] = entry
    end

    if ctx.grounded then
        local over = classifyOver(profile, obstacle)
        add(over)
        if over.type == 'THROUGH' then
            add(candidate('OVER', false, reasons.OBSTACLE_TOP_BLOCKED, ('%.2f'):format(obstacle.topClearance or 0.0)))
        elseif detailed then
            local throughStarted = Profiler.Start()
            add(classifyOpening(origin, scan.dir, layers))
            Profiler.Stop('through', throughStarted)
        else
            add(candidate('THROUGH', false, reasons.THROUGH_NO_FRAME, 'lazy'))
        end
        local underStarted = Profiler.Start()
        local underCandidate = classifyUnder(origin, scan.dir, layers, profile)
        Profiler.Stop('under', underStarted)
        add(underCandidate)
        profile.passageHeight = underCandidate.passageHeight
        profile.passageDepth = underCandidate.passageDepth
        profile.lowerClearance = underCandidate.passageHeight
        add(classifyBalance(scan))
    end
    local climb, ledgeCandidate = classifyFront(origin, profile, front, ctx.airborne)
    if ctx.grounded then add(climb) end
    add(ledgeCandidate)
    add(classifyWall(scan, ctx.airborne))

    local ledge = ledgeCandidate.ledge
    if ledge and ledge.topZ then
        profile.ledgeFound = ledge.valid == true
        profile.ledgeCoords = ledge.edge
        profile.ledgeHeight = ledge.height
    end

    profile.candidates = list
    profile.ranked = Traversal.Rank(list, Config.Resolver.tieMargin)
    local best = profile.ranked[1]
    if best then
        profile.valid = true
        profile.traversalType = best.type
        profile.path = best.path
    end
    draw(profile)
    return profile
end

return Traversal
