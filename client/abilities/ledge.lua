local Vec = require 'client.core.vec'
local State = require 'client.core.state'
local Movement = require 'client.core.movement'
local Cooldown = require 'client.core.cooldowns'
local Ledge = require 'client.detection.ledge'
local Momentum = require 'client.systems.momentum'
local Animation = require 'client.systems.animation'
local Camera = require 'client.systems.camera'
local Collision = require 'client.systems.collision'
local DebugState = require 'client.debug.state'

local LedgeAbility = { name = 'ledge', states = { Constants.States.LEDGE_GRAB, Constants.States.LEDGE_HANG } }

local settings = Config.Ledge
local hopSettings = Config.Ledge.jump
local input = Config.Input
local reasons = Constants.Reasons
local S = Constants.States
local align = settings.handAlign
local bones = Constants.Bones
local lastDrop = 0
local active = nil
local placed = nil
local corrections = {}

local clipKey = function(name)
    local spec = Animation.Resolve(name)
    return spec and (spec.dict .. '/' .. spec.clip) or name
end

local correctionFor = function(key)
    if not corrections[key] then
        local seed = corrections[clipKey(settings.animation.idle)]
        corrections[key] = { up = seed and seed.up or 0.0, out = seed and seed.out or 0.0, errUp = 0.0, errOut = 0.0, correctingUp = false, correctingOut = false }
    end
    return corrections[key]
end

local currentKey = function()
    local state = Animation.State()
    if not state or not state.dict then return nil end
    return state.dict .. '/' .. state.clip
end

LedgeAbility.Adjust = function(ledge, position, name)
    if not align.enabled then return position end
    local key = name and clipKey(name) or currentKey()
    if not key then return position end
    local correction = correctionFor(key)
    return position + Vec.Up * correction.up + ledge.normal * correction.out
end

local hysteresis = function(engaged, err)
    local magnitude = math.abs(err)
    if engaged then return magnitude > align.deadband end
    return magnitude > align.tolerance
end

local learn = function(ctx, ledge)
    local key = currentKey()
    if not align.enabled or not key or not Animation.IsPlaying() then return end
    local correction = correctionFor(key)
    local left = GetPedBoneCoords(ctx.ped, bones.leftHand, 0.0, 0.0, 0.0)
    local right = GetPedBoneCoords(ctx.ped, bones.rightHand, 0.0, 0.0, 0.0)
    local hands = (left + right) * 0.5
    correction.errUp = ledge.topZ + align.heightOffset - hands.z
    correction.errOut = align.wallDistance - Vec.Dot(Vec.Flat(hands - ledge.edge), ledge.normal)
    local gain = Vec.Clamp(align.gain * ctx.dt, 0.0, 1.0)
    correction.correctingUp = hysteresis(correction.correctingUp, correction.errUp)
    correction.correctingOut = hysteresis(correction.correctingOut, correction.errOut)
    if correction.correctingUp then
        correction.up = Vec.Clamp(correction.up + correction.errUp * gain, -align.maxCorrection, align.maxCorrection)
    end
    if correction.correctingOut then
        correction.out = Vec.Clamp(correction.out + correction.errOut * gain, -align.maxCorrection, align.maxCorrection)
    end
    DebugState.LedgeHands(key, correction, hands)
end

LedgeAbility.Corrections = function()
    return corrections
end

LedgeAbility.Evaluate = function(ctx, scan)
    if not settings.enabled then return false, reasons.LEDGE_DENIED_DISABLED end
    if not State.CanTransition(S.LEDGE_GRAB) then return false, reasons.LEDGE_DENIED_STATE end
    if ctx.now - lastDrop < settings.regrabCooldown then return false, reasons.LEDGE_DENIED_COOLDOWN end
    if not Cooldown.CanUse(LedgeAbility.name, ctx.now) then return false, reasons.LEDGE_DENIED_COOLDOWN end

    local ledge = scan.ledge
    local ok, reason = Ledge.CanGrab(ctx, ledge, ctx.velocity.z)
    if not ok then return false, reason end
    if Vec.Dot(ctx.approachDir, ledge.wallDir) < settings.minApproachDot then return false, reasons.LEDGE_DENIED_BAD_ANGLE end
    return true, reasons.OK, ledge
end

LedgeAbility.Play = function(name, options)
    Animation.CrossFade(name, options)
    DebugState.LedgeAnimation(Animation.State())
end

local smooth = function(ctx, ledge, target)
    if not placed then return target end
    local delta = target - placed.position
    local normalError = Vec.Dot(Vec.Flat(delta), ledge.normal)
    local rest = delta - ledge.normal * normalError
    if math.abs(normalError) > settings.driftTolerance then
        local limit = settings.driftRate * ctx.dt
        normalError = Vec.Clamp(normalError, -limit, limit)
    else
        normalError = 0.0
    end
    return placed.position + rest + ledge.normal * normalError
end

LedgeAbility.Place = function(ctx, ledge, position, heading, options)
    options = options or {}
    local target = options.adjust and LedgeAbility.Adjust(ledge, position) or position
    if options.smooth then target = smooth(ctx, ledge, target) end
    local moved = not placed or #(target - placed.position) > settings.placeEpsilon
        or math.abs(Movement.HeadingDelta(placed.heading, heading)) > settings.headingEpsilon
    if moved then
        Movement.Place(ctx.ped, Animation.Apply(target, heading))
        placed = { position = target, heading = heading, coords = GetEntityCoords(ctx.ped) }
    end
    if options.adjust then learn(ctx, ledge) end
    DebugState.Ledge(ledge, heading, target)
end

LedgeAbility.Displaced = function(ctx)
    return placed ~= nil and placed.coords ~= nil and #(ctx.coords - placed.coords) > settings.pushTolerance
end

LedgeAbility.Enter = function(ctx, ledge, state)
    Movement.Hold(ctx.ped)
    if state == S.LEDGE_GRAB then
        placed = nil
        ledge.entrySpeed = Momentum.Capture(ctx).speed2d
        active = {
            ledge = ledge,
            startHeading = ctx.heading,
            heading = ctx.heading,
            tween = Movement.Tween(ctx.coords, LedgeAbility.Adjust(ledge, ledge.hang, settings.animation.idle), nil, settings.grabDuration, Movement.EaseOut),
        }
        LedgeAbility.Play(settings.animation.grab, { duration = settings.grabDuration })
        Collision.BeginTraversal(ctx.ped, 'LEDGE', settings.grabDuration)
        Camera.Shake('ledgeGrab')
        return
    end
    Collision.EndTraversal()
    active = active or {}
    active.ledge = ledge
    active.heading = ledge.heading
    active.hangSince = active.hangSince or ctx.now
    active.checkedAt = ctx.now
    active.invalidSince = nil
    LedgeAbility.Play(settings.animation.idle)
end

LedgeAbility.Current = function()
    return active and active.ledge
end

LedgeAbility.HangElapsed = function(now)
    return active and active.hangSince and now - active.hangSince or 0
end

LedgeAbility.CanClimbForward = function(ctx)
    return settings.climbWithForward and State.Is(S.LEDGE_HANG) and active ~= nil and active.hangSince ~= nil
        and ctx.now - active.hangSince >= settings.minHangMs
        and ctx.input.forward >= settings.climbForwardThreshold
end

LedgeAbility.ClimbFrom = function(ledge)
    if not ledge.climbable then
        local reason = reasons.CLIMB_DENIED_LANDING_BLOCKED
        if not ledge.headClear then
            reason = reasons.CLIMB_DENIED_HEAD_BLOCKED
        elseif not ledge.landing then
            reason = reasons.CLIMB_DENIED_NO_LANDING
        end
        return { hold = true, reason = reason }
    end
    return { next = S.CLIMBING, payload = ledge }
end

LedgeAbility.DropFrom = function(ledge, reason)
    lastDrop = GetGameTimer()
    return { next = S.FALLING, velocity = ledge.normal * settings.dropPush, reason = reason }
end

LedgeAbility.Hopping = function()
    return active ~= nil and active.hop ~= nil
end

local hopTarget = function(ledge, side)
    if side ~= 0 then
        local animation = side > 0 and settings.animation.jumpRight or settings.animation.jumpLeft
        local meta = Animation.Meta(animation)
        if not meta then return nil, reasons.ANIM_MISSING end
        local target = Ledge.FindSide(ledge, side, math.abs(meta.side))
        if not target.valid then return nil, target.reason end
        return target, animation, meta
    end
    local target = Ledge.FindUp(ledge, hopSettings.upMin, hopSettings.powerMax)
    if not target.valid then return nil, target.reason end
    local animation = target.rise <= hopSettings.upMax + Config.Detection.heightTolerance and settings.animation.jumpUp or settings.animation.jumpUpPower
    local meta = Animation.Meta(animation)
    if not meta then return nil, reasons.ANIM_MISSING end
    return target, animation, meta
end

LedgeAbility.Hop = function(ctx, side)
    if not hopSettings.enabled or not active or not active.ledge or active.hop or not placed then return false, reasons.LEDGE_JUMP_DENIED_NO_TARGET end
    local target, animation, meta = hopTarget(active.ledge, side)
    if not target then return false, animation end
    target.entrySpeed = active.ledge.entrySpeed
    local destination = LedgeAbility.Adjust(target, target.hang, settings.animation.idle)
    active.hop = {
        target = target,
        animation = animation,
        from = placed.position,
        to = destination - Vec.Up * (meta.rise or 0.0),
        startHeading = active.heading,
        startedAt = ctx.now,
        duration = meta.duration * 1000.0,
    }
    LedgeAbility.Play(animation, { duration = active.hop.duration })
    return true, side ~= 0 and reasons.LEDGE_JUMP_SIDE or reasons.LEDGE_JUMP_UP
end

local finishHop = function(ctx)
    local target = active.hop.target
    active.hop = nil
    active.ledge = target
    active.heading = target.heading
    active.hangSince = ctx.now
    active.checkedAt = ctx.now
    active.invalidSince = nil
    placed = nil
    LedgeAbility.Play(settings.animation.idle, { blendIn = Config.Animations.instantBlend })
    LedgeAbility.Place(ctx, target, target.hang, target.heading, { adjust = true })
    return nil
end

local updateHop = function(ctx)
    local hop = active.hop
    local t = Vec.Clamp((ctx.now - hop.startedAt) / math.max(hop.duration, 1.0), 0.0, 1.0)
    local e = Movement.EaseInOut(t)
    active.heading = Movement.LerpHeading(hop.startHeading, hop.target.heading, e)
    LedgeAbility.Place(ctx, hop.target, Vec.Lerp(hop.from, hop.to, e), active.heading)
    if t < 1.0 then return nil end
    return finishHop(ctx)
end

local validate = function(ctx)
    if LedgeAbility.Displaced(ctx) then return LedgeAbility.DropFrom(active.ledge, reasons.LEDGE_DISPLACED) end
    if ctx.now - active.checkedAt < settings.validateInterval then return nil end
    active.checkedAt = ctx.now
    local check = Ledge.Follow(active.ledge, active.ledge.edge)
    if check.valid then
        active.invalidSince = nil
        return nil
    end
    active.invalidSince = active.invalidSince or ctx.now
    if ctx.now - active.invalidSince < settings.invalidGraceMs then return nil end
    return LedgeAbility.DropFrom(active.ledge, reasons.LEDGE_INVALIDATED)
end

LedgeAbility.Validate = function(ctx)
    if not active or not active.checkedAt then return nil end
    return validate(ctx)
end

local updateGrab = function(ctx)
    local position, t = Movement.Sample(active.tween)
    active.heading = Movement.LerpHeading(active.startHeading, active.ledge.heading, active.tween.ease(t))
    LedgeAbility.Place(ctx, active.ledge, position, active.heading)
    if t < 1.0 then return nil end
    return { next = S.LEDGE_HANG, payload = active.ledge }
end

local updateHang = function(ctx)
    if active.hop then return updateHop(ctx) end
    local ledge = active.ledge
    local invalid = validate(ctx)
    if invalid then return invalid end
    active.heading = Movement.TurnHeading(active.heading, ledge.heading, settings.alignGain, ctx.dt)
    LedgeAbility.Place(ctx, ledge, ledge.hang, active.heading, { adjust = true, smooth = true })
    if math.abs(ctx.input.side) > input.deadzone then
        return { next = S.LEDGE_MOVE, payload = ledge }
    end
    return nil
end

LedgeAbility.Update = function(ctx, state)
    if state == S.LEDGE_GRAB then return updateGrab(ctx) end
    return updateHang(ctx)
end

LedgeAbility.Recover = function()
    if not active or not active.ledge then return nil end
    active.hop = nil
    lastDrop = GetGameTimer()
    return active.ledge.normal * settings.dropPush
end

LedgeAbility.Exit = function(nextState)
    Collision.EndTraversal()
    if nextState == S.LEDGE_HANG or nextState == S.LEDGE_MOVE then return end
    active = nil
    placed = nil
    DebugState.Ledge(nil)
    DebugState.LedgeCorrections(corrections)
end

LedgeAbility.Reset = function()
    active = nil
    placed = nil
end

return LedgeAbility
