local Vec = require 'client.core.vec'

local Movement = {}

local held = false

Movement.IsHeld = function()
    return held
end

Movement.Hold = function(ped)
    if held then return end
    held = true
    SetEntityVelocity(ped, 0.0, 0.0, 0.0)
    FreezeEntityPosition(ped, true)
end

Movement.Place = function(ped, position, heading)
    SetEntityCoordsNoOffset(ped, position.x, position.y, position.z, true, true, false)
    if heading then SetEntityHeading(ped, heading) end
end

Movement.Release = function(ped)
    if not held then return end
    held = false
    FreezeEntityPosition(ped, false)
end

Movement.Linear = function(t)
    return t
end

Movement.EaseOut = function(t)
    local u = 1.0 - t
    return 1.0 - u * u
end

Movement.EaseInOut = function(t)
    return t * t * (3.0 - 2.0 * t)
end

Movement.Tween = function(from, to, control, duration, ease)
    return {
        from = from,
        to = to,
        control = control or Vec.Lerp(from, to, 0.5),
        duration = math.max(duration, 1),
        ease = ease or Movement.EaseInOut,
        startedAt = GetGameTimer(),
    }
end

Movement.Through = function(from, apex, to, split, duration, ease)
    local tween = Movement.Tween(from, to, nil, duration, ease)
    local phase = Vec.Clamp(split, Constants.Epsilon, 1.0 - Constants.Epsilon)
    tween.apex = apex
    tween.split = tween.ease(phase)
    tween.rise = Vec.WithZ(Vec.Lerp(from, apex, 0.5), apex.z)
    tween.fall = Vec.WithZ(Vec.Lerp(apex, to, 0.5), apex.z)
    return tween
end

Movement.Point = function(tween, e)
    if not tween.apex then return Vec.Bezier(tween.from, tween.control, tween.to, e) end
    if e <= tween.split then return Vec.Bezier(tween.from, tween.rise, tween.apex, e / tween.split) end
    return Vec.Bezier(tween.apex, tween.fall, tween.to, (e - tween.split) / (1.0 - tween.split))
end

Movement.Sample = function(tween)
    local t = Vec.Clamp((GetGameTimer() - tween.startedAt) / tween.duration, 0.0, 1.0)
    return Movement.Point(tween, tween.ease(t)), t
end

Movement.Arc = function(from, to, peakZ)
    local mid = Vec.Lerp(from, to, 0.5)
    return Vec.WithZ(mid, 2.0 * peakZ - 0.5 * (from.z + to.z))
end

Movement.Approach = function(current, target, gain, dt)
    return Vec.Lerp(current, target, Vec.Clamp(gain * dt, 0.0, 1.0))
end

Movement.HeadingDelta = function(from, to)
    return (to - from + 540.0) % 360.0 - 180.0
end

Movement.LerpHeading = function(from, to, t)
    return (from + Movement.HeadingDelta(from, to) * Vec.Clamp(t, 0.0, 1.0)) % 360.0
end

Movement.TurnHeading = function(current, target, gain, dt)
    return Movement.LerpHeading(current, target, gain * dt)
end

return Movement
