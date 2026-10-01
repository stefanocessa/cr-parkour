Config = {}

-- ============================================================================
-- General
-- ============================================================================

-- Gameplay tuning preset applied on top of this file (see shared/presets.lua):
-- 'realistic' | 'balanced' | 'arcade'. 'balanced' = the values below, unchanged.
Config.Preset = 'balanced'

-- Debug overlay (raycasts, state panel, reason codes). Keep false in production.
Config.Debug = false

-- Registers the debug commands (/parkourdebug, /parkoursnapshot, /parkourperf, /parkouranims, /parkouranim)
-- even when Config.Debug, Config.TuningMode and Config.Profiler.enabled are all false.
Config.DebugCommands = false

-- In-game ox_lib tuning menu opened by /parkourdebug. Development only.
Config.TuningMode = false

-- ============================================================================
-- Input
-- ============================================================================

Config.Input = {
    command = 'parkour',                                             -- keybind name (+parkour / -parkour)
    description = 'Parkour: tieni premuto per la modalità parkour',  -- shown in FiveM key settings
    primaryKey = 'E',                                                -- default key, players can rebind it
    deadzone = 0.25,                                                 -- movement stick/keys deadzone
    controls = {                                                     -- GTA control ids
        jump = 22,
        duck = 36,
        context = { 38, 51 },
        sprint = 21,
        moveUp = 32,
        moveDown = 33,
        moveLeft = 34,
        moveRight = 35,
    },
    -- GTA controls disabled while an ability is running
    blockedDuringAbility = { 21, 22, 24, 25, 30, 31, 32, 33, 34, 35, 36, 37, 44, 45, 140, 141, 142, 257, 263, 264 },
}

-- Remembers a press for a short time so it can fire on the next valid scan (ms).
Config.InputBuffer = {
    enabled = true,
    duration = 200,
    disabledWindow = 34,
    actions = {
        climb = 450,
        walljump = 300,
        roll = 250,
        trick = 150,
    },
}

-- Grace time after walking off an edge during which precision / long jump still start (ms).
Config.CoyoteTime = {
    enabled = true,
    duration = 120,
    maxDropSpeed = 2.5,
}

-- ============================================================================
-- Performance
-- ============================================================================

-- 'quality' | 'balanced' | 'performance': only changes loop / scan intervals and cache lifetimes (ms).
Config.Performance = {
    mode = 'balanced',
    presets = {
        quality = {
            idleTick = 150,
            moveTick = 80,
            wakeSlice = 25,
            statusInterval = 50,
            watchdogInterval = 100,
            debugTextMs = 100,
            candidatePersistMs = 150,
            geometryTTL = 80,
            scan = { idleInterval = 90, moveInterval = 45, runInterval = 30, sprintInterval = 25, airInterval = 15, activeInterval = 15 },
        },
        balanced = {
            idleTick = 250,
            moveTick = 120,
            wakeSlice = 50,
            statusInterval = 100,
            watchdogInterval = 150,
            debugTextMs = 150,
            candidatePersistMs = 120,
            geometryTTL = 120,
            scan = { idleInterval = 120, moveInterval = 60, runInterval = 40, sprintInterval = 30, airInterval = 15, activeInterval = 20 },
        },
        performance = {
            idleTick = 300,
            moveTick = 150,
            wakeSlice = 75,
            statusInterval = 150,
            watchdogInterval = 250,
            debugTextMs = 200,
            candidatePersistMs = 100,
            geometryTTL = 180,
            scan = { idleInterval = 150, moveInterval = 75, runInterval = 50, sprintInterval = 40, airInterval = 20, activeInterval = 25 },
        },
    },
}

-- Raycast / obstacle geometry cache. geometryTTL is overwritten by the performance preset.
Config.Cache = {
    geometryTTL = 120,
    positionTolerance = 0.08,
    headingTolerance = 6.0,
    normalDot = 0.99,
}

-- Timing overlay (/parkourperf). Development only.
Config.Profiler = {
    enabled = false,
    command = 'parkourperf',
}

-- ============================================================================
-- Body, physics and raycasts (meters unless noted)
-- ============================================================================

Config.Body = {
    rootHeight = 0.98,
    height = 1.8,
    radius = 0.3,
    headHeight = 1.7,
    handReach = 2.1,
}

Config.Physics = {
    gravity = 9.81,
}

-- Shape test flags / options passed to StartExpensiveSynchronousShapeTestLosProbe.
Config.Raycast = {
    flags = 19,
    options = 4,
}

-- Named body heights above the feet, used by every scan.
Config.Heights = {
    feet = 0.15,
    knees = 0.5,
    waist = 0.95,
    chest = 1.3,
    head = 1.7,
    overhead = 2.1,
}

-- Surface classification from the hit normal's Z component.
Config.Surface = {
    maxWallNormalZ = 0.35,
    minTopNormalZ = 0.75,
    maxCeilingNormalZ = -0.75,
}

-- ============================================================================
-- Detection
-- ============================================================================

-- Scan intervals (ms) are overwritten by the active performance preset.
Config.Scan = {
    idleInterval = 120,
    moveInterval = 60,
    runInterval = 40,
    sprintInterval = 30,
    airInterval = 15,
    activeInterval = 20,
    idleSpeed = 0.4,
    runSpeed = 3.5,
    sideScanSpeed = 2.0,
    candidateHoldMs = 250,
    downDistance = 3.0,
    upDistance = 1.2,
}

-- Tolerances applied to every ability boundary, and short persistence of a valid candidate (ms).
Config.Detection = {
    heightTolerance = 0.05,
    distanceTolerance = 0.15,
    angleTolerance = 10.0,
    speedTolerance = 0.5,
    candidatePersistMs = 120,
    persistProbeBelow = 0.1,
    persistDistance = 0.35,
    persistDot = 0.9,
}

-- Front obstacle measurement: edge, top surface, depth.
Config.Obstacle = {
    heights = { 'feet', 'knees', 'waist', 'chest', 'head', 'overhead' },
    ambiguousMargin = 0.5,
    scanDistance = 1.5,
    groundProbe = 0.6,
    baseInset = 0.12,
    faceMargin = 0.35,
    edgeRefine = 5,
    topSamples = { 0.04, 0.1, 0.18 },
    topProbeAbove = 0.25,
    topProbeBelow = 0.15,
    maxTopVariance = 0.18,
    depthStep = 0.12,
    depthRefine = 3,
    depthProbeAbove = 0.15,
    depthTolerance = 0.15,
    maxDepth = 2.1,
    ceilingMargin = 0.1,
}

-- Wall detection (front / left / right).
Config.Wall = {
    heights = { 'waist', 'chest', 'head' },
    minHits = 2,
    maxNormalSpread = 25.0,
    sideDistance = 1.1,
    frontDistance = 1.3,
}

Config.Landing = {
    probeAbove = 0.5,
    clearanceHeight = 1.8,
}

-- Ballistic prediction used by precision, long jump, tricks and wall flip.
Config.Trajectory = {
    step = 0.08,
    maxTime = 2.0,
    feetProbe = 0.1,
    guideBreakSpeed = 2.5,
}

-- Material names or hashes that are never parkour surfaces. whitelist = nil disables the whitelist.
Config.Materials = {
    blacklist = { 'tree_bark', 'leaves', 'bushes', 'twigs' },
    whitelist = nil,
}

-- Vehicles, moving props and blacklisted models still block the player but are not used as parkour surfaces.
Config.DynamicSurfaces = {
    vehicles = true,
    movingProps = true,
    movingSpeed = 0.1,
    blacklistVehicleClasses = { 14, 15, 16, 19, 20, 21 },
    blacklistModels = {
        'prop_vend_soda_01', 'prop_vend_soda_02', 'prop_vend_water_01', 'prop_vend_coffe_01',
        'prop_vend_condom_01', 'prop_vend_fags_01', 'prop_vend_snak_01', 'prop_vend_snak_01_tu',
        'prop_atm_01', 'prop_atm_02', 'prop_atm_03', 'prop_fleeca_atm',
        'prop_phonebox_01a', 'prop_phonebox_01b', 'prop_phonebox_01c', 'prop_phonebox_02', 'prop_phonebox_03',
        'prop_phonebox_04',
        'prop_gas_pump_1a', 'prop_gas_pump_1b', 'prop_gas_pump_1c', 'prop_gas_pump_1d', 'prop_gas_pump_old2',
        'prop_gas_pump_old3',
        'monster', 'monster3', 'monster4', 'monster5', 'marshall', 'bigfoot',
        'rhino', 'khanjali', 'apc', 'chernobog', 'barrage', 'halftrack', 'minitank', 'scarab', 'scarab2', 'scarab3',
        'dump', 'cutter', 'bulldozer', 'rubble', 'tiptruck', 'tiptruck2', 'phantom', 'phantom2', 'phantom3', 'hauler',
        'hauler2', 'packer',
    },
}

-- ============================================================================
-- Traversal (OVER / UNDER / THROUGH / CLIMB / LEDGE / WALL / BALANCE)
-- ============================================================================

-- Body layers and category scores of the traversal space scanner.
Config.Traversal = {
    layers = { 'feet', 'knees', 'waist', 'chest', 'head', 'overhead' },
    lowerLayers = { 'feet', 'knees' },
    contactLayers = { 'feet', 'knees', 'waist' },
    upperLayers = { 'waist', 'chest', 'head' },
    lateralProbe = 1.0,
    scores = { UNDER = 0.95, OVER = 0.85, THROUGH = 0.8, CLIMB = 0.75, LEDGE = 0.65, WALL = 0.5, BALANCE = 0.9, OPEN = 0.2 },
    quality = 0.4,
    floatingPenalty = 0.6,
    priority = { 'UNDER', 'OVER', 'THROUGH', 'BALANCE', 'CLIMB', 'LEDGE', 'WALL' },
}

Config.TraversalCapsule = {
    width = 0.6,
    standingHeight = 1.8,
    crouchedHeight = 1.2,
    slideHeight = 0.95,
    shoulderHeights = { 'knees', 'waist', 'chest', 'head' },
}

-- Ability scoring and reason-code priority used by the resolver.
Config.Resolver = {
    fallbackScore = { ledge = 1.0, balance = 0.95, tictac = 0.6 },
    defaultScore = 0.5,
    tieMargin = 0.05,
    weights = {
        wallclimb = { base = 0.5, height = 0.3, angle = 0.2 },
        wallrun = { base = 0.4, angle = 0.6 },
    },
    reasonOrder = { 'OVER', 'THROUGH', 'UNDER', 'CLIMB', 'LEDGE', 'WALL', 'BALANCE' },
    noGeometry = {
        'VAULT_DENIED_NO_OBSTACLE', 'NO_OBSTACLE', 'WALLCLIMB_DENIED_NO_WALL', 'WALLRUN_DENIED_NO_WALL',
        'LEDGE_DENIED_NO_WALL',
        'TICTAC_DENIED_NO_WALL', 'BALANCE_DENIED_NO_SURFACE', 'BALANCE_DENIED_SURFACE_TOO_WIDE',
        'BALANCE_DENIED_NOT_ELEVATED',
        'UNDER_LOWER_BLOCKED', 'UNDER_NO_BLOCKER', 'THROUGH_NO_FRAME', 'WALL_NONE', 'CLIMB_PREFERRED',
        'LEDGE_DENIED_STATE',
    },
    escalate = { 'OBSTACLE_TALL', 'OBSTACLE_TOO_HIGH', 'CLIMB_NOT_CLIMBABLE' },
}

-- Anti-loop on the same obstacle: blocked until the cooldown passes AND the player moved resetDistance away
-- (always released after releaseMs). Same obstacle from the other side is a new target.
Config.TraversalRepeat = {
    vault = { sameObstacleCooldown = 350, resetDistance = 1.0, releaseMs = 2000, radius = 0.6, sameSideDot = 0.7 },
    wallclimb = { sameObstacleCooldown = 600, resetDistance = 1.2, releaseMs = 2500, radius = 1.0, sameSideDot = 0.7 },
}

-- Extra time after a kinematic traversal before the watchdog forces a reset (ms).
Config.CollisionTraversal = {
    graceMs = 500,
}

-- UNDER: cinematic slide under low obstacles along a validated corridor.
Config.Under = {
    enabled = true,
    triggerDistance = 1.6,
    step = 0.35,
    maxLength = 7.5,
    exitScan = 4.2,
    stepUp = 0.4,
    stepDown = 0.4,
    headroomTolerance = 0.1,
    corridorHeights = { 'feet', 'knees' },
    shoulderHeight = 'knees',
    entryMargin = 0.3,
    exitMargin = 0.4,
    minExitLength = 1.0,
    intentSpeed = 1.2,
    intentDot = 0.5,
    maxApproachAngle = 40.0,
    pool = { 'slide.forward', 'slide.backside', 'slide.kipUp' },
    rate = { min = 0.8, max = 1.4, standing = 3.0 },
    momentumKeep = 0.9,
    minExitSpeed = 2.5,
    groundTolerance = 0.35,
    score = { speed = 0.7, exit = 0.3, passageSpan = 0.6, speedSpan = 3.0 },
}

-- THROUGH: window-like openings (vault through) and full-height openings (no ability).
Config.Through = {
    enabled = true,
    probeDistance = 1.4,
    frameMargin = 0.1,
    frameDepth = 0.5,
    exitDistance = 1.0,
}

-- ============================================================================
-- Vault (OVER traversal)
-- ============================================================================

Config.Vault = {
    enabled = true,
    -- registry entries evaluated for every vault; generic jump_over clips are the fallback
    pool = {
        'vault.kash', 'vault.monkey', 'vault.safety', 'vault.reverse', 'vault.slide', 'vault.roll',
        'vault.jumpOver1', 'vault.jumpOver3', 'vault.jumpOver2',
    },
    minHeight = 0.50,
    maxHeight = 1.35,
    minSpeed = 0.0,
    intentSpeed = 1.2,          -- below this speed the player must push towards the obstacle
    intentDot = 0.5,
    maxDistance = 1.3,
    maxApproachAngle = 50.0,
    maxDepth = 2.0,
    landingOffset = 0.5,
    maxRunout = 1.5,
    runoutHeights = { 'knees', 'chest' },
    runoutStepTolerance = 0.4,
    maxDrop = 2.5,
    minLandingDrop = 0.25,
    bodyClearance = 0.55,
    headClearance = 0.3,
    topClearance = 0.7,
    pathHeights = { 0.0, 0.5 },
    exitClearance = 0.7,
    exitHeights = { 'knees', 'chest' },
    groundTolerance = 0.35,
    jumpOutVelocity = 4.2,
    liftClearance = 0.45,       -- first value to tune in game if the body passes too high / too low
    maxLower = 0.6,
    maxRaise = 0.25,
    rootTolerance = 0.15,
    rate = { min = 0.8, max = 1.4, standing = 3.0 },
    momentumKeep = 0.88,
    minExitSpeed = 2.5,
    score = {
        height = 0.4,
        depth = 0.2,
        speed = 0.15,
        angle = 0.15,
        approach = 0.1,
        heightSpan = 0.6,
        speedSpan = 3.0,
        angleSpan = 45.0,
        approachSpan = 1.5,
        minAdvanced = 0.55,
        advancedBonus = 0.1,
        tieMargin = 0.02,
    },
    heightBands = { low = 0.75, medium = 1.05 },
    HeightCorrection = { low = 0.0, medium = 0.0, high = 0.0 },
}

-- ============================================================================
-- Wallrun / walljump / wall climb
-- ============================================================================

Config.Wallrun = {
    enabled = true,
    allowGroundStart = true,
    minSpeed = 4.2,
    endSpeed = 2.8,
    maxApproachAngle = 40.0,
    minGroundClearance = 0.35,
    maxDuration = 1600,         -- ms
    speedKeep = 0.95,
    speedDecay = 1.2,
    drag = 0.08,
    initialLift = 2.2,
    maxEntryLift = 4.0,
    gravityScale = 0.28,
    wallDistance = 0.42,
    distanceTolerance = 0.03,
    stickGain = 8.0,
    maxCurve = 35.0,
    forwardClearance = 1.2,
    blockedPush = 1.6,
    lostGraceMs = 120,
    wallCheckInterval = 50,
    sameWallDot = 0.9,
    sameWallCooldown = 900,
    ledgeScanInterval = 60,
    towardWallDot = 0.5,
    turnGain = 10.0,
    animation = { left = 'wallrun.left', right = 'wallrun.right' },
    Offsets = {                 -- visual correction per side
        left = { heading = 0.0, wallOffset = 0.0, up = 0.0 },
        right = { heading = 0.0, wallOffset = 0.0, up = 0.0 },
    },
}

Config.Walljump = {
    enabled = true,
    fromWallclimb = true,
    pushOut = 5.2,
    upVelocity = 5.0,
    alongKeep = 0.65,
    impulseMs = 120,
    minDuration = 260,
    turnGain = 8.0,
    animation = { left = 'walljump.left', right = 'walljump.right', back = 'walljump.back' },
}

Config.Wallclimb = {
    enabled = true,
    minSpeed = 0.0,
    runSpeed = 3.5,
    slowMaxHeight = 3.2,        -- max ledge height when approaching below runSpeed
    intentSpeed = 1.2,
    intentDot = 0.5,
    maxDistance = 1.0,
    maxApproachAngle = 40.0,
    minHeight = 1.3,
    maxHeight = 4.4,
    headClearance = 0.6,
    climbSpeed = 3.6,
    speedFromEntry = 0.25,
    deceleration = 3.2,
    maxDuration = 900,
    maxRise = 2.4,
    wallDistance = 0.4,
    settleGain = 10.0,
    turnGain = 12.0,
    pushOffVelocity = 2.0,
    animation = 'wallclimb.run',
}

-- ============================================================================
-- Ledge / shimmy / climb-up
-- ============================================================================

Config.Ledge = {
    enabled = true,
    autoGrabFromAbility = true, -- grab a ledge during an air ability even without holding the parkour key
    reach = 1.0,
    faceHeights = { 'chest', 'head', 'overhead' },
    faceDistance = 1.3,
    scanStep = 0.2,
    scanBackoff = 0.3,
    minHeight = 1.2,
    maxHeight = 4.6,
    grabMinOffset = -0.45,
    grabMaxOffset = 0.55,
    minApproachDot = 0.35,
    maxFallSpeed = 13.0,
    topInset = 0.2,
    topProbeAbove = 0.5,
    topTolerance = 0.3,
    headClearance = 0.9,
    landingDepth = 0.55,
    climbClearance = 1.7,
    hangDistance = 0.38,
    verticalOffset = -1.15,
    climbWithForward = true,
    grabDuration = 220,
    minHangMs = 250,
    climbForwardThreshold = 0.6,
    regrabCooldown = 650,
    jump = {                    -- ledge to ledge hops (up / side)
        enabled = true,
        upMin = 0.6,
        upMax = 1.5,
        powerMax = 2.6,
        wallProbe = 0.3,
        sideInput = 0.5,
        sideMin = 1.2,
        sideMax = 3.6,
        sideStep = 0.3,
        sideTolerance = 0.4,
    },
    dropPush = 1.2,
    alignGain = 12.0,
    validateInterval = 150,
    invalidGraceMs = 200,
    pushTolerance = 0.35,
    driftTolerance = 0.03,
    driftRate = 0.6,
    placeEpsilon = 0.004,
    headingEpsilon = 0.2,
    handAlign = {               -- automatic hand-to-edge alignment while hanging
        enabled = true,
        heightOffset = 0.12,
        wallDistance = 0.05,
        gain = 4.0,
        tolerance = 0.04,
        deadband = 0.015,
        maxCorrection = 1.1
    },
    animation = {
        grab = 'ledge.grab',
        idle = 'ledge.idle',
        left = 'ledge.moveLeft',
        right = 'ledge.moveRight',
        cornerLeft = 'ledge.cornerLeft',
        cornerRight = 'ledge.cornerRight',
        climb = 'ledge.climb',
        jumpLeft = 'ledge.jumpLeft',
        jumpRight = 'ledge.jumpRight',
        jumpUp = 'ledge.jumpUp',
        jumpUpPower = 'ledge.jumpUpPower',
    },
    Offsets = {                 -- visual correction per ledge animation
        grab = { forward = 0.0, right = 0.0, up = 0.0, heading = 0.0 },
        idle = { forward = 0.0, right = 0.0, up = 0.0, heading = 0.0 },
        moveLeft = { forward = 0.0, right = 0.0, up = 0.0, heading = 0.0 },
        moveRight = { forward = 0.0, right = 0.0, up = 0.0, heading = 0.0 },
        cornerLeft = { forward = 0.0, right = 0.0, up = 0.0, heading = 0.0 },
        cornerRight = { forward = 0.0, right = 0.0, up = 0.0, heading = 0.0 },
        climb = { forward = 0.0, right = 0.0, up = 0.0, heading = 0.0 },
    },
    offsetAnimation = {
        grab = 'grab',
        idle = 'idle',
        moveLeft = 'left',
        moveRight = 'right',
        cornerLeft = 'cornerLeft',
        cornerRight = 'cornerRight',
        climb = 'climb',
    },
}

Config.Shimmy = {
    enabled = true,
    speed = 1.13,
    probeAhead = 0.35,
    maxStep = 0.3,
    bodyCheck = 0.15,
    turnGain = 10.0,
    corner = {
        enabled = true,
        reach = 0.6,
        depth = 0.3,
        inset = 0.25,
        minAngle = 30.0,
        maxAngle = 135.0,
        duration = 600,
        bulge = 0.3,
    },
}

Config.Climb = {
    enabled = true,
    duration = 900,
    arc = 0.35,
    exitSpeed = 2.0,
    exitSprintSpeed = 5.0,
    momentumKeep = 0.3,
    recoverLift = 2.0,
}

-- ============================================================================
-- Slide / roll / fall
-- ============================================================================

-- Manual slide (parkour key + crouch while running).
Config.Slide = {
    enabled = true,
    minSpeed = 4.0,
    entryKeep = 1.05,
    deceleration = 3.8,
    minDuration = 450,
    maxDuration = 1300,
    exitSpeed = 2.2,
    underSpeed = 1.6,
    frontBlockDistance = 0.6,
    airborneCancel = 0.6,
    minUphillNormalZ = 0.94,
    slopeInterval = 120,
    slopeGravity = 0.6,
    maxSpeed = 9.0,
    turnGain = 12.0,
    variant = 'forward',
    animations = { forward = 'slide.forward', backside = 'slide.backside', kipUp = 'slide.kipUp' },
    kipUp = {
        enabled = false,
        maxSpeed = 1.5,
        duration = 1200,
        brake = 0.25,
    },
}

Config.Roll = {
    enabled = true,
    windowMs = 350,             -- press crouch this long before impact
    lateGraceMs = 120,          -- ...or this long after landing
    minFall = 2.2,
    maxFall = 14.0,
    predictDistance = 30.0,
    duration = 650,
    momentumKeep = 0.8,
    veryLargeKeep = 0.45,
    largeFallReduction = 0.5,
    frontClearance = 1.0,
    frontHeights = { 'knees', 'waist' },
    minSpeed = 3.2,
    deceleration = 2.5,
    sideThreshold = 0.35,
    turnGain = 12.0,
    animations = { forward = 'roll.forward', left = 'roll.left', right = 'roll.right' },
}

-- Fall categories (m). damagePerMeter = 0 disables the built-in damage.
-- serverHook sends a rate-limited, client-reported 'cr-parkour:server:fallImpact' (never trust it for economy/anticheat).
Config.Fall = {
    medium = 2.2,
    large = 4.0,
    veryLarge = 9.0,
    hardLandingKeep = 0.45,
    ragdollTime = { min = 1500, max = 3000 },
    damagePerMeter = 0,
    serverHook = true,
    reportCooldown = 1000,
    maxReportedDistance = 500.0,
}

-- Emits the local 'cr-parkour:damage' event for every damage hook.
Config.Damage = {
    events = true,
}

-- ============================================================================
-- Air abilities: tic-tac, wall flip, precision, long jump, tricks
-- ============================================================================

Config.TicTac = {
    enabled = true,
    minSpeed = 4.0,
    minAngle = 20.0,
    maxAngle = 70.0,
    contactDistance = 1.0,
    tangentKeep = 0.9,
    normalRestitution = 0.55,
    minPush = 2.5,
    upVelocity = 4.2,
    exitClearance = 1.5,
    impulseMs = 150,
    minDuration = 300,
    turnGain = 10.0,
    animation = { left = 'tictac.left', right = 'tictac.right' },
}

-- Requires the custom 'wallflip' clip (no native fallback).
Config.WallFlip = {
    enabled = true,
    minSpeed = 1.5,
    maxDistance = 1.2,
    maxApproachAngle = 30.0,
    minWallHeight = 1.9,
    headClearance = 1.2,
    backClearance = 2.2,
    backHeights = { 'knees', 'waist', 'chest', 'head' },
    backSpeed = 3.2,
    upVelocity = 5.6,
    maxDrop = 3.0,
    minLandingTime = 0.35,
    impulseMs = 200,
    endEvent = 'control',
    maxDuration = 2200,
    turnGain = 10.0,
    animation = 'wallflip',
    autoWhenTooHigh = true,     -- try a wall flip automatically when the wall is too high to climb
    wallGap = 0.55,
    landingTolerance = 0.35,
    phaseRefine = 8,
}

Config.Precision = {
    enabled = true,
    minDistance = 1.4,
    maxDistance = 5.5,
    step = 0.3,
    gapDepth = 0.6,
    maxRise = 1.2,
    maxDrop = 3.0,
    probeAbove = 0.6,
    heightTolerance = 0.25,
    arcHeight = 0.6,
    minLandingWidth = 0.35,
    widthProbe = 0.6,
    widthStep = 0.1,
    minLandingDepth = 0.3,
    landingInset = 0.2,
    standingSpeed = 3.0,
    speedFactor = 1.35,
    maxHorizontalSpeed = 9.5,
    maxVerticalSpeed = 7.0,
    pathTolerance = 0.6,
    minDuration = 250,
    turnGain = 12.0,
    classes = {
        { name = 'short',  maxDistance = 2.2,  animation = 'precision.short' },
        { name = 'medium', maxDistance = 3.8,  animation = 'precision.medium' },
        { name = 'long',   maxDistance = 99.0, animation = 'precision.long' },
    },
}

Config.LongJump = {
    enabled = true,
    minSpeed = 5.5,
    forwardMultiplier = 1.25,
    maxHorizontalSpeed = 10.0,
    verticalBoost = 1.5,
    clearDistance = 2.5,
    headClearance = 0.5,
    minAirTime = 0.35,
    impulseMs = 120,
    turnGain = 12.0,
    minDuration = 1500,
    animation = 'jump.big',
}

-- Air tricks. Only 'tricks.frontTwist' has a clip (custom pack), the other directions are denied.
Config.Tricks = {
    enabled = true,
    modifier = {                -- second keybind, used together with the parkour key
        command = 'parkourtrick',
        description = 'Parkour: wall flip / trick (insieme al tasto parkour)',
        key = 'X',
    },
    minGroundDistance = 2.2,
    minAirTime = 0.75,
    headClearance = 0.6,
    minVerticalSpeed = -6.0,
    pop = 1.2,
    endEvent = 'control',
    animations = {
        forward = 'tricks.frontflip',
        back = 'tricks.backflip',
        left = 'tricks.sideflipLeft',
        right = 'tricks.sideflipRight',
        none = 'tricks.frontTwist',
    },
}

-- ============================================================================
-- Balance
-- ============================================================================

Config.Balance = {
    enabled = true,
    maxWidth = 0.55,
    exitWidth = 0.75,
    minDrop = 0.6,
    probeStep = 0.08,
    probeRange = 0.6,
    probeAbove = 0.3,
    heightTolerance = 0.15,
    minForward = 0.8,
    maxEntrySpeed = 6.5,
    walkSpeed = 1.3,
    runSpeed = 2.6,
    centerGain = 6.0,
    turnGain = 8.0,
    scanInterval = 90,
    jumpForward = 3.8,
    jumpUp = 4.2,
    animation = { idle = 'balance.idle', run = 'balance.run', jump = 'balance.jump' },
}

-- ============================================================================
-- Combos and momentum
-- ============================================================================

-- After an ability ends, chained abilities within transitionWindow (ms) get minSpeed * speedGrace.
Config.Combo = {
    transitionWindow = 900,
    speedGrace = 0.8,
    chains = {
        tictac = { 'wallrun', 'tictac', 'ledge', 'trick' },
        wallrun = { 'walljump', 'ledge', 'wallflip' },
        walljump = { 'wallrun', 'tictac', 'ledge', 'trick' },
        vault = { 'precision', 'longjump', 'tictac' },
        longjump = { 'ledge', 'tictac', 'wallrun', 'trick' },
        precision = { 'roll', 'ledge', 'tictac', 'wallrun', 'precision' },
        balance = { 'precision', 'ledge' },
        wallflip = { 'roll' },
    },
}

Config.Momentum = {
    carryWindowMs = 400,
    maxSpeed = 12.0,
    forceMotionSpeed = 2.0,
}

-- ============================================================================
-- Gameplay rules: cooldowns, safety, weapons, stamina
-- ============================================================================

-- Per ability (ms): cooldown after the end, retriggerDelay after the start,
-- minimumExitTime before a voluntary exit. globalGap = minimum time between two ability starts.
Config.Cooldowns = {
    globalGap = 90,
    vault = { cooldown = 150, retriggerDelay = 0, minimumExitTime = 0 },
    slide = { cooldown = 700, retriggerDelay = 0, minimumExitTime = 0 },
    roll = { cooldown = 300, retriggerDelay = 0, minimumExitTime = 0 },
    wallrun = { cooldown = 250, retriggerDelay = 0, minimumExitTime = 180 },
    walljump = { cooldown = 0, retriggerDelay = 250, minimumExitTime = 0 },
    wallclimb = { cooldown = 300, retriggerDelay = 0, minimumExitTime = 150 },
    ledge = { cooldown = 0, retriggerDelay = 0, minimumExitTime = 150 },
    shimmy = { cooldown = 0, retriggerDelay = 0, minimumExitTime = 0 },
    climb = { cooldown = 0, retriggerDelay = 0, minimumExitTime = 0 },
    tictac = { cooldown = 0, retriggerDelay = 350, minimumExitTime = 0 },
    wallflip = { cooldown = 0, retriggerDelay = 900, minimumExitTime = 0 },
    precision = { cooldown = 0, retriggerDelay = 400, minimumExitTime = 0 },
    longjump = { cooldown = 0, retriggerDelay = 1200, minimumExitTime = 0 },
    trick = { cooldown = 0, retriggerDelay = 600, minimumExitTime = 0 },
    balance = { cooldown = 400, retriggerDelay = 0, minimumExitTime = 300 },
}

-- Watchdog: max time in each ability state before Recovery.SafeReset (ms).
Config.StateTimeouts = {
    VAULTING = 2500,
    SLIDING = 3500,
    ROLLING = 2500,
    WALLRUNNING = 3000,
    WALLCLIMBING = 2000,
    WALLJUMPING = 4000,
    LEDGE_GRAB = 1500,
    CLIMBING = 3500,
    TICTAC = 4000,
    WALLFLIP = 4000,
    PRECISION = 5000,
    LONGJUMP = 5000,
    TRICK = 4000,
}

-- A coordinate jump above teleportDistance (or a ped change) resets parkour without residual velocity.
Config.Recovery = {
    teleportDistance = 8.0,
    teleportSpeedFactor = 1.5,
    maxControlledFallSpeed = 25.0,
}

-- GTA task ids / parachute states that block parkour.
Config.Safety = {
    ladderTasks = { 1, 47, 48 },
    parachuteStates = { 1, 2, 3 },
}

Config.Weapons = {
    allowParkour = true,
    allowAdvancedTricks = false,  -- when armed, only simpleAbilities are allowed
    armedFlags = 7,
    simpleAbilities = { 'vault', 'slide', 'roll', 'wallclimb', 'ledge', 'shimmy', 'climb', 'balance' },
}

-- Optional GTA stamina integration. costs = % of max stamina per start, drain = % per second.
Config.Stamina = {
    enabled = false,
    costs = {
        vault = 6.0,
        wallrun = 5.0,
        wallclimb = 10.0,
        walljump = 8.0,
        ledge = 4.0,
        climb = 6.0,
        longjump = 10.0,
        slide = 5.0,
        ledgejump = 6.0,
        tictac = 6.0,
        wallflip = 10.0,
        precision = 8.0,
        trick = 8.0,
        roll = 0.0,
        shimmy = 0.0,
        balance = 0.0,
    },
    drain = {
        wallrun = 18.0,
    },
    minDrainTime = 0.3,
}

-- ============================================================================
-- Animations (registry in shared/animations.lua)
-- ============================================================================

-- Resolution order for every entry: custom clip -> native GTA clip -> safe (no clip, virtual timeline).
Config.Animations = {
    enabled = true,             -- false = never use custom clips
    fallbackToNative = true,
    debugMissing = true,        -- print missing dict/clip warnings (only while debug is on)
    loadTimeout = 1500,
    retryMs = 5000,
    maxAliasDepth = 4,
    rootMotionAssist = 0.35,
    rootMotionThreshold = 0.15,
    headingThreshold = 5.0,
    startPhase = 0.0,
    instantBlend = 1000.0,
    crossFade = { blendIn = 6.0, blendOut = 6.0 },
    defaults = {
        blendIn = 4.0,
        blendOut = 4.0,
        duration = -1,
        flag = 0,
        playbackRate = 1.0,
        lockX = false,
        lockY = false,
        lockZ = false,
        rootMotion = false,
        cancelable = true,
        headingOffset = 0.0,
        positionOffset = { forward = 0.0, right = 0.0, up = 0.0 },
    },
    events = {                  -- normalized clip phases used by abilities
        start = 0.0,
        assist = 0.25,
        cross = 0.5,
        transition = 0.6,
        control = 0.85,
        exit = 1.0,
    },
}

-- Per entry overrides, e.g. Config.AnimationOverrides['ledge.idle'] = { custom = { dict = '...', clip = '...' } }
Config.AnimationOverrides = {}

-- Per entry visual offsets, e.g. Config.AnimationOffsets['vault.kash'] = { forward = 0.0, right = 0.0, up = 0.0, heading = 0.0 }
Config.AnimationOffsets = {}

-- Optional "dict clip" lists of the custom pack, only used by the /parkouranims report.
Config.AnimationPack = {
    manifests = { 'stream/animas-1.txt', 'stream/anims-2.txt' },
}

Config.AnimationTools = {
    listCommand = 'parkouranims',
    measureCommand = 'parkouranim',
    maxMeasureMs = 6000,
    reportDelayMs = 3000,
}

-- ============================================================================
-- Camera
-- ============================================================================

-- Light roll / FOV / shake effects. overlay = false disables the scripted camera overlay (roll / FOV).
Config.Camera = {
    enabled = true,
    overlay = true,
    blendIn = 6.0,
    blendOut = 3.5,
    maxRoll = 6.0,
    maxFov = 10.0,
    settleEpsilon = 0.02,
    wallrun = { roll = 3.0, fovBoost = 4.0 },
    slide = { fovBoost = 3.0 },
    roll = { fovBoost = 1.5, shake = 0.15 },
    wallflip = { fovBoost = 3.0 },
    precision = { fovBoost = 2.5 },
    longJump = { fovBoost = 5.0 },
    ledgeGrab = { fovBoost = -2.0, duration = 350, shake = 0.2 },
    walljump = { shake = 0.12 },
    landing = { shake = 0.35, heavyShake = 0.5 },
    shakeName = 'JOLT_SHAKE',
    heavyShakeName = 'HIGH_FALL_SHAKE',
}

-- ============================================================================
-- Debug
-- ============================================================================

Config.DebugCommand = 'parkourdebug'
Config.SnapshotCommand = 'parkoursnapshot'

-- What the debug overlay draws once enabled.
Config.DebugFlags = {
    rays = true,
    state = true,
    animations = true,
}

Config.DebugPanel = {
    x = 0.012,
    y = 0.08,
    width = 0.2,
    lineHeight = 0.016,
    scale = 0.27,
    font = 4,
    persistMs = 160,
    pointSize = 0.08,
    ledgeMarkWidth = 0.3,
    padding = 0.004,
    backgroundAlpha = 150,
    reasonTtl = 3000,
    vectorLength = 0.8,
    pathSegments = 14,
    performanceX = 0.79,
    performanceWidth = 0.2,
    pipelineX = 0.225,
    pipelineWidth = 0.21,
}
