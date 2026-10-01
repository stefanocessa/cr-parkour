local Damage = {}

local settings = Config.Damage
local fall = Config.Fall
local handlers = {}

Damage.Kinds = { hardLanding = true, failedRoll = true, largeFall = true, collision = true }

Damage.SetHandler = function(kind, handler)
    if not Damage.Kinds[kind] then return false end
    handlers[kind] = handler
    return true
end

local defaults = {
    largeFall = function(data)
        local ped = cache.ped
        local meters = math.max(0.0, data.distance - fall.veryLarge) * (data.reduction or 1.0)
        if fall.damagePerMeter > 0 and meters > 0.0 then
            ApplyDamageToPed(ped, math.floor(meters * fall.damagePerMeter), false)
        end
        if not data.rolled then
            SetPedToRagdoll(ped, fall.ragdollTime.min, fall.ragdollTime.max, 0, false, false, false)
        end
    end,
}

Damage.Emit = function(kind, data)
    data.kind = kind
    if settings.events then TriggerEvent('cr-parkour:damage', kind, data) end
    local handler = handlers[kind]
    if handler then
        local ok, handled = pcall(handler, data)
        if ok and handled then return true end
    end
    if defaults[kind] then defaults[kind](data) end
    return false
end

return Damage
