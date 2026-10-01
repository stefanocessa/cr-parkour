local Vec = require 'client.core.vec'

local Cooldown = {}

local settings = Config.Cooldowns
local repeats = Config.TraversalRepeat
local empty = { cooldown = 0, retriggerDelay = 0, minimumExitTime = 0 }
local started = {}
local ended = {}
local targets = {}
local lastStart = 0

local rules = function(ability)
    return settings[ability] or empty
end

Cooldown.Remaining = function(ability, now)
    now = now or GetGameTimer()
    local rule = rules(ability)
    local remaining = 0
    if started[ability] then remaining = math.max(remaining, started[ability] + (rule.retriggerDelay or 0) - now) end
    if ended[ability] then remaining = math.max(remaining, ended[ability] + (rule.cooldown or 0) - now) end
    return remaining
end

Cooldown.GlobalRemaining = function(now)
    return math.max(0, lastStart + settings.globalGap - (now or GetGameTimer()))
end

Cooldown.CanUse = function(ability, now)
    return Cooldown.Remaining(ability, now) <= 0
end

Cooldown.CanStart = function(ability, now)
    if Cooldown.GlobalRemaining(now) > 0 then return false, Constants.Reasons.PARKOUR_DENIED_GLOBAL_COOLDOWN end
    return true
end

Cooldown.Start = function(ability, now)
    now = now or GetGameTimer()
    started[ability] = now
    lastStart = now
end

Cooldown.End = function(ability, now)
    ended[ability] = now or GetGameTimer()
end

Cooldown.Remember = function(ability, point, normal, now)
    if not repeats[ability] or not point then return end
    targets[ability] = { point = point, normal = normal, at = now or GetGameTimer(), released = false }
end

local distance2dSq = function(a, b)
    local dx, dy = a.x - b.x, a.y - b.y
    return dx * dx + dy * dy
end

Cooldown.Track = function(coords, now)
    for ability, target in pairs(targets) do
        local rule = repeats[ability]
        if not target.released and (distance2dSq(coords, target.point) >= rule.resetDistance * rule.resetDistance or now - target.at >= rule.releaseMs) then
            target.released = true
        end
    end
end

Cooldown.SameTarget = function(ability, point, normal, now)
    local rule = repeats[ability]
    local last = targets[ability]
    if not rule or not last or not point then return false end
    if distance2dSq(point, last.point) > rule.radius * rule.radius then return false end
    if normal and last.normal and Vec.Dot(normal, last.normal) < rule.sameSideDot then return false end
    return (now or GetGameTimer()) - last.at < rule.sameObstacleCooldown or not last.released
end

Cooldown.RepeatInfo = function(ability, now)
    local last = targets[ability]
    if not last then return nil end
    return { age = now - last.at, released = last.released }
end

Cooldown.CanExit = function(ability, elapsed)
    return elapsed >= (rules(ability).minimumExitTime or 0)
end

Cooldown.Info = function(now)
    local result = {}
    for ability in pairs(settings) do
        if type(settings[ability]) == 'table' then
            local remaining = Cooldown.Remaining(ability, now)
            if remaining > 0 then result[#result + 1] = ('%s %d'):format(ability, remaining) end
        end
    end
    table.sort(result)
    return result
end

return Cooldown
