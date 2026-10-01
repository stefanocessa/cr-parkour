local Vec = require 'client.core.vec'

local Momentum = {}

local settings = Config.Momentum
local stored, storedAt = nil, 0
local lastEntry = nil

Momentum.From = function(velocity)
    local direction, speed2d = Vec.Normalize2d(velocity)
    return {
        velocity = velocity,
        speed = #velocity,
        speed2d = speed2d,
        direction = direction,
    }
end

Momentum.Store = function(momentum)
    stored = momentum.velocity
    storedAt = GetGameTimer()
end

Momentum.Last = function()
    if not stored or GetGameTimer() - storedAt > settings.carryWindowMs then return nil end
    return Momentum.From(stored)
end

Momentum.Peek = function(ctx, velocity)
    local live = velocity or ctx.velocity
    local carried = Momentum.Last()
    if carried and carried.speed2d > Vec.Length2d(live) then
        return Momentum.From(vector3(carried.velocity.x, carried.velocity.y, live.z))
    end
    return Momentum.From(live)
end

Momentum.Capture = function(ctx, velocity)
    lastEntry = Momentum.Peek(ctx, velocity)
    return lastEntry
end

Momentum.LastEntry = function()
    return lastEntry
end

Momentum.Assist = function(current, desired, factor)
    return current + (desired - current) * factor
end

Momentum.Drive = function(ped, current, desired, factor)
    local velocity = Momentum.Assist(current, desired, factor)
    SetEntityVelocity(ped, velocity.x, velocity.y, velocity.z)
    return velocity
end

Momentum.Scale = function(momentum, multiplier)
    return Momentum.From(momentum.velocity * multiplier)
end

Momentum.ProjectOnDirection = function(momentum, direction)
    local along = math.max(0.0, Vec.Dot(Vec.Flat(momentum.velocity), direction))
    return Momentum.From(direction * along)
end

Momentum.WithSpeed = function(direction, speed, verticalSpeed)
    return Momentum.From(direction * speed + Vec.Up * (verticalSpeed or 0.0))
end

Momentum.Clamp = function(momentum, minSpeed, maxSpeed, fallbackDirection)
    local direction = momentum.direction or fallbackDirection
    if not direction then return momentum end
    local speed = Vec.Clamp(momentum.speed2d, minSpeed or 0.0, maxSpeed or settings.maxSpeed)
    return Momentum.WithSpeed(direction, speed, momentum.velocity.z)
end

Momentum.Clear = function()
    stored, storedAt, lastEntry = nil, 0, nil
end

Momentum.Apply = function(ped, momentum)
    local velocity = momentum.velocity
    SetEntityVelocity(ped, velocity.x, velocity.y, velocity.z)
    Momentum.Store(momentum)
end

return Momentum
