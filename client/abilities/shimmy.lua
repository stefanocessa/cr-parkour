local Vec = require 'client.core.vec'
local Movement = require 'client.core.movement'
local Ledge = require 'client.detection.ledge'
local LedgeAbility = require 'client.abilities.ledge'
local Animation = require 'client.systems.animation'
local Collision = require 'client.systems.collision'
local DebugState = require 'client.debug.state'

local Shimmy = { name = 'shimmy', states = { Constants.States.LEDGE_MOVE } }

local settings = Config.Shimmy
local corner = settings.corner
local animations = Config.Ledge.animation
local input = Config.Input
local reasons = Constants.Reasons
local S = Constants.States
local active = nil

local carry = function(from, to)
    to.entrySpeed = from.entrySpeed
    return to
end

local play = function(name, options)
    if active.animation ~= name then
        active.animation = name
        LedgeAbility.Play(name, options)
    end
end

local blocked = function(reason)
    play(animations.idle)
    return { hold = true, reason = reason }
end

local backToHang = function()
    return { next = S.LEDGE_HANG, payload = Ledge.Inspect(active.ledge) }
end

local startCorner = function(ctx, ledge, direction, sign, kind)
    if not corner.enabled then return blocked(reasons.SHIMMY_DENIED_NO_EDGE) end
    local finder = kind == 'outer' and Ledge.OuterCorner or Ledge.InnerCorner
    local target = finder(ledge, direction)
    if not target.valid then return blocked(target.reason) end

    local control = Vec.Lerp(ctx.coords, target.hang, 0.5)
    if kind == 'outer' then
        local bulge = Vec.Normalize2d(ledge.normal + target.normal)
        if bulge then control = control + bulge * corner.bulge end
    end

    local animation = sign > 0 and animations.cornerRight or animations.cornerLeft
    local duration = Animation.SyncedDuration(animation, corner.duration)
    active.corner = {
        target = carry(ledge, target),
        startHeading = active.heading,
        tween = Movement.Tween(ctx.coords, LedgeAbility.Adjust(target, target.hang, animations.idle), control, duration, Movement.EaseInOut),
    }
    play(animation, { duration = duration })
    DebugState.SetReason('shimmy', kind == 'outer' and reasons.SHIMMY_CORNER_OUTER or reasons.SHIMMY_CORNER_INNER, ('%.0f deg'):format(target.cornerAngle))
    return nil
end

local updateCorner = function(ctx)
    local turn = active.corner
    local position, t = Movement.Sample(turn.tween)
    active.heading = Movement.LerpHeading(turn.startHeading, turn.target.heading, turn.tween.ease(t))
    LedgeAbility.Place(ctx, turn.target, position, active.heading)
    if t < 1.0 then return nil end
    active.ledge = turn.target
    active.corner = nil
    active.animation = nil
    return nil
end

Shimmy.Enter = function(ctx, ledge)
    active = { ledge = ledge, heading = ledge.heading, animation = nil, corner = nil }
end

Shimmy.Current = function()
    return active and active.ledge
end

Shimmy.IsTurning = function()
    return active ~= nil and active.corner ~= nil
end

Shimmy.Settle = function()
    return backToHang()
end

Shimmy.Update = function(ctx)
    if active.corner then return updateCorner(ctx) end
    if not settings.enabled then return backToHang() end

    local side = ctx.input.side
    if math.abs(side) <= input.deadzone then return backToHang() end

    local ledge = active.ledge
    local sign = side > 0 and 1.0 or -1.0
    local direction = ledge.tangent * sign
    local step = settings.speed * math.abs(side) * ctx.dt
    play(sign > 0 and animations.right or animations.left)

    local ahead = Ledge.Follow(ledge, ledge.edge + direction * (step + settings.probeAhead))
    if not ahead.valid then return startCorner(ctx, ledge, direction, sign, 'outer') end
    if Collision.BodyBlocked(ledge.hang, direction, step + settings.bodyCheck, { 'chest', 'head' }) then
        return startCorner(ctx, ledge, direction, sign, 'inner')
    end

    local nextLedge = Ledge.Follow(ledge, ledge.edge + direction * step)
    if not nextLedge.valid then return blocked(reasons.SHIMMY_DENIED_NO_EDGE) end

    active.ledge = carry(ledge, nextLedge)
    active.heading = Movement.TurnHeading(active.heading, nextLedge.heading, settings.turnGain, ctx.dt)
    LedgeAbility.Place(ctx, nextLedge, nextLedge.hang, active.heading, { adjust = true, smooth = true })
    return nil
end

Shimmy.Recover = function()
    local ledge = active and (active.corner and active.corner.target or active.ledge)
    if not ledge then return nil end
    return ledge.normal * Config.Ledge.dropPush
end

Shimmy.Exit = function(nextState)
    active = nil
    if nextState ~= S.LEDGE_HANG then DebugState.Ledge(nil) end
end

Shimmy.Reset = function()
    active = nil
end

return Shimmy
