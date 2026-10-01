local S = Constants.States

local State = {}

local locomotion = { S.IDLE, S.RUNNING, S.SPRINTING, S.JUMPING, S.FALLING }
local grounded = { S.IDLE, S.RUNNING, S.SPRINTING }

local merge = function(...)
    local result = {}
    for _, list in ipairs({ ... }) do
        for i = 1, #list do result[#result + 1] = list[i] end
    end
    return result
end

local groundStarts = { S.VAULTING, S.SLIDING, S.WALLCLIMBING, S.WALLRUNNING, S.ROLLING, S.WALLFLIP, S.PRECISION, S.LONGJUMP, S.BALANCING }
local airStarts = { S.WALLRUNNING, S.LEDGE_GRAB, S.ROLLING, S.TICTAC, S.TRICK }

local rules = {
    [S.IDLE] = merge(locomotion, { S.VAULTING, S.WALLCLIMBING, S.ROLLING, S.PRECISION, S.BALANCING }),
    [S.RUNNING] = merge(locomotion, groundStarts),
    [S.SPRINTING] = merge(locomotion, groundStarts),
    [S.JUMPING] = merge(locomotion, airStarts, { S.WALLCLIMBING, S.WALLFLIP }),
    [S.FALLING] = merge(locomotion, airStarts, { S.PRECISION, S.LONGJUMP }),
    [S.VAULTING] = locomotion,
    [S.SLIDING] = locomotion,
    [S.ROLLING] = locomotion,
    [S.WALLRUNNING] = merge(locomotion, { S.WALLJUMPING, S.LEDGE_GRAB, S.WALLFLIP }),
    [S.WALLCLIMBING] = merge({ S.FALLING, S.WALLJUMPING, S.LEDGE_GRAB, S.WALLFLIP }, grounded),
    [S.WALLJUMPING] = merge(locomotion, airStarts),
    [S.TICTAC] = merge(locomotion, airStarts),
    [S.PRECISION] = merge(locomotion, airStarts),
    [S.LONGJUMP] = merge(locomotion, airStarts),
    [S.WALLFLIP] = merge(locomotion, { S.ROLLING }),
    [S.TRICK] = merge(locomotion, { S.ROLLING }),
    [S.BALANCING] = merge(locomotion, { S.PRECISION }),
    [S.LEDGE_GRAB] = { S.LEDGE_HANG, S.FALLING },
    [S.LEDGE_HANG] = { S.LEDGE_MOVE, S.CLIMBING, S.FALLING },
    [S.LEDGE_MOVE] = { S.LEDGE_HANG, S.FALLING },
    [S.CLIMBING] = merge(grounded, { S.FALLING }),
    [S.RAGDOLL] = locomotion,
}

local allowed = {}
for from, targets in pairs(rules) do
    allowed[from] = { [S.RAGDOLL] = true }
    for i = 1, #targets do allowed[from][targets[i]] = true end
end

local current, previous = S.IDLE, S.IDLE
local enteredAt = 0
local data = nil
local listeners = {}

State.Current = function()
    return current
end

State.Previous = function()
    return previous
end

State.Data = function()
    return data
end

State.EnteredAt = function()
    return enteredAt
end

State.Elapsed = function()
    return GetGameTimer() - enteredAt
end

State.Is = function(...)
    for _, state in ipairs({ ... }) do
        if current == state then return true end
    end
    return false
end

State.IsLocomotion = function(state)
    return Constants.Locomotion[state or current] == true
end

State.IsAbility = function(state)
    return not State.IsLocomotion(state)
end

State.IsKinematic = function(state)
    return Constants.Kinematic[state or current] == true
end

State.CanTransition = function(target)
    if target == current then return true end
    return allowed[current] ~= nil and allowed[current][target] == true
end

State.OnChange = function(listener)
    listeners[#listeners + 1] = listener
end

local apply = function(target, payload)
    previous, current = current, target
    enteredAt = GetGameTimer()
    data = payload
    for i = 1, #listeners do listeners[i](current, previous, payload) end
end

State.Set = function(target, payload)
    if target == current then
        data = payload or data
        return true
    end
    if not State.CanTransition(target) then return false, Constants.Reasons.INVALID_TRANSITION end
    apply(target, payload)
    return true
end

State.Force = function(target)
    apply(target or S.IDLE, nil)
end

State.Derive = function(ctx)
    if ctx.ragdoll then return S.RAGDOLL end
    if ctx.airborne then
        return (ctx.jumping or ctx.velocity.z > 0.0) and S.JUMPING or S.FALLING
    end
    if ctx.sprinting then return S.SPRINTING end
    if ctx.speed2d > Config.Scan.idleSpeed then return S.RUNNING end
    return S.IDLE
end

State.SyncLocomotion = function(ctx)
    if not State.IsLocomotion() then return current end
    local target = State.Derive(ctx)
    if target ~= current then
        if State.CanTransition(target) then apply(target, nil) end
    end
    return current
end

return State
