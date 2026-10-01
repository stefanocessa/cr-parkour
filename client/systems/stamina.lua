local Stamina = {}

local settings = Config.Stamina
local reasons = Constants.Reasons
local denyReasons = {
    vault = reasons.VAULT_DENIED_LOW_STAMINA,
    wallrun = reasons.WALLRUN_DENIED_LOW_STAMINA,
}
local last = { ability = nil, required = 0.0 }

Stamina.Enabled = function()
    return settings.enabled == true
end

Stamina.Get = function()
    if not Stamina.Enabled() then return nil, nil end
    return GetPlayerStamina(cache.playerId), GetPlayerMaxStamina(cache.playerId)
end

local points = function(percent, maximum)
    return (percent or 0.0) * maximum / 100.0
end

Stamina.Required = function(ability)
    local _, maximum = Stamina.Get()
    if not maximum then return 0.0 end
    local drain = settings.drain[ability] or 0.0
    return points(settings.costs[ability], maximum) + points(drain * settings.minDrainTime, maximum)
end

Stamina.CanPerform = function(ability)
    if not Stamina.Enabled() then return true, reasons.OK end
    local current = Stamina.Get()
    local required = Stamina.Required(ability)
    last.ability, last.required = ability, required
    if required <= 0.0 or current >= required then return true, reasons.OK end
    return false, denyReasons[ability] or reasons.PARKOUR_DENIED_LOW_STAMINA
end

local set = function(value)
    SetPlayerStamina(cache.playerId, math.max(value, 0.0))
end

Stamina.Consume = function(ability)
    if not Stamina.Enabled() then return end
    local current, maximum = Stamina.Get()
    local cost = points(settings.costs[ability], maximum)
    if cost > 0.0 then set(current - cost) end
end

Stamina.Drain = function(ability, dt)
    if not Stamina.Enabled() then return true end
    local rate = settings.drain[ability]
    if not rate then return true end
    local current, maximum = Stamina.Get()
    local remaining = current - points(rate * dt, maximum)
    set(remaining)
    return remaining > 0.0
end

Stamina.Info = function()
    local current, maximum = Stamina.Get()
    return {
        enabled = Stamina.Enabled(),
        current = current,
        maximum = maximum,
        ability = last.ability,
        required = last.required,
    }
end

return Stamina
