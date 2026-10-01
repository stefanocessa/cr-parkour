local Vec = require 'client.core.vec'
local State = require 'client.core.state'
local Context = require 'client.core.context'
local Movement = require 'client.core.movement'
local Cooldown = require 'client.core.cooldowns'
local Raycast = require 'client.detection.raycast'
local Landing = require 'client.detection.landing'
local Collision = require 'client.systems.collision'
local Momentum = require 'client.systems.momentum'
local Animation = require 'client.systems.animation'
local Rays = require 'client.debug.rays'
local DebugState = require 'client.debug.state'

local Vault = { name = 'vault', states = { Constants.States.VAULTING } }

local settings = Config.Vault
local weights = settings.score
local detection = Config.Detection
local body = Config.Body
local heights = Config.Heights
local panel = Config.DebugPanel
local reasons = Constants.Reasons
local S = Constants.States
local active = nil

local heightBand = function(height)
    local bands = settings.heightBands
    if height <= bands.low then return 'low' end
    if height <= bands.medium then return 'medium' end
    return 'high'
end

local fit = function(value, center, span)
    return Vec.Clamp(1.0 - math.abs(value - center) / math.max(span, Constants.Epsilon), 0.0, 1.0)
end

local designHeight = function(meta)
    return body.rootHeight + meta.lift - settings.liftClearance
end

local clipSpeed = function(meta)
    return meta.crossDistance / math.max(meta.cross * meta.duration, Constants.Epsilon)
end

local speedFit = function(speed, meta)
    local nominal = clipSpeed(meta)
    local low, high = nominal * settings.rate.min, nominal * settings.rate.max
    if speed >= low and speed <= high then return 1.0 end
    return fit(speed, speed < low and low or high, weights.speedSpan)
end

local runway = function(obstacle, distance)
    local base = obstacle.depth * 0.5 + settings.landingOffset
    local extra = distance - base
    local from = obstacle.landingPoint
    if extra <= Constants.Epsilon then return from end
    for i = 1, #settings.runoutHeights do
        local origin = Vec.WithZ(from, from.z + heights[settings.runoutHeights[i]])
        if Raycast.Direction(origin, obstacle.intoDir, extra).hit then return nil end
    end
    local ground = Landing.FindGround(from + obstacle.intoDir * extra, from.z + settings.runoutStepTolerance, from.z - settings.runoutStepTolerance)
    return ground and ground.coords or nil
end

local reject = function(name, reason)
    return { name = name, reason = reason }
end

local evaluateClip = function(ctx, obstacle, name, measure)
    local meta = Animation.Meta(name)
    if not meta then return reject(name, 'no_metadata') end
    local spec = Animation.Resolve(name)
    if not spec then return reject(name, 'animation_not_loaded') end
    local tolerance = detection.heightTolerance
    if measure.height < meta.minHeight - tolerance or measure.height > meta.maxHeight + tolerance then return reject(name, 'height_outside_range') end
    if measure.depth < (meta.minDepth or 0.0) - tolerance or measure.depth > (meta.maxDepth or settings.maxDepth) + tolerance then return reject(name, 'depth_outside_range') end
    if measure.speed < (meta.minSpeed or 0.0) - detection.speedTolerance then return reject(name, 'speed_too_low') end
    if meta.maxSpeed and measure.speed > meta.maxSpeed + detection.speedTolerance then return reject(name, 'speed_too_high') end
    if measure.clearance < (meta.clearanceRequired or 0.0) - tolerance then return reject(name, 'clearance_too_low') end
    if meta.minAngle and measure.angle < meta.minAngle then return reject(name, 'angle_too_small') end
    if meta.maxAngle and measure.angle > meta.maxAngle + detection.angleTolerance then return reject(name, 'angle_too_large') end
    if meta.requiresAirborne and not ctx.airborne then return reject(name, 'requires_airborne') end

    local base = obstacle.depth * 0.5 + settings.landingOffset
    local landDistance = Vec.Clamp(meta.touchDistance, base, base + settings.maxRunout)
    local landing = runway(obstacle, landDistance)
    if not landing then return reject(name, 'runout_blocked') end

    local design = designHeight(meta)
    local depthCenter = ((meta.minDepth or 0.0) + (meta.maxDepth or settings.maxDepth)) * 0.5
    local depthSpan = math.max(((meta.maxDepth or settings.maxDepth) - (meta.minDepth or 0.0)) * 0.5, detection.distanceTolerance)
    local approach = measure.distance <= meta.crossDistance and 1.0 or fit(measure.distance, meta.crossDistance, weights.approachSpan)
    local value = weights.height * fit(measure.height, design, weights.heightSpan)
        + weights.depth * fit(measure.depth, depthCenter, depthSpan)
        + weights.speed * speedFit(measure.speed, meta)
        + weights.angle * fit(measure.angle, meta.preferredAngle or 0.0, weights.angleSpan)
        + weights.approach * approach
    return { name = name, meta = meta, spec = spec, score = value, landing = landing, landDistance = landDistance, design = design }
end

Vault.Select = function(ctx, obstacle)
    local measure = {
        height = obstacle.height,
        depth = obstacle.depth,
        speed = ctx.speed2d,
        angle = obstacle.approachAngle,
        distance = Vec.Distance2d(ctx.coords, obstacle.center),
        clearance = obstacle.topClearance or Config.TraversalCapsule.standingHeight,
    }
    local list, advanced, generic = {}, nil, nil
    for i = 1, #settings.pool do
        local clip = evaluateClip(ctx, obstacle, settings.pool[i], measure)
        list[#list + 1] = clip
        if clip.score then
            if clip.meta.generic then
                if not generic or clip.score > generic.score + weights.tieMargin then generic = clip end
            elseif clip.score >= weights.minAdvanced and (not advanced or clip.score > advanced.score + weights.tieMargin) then
                advanced = clip
            end
        end
    end
    local selected = generic
    if advanced and (not generic or advanced.score + weights.advancedBonus >= generic.score) then selected = advanced end
    DebugState.VaultCandidates(list, selected and selected.name, measure)
    return selected, list
end

local firstRejection = function(list)
    for i = 1, #list do
        local meta = Animation.Meta(list[i].name)
        if list[i].reason and meta and meta.generic then return ('%s %s'):format(list[i].name, list[i].reason) end
    end
    return list[1] and list[1].reason
end

Vault.BuildContext = function(ctx, obstacle, clip, speed)
    local meta = clip.meta
    local band = heightBand(obstacle.height)
    local correction = settings.HeightCorrection[band] or 0.0
    local verticalOffset = meta.verticalOffset or 0.0
    local rootOffset = Vec.Clamp(ctx.coords.z - obstacle.groundZ, body.rootHeight - settings.rootTolerance, body.rootHeight + settings.rootTolerance)
    local entityLift = Vec.Clamp(obstacle.height - clip.design, -settings.maxLower, settings.maxRaise) + correction + verticalOffset
    local apexZ = obstacle.groundZ + rootOffset + entityLift
    local center = obstacle.center + obstacle.intoDir * (meta.forwardOffset or 0.0)
    local distance = Vec.Distance2d(ctx.coords, center)
    local startPhase = meta.cross * (1.0 - math.min(1.0, distance / math.max(meta.crossDistance, Constants.Epsilon)))
    local rate = Vec.Clamp(math.max(speed, settings.rate.standing) / clipSpeed(meta), settings.rate.min, settings.rate.max)
    local span = math.max(meta.touch - startPhase, Constants.Epsilon)
    return {
        animation = clip.name,
        dict = clip.spec.dict,
        clip = clip.spec.clip,
        score = clip.score,
        obstacleHeight = obstacle.height,
        obstacleDepth = obstacle.depth,
        topZ = obstacle.topZ,
        groundZ = obstacle.groundZ,
        landingZ = clip.landing.z,
        approachSpeed = speed,
        frontFace = obstacle.frontEdge,
        topSurface = obstacle.top,
        centerPoint = obstacle.center,
        landingPoint = clip.landing,
        start = ctx.coords,
        apex = Vec.WithZ(center, apexZ),
        target = clip.landing + Vec.Up * rootOffset,
        targetZ = apexZ,
        bodyPeakZ = apexZ + meta.lift,
        design = clip.design,
        lift = meta.lift,
        entityLift = entityLift,
        rootOffset = rootOffset,
        verticalOffset = verticalOffset,
        correction = correction,
        band = band,
        startPhase = startPhase,
        rate = rate,
        cross = meta.cross,
        split = (meta.cross - startPhase) / span,
        duration = span * meta.duration * 1000.0 / rate,
    }
end

local pathFor = function(context)
    return Movement.Through(context.start, context.apex, context.target, context.split, context.duration, Movement.Linear)
end

local drawGeometry = function(context, tween)
    if not Rays.IsEnabled() then return end
    local lines = {}
    Rays.Cross(lines, context.frontFace, 'face')
    if context.path then Rays.Cross(lines, context.path.entry, 'valid') end
    Rays.Cross(lines, context.topSurface, 'top')
    Rays.Cross(lines, context.centerPoint, 'top')
    Rays.Cross(lines, context.landingPoint, 'landing')
    Rays.Cross(lines, context.apex, 'target')
    lines[#lines + 1] = { context.apex, context.centerPoint, 'target' }
    local previous = tween.from
    for i = 1, panel.pathSegments do
        local point = Movement.Point(tween, i / panel.pathSegments)
        lines[#lines + 1] = { previous, point, 'path' }
        previous = point
    end
    Rays.Shape('vault', lines)
    DebugState.VaultContext(context)
end

local traversalCandidate = function(scan)
    local profile = scan.profile
    if not profile then return nil end
    local opening = profile.byType.THROUGH
    if opening and opening.window then return opening end
    return profile.byType.OVER
end

Vault.Candidate = traversalCandidate

Vault.Evaluate = function(ctx, scan)
    if not settings.enabled then return false, reasons.VAULT_DENIED_DISABLED end
    if not State.CanTransition(S.VAULTING) then return false, reasons.VAULT_DENIED_STATE end
    if not ctx.grounded then return false, reasons.VAULT_DENIED_NOT_GROUNDED end
    if not Cooldown.CanUse(Vault.name, ctx.now) then return false, reasons.VAULT_DENIED_COOLDOWN end

    local candidate = traversalCandidate(scan)
    if not candidate then return false, reasons.VAULT_DENIED_NO_OBSTACLE end
    if not candidate.valid then return false, candidate.reason, nil, candidate.detail end
    if not candidate.path or not candidate.path.valid then return false, reasons.TRAVERSAL_PATH_INVALID end

    local obstacle = scan.obstacle
    if ctx.speed2d < settings.minSpeed then return false, reasons.VAULT_DENIED_LOW_SPEED end
    if not Context.HasIntent(ctx, obstacle.intoDir, settings.intentSpeed, settings.intentDot) then return false, reasons.PARKOUR_DENIED_NO_INTENT end
    if Cooldown.SameTarget(Vault.name, obstacle.frontEdge, obstacle.normal, ctx.now) then return false, reasons.SAME_OBSTACLE_BLOCKED end

    local clip, list = Vault.Select(ctx, obstacle)
    if not clip then return false, reasons.VAULT_DENIED_NO_ANIMATION, nil, firstRejection(list) end

    if Rays.IsEnabled() then
        local context = Vault.BuildContext(ctx, obstacle, clip, ctx.speed2d)
        context.path = candidate.path
        drawGeometry(context, pathFor(context))
    end

    return true, reasons.OK, {
        obstacle = obstacle,
        direction = obstacle.intoDir,
        clip = clip,
        score = clip.score,
        path = candidate.path,
        traversal = candidate.type,
    }
end

Vault.Score = function(payload)
    return payload.score
end

Vault.Verify = function(ctx, payload)
    local obstacle = payload.obstacle
    if not ctx.grounded then return false end
    local distance = Vec.Distance2d(ctx.coords, obstacle.frontEdge)
    if distance > settings.maxDistance + detection.distanceTolerance + detection.persistDistance then return false end
    if Cooldown.SameTarget(Vault.name, obstacle.frontEdge, obstacle.normal, ctx.now) then return false end
    local probe = Raycast.Direction(Vec.WithZ(ctx.coords, obstacle.edgeZ - detection.persistProbeBelow), obstacle.intoDir, distance + detection.persistDistance)
    if not Raycast.IsWall(probe) then return false end
    local normal = Vec.Normalize2d(probe.normal)
    return normal ~= nil and Vec.Dot(normal, obstacle.normal) >= detection.persistDot
end

Vault.Enter = function(ctx, payload)
    local obstacle = payload.obstacle
    local clip = payload.clip
    local entry = Momentum.Capture(ctx)
    local context = Vault.BuildContext(ctx, obstacle, clip, entry.speed2d)
    local tween = pathFor(context)

    context.path = payload.path
    Cooldown.Remember(Vault.name, obstacle.frontEdge, obstacle.normal, ctx.now)
    Movement.Hold(ctx.ped)
    Collision.BeginTraversal(ctx.ped, payload.traversal == 'THROUGH' and 'THROUGH' or 'OVER', context.duration)
    active = {
        payload = payload,
        context = context,
        target = context.target,
        entry = entry,
        startHeading = ctx.heading,
        heading = Vec.Heading(payload.direction),
        startedAt = ctx.now,
        tween = tween,
    }
    drawGeometry(context, tween)
    DebugState.SetReason('vault', reasons.VAULT_STYLE, clip.name)
    Animation.Play(clip.name, { duration = context.duration, startPhase = context.startPhase, rate = context.rate })
end

Vault.Context = function()
    return active and active.context
end

Vault.Approaching = function(ctx, scan)
    local candidate = traversalCandidate(scan)
    if not ctx.grounded or not candidate or not candidate.approaching then return false end
    return Context.HasIntent(ctx, scan.obstacle.intoDir, settings.intentSpeed, settings.intentDot)
end

Vault.Update = function(ctx)
    local position, t = Movement.Sample(active.tween)
    local align = Vec.Clamp(t / Animation.EventTime('assist'), 0.0, 1.0)
    Movement.Place(ctx.ped, Animation.Apply(position, Movement.LerpHeading(active.startHeading, active.heading, align)))
    if t < 1.0 then return nil end

    local direction = active.payload.direction
    local exit = Momentum.Clamp(Momentum.Scale(Momentum.ProjectOnDirection(active.entry, direction), settings.momentumKeep), settings.minExitSpeed, nil, direction)
    if not Collision.Ground(active.target, settings.groundTolerance) then
        return { next = S.FALLING, velocity = exit.velocity, reason = reasons.VAULT_END_AIRBORNE }
    end
    local controlAt = active.startedAt + active.tween.duration * Animation.EventTime('control')
    local pressedAt = Context.PressedAt('jump')
    if pressedAt and pressedAt >= controlAt then
        Context.Consume('jump', ctx.now - controlAt)
        return { next = S.JUMPING, velocity = exit.velocity + Vec.Up * settings.jumpOutVelocity }
    end
    return { next = ctx.sprintHeld and S.SPRINTING or S.RUNNING, velocity = exit.velocity, motion = true }
end

Vault.Recover = function()
    if not active then return nil end
    return active.payload.direction * settings.minExitSpeed
end

Vault.Exit = function()
    active = nil
    Collision.EndTraversal()
end

return Vault
