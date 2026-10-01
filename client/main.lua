local State = require 'client.core.state'
local Context = require 'client.core.context'
local Scanner = require 'client.core.scanner'
local Resolver = require 'client.core.resolver'
local Combo = require 'client.core.combo'
local Input = require 'client.core.input'
local Lifecycle = require 'client.core.lifecycle'
local Recovery = require 'client.core.recovery'
local Cooldown = require 'client.core.cooldowns'
local Movement = require 'client.core.movement'
local Animation = require 'client.systems.animation'
local Momentum = require 'client.systems.momentum'
local Camera = require 'client.systems.camera'
local Damage = require 'client.systems.damage'
local Stamina = require 'client.systems.stamina'
local Collision = require 'client.systems.collision'
local Wallclimb = require 'client.abilities.wallclimb'
local Rays = require 'client.debug.rays'
local DebugState = require 'client.debug.state'
local AnimationDebug = require 'client.debug.animations'
local Profiler = require 'client.debug.profiler'
local Tuning = require 'client.debug.tuning'
local Snapshot = require 'client.debug.snapshot'

local reasons = Constants.Reasons
local panel = Config.DebugPanel
local performance = Config.Performance.active
local debugEnabled = Config.Debug
local overlayRunning = false
local wake = false
local lastWait = 0
local text = { at = 0, panel = nil, pipeline = nil, profiler = nil }
local flags = {
    rays = Config.DebugFlags.rays,
    state = Config.DebugFlags.state,
    animations = Config.DebugFlags.animations,
}

Rays.SetDrawing(flags.rays)

Input.Register()
Input.OnWake(function() wake = true end)

State.OnChange(function(current, previous)
    if State.IsLocomotion(current) and State.IsLocomotion(previous) then return end
    TriggerEvent('cr-parkour:stateChanged', { state = current, previous = previous })
end)

local sleep = function(ms)
    if ms <= 0 then return Wait(0) end
    local deadline = GetGameTimer() + ms
    wake = false
    repeat
        Wait(math.max(math.min(performance.wakeSlice, deadline - GetGameTimer()), 0))
    until wake or GetGameTimer() >= deadline
end

local errors = {}

local tick = function()
    local started = Profiler.Start()
    local ctx = Context.Update()
    Profiler.Stop('context', started)
    Resolver.Tick(ctx)
    Profiler.Tick(ctx.now)
    lastWait = Resolver.NextWait(ctx)
end

local recoverFromError = function(err)
    if not errors[err] then
        errors[err] = true
        lib.print.error(('[cr-parkour] %s'):format(err))
    end
    if State.IsAbility() or Movement.IsHeld() or Collision.IsProtected() then
        pcall(Recovery.SafeReset, Context.Get(), reasons.RECOVERY_ERROR, { dropVelocity = true })
    end
    lastWait = performance.idleTick
end

CreateThread(function()
    Animation.Preload()
    Profiler.Loop('main', true)
    while true do
        local ok, err = pcall(tick)
        if not ok then recoverFromError(err) end
        sleep(lastWait)
    end
end)

local debugExtras = function(ctx)
    local ok, blockedReason = Context.CanParkour(ctx)
    local decision = Resolver.Decision()
    local run = Lifecycle.Run()
    return {
        parkour = {
            held = Input.IsParkourHeld(),
            candidate = decision.candidate,
            selected = run and run.ability or decision.selected,
            stamina = Stamina.Info(),
        },
        decision = decision,
        ledgeProbe = Wallclimb.LastLedge(),
        collision = Collision.TraversalMode(),
        animation = flags.animations and Animation.State() or nil,
        entry = Momentum.LastEntry(),
        combo = Combo.Info(GetGameTimer()),
        run = run,
        camera = Camera.State(),
        cooldowns = Cooldown.Info(GetGameTimer()),
        blocked = not ok and blockedReason or nil,
        preset = Config.ActivePreset,
        armed = ctx.armed,
    }
end

local profilerInfo = function()
    local run = Lifecycle.Run()
    local decision = Resolver.Decision()
    local ability = run and run.ability or nil
    if ability and decision.variant and decision.variant ~= ability then ability = ('%s (%s)'):format(ability, decision.variant) end
    return {
        held = Input.IsParkourHeld(),
        traversal = decision.selected or (decision.profile and decision.profile.traversalType) or 'NONE',
        ability = ability,
        state = State.Current(),
        wait = lastWait,
    }
end

local refreshText = function(ctx, now)
    text.at = now + panel.textRefreshMs
    text.panel, text.pipeline, text.profiler = nil, nil, nil
    if debugEnabled and flags.state then
        local extras = debugExtras(ctx)
        local scan = Scanner.Last()
        text.panel = DebugState.BuildPanel(ctx, State, scan, extras)
        text.pipeline = DebugState.BuildPipeline(ctx, State, scan, extras)
    end
    if Profiler.IsEnabled() then text.profiler = Profiler.Lines(profilerInfo()) end
end

local startOverlayLoop = function()
    if overlayRunning then return end
    overlayRunning = true
    text.at = 0
    CreateThread(function()
        Profiler.Loop('debug', true)
        while debugEnabled or Profiler.IsEnabled() do
            local now = GetGameTimer()
            if now >= text.at then refreshText(Context.Get(), now) end
            if debugEnabled and flags.rays then Rays.Draw() end
            if text.panel then DebugState.DrawLines(text.panel, panel.x, panel.y, panel.width) end
            if text.pipeline then DebugState.DrawLines(text.pipeline, panel.pipelineX, panel.y, panel.pipelineWidth) end
            if text.profiler then DebugState.DrawLines(text.profiler, panel.performanceX, panel.y, panel.performanceWidth) end
            Wait(0)
        end
        text.panel, text.pipeline, text.profiler = nil, nil, nil
        Profiler.Loop('debug', false)
        overlayRunning = false
    end)
end

local setDebug = function(value)
    debugEnabled = value
    Rays.SetEnabled(value)
    text.at = 0
    if value then startOverlayLoop() end
end

local tuningActions = {
    flags = function()
        return { rays = flags.rays, state = flags.state, animations = flags.animations, performance = Profiler.IsEnabled() }
    end,
    toggle = function(flag)
        if flag == 'performance' then
            Profiler.SetEnabled(not Profiler.IsEnabled())
            if Profiler.IsEnabled() then startOverlayLoop() end
            return
        end
        flags[flag] = not flags[flag]
        Rays.SetDrawing(flags.rays)
        setDebug(flags.rays or flags.state or flags.animations)
    end,
    reloadAnimations = function()
        Animation.Reload(LoadResourceFile(GetCurrentResourceName(), 'shared/animations.lua'))
        lib.notify({ title = 'Parkour', description = 'Registry animazioni ricaricato', type = 'info' })
    end,
    rebuildOffsets = Animation.RebuildOffsets,
    reset = function()
        Recovery.SafeReset(Context.Get(), reasons.RECOVERY_TUNING_RESET, { state = Constants.States.IDLE })
    end,
    recover = function()
        Recovery.SafeReset(Context.Get(), reasons.RECOVERY_MANUAL, { clearTasks = true })
    end,
    snapshot = Snapshot.Copy,
}

local registerDebugCommands = function()
    RegisterCommand(Config.DebugCommand, function()
        if Config.TuningMode then
            if not debugEnabled then setDebug(true) end
            return Tuning.Open(tuningActions)
        end
        setDebug(not debugEnabled)
        lib.notify({ title = 'Parkour', description = debugEnabled and 'Debug attivo' or 'Debug disattivo', type = 'info' })
    end, false)

    RegisterCommand(Config.SnapshotCommand, function()
        Snapshot.Copy()
    end, false)

    RegisterCommand(Config.Profiler.command, function()
        Profiler.SetEnabled(not Profiler.IsEnabled())
        if Profiler.IsEnabled() then startOverlayLoop() end
        lib.notify({ title = 'Parkour', description = Profiler.IsEnabled() and 'Profiler attivo' or 'Profiler disattivo', type = 'info' })
    end, false)

    RegisterCommand(Config.AnimationTools.listCommand, function()
        CreateThread(AnimationDebug.Report)
    end, false)

    RegisterCommand(Config.AnimationTools.measureCommand, function(_, args)
        if not args[1] then return lib.print.warn(('[cr-parkour] uso: /%s <nome.registry>'):format(Config.AnimationTools.measureCommand)) end
        CreateThread(function() AnimationDebug.Measure(args[1]) end)
    end, false)
end

if Config.DebugCommands or Config.Debug or Config.TuningMode or Config.Profiler.enabled then registerDebugCommands() end

if debugEnabled or Profiler.IsEnabled() then startOverlayLoop() end

if debugEnabled then
    CreateThread(function()
        Wait(Config.AnimationTools.reportDelayMs)
        AnimationDebug.Report()
    end)
end

lib.onCache('ped', function()
    Recovery.SafeReset(Context.Get(), reasons.RECOVERY_RESPAWN, { state = Constants.States.IDLE, dropVelocity = true })
    Scanner.Invalidate()
    Context.RefreshStatus()
end)

lib.onCache('vehicle', Context.RefreshStatus)
lib.onCache('weapon', Context.RefreshStatus)

local isParkouring = function()
    return State.IsAbility()
end

local currentAbility = function()
    local ability = Lifecycle.Active()
    return ability and ability.name or nil
end

exports('IsParkouring', isParkouring)
exports('IsBusy', isParkouring)
exports('GetParkourState', State.Current)
exports('GetState', State.Current)
exports('GetCurrentAbility', currentAbility)
exports('IsParkourEnabled', Context.IsEnabled)

exports('SetParkourEnabled', function(value)
    Context.SetEnabled(value)
    if not value and State.IsAbility() then
        Recovery.SafeReset(Context.Get(), reasons.PARKOUR_DENIED_DISABLED)
    end
end)

exports('CanParkour', function()
    return Context.CanParkour(Context.Get())
end)

exports('CancelParkour', function(force)
    if not State.IsAbility() then return false end
    if not force and not Animation.IsCancelable() then return false end
    Recovery.SafeReset(Context.Get(), reasons.RECOVERY_EXPORT_CANCEL)
    return true
end)

exports('SetDamageHandler', Damage.SetHandler)

exports('SetLandingDamageHandler', function(handler)
    Damage.SetHandler('hardLanding', handler)
    Damage.SetHandler('largeFall', handler)
    Damage.SetHandler('failedRoll', handler)
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    Input.Release()
    Recovery.SafeReset(Context.Get(), reasons.RECOVERY_RESOURCE_STOP, { immediate = true, state = Constants.States.IDLE })
    Scanner.Invalidate()
    debugEnabled = false
    Rays.SetEnabled(false)
    Profiler.SetEnabled(false)
end)
