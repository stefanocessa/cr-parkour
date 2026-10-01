local Vec = require 'client.core.vec'
local Movement = require 'client.core.movement'
local State = require 'client.core.state'
local Cooldown = require 'client.core.cooldowns'
local Raycast = require 'client.detection.raycast'
local Momentum = require 'client.systems.momentum'
local Animation = require 'client.systems.animation'
local Collision = require 'client.systems.collision'
local Damage = require 'client.systems.damage'
local DebugState = require 'client.debug.state'

local Slide = { name = 'slide', states = { Constants.States.SLIDING } }

local settings = Config.Slide
local under = Config.Under
local detection = Config.Detection
local gravity = Config.Physics.gravity
local body = Config.Body
local reasons = Constants.Reasons
local S = Constants.States
local lowBody = { 'feet', 'knees' }
local active = nil

local groundNormal = function(coords)
    local result = Raycast.Down(coords, body.rootHeight + settings.airborneCancel)
    if not Raycast.IsFloor(result) then return nil end
    return result.normal
end

local uphill = function(normal, dir)
    return normal ~= nil and Vec.Dot(Vec.Flat(normal), dir) < 0.0 and normal.z < settings.minUphillNormalZ
end

Slide.Evaluate = function(ctx)
    if not settings.enabled then return false, reasons.SLIDE_DENIED_DISABLED end
    if not State.CanTransition(S.SLIDING) then return false, reasons.SLIDE_DENIED_STATE end
    if not ctx.grounded or ctx.ragdoll then return false, reasons.SLIDE_DENIED_NOT_GROUNDED end
    if not Cooldown.CanUse(Slide.name, ctx.now) then return false, reasons.SLIDE_DENIED_COOLDOWN end
    if ctx.speed2d < settings.minSpeed then return false, reasons.SLIDE_DENIED_LOW_SPEED end
    return true, reasons.OK, {}
end

Slide.Validate = function(ctx)
    if uphill(groundNormal(ctx.coords), ctx.moveDir) then return false, reasons.SLIDE_DENIED_SLOPE end
    if Collision.BodyBlocked(ctx.coords, ctx.moveDir, settings.frontBlockDistance, lowBody) then return false, reasons.SLIDE_DENIED_FRONT_BLOCKED end
    return true, reasons.OK
end

local curveAt = function(meta, phase)
    local curve = meta.curve
    local x = Vec.Clamp(phase, 0.0, 1.0) * (#curve - 1)
    local i = math.floor(x)
    if i >= #curve - 1 then return curve[#curve] end
    local f = x - i
    return curve[i + 1] * (1.0 - f) + curve[i + 2] * f
end

local phaseAt = function(meta, distance)
    local curve = meta.curve
    if distance <= curve[1] then return 0.0 end
    for i = 1, #curve - 1 do
        if distance <= curve[i + 1] then
            local f = (distance - curve[i]) / math.max(curve[i + 1] - curve[i], Constants.Epsilon)
            return (i - 1 + f) / (#curve - 1)
        end
    end
    return 1.0
end

local fit = function(value, center, span)
    return Vec.Clamp(1.0 - math.abs(value - center) / math.max(span, Constants.Epsilon), 0.0, 1.0)
end

local reject = function(name, reason)
    return { name = name, reason = reason }
end

local planVariant = function(ctx, passage, name)
    local meta = Animation.Meta(name)
    if not meta or not meta.curve then return reject(name, 'no_metadata') end
    local spec = Animation.Resolve(name)
    if not spec then return reject(name, 'animation_not_loaded') end
    if passage.passageHeight < meta.minPassage - detection.heightTolerance then return reject(name, 'passage_too_low') end
    if ctx.speed2d < meta.minSpeed - detection.speedTolerance then return reject(name, 'speed_too_low') end
    if ctx.speed2d > meta.maxSpeed + detection.speedTolerance then return reject(name, 'speed_too_high') end

    local lowStart, lowEnd, stand = curveAt(meta, meta.lowStart), curveAt(meta, meta.lowEnd), curveAt(meta, meta.standPhase)
    local offset = math.max(0.0, lowStart - (passage.passageStart - under.entryMargin))
    if lowEnd - offset < passage.passageEnd + under.exitMargin then return reject(name, 'passage_too_long') end
    local travel = stand - offset
    local samples = passage.samples
    if samples[#samples].distance < travel - under.step then return reject(name, 'exit_too_short') end
    for i = 1, #samples do
        local sample = samples[i]
        if sample.distance > passage.passageEnd and sample.distance <= travel
            and sample.clearance < Config.TraversalCapsule.standingHeight - under.headroomTolerance then
            return reject(name, 'exit_blocked')
        end
    end

    local startPhase = phaseAt(meta, offset)
    local span = math.max(meta.standPhase - startPhase, Constants.Epsilon)
    local nominal = travel / (span * meta.duration)
    local rate = Vec.Clamp(math.max(ctx.speed2d, under.rate.standing) / nominal, under.rate.min, under.rate.max)
    local weights = under.score
    local value = weights.speed * fit(ctx.speed2d, nominal, weights.speedSpan)
        + weights.exit * Vec.Clamp(passage.exitLength / (travel - passage.passageEnd + Constants.Epsilon), 0.0, 1.0)
    return {
        name = name,
        meta = meta,
        spec = spec,
        score = value,
        startPhase = startPhase,
        rate = rate,
        travel = travel,
        duration = span * meta.duration * 1000.0 / rate,
    }
end

Slide.SelectUnder = function(ctx, passage)
    local list, best = {}, nil
    for i = 1, #under.pool do
        local plan = planVariant(ctx, passage, under.pool[i])
        list[#list + 1] = plan
        if plan.score and (not best or plan.score > best.score + Config.Vault.score.tieMargin) then best = plan end
    end
    DebugState.UnderVariants(list, best and best.name)
    return best, list
end

local underCandidate = function(scan)
    return scan.profile and scan.profile.byType.UNDER or nil
end

Slide.EvaluateUnder = function(ctx, scan)
    if not under.enabled then return false, reasons.SLIDE_DENIED_DISABLED end
    if not State.CanTransition(S.SLIDING) then return false, reasons.SLIDE_DENIED_STATE end
    if not ctx.grounded or ctx.ragdoll then return false, reasons.SLIDE_DENIED_NOT_GROUNDED end
    if not Cooldown.CanUse(Slide.name, ctx.now) then return false, reasons.SLIDE_DENIED_COOLDOWN end
    local passage = underCandidate(scan)
    if not passage then return false, reasons.UNDER_NO_BLOCKER end
    if not passage.valid then return false, passage.reason, nil, passage.detail end
    if not passage.path or not passage.path.valid then return false, reasons.TRAVERSAL_PATH_INVALID end
    local dir = scan.dir
    if ctx.inputDir == nil and ctx.speed2d < under.intentSpeed then return false, reasons.PARKOUR_DENIED_NO_INTENT end
    if Vec.Angle2d(ctx.moveDir, dir) > under.maxApproachAngle + detection.angleTolerance and ctx.speed2d >= under.intentSpeed then
        return false, reasons.UNDER_DENIED_BAD_ANGLE
    end
    local plan, list = Slide.SelectUnder(ctx, passage)
    if not plan then
        local first = list[1]
        return false, reasons.UNDER_DENIED_NO_VARIANT, nil, first and ('%s %s'):format(first.name, first.reason or '-')
    end
    return true, reasons.OK, { under = passage, plan = plan, direction = dir, score = passage.score, path = passage.path }
end

Slide.Verify = function(ctx, payload)
    if not payload.under or not ctx.grounded then return false end
    local passage = payload.under
    for i = 1, #passage.samples do
        local sample = passage.samples[i]
        if sample.underside then
            local check = Raycast.Up(sample.point + Vec.Up * Config.Heights.feet, Config.TraversalCapsule.standingHeight)
            return check.hit and math.abs(check.coords.z - sample.underside.z) <= detection.heightTolerance * 2.0
        end
    end
    return false
end

Slide.IsKinematic = function()
    return active ~= nil and active.under ~= nil
end

local buildRoute = function(ctx, payload)
    local plan = payload.plan
    local rootOffset = Vec.Clamp(ctx.coords.z - payload.under.samples[1].ground, body.rootHeight - Config.Vault.rootTolerance, body.rootHeight + Config.Vault.rootTolerance)
    local points = { { distance = 0.0, position = ctx.coords } }
    local samples = payload.under.samples
    for i = 1, #samples do
        if samples[i].distance >= plan.travel then break end
        points[#points + 1] = { distance = samples[i].distance, position = samples[i].point + Vec.Up * rootOffset }
    end
    local lastGround = samples[#points - 1] and samples[#points - 1].ground or samples[1].ground
    points[#points + 1] = { distance = plan.travel, position = Vec.WithZ(ctx.coords + payload.direction * plan.travel, lastGround + rootOffset) }
    return points
end

local routeAt = function(points, distance)
    for i = 2, #points do
        if distance <= points[i].distance then
            local a, b = points[i - 1], points[i]
            local f = (distance - a.distance) / math.max(b.distance - a.distance, Constants.Epsilon)
            return Vec.Lerp(a.position, b.position, f)
        end
    end
    return points[#points].position
end

local enterUnder = function(ctx, payload)
    local entry = Momentum.Capture(ctx)
    local plan = payload.plan
    Movement.Hold(ctx.ped)
    Collision.BeginTraversal(ctx.ped, 'UNDER', plan.duration)
    active = {
        under = payload.under,
        plan = plan,
        direction = payload.direction,
        entry = entry,
        route = buildRoute(ctx, payload),
        heading = ctx.heading,
        targetHeading = Vec.Heading(payload.direction),
        startedAt = ctx.now,
    }
    DebugState.UnderPlan(payload.under, plan)
    Animation.Play(plan.name, { duration = plan.duration, startPhase = plan.startPhase, rate = plan.rate })
end

local updateUnder = function(ctx)
    local t = Vec.Clamp((ctx.now - active.startedAt) / math.max(active.plan.duration, 1.0), 0.0, 1.0)
    active.heading = Movement.TurnHeading(active.heading, active.targetHeading, settings.turnGain, ctx.dt)
    Movement.Place(ctx.ped, Animation.Apply(routeAt(active.route, active.plan.travel * t), active.heading))
    if t < 1.0 then return nil end
    local direction = active.direction
    local exit = Momentum.Clamp(Momentum.Scale(Momentum.ProjectOnDirection(active.entry, direction), under.momentumKeep), under.minExitSpeed, nil, direction)
    local finalPosition = active.route[#active.route].position
    if not Collision.Ground(finalPosition, under.groundTolerance) then
        return { next = S.FALLING, velocity = exit.velocity, reason = reasons.SLIDE_END_BLOCKED }
    end
    return { next = ctx.sprintHeld and S.SPRINTING or S.RUNNING, velocity = exit.velocity, motion = true }
end

Slide.Enter = function(ctx, payload)
    if payload and payload.under then return enterUnder(ctx, payload) end
    local entry = Momentum.Capture(ctx)
    local direction = entry.direction or ctx.moveDir
    active = {
        direction = direction,
        speed = entry.speed2d * settings.entryKeep,
        heading = ctx.heading,
        targetHeading = Vec.Heading(direction),
        startedAt = ctx.now,
        slopeAt = 0,
        slope = 0.0,
        recovery = nil,
    }
    Animation.Play(settings.animations[settings.variant] or settings.animations.forward, { duration = settings.maxDuration })
end

local startRecovery = function(ctx)
    local kipUp = settings.kipUp
    local duration = Animation.SyncedDuration(settings.animations.kipUp, kipUp.duration)
    active.recovery = { startedAt = ctx.now, duration = duration }
    Animation.CrossFade(settings.animations.kipUp, { duration = duration })
    return nil
end

local updateRecovery = function(ctx)
    local recovery = active.recovery
    local done = ctx.now - recovery.startedAt >= recovery.duration or Animation.Reached('control')
    if done or (ctx.input.active and Animation.Reached('transition')) then
        return { velocity = Vec.WithZ(ctx.velocity, 0.0), motion = true }
    end
    Momentum.Drive(ctx.ped, ctx.velocity, Vec.WithZ(Vec.Zero, ctx.velocity.z), settings.kipUp.brake)
    return nil
end

local canRecover = function(ctx)
    return settings.kipUp.enabled and not ctx.input.active and active.speed <= settings.kipUp.maxSpeed
end

local sampleSlope = function(ctx)
    if ctx.now - active.slopeAt < settings.slopeInterval then return active.slope end
    active.slopeAt = ctx.now
    local normal = groundNormal(ctx.coords)
    active.slope = normal and -Vec.Dot(Vec.Flat(normal), active.direction) or 0.0
    return active.slope
end

Slide.Update = function(ctx)
    if active.under then return updateUnder(ctx) end
    if active.recovery then return updateRecovery(ctx) end

    local elapsed = ctx.now - active.startedAt
    local dir = active.direction
    local slope = sampleSlope(ctx)
    active.speed = active.speed - (settings.deceleration + slope * gravity * settings.slopeGravity) * ctx.dt
    active.speed = Vec.Clamp(active.speed, 0.0, settings.maxSpeed)

    if ctx.airborne and ctx.groundClearance > settings.airborneCancel then
        return { next = S.FALLING, velocity = dir * active.speed + Vec.Up * ctx.velocity.z }
    end

    local underCover = Collision.CeilingBlocked(ctx.coords)
    if underCover then active.speed = math.max(active.speed, settings.underSpeed) end

    if Collision.BodyBlocked(ctx.coords, dir, settings.frontBlockDistance, lowBody) then
        Damage.Emit('collision', { ability = Slide.name, speed = active.speed })
        if underCover then
            active.direction = Vec.Negate(dir)
            active.targetHeading = active.heading
            return nil
        end
        return { velocity = Vec.WithZ(Vec.Zero, ctx.velocity.z), reason = reasons.SLIDE_END_BLOCKED }
    end

    local finished = elapsed >= settings.maxDuration
        or (elapsed >= settings.minDuration and active.speed <= settings.exitSpeed and not underCover)
    if finished then
        if canRecover(ctx) then return startRecovery(ctx) end
        return { velocity = dir * active.speed, motion = true }
    end

    Momentum.Drive(ctx.ped, ctx.velocity, Vec.WithZ(dir * active.speed, ctx.velocity.z), Animation.Assist())
    active.heading = Movement.TurnHeading(active.heading, active.targetHeading, settings.turnGain, ctx.dt)
    SetEntityHeading(ctx.ped, active.heading)
    return nil
end

Slide.Exit = function()
    if active and active.under then Collision.EndTraversal() end
    active = nil
end

Slide.Recover = function()
    if not active then return nil end
    return active.direction * (active.under and under.minExitSpeed or settings.exitSpeed)
end

return Slide
