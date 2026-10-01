local Momentum = require 'client.systems.momentum'

local Combo = {}

local settings = Config.Combo
local previous = nil
local current = nil

Combo.Enter = function(name, state, now)
    current = {
        name = name,
        state = state,
        startedAt = now,
        entry = Momentum.LastEntry(),
        previous = previous and now - previous.endedAt <= settings.transitionWindow and previous.name or nil,
    }
end

Combo.Exit = function(name, now, velocity)
    previous = { name = name, endedAt = now, exit = velocity and Momentum.From(velocity) or nil }
    current = nil
end

Combo.Reset = function()
    previous, current = nil, nil
end

Combo.Previous = function(now)
    if not previous or now - previous.endedAt > settings.transitionWindow then return nil end
    return previous
end

Combo.Chains = function(target, now)
    local last = current or Combo.Previous(now)
    local list = last and settings.chains[last.name]
    if not list then return false end
    for i = 1, #list do
        if list[i] == target then return true end
    end
    return false
end

Combo.MinSpeed = function(target, base, now)
    return Combo.Chains(target, now) and base * settings.speedGrace or base
end

Combo.Info = function(now)
    local last = Combo.Previous(now)
    return {
        previous = current and current.previous or (last and last.name),
        current = current and current.name,
        since = last and now - last.endedAt or nil,
        entry = current and current.entry,
    }
end

return Combo
