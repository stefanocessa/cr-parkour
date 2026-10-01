local pack = 'parkour@anims'
local pack2 = 'parkour_part_2@anim'

Config.AnimationRegistry = {
    ledge = {
        grab = {
            custom = 'ledge.idle',
            native = { dict = 'missfam1_yachtbattleonyacht02_', clip = 'onboom_twohand_hang_idle', flags = { 'LOOPING' }, blendIn = 6.0, headingOffset = 180.0 },
        },
        idle = {
            custom = { dict = pack2, clip = 'ledge_idle', flags = { 'LOOPING' }, blendIn = 6.0 },
            native = 'ledge.grab',
        },
        moveLeft = {
            custom = { dict = pack2, clip = 'ledge_move_l', flags = { 'LOOPING' }, blendIn = 6.0 },
            native = { dict = 'missfam1_yachtbattleonyacht02_', clip = 'onboom_twohand_hang_idle', flags = { 'LOOPING' }, playbackRate = 1.4, headingOffset = 180.0 },
        },
        moveRight = {
            custom = { dict = pack2, clip = 'ledge_move_r', flags = { 'LOOPING' }, blendIn = 6.0 },
            native = 'ledge.moveLeft',
        },
        cornerLeft = {
            custom = { dict = pack2, clip = 'ledge_corner_outer_l', flags = { 'HOLD_LAST_FRAME' }, blendIn = 6.0 },
            native = 'ledge.grab',
            syncDuration = true,
        },
        cornerRight = {
            custom = { dict = pack2, clip = 'ledge_corner_outer_r', flags = { 'HOLD_LAST_FRAME' }, blendIn = 6.0 },
            native = 'ledge.grab',
            syncDuration = true,
        },
        jumpLeft = {
            custom = { dict = pack2, clip = 'ledge_jump_l', flags = { 'NOT_INTERRUPTABLE' }, blendIn = 6.0 },
            meta = { duration = 1.00, lift = 1.25, cross = 0.57, side = -3.35, rise = 0.0 },
        },
        jumpRight = {
            custom = { dict = pack2, clip = 'ledge_jump_r', flags = { 'NOT_INTERRUPTABLE' }, blendIn = 6.0 },
            meta = { duration = 1.00, lift = 1.25, cross = 0.57, side = 3.35, rise = 0.0 },
        },
        jumpUp = {
            custom = { dict = pack2, clip = 'ledge_jump_up', flags = { 'NOT_INTERRUPTABLE', 'HOLD_LAST_FRAME' }, blendIn = 6.0 },
            meta = { duration = 0.87, lift = 1.31, cross = 0.69, side = 0.0, rise = 1.19 },
        },
        jumpUpPower = {
            custom = { dict = pack2, clip = 'ledge_jump_up_power', flags = { 'NOT_INTERRUPTABLE', 'HOLD_LAST_FRAME' }, blendIn = 6.0 },
            meta = { duration = 1.00, lift = 2.44, cross = 0.97, side = 0.0, rise = 2.42 },
        },
        hangingSequence = { custom = { dict = pack2, clip = 'hanging_sequince' } },
        climb = {
            native = { dict = 'missfbi1', clip = 'ledge_climbout', flags = { 'NOT_INTERRUPTABLE' }, blendIn = 6.0, playbackRate = 1.3 },
            syncDuration = true,
        },
        climbStand = {
            native = { dict = 'move_climb', clip = 'standclimbup_180_low', flags = { 'NOT_INTERRUPTABLE' }, playbackRate = 1.1 },
        },
    },

    wallrun = {
        left = {
            custom = { dict = pack2, clip = 'wallrun_left_side', flags = { 'HOLD_LAST_FRAME' }, blendIn = 6.0 },
            native = { dict = 'move_climb', clip = 'clamberpose_run_angled_20', flags = { 'LOOPING' } },
        },
        right = {
            custom = { dict = pack2, clip = 'wallrun_right_side', flags = { 'HOLD_LAST_FRAME' }, blendIn = 6.0 },
            native = 'wallrun.left',
        },
    },

    walljump = {
        left = {
            native = { dict = 'move_jump', clip = 'jump_launch_high_l', blendIn = 8.0 },
        },
        right = {
            native = { dict = 'move_jump', clip = 'jump_launch_high_r', blendIn = 8.0 },
        },
        back = {
            native = { dict = 'move_jump', clip = 'jump_launch_long_high_r', blendIn = 8.0 },
        },
    },

    wallclimb = {
        run = {
            native = { dict = 'move_climb', clip = 'runclimbup_295_low', flags = { 'NOT_INTERRUPTABLE' }, playbackRate = 1.2 },
        },
    },

    vault = {
        jumpOver1 = {
            custom = { dict = pack, clip = 'jump_over_01', flags = { 'NOT_INTERRUPTABLE' }, blendIn = 8.0 },
            native = { dict = 'move_climb', clip = 'standvault_80', flags = { 'NOT_INTERRUPTABLE' }, blendIn = 8.0, playbackRate = 1.3 },
            meta = {
                generic = true,
                duration = 1.17, lift = 0.44, cross = 0.63, crossDistance = 2.75, touch = 0.83, touchDistance = 1.01,
                minHeight = 0.50, maxHeight = 1.00, minDepth = 0.0, maxDepth = 1.0, minSpeed = 0.0, maxSpeed = 9.5, preferredAngle = 0.0, maxAngle = 50.0,
                requiresAirborne = false, clearanceRequired = 0.90, verticalOffset = 0.0, forwardOffset = 0.0, rootMotion = false,
            },
        },
        jumpOver2 = {
            custom = { dict = pack, clip = 'jump_over_02', flags = { 'NOT_INTERRUPTABLE' }, blendIn = 8.0 },
            native = { dict = 'move_climb', clip = 'standvaultclose_80', flags = { 'NOT_INTERRUPTABLE' }, blendIn = 8.0, playbackRate = 1.1 },
            meta = {
                generic = true,
                duration = 2.10, lift = 0.78, cross = 0.37, crossDistance = 2.57, touch = 0.57, touchDistance = 1.08,
                minHeight = 0.85, maxHeight = 1.35, minDepth = 0.0, maxDepth = 1.2, minSpeed = 0.0, maxSpeed = 9.5, preferredAngle = 0.0, maxAngle = 50.0,
                requiresAirborne = false, clearanceRequired = 1.00, verticalOffset = 0.0, forwardOffset = 0.0, rootMotion = false,
            },
        },
        jumpOver3 = {
            custom = { dict = pack, clip = 'jump_over_03', flags = { 'NOT_INTERRUPTABLE' }, blendIn = 8.0 },
            native = 'vault.jumpOver1',
            meta = {
                generic = true,
                duration = 1.20, lift = 0.41, cross = 0.31, crossDistance = 1.09, touch = 0.78, touchDistance = 2.07,
                minHeight = 0.50, maxHeight = 0.95, minDepth = 0.0, maxDepth = 0.8, minSpeed = 0.0, maxSpeed = 9.5, preferredAngle = 0.0, maxAngle = 50.0,
                requiresAirborne = false, clearanceRequired = 0.85, verticalOffset = 0.0, forwardOffset = 0.0, rootMotion = false,
            },
        },
        kash = {
            custom = { dict = pack2, clip = 'kash_vault', flags = { 'NOT_INTERRUPTABLE' }, blendIn = 8.0 },
            meta = {
                duration = 1.48, lift = 0.77, cross = 0.32, crossDistance = 1.80, touch = 0.81, touchDistance = 2.99,
                minHeight = 0.80, maxHeight = 1.35, minDepth = 0.3, maxDepth = 1.4, minSpeed = 4.0, maxSpeed = 9.5, preferredAngle = 0.0, maxAngle = 20.0,
                requiresAirborne = false, clearanceRequired = 0.85, verticalOffset = 0.0, forwardOffset = 0.0, rootMotion = false,
            },
        },
        monkey = {
            custom = { dict = pack2, clip = 'monkey_vault', flags = { 'NOT_INTERRUPTABLE' }, blendIn = 8.0 },
            meta = {
                duration = 0.97, lift = 0.76, cross = 0.41, crossDistance = 1.80, touch = 0.79, touchDistance = 2.19,
                minHeight = 0.80, maxHeight = 1.35, minDepth = 0.4, maxDepth = 1.6, minSpeed = 3.5, maxSpeed = 9.5, preferredAngle = 0.0, maxAngle = 25.0,
                requiresAirborne = false, clearanceRequired = 0.80, verticalOffset = 0.0, forwardOffset = 0.0, rootMotion = false,
            },
        },
        safety = {
            custom = { dict = pack2, clip = 'safety_l_vault', flags = { 'NOT_INTERRUPTABLE' }, blendIn = 8.0 },
            meta = {
                duration = 1.00, lift = 0.77, cross = 0.37, crossDistance = 1.54, touch = 0.80, touchDistance = 1.49,
                minHeight = 0.60, maxHeight = 1.30, minDepth = 0.0, maxDepth = 1.0, minSpeed = 1.5, maxSpeed = 7.0, preferredAngle = 0.0, maxAngle = 35.0,
                requiresAirborne = false, clearanceRequired = 0.95, verticalOffset = 0.0, forwardOffset = 0.0, rootMotion = false,
            },
        },
        reverse = {
            custom = { dict = pack2, clip = 'revers_l_vault', flags = { 'NOT_INTERRUPTABLE' }, blendIn = 8.0 },
            meta = {
                duration = 0.93, lift = 0.65, cross = 0.36, crossDistance = 1.94, touch = 0.79, touchDistance = 1.46,
                minHeight = 0.60, maxHeight = 1.20, minDepth = 0.0, maxDepth = 0.8, minSpeed = 2.5, maxSpeed = 7.5, preferredAngle = 30.0, minAngle = 20.0, maxAngle = 50.0,
                requiresAirborne = false, clearanceRequired = 1.05, verticalOffset = 0.0, forwardOffset = 0.0, rootMotion = false,
            },
        },
        slide = {
            custom = { dict = pack2, clip = 'slide_r_vault', flags = { 'NOT_INTERRUPTABLE' }, blendIn = 8.0 },
            meta = {
                duration = 1.33, lift = 0.60, cross = 0.25, crossDistance = 1.11, touch = 0.80, touchDistance = 3.37,
                minHeight = 0.50, maxHeight = 1.10, minDepth = 0.5, maxDepth = 1.8, minSpeed = 2.5, maxSpeed = 8.0, preferredAngle = 0.0, maxAngle = 30.0,
                requiresAirborne = false, clearanceRequired = 0.75, verticalOffset = 0.0, forwardOffset = 0.0, rootMotion = false,
            },
        },
        roll = {
            custom = { dict = pack2, clip = 'roll_a_vault', flags = { 'NOT_INTERRUPTABLE' }, blendIn = 8.0 },
            meta = {
                duration = 1.07, lift = 0.64, cross = 0.22, crossDistance = 1.11, touch = 0.78, touchDistance = 3.51,
                minHeight = 0.60, maxHeight = 1.15, minDepth = 0.8, maxDepth = 2.0, minSpeed = 3.0, maxSpeed = 8.0, preferredAngle = 0.0, maxAngle = 25.0,
                requiresAirborne = false, clearanceRequired = 0.70, verticalOffset = 0.0, forwardOffset = 0.0, rootMotion = false,
            },
        },
    },

    jump = {
        big = {
            custom = { dict = pack, clip = 'big_jump_01', flags = { 'NOT_INTERRUPTABLE' }, blendIn = 8.0 },
            native = { dict = 'move_jump', clip = 'jump_launch_long_high_l', blendIn = 8.0 },
            meta = { duration = 2.37, lift = 0.76, cross = 0.38, crossDistance = 2.97, touch = 0.54, touchDistance = 1.13 },
        },
        swing = {
            custom = { dict = pack, clip = 'swing_jump', flags = { 'NOT_INTERRUPTABLE' }, blendIn = 8.0 },
            native = { dict = 'move_jump', clip = 'jump_launch_long_l', blendIn = 8.0 },
            meta = { duration = 2.43, lift = 0.94, cross = 0.73, crossDistance = 3.85, touch = 0.86, touchDistance = 0.84 },
        },
    },

    tictac = {
        left = { custom = { dict = pack2, clip = 'tictak_l_vault', flags = { 'NOT_INTERRUPTABLE' }, blendIn = 8.0 } },
        right = { custom = { dict = pack2, clip = 'tictak_r_vault', flags = { 'NOT_INTERRUPTABLE' }, blendIn = 8.0 } },
    },

    wallflip = {
        custom = { dict = pack, clip = 'wall_flip', flags = { 'NOT_INTERRUPTABLE' }, blendIn = 8.0 },
        meta = {
            duration = 2.23,
            contact = 0.27,
            land = 0.58,
            settle = 0.84,
            lift = 0.88,
            curve = { 0.01, 0.49, 1.03, 1.45, 1.67, 1.64, 1.55, 1.44, 1.11, 0.83, 0.67, 0.53, 0.42, 0.32, 0.29, 0.28, 0.29 },
        },
    },

    longjump = {
        custom = 'jump.big',
        native = { dict = 'move_jump', clip = 'jump_launch_long_high_l', blendIn = 8.0 },
    },

    precision = {
        short = { native = { dict = 'move_jump', clip = 'jump_launch_l', blendIn = 8.0 } },
        medium = { native = { dict = 'move_jump', clip = 'jump_launch_long_l', blendIn = 8.0 } },
        long = { custom = 'jump.swing', native = 'precision.medium' },
    },

    roll = {
        forward = {
            custom = 'roll.right',
            native = { dict = 'move_fall', clip = 'land_roll', flags = { 'NOT_INTERRUPTABLE' }, blendIn = 8.0 },
            syncDuration = true,
        },
        left = {
            custom = { dict = pack2, clip = 'diveroll_l', flags = { 'NOT_INTERRUPTABLE' }, blendIn = 8.0 },
            native = 'roll.forward',
            syncDuration = true,
        },
        right = {
            custom = { dict = pack2, clip = 'diveroll_r', flags = { 'NOT_INTERRUPTABLE' }, blendIn = 8.0 },
            native = 'roll.forward',
            syncDuration = true,
        },
    },

    slide = {
        forward = {
            custom = { dict = pack, clip = 'slide', flags = { 'HOLD_LAST_FRAME', 'NOT_INTERRUPTABLE' }, blendIn = 8.0 },
            native = { dict = 'missheistfbi3b_ig6_v2', clip = 'rubble_slide_gunman', flags = { 'HOLD_LAST_FRAME', 'NOT_INTERRUPTABLE' }, blendIn = 8.0 },
            meta = {
                duration = 1.53, lowStart = 0.17, lowEnd = 0.65, standPhase = 0.78, bodyDrop = 0.60,
                curve = { 0.00, 0.69, 1.48, 2.26, 3.00, 3.67, 4.21, 4.68, 5.10, 5.53, 6.12 },
                minPassage = 1.0, minSpeed = 3.0, maxSpeed = 9.0, rootMotion = false,
            },
        },
        backside = {
            custom = { dict = pack, clip = 'slide_backside', flags = { 'HOLD_LAST_FRAME', 'NOT_INTERRUPTABLE' }, blendIn = 8.0 },
            native = 'slide.forward',
            meta = {
                duration = 2.07, lowStart = 0.13, lowEnd = 0.56, standPhase = 0.63, bodyDrop = 0.76,
                curve = { 0.00, 0.78, 1.89, 2.83, 3.61, 4.30, 4.91, 5.77, 6.45, 7.05, 7.83 },
                minPassage = 0.85, minSpeed = 3.0, maxSpeed = 9.0, rootMotion = false,
            },
        },
        kipUp = {
            custom = { dict = pack, clip = 'slide_kip_up', flags = { 'NOT_INTERRUPTABLE' }, blendIn = 6.0 },
            meta = {
                duration = 2.77, lowStart = 0.12, lowEnd = 0.47, standPhase = 0.90, bodyDrop = 0.61,
                curve = { 0.00, 1.35, 2.78, 3.92, 4.85, 5.30, 5.60, 6.05, 6.62, 7.11, 7.52 },
                minPassage = 1.0, minSpeed = 1.5, maxSpeed = 4.5, rootMotion = false,
            },
        },
    },

    land = {
        hard = {
            native = { dict = 'move_fall', clip = 'high_land_stand', flags = { 'UPPERBODY', 'SECONDARY' } },
        },
    },

    balance = {
        idle = { custom = { dict = pack2, clip = 'balance_idle', flags = { 'LOOPING' }, blendIn = 4.0 } },
        run = { custom = { dict = pack2, clip = 'balance_run', flags = { 'LOOPING' }, blendIn = 4.0 } },
        jump = { custom = { dict = pack2, clip = 'balance_jump_f', flags = { 'NOT_INTERRUPTABLE' }, blendIn = 6.0 } },
        dropLeft = { custom = { dict = pack2, clip = 'balance_drop_l' } },
        dropRight = { custom = { dict = pack2, clip = 'balance_drop_r' } },
    },

    tricks = {
        frontflip = {},
        backflip = {},
        sideflipLeft = {},
        sideflipRight = {},
        frontTwist = { custom = { dict = pack, clip = 'front_twist_flip', flags = { 'NOT_INTERRUPTABLE' }, blendIn = 8.0 } },
        swingJump = { custom = { dict = pack, clip = 'swing_jump' } },
    },
}
