local Vec = require 'client.core.vec'
local State = require 'client.core.state'

local Context = {}

local input = Config.Input
local buffer = Config.InputBuffer
local coyote = Config.CoyoteTime
local recovery = Config.Recovery
local safety = Config.Safety
local controls = input.controls
local body = Config.Body
local reasons = Constants.Reasons
local performance = Config.Performance.active

local ctx = { input = { forward = 0.0, side = 0.0, active = false }, parkourHeld = false, speed = 0.0, speed2d = 0.0, horizontalSpeed = 0.0 }
local presses = {}
local air = { active = false, startZ = 0.0, apexZ = 0.0, velocity = Vec.Zero }
local ground = { leftAt = 0, jumped = false, locked = false, z = nil }
local enabled = true
local previous = { ped = nil, coords = nil, speed = 0.0, at = 0 }
local status = { at = 0, force = true }

local parachuteStates = {}
for i = 1, #safety.parachuteStates do parachuteStates[safety.parachuteStates[i]] = true end

local readInput = function(target)
    local forward = GetDisabledControlNormal(0, controls.moveUp) - GetDisabledControlNormal(0, controls.moveDown)
    local side = GetDisabledControlNormal(0, controls.moveRight) - GetDisabledControlNormal(0, controls.moveLeft)
    target.forward = forward
    target.side = side
    target.active = math.abs(forward) > input.deadzone or math.abs(side) > input.deadzone
    return target
end

local cameraBasis = function()
    local camForward = Vec.FromHeading(GetGameplayCamRot(Constants.CameraRotationOrder).z)
    return camForward, Vec.Right(camForward)
end

local onLadder = function(ped)
    for i = 1, #safety.ladderTasks do
        if GetIsTaskActive(ped, safety.ladderTasks[i]) then return true end
    end
    return false
end

local trackAir = function(coords, velocity)
    ctx.justLanded = false
    if ctx.airborne then
        if not air.active then
            air.active = true
            air.startZ = math.max(coords.z, ground.z or coords.z)
            air.apexZ = air.startZ
            ground.leftAt = ctx.now
            ground.jumped = ground.locked or ctx.jumping or velocity.z > coyote.maxDropSpeed
        end
        if coords.z > air.apexZ then air.apexZ = coords.z end
        air.velocity = velocity
        ctx.fallDistance = air.apexZ - coords.z
    elseif air.active then
        air.active = false
        ctx.justLanded = true
        ctx.landedFall = air.apexZ - coords.z
        ctx.landingVelocity = air.velocity
        ctx.fallDistance = 0.0
        ground.z = coords.z
    else
        ctx.fallDistance = 0.0
        ground.locked = false
        ground.z = coords.z
    end
    ctx.fallStartZ = air.apexZ
    ctx.coyote = coyote.enabled and ctx.airborne and not ground.jumped
        and ctx.now - ground.leftAt <= coyote.duration
        and velocity.z > -coyote.maxDropSpeed
end

local detectTeleport = function(ped, coords, now)
    local teleported = false
    if previous.ped ~= nil and previous.ped ~= ped then
        teleported = true
    elseif previous.coords then
        local elapsed = math.max(now - previous.at, 0) / 1000.0
        local limit = math.max(recovery.teleportDistance, previous.speed * elapsed * recovery.teleportSpeedFactor)
        local delta = coords - previous.coords
        teleported = delta.x * delta.x + delta.y * delta.y + delta.z * delta.z > limit * limit
    end
    previous.ped, previous.coords, previous.speed, previous.at = ped, coords, ctx.speed or 0.0, now
    return teleported
end

local refreshStatus = function(ped, now)
    status.at, status.force = now, false
    local vehicle = cache.vehicle
    ctx.onFoot = IsPedOnFoot(ped)
    ctx.inVehicle = vehicle ~= nil and vehicle ~= false
    ctx.enteringVehicle = IsPedGettingIntoAVehicle(ped)
    ctx.swimming = IsPedSwimming(ped)
    ctx.underwater = ctx.swimming and IsPedSwimmingUnderWater(ped)
    ctx.nativeClimbing = IsPedClimbing(ped)
    ctx.ladder = onLadder(ped)
    ctx.parachute = parachuteStates[GetPedParachuteState(ped)] == true
    ctx.freefall = IsPedInParachuteFreeFall(ped)
    ctx.armed = cache.weapon and IsPedArmed(ped, Config.Weapons.armedFlags) or false
end

Context.Update = function()
    local ped = cache.ped
    local now = GetGameTimer()
    local coords = GetEntityCoords(ped)
    local velocity = GetEntityVelocity(ped)
    local heading = GetEntityHeading(ped)

    ctx.ped = ped
    ctx.now = now
    ctx.timestamp = now
    ctx.dt = GetFrameTime()
    ctx.teleported = detectTeleport(ped, coords, now)
    ctx.coords = coords
    ctx.feetZ = coords.z - body.rootHeight
    ctx.velocity = velocity
    ctx.speed = #velocity
    ctx.speed2d = Vec.Length2d(velocity)
    ctx.horizontalSpeed = ctx.speed2d
    ctx.heading = heading
    ctx.forward = Vec.FromHeading(heading)
    ctx.right = Vec.Right(ctx.forward)
    ctx.moveDir = Vec.Normalize2d(velocity) or ctx.forward
    ctx.state = State.Current()

    readInput(ctx.input)
    if ctx.input.active or ctx.parkourHeld or State.IsAbility(ctx.state) then
        ctx.camForward, ctx.camRight = cameraBasis()
    elseif not ctx.camForward then
        ctx.camForward, ctx.camRight = ctx.forward, ctx.right
    end
    ctx.inputDir = ctx.input.active and Vec.Normalize2d(ctx.camForward * ctx.input.forward + ctx.camRight * ctx.input.side) or nil
    if ctx.inputDir then
        ctx.approachDir = ctx.inputDir
    elseif ctx.speed2d > Config.Scan.idleSpeed then
        ctx.approachDir = ctx.moveDir
    else
        ctx.approachDir = ctx.forward
    end

    ctx.sprintHeld = IsDisabledControlPressed(0, controls.sprint)
    ctx.dead = IsEntityDead(ped) or IsPedDeadOrDying(ped, true)
    ctx.gettingUp = IsPedGettingUp(ped)
    ctx.ragdoll = IsPedRagdoll(ped) or ctx.gettingUp
    if status.force or now - status.at >= performance.statusInterval then refreshStatus(ped, now) end
    ctx.jumping = IsPedJumping(ped)
    ctx.falling = IsPedFalling(ped)
    ctx.airborne = IsEntityInAir(ped) or ctx.jumping or ctx.falling
    ctx.grounded = not ctx.airborne
    ctx.sprinting = IsPedSprinting(ped)
    ctx.running = IsPedRunning(ped)
    ctx.groundClearance = GetEntityHeightAboveGround(ped) - body.rootHeight

    trackAir(coords, velocity)
    return ctx
end

Context.Get = function()
    return ctx
end

Context.RefreshStatus = function()
    status.force = true
end

Context.SetHeld = function(value)
    ctx.parkourHeld = value == true
    status.force = true
end

Context.SetEnabled = function(value)
    enabled = value == true
end

Context.IsEnabled = function()
    return enabled
end

Context.CanParkour = function(c)
    c = c or ctx
    if not c.ped then return false, reasons.PARKOUR_DENIED_NOT_ON_FOOT end
    if not enabled then return false, reasons.PARKOUR_DENIED_DISABLED end
    if c.dead then return false, reasons.PARKOUR_DENIED_DEAD end
    if c.inVehicle then return false, reasons.PARKOUR_DENIED_VEHICLE end
    if c.enteringVehicle then return false, reasons.PARKOUR_DENIED_ENTERING_VEHICLE end
    if not c.onFoot then return false, reasons.PARKOUR_DENIED_NOT_ON_FOOT end
    if c.gettingUp then return false, reasons.PARKOUR_DENIED_GETTING_UP end
    if c.ragdoll then return false, reasons.PARKOUR_DENIED_RAGDOLL end
    if c.underwater then return false, reasons.PARKOUR_DENIED_UNDERWATER end
    if c.swimming then return false, reasons.PARKOUR_DENIED_SWIMMING end
    if c.ladder then return false, reasons.PARKOUR_DENIED_LADDER end
    if c.nativeClimbing then return false, reasons.PARKOUR_DENIED_NATIVE_CLIMB end
    if c.parachute then return false, reasons.PARKOUR_DENIED_PARACHUTE end
    if c.freefall or (c.falling and c.velocity.z < -recovery.maxControlledFallSpeed) then return false, reasons.PARKOUR_DENIED_FREEFALL end
    return true, reasons.OK
end

Context.ResetAir = function()
    air.active = false
    air.apexZ = ctx.coords and ctx.coords.z or 0.0
    ground.jumped = true
    ground.locked = true
end

Context.AirVelocity = function()
    return air.velocity
end

Context.BufferWindow = function(kind)
    if not buffer.enabled then return buffer.disabledWindow end
    return kind and buffer.actions[kind] or buffer.duration
end

Context.Press = function(action)
    presses[action] = GetGameTimer()
end

Context.Pending = function(action, window)
    local at = presses[action]
    return at ~= nil and GetGameTimer() - at <= (window or Context.BufferWindow())
end

Context.PressedAt = function(action)
    return presses[action]
end

Context.Consume = function(action, window)
    if not Context.Pending(action, window) then return false end
    presses[action] = nil
    return true
end

Context.ClearPresses = function()
    presses = {}
end

Context.HasPending = function()
    local longest = Context.BufferWindow()
    for _, window in pairs(buffer.actions) do longest = math.max(longest, window) end
    for action in pairs(presses) do
        if Context.Pending(action, longest) then return true end
    end
    return false
end

Context.HasIntent = function(c, dir, speedLimit, minDot)
    if c.speed2d >= speedLimit then return true end
    return c.inputDir ~= nil and Vec.Dot(c.inputDir, dir) >= minDot
end

Context.Origin = function(coords)
    return { coords = coords, feetZ = coords.z - body.rootHeight }
end

return Context
