local State = require 'client.core.state'
local Context = require 'client.core.context'
local Cooldown = require 'client.core.cooldowns'
local Slide = require 'client.abilities.slide'
local Roll = require 'client.abilities.roll'
local Wallrun = require 'client.abilities.wallrun'
local Wallclimb = require 'client.abilities.wallclimb'
local LedgeAbility = require 'client.abilities.ledge'
local Shimmy = require 'client.abilities.shimmy'
local WallFlip = require 'client.abilities.wallflip'
local Precision = require 'client.abilities.precision'
local LongJump = require 'client.abilities.longjump'
local Tricks = require 'client.abilities.tricks'
local Balance = require 'client.abilities.balance'
local Stamina = require 'client.systems.stamina'
local Rays = require 'client.debug.rays'
local DebugState = require 'client.debug.state'

local Input = {}

local settings = Config.Input
local controls = settings.controls
local S = Constants.States
local reasons = Constants.Reasons
local candidates = { vault = false, wallclimb = false, wallrun = false, balance = false, slide = false, jump = false, expires = 0 }
local targets = { primary = nil, secondary = nil, jump = nil }
local hold = { active = false, since = 0, keybind = nil }
local wakeListeners = {}
local attempt = { press = nil, scan = nil }

local report = function(code, detail)
    DebugState.SetReason('input', code, detail)
end

local trickKey = nil

local modifierHeld = function()
    return trickKey ~= nil and trickKey.isPressed == true
end

Input.SetParkourHeld = function(value)
    value = value == true
    if hold.active == value then return end
    hold.active = value
    hold.since = GetGameTimer()
    Context.SetHeld(value)
    if value then
        Context.Press(modifierHeld() and 'trick' or 'primary')
        for i = 1, #wakeListeners do wakeListeners[i]() end
    end
end

Input.OnWake = function(listener)
    wakeListeners[#wakeListeners + 1] = listener
end

Input.IsParkourHeld = function()
    return hold.active
end

Input.TrickHeld = function()
    return hold.active and modifierHeld()
end

Input.HeldSince = function()
    return hold.active and hold.since or nil
end

Input.Register = function()
    if hold.keybind then return end
    local modifier = Config.Tricks.modifier
    trickKey = lib.addKeybind({
        name = modifier.command,
        description = modifier.description,
        defaultMapper = 'keyboard',
        defaultKey = modifier.key,
        onPressed = function()
            if hold.active then Context.Press('trick') end
        end,
    })
    hold.keybind = lib.addKeybind({
        name = settings.command,
        description = settings.description,
        defaultMapper = 'keyboard',
        defaultKey = settings.primaryKey,
        onPressed = function() Input.SetParkourHeld(true) end,
        onReleased = function() Input.SetParkourHeld(false) end,
    })
end

Input.Release = function()
    Input.SetParkourHeld(false)
    if hold.keybind then hold.keybind.isPressed = false end
    if trickKey then trickKey.isPressed = false end
end

Input.SetCandidates = function(ctx, found)
    candidates.vault = found.vault == true
    candidates.wallclimb = found.wallclimb == true
    candidates.wallrun = found.wallrun == true
    candidates.balance = found.balance == true
    candidates.jump = found.jump == true
    candidates.slide = found.slide == true
    if candidates.vault or candidates.wallclimb or candidates.wallrun or candidates.balance or candidates.slide or candidates.jump then
        candidates.expires = ctx.now + Config.Scan.candidateHoldMs
    end
end

Input.ClearCandidates = function()
    candidates.vault, candidates.wallclimb, candidates.wallrun, candidates.balance, candidates.slide, candidates.jump = false, false, false, false, false, false
    candidates.expires = 0
end

Input.HasCandidate = function(ctx)
    return ctx.now <= candidates.expires
        and (candidates.vault or candidates.wallclimb or candidates.wallrun or candidates.balance or candidates.slide or candidates.jump)
end

Input.Candidates = function()
    return candidates
end

Input.ConsumeTraversal = function()
    Context.Consume('primary', Context.BufferWindow('climb'))
end

local isLedge = function(state)
    return state == S.LEDGE_HANG or state == S.LEDGE_MOVE
end

local isBusy = function(state)
    return State.IsAbility(state) and not Constants.AirAbilities[state]
end

local primaryTarget = function(ctx)
    local state = State.Current()
    if isLedge(state) then return 'climb' end
    if state == S.WALLRUNNING and Config.Walljump.enabled then return 'walljump' end
    if state == S.WALLCLIMBING and Config.Walljump.fromWallclimb then return 'walljump' end
    if state == S.BALANCING then return 'balanceJump' end
    if isBusy(state) or not hold.active then return nil end
    if ctx.airborne then return 'air' end
    if not Input.HasCandidate(ctx) then return 'scan' end
    if candidates.balance then return 'balance' end
    if candidates.slide then return 'under' end
    if candidates.vault then return 'vault' end
    if candidates.wallclimb then return 'wallclimb' end
    if candidates.wallrun then return 'wallrun' end
    return 'scan'
end

local secondaryTarget = function(ctx)
    local state = State.Current()
    if isLedge(state) then return 'drop' end
    if isBusy(state) or not hold.active then return nil end
    if ctx.airborne then return Roll.Approaching(ctx, Context.BufferWindow('roll')) and 'roll' or nil end
    if Roll.HasLateWindow(ctx) then return 'roll' end
    if Slide.Evaluate(ctx) then return 'slide' end
    return nil
end

local jumpTarget = function(ctx)
    if not hold.active or not State.IsLocomotion() then return nil end
    if not ctx.grounded and not ctx.coyote then return nil end
    if candidates.jump and Input.HasCandidate(ctx) then return 'special' end
    return nil
end

Input.Update = function(ctx)
    if hold.active and IsPauseMenuActive() then Input.Release() end

    local ability = State.IsAbility()
    if ability then
        for i = 1, #settings.blockedDuringAbility do DisableControlAction(0, settings.blockedDuringAbility[i], true) end
        if IsDisabledControlJustPressed(0, controls.jump) then
            Context.Press('jump')
            if hold.active then Context.Press('special') end
        end
    end

    targets.primary = primaryTarget(ctx)
    targets.secondary = secondaryTarget(ctx)
    targets.jump = not ability and jumpTarget(ctx) or nil

    if targets.primary and targets.primary ~= 'scan' then
        for i = 1, #controls.context do DisableControlAction(0, controls.context[i], true) end
    end
    if targets.secondary then
        DisableControlAction(0, controls.duck, true)
        if IsDisabledControlJustPressed(0, controls.duck) then Context.Press('secondary') end
    end
    if targets.jump then
        DisableControlAction(0, controls.jump, true)
        if IsDisabledControlJustPressed(0, controls.jump) then Context.Press('special') end
    end

    if Rays.IsEnabled() then
        DebugState.Input({
            held = hold.active,
            primary = targets.primary,
            secondary = targets.secondary,
            jump = ability and (hold.active and 'special' or 'bloccato') or (targets.jump or 'GTA'),
            buffered = Context.Pending('primary') and 'E' or (Context.Pending('special') and 'SPACE')
                or (Context.Pending('secondary', Context.BufferWindow('roll')) and 'CTRL' or nil),
            coyote = ctx.coyote,
        })
    end
end

local currentLedge = function()
    if State.Is(S.LEDGE_MOVE) then return Shimmy.Current() end
    return LedgeAbility.Current()
end

local secondary = function(ctx, api)
    local target = targets.secondary
    if target == 'drop' then
        local ledge = currentLedge()
        if not ledge or Shimmy.IsTurning() then return false end
        Context.Consume('secondary')
        report(reasons.INPUT_CTRL_DROP)
        local ability = State.Is(S.LEDGE_MOVE) and Shimmy or LedgeAbility
        return api.apply(ctx, ability, LedgeAbility.DropFrom(ledge))
    end

    if target == 'roll' and ctx.airborne then
        if not Roll.InWindow(ctx) then return false end
        local ok, reason = Roll.Arm(ctx)
        DebugState.SetReason('roll', reason)
        if ok then
            Context.Consume('secondary', Context.BufferWindow('roll'))
            report(reasons.INPUT_CTRL_ROLL, 'armed')
        end
        return false
    end

    if target == 'roll' then
        Context.Consume('secondary', Context.BufferWindow('roll'))
        local ok, reason, payload = Roll.EvaluateLate(ctx)
        DebugState.SetReason('roll', ok and reasons.OK or reason)
        if ok and api.enter(ctx, S.ROLLING, payload) then
            report(reasons.INPUT_CTRL_ROLL, 'late')
            return true
        end
        return false
    end

    if target == 'slide' then
        Context.Consume('secondary')
        local valid, reason = Slide.Validate(ctx)
        if not valid then
            DebugState.SetReason('slide', reason)
            report(reasons.INPUT_CTRL_NONE, reason)
            return false
        end
        if api.start(ctx, Slide, S.SLIDING) then
            report(reasons.INPUT_CTRL_SLIDE)
            return true
        end
        return false
    end

    if Context.Pending('secondary', Context.BufferWindow('roll')) and ctx.airborne then return false end
    Context.Consume('secondary')
    report(reasons.INPUT_CTRL_NONE)
    return false
end

local trick = function(ctx, scan, api)
    if not Context.Pending('trick', Context.BufferWindow('trick')) then return false end
    local pressedAt = Context.PressedAt('trick')
    if attempt.press == pressedAt and attempt.scan == scan.at then return false end
    attempt.press, attempt.scan = pressedAt, scan.at
    if api.start(ctx, WallFlip, S.WALLFLIP, scan) then
        Context.Consume('trick', Context.BufferWindow('trick'))
        report(reasons.INPUT_TRICK_WALLFLIP)
        return true
    end
    if ctx.airborne and api.start(ctx, Tricks, S.TRICK) then
        Context.Consume('trick', Context.BufferWindow('trick'))
        report(reasons.INPUT_TRICK_AIR)
        return true
    end
    report(reasons.INPUT_TRICK_NONE)
    return false
end

local voluntaryExit = function(ctx, ability, canExit)
    if canExit(ctx.now) then return true end
    report(reasons.PARKOUR_DENIED_EXIT_TOO_EARLY, ability)
    return false
end

local jumpRequested = function(window)
    return Context.Pending('primary', window) or Context.Pending('special', window)
end

local consumeJump = function(window)
    Context.Consume('primary', window)
    Context.Consume('special', window)
end

local hopSide = function(ctx)
    local side = ctx.input.side
    if math.abs(side) < Config.Ledge.jump.sideInput then return 0 end
    return side > 0 and 1 or -1
end

local hop = function(ctx, side, climbReason)
    local allowed, reason = Stamina.CanPerform('ledgejump')
    if not allowed then
        report(reason, 'ledgejump')
        return false
    end
    local ok, result = LedgeAbility.Hop(ctx, side)
    if not ok then
        report(reasons.INPUT_E_NONE, climbReason and ('%s / %s'):format(climbReason, result) or result)
        return false
    end
    Stamina.Consume('ledgejump')
    report(reasons.INPUT_E_LEDGE_JUMP, result)
    return true
end

local abilityAction = function(ctx, scan, api)
    local state = State.Current()

    if state == S.LEDGE_HANG then
        if LedgeAbility.Hopping() then return false end
        local window = Context.BufferWindow('climb')
        local requested = jumpRequested(window)
        if not requested and not LedgeAbility.CanClimbForward(ctx) then return false end
        local ledge = LedgeAbility.Current()
        if not ledge then return false end
        if not Cooldown.CanExit(LedgeAbility.name, LedgeAbility.HangElapsed(ctx.now)) then return false end
        consumeJump(window)
        local side = hopSide(ctx)
        if requested and side ~= 0 then return hop(ctx, side) end
        local result = LedgeAbility.ClimbFrom(ledge)
        if result.hold and requested then return hop(ctx, 0, result.reason) end
        report(result.hold and reasons.INPUT_E_NONE or reasons.INPUT_E_CLIMB, result.reason)
        return api.apply(ctx, LedgeAbility, result)
    end

    if state == S.LEDGE_MOVE then
        if Shimmy.IsTurning() then return false end
        return api.apply(ctx, Shimmy, Shimmy.Settle())
    end

    if state == S.WALLRUNNING or state == S.WALLCLIMBING then
        local window = Context.BufferWindow('walljump')
        if not jumpRequested(window) then return false end
        local ability = state == S.WALLRUNNING and Wallrun or Wallclimb
        if not voluntaryExit(ctx, ability.name, ability.CanExit) then return false end
        if not Cooldown.CanUse('walljump', ctx.now) then
            report(reasons.WALLJUMP_DENIED_COOLDOWN)
            return false
        end
        local allowed, reason = Stamina.CanPerform('walljump')
        if not allowed then
            consumeJump(window)
            report(reason, 'walljump')
            return false
        end
        local result = ability.JumpResult()
        if not result then return false end
        consumeJump(window)
        report(reasons.INPUT_E_WALLJUMP)
        return api.apply(ctx, ability, result)
    end

    if state == S.BALANCING then
        if not jumpRequested() then return false end
        if not voluntaryExit(ctx, Balance.name, Balance.CanExit) then return false end
        local result = Balance.JumpResult(ctx, scan)
        if not result then return false end
        consumeJump()
        report(reasons.INPUT_E_BALANCE_JUMP)
        return api.apply(ctx, Balance, result)
    end

    return false
end

local special = function(ctx, scan, api)
    Context.Consume('special')
    if not State.IsLocomotion() or ctx.now - scan.at > Config.Scan.candidateHoldMs then
        report(reasons.INPUT_E_NONE, 'special')
        return false
    end
    if api.start(ctx, Precision, S.PRECISION, scan) then
        Input.ConsumeTraversal()
        report(reasons.INPUT_JUMP_SPECIAL, 'precision')
        return true
    end
    if api.start(ctx, LongJump, S.LONGJUMP, scan) then
        Input.ConsumeTraversal()
        report(reasons.INPUT_JUMP_SPECIAL, 'longjump')
        return true
    end
    report(reasons.INPUT_E_NONE, 'special')
    return false
end

Input.Dispatch = function(ctx, scan, api)
    if Context.PressedAt('trick') and trick(ctx, scan, api) then return true end
    if Context.Pending('secondary', Context.BufferWindow('roll')) and secondary(ctx, api) then return true end
    if State.IsAbility() and (jumpRequested(Context.BufferWindow('climb')) or LedgeAbility.CanClimbForward(ctx)) then
        return abilityAction(ctx, scan, api)
    end
    if Context.Pending('special') and special(ctx, scan, api) then return true end
    return false
end

Input.Targets = function()
    return targets
end

return Input
