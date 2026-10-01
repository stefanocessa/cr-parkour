local State = require 'client.core.state'
local Context = require 'client.core.context'
local Movement = require 'client.core.movement'
local Combo = require 'client.core.combo'
local Lifecycle = require 'client.core.lifecycle'
local Momentum = require 'client.systems.momentum'
local Animation = require 'client.systems.animation'
local Collision = require 'client.systems.collision'
local Camera = require 'client.systems.camera'
local DebugState = require 'client.debug.state'

local Recovery = {}

local S = Constants.States
local reasons = Constants.Reasons
local timeouts = Config.StateTimeouts
local performance = Config.Performance.active
local last = nil
local nextCheck = 0

Recovery.SafeReset = function(ctx, reason, options)
    options = options or {}
    local ped = ctx and ctx.ped or cache.ped
    local live = ctx ~= nil and ctx.coords ~= nil
    local velocity = live and Lifecycle.Cancel(ctx, reason) or nil

    Lifecycle.ResetAll()
    Animation.StopAllParkour(options.immediate)
    if options.clearTasks then ClearPedTasks(ped) end
    Movement.Release(ped)
    Collision.EndTraversal()
    Collision.Protect(ped, false)
    Camera.Reset()
    Momentum.Clear()
    Combo.Reset()
    Context.ResetAir()
    Context.ClearPresses()

    if velocity and not options.dropVelocity then SetEntityVelocity(ped, velocity.x, velocity.y, velocity.z) end
    State.Force(options.state or (live and State.Derive(ctx)) or S.IDLE)

    last = { reason = reason, at = GetGameTimer() }
    DebugState.SetReason('recovery', reason)
end

Recovery.Last = function()
    return last
end

Recovery.Watchdog = function(ctx, ability, protectedByRoll)
    if ctx.now < nextCheck then return false end
    nextCheck = ctx.now + performance.watchdogInterval
    local current = State.Current()
    local timeout = timeouts[current]
    if ability and timeout and State.Elapsed() > timeout then
        Recovery.SafeReset(ctx, reasons.RECOVERY_WATCHDOG, { clearTasks = true, state = State.Derive(ctx) })
        DebugState.SetReason('watchdog', reasons.RECOVERY_WATCHDOG, ('%s > %dms'):format(current, timeout))
        return true
    end
    if Collision.TraversalExpired(ctx.now) then
        DebugState.SetReason('watchdog', reasons.COLLISION_TRAVERSAL_TIMEOUT, Collision.TraversalMode())
        Recovery.SafeReset(ctx, reasons.COLLISION_TRAVERSAL_TIMEOUT, { clearTasks = true, state = State.Derive(ctx) })
        return true
    end
    if ability then return false end

    if Movement.IsHeld() then
        Movement.Release(ctx.ped)
        DebugState.SetReason('watchdog', reasons.RECOVERY_ORPHAN_HOLD, current)
    end
    if Animation.IsLooping() then
        Animation.Stop()
        DebugState.SetReason('watchdog', reasons.RECOVERY_ORPHAN_ANIMATION, current)
    end
    if Collision.IsProtected() and ctx.grounded and not protectedByRoll then
        Collision.Protect(ctx.ped, false)
        DebugState.SetReason('watchdog', reasons.RECOVERY_ORPHAN_PROTECTION, current)
    end
    return false
end

return Recovery
