Config.Presets = {
    realistic = {
        scale = {
            ['Wallrun.maxDuration'] = 0.8,
            ['Wallrun.gravityScale'] = 1.35,
            ['Wallrun.minSpeed'] = 1.1,
            ['Precision.maxDistance'] = 0.85,
            ['Precision.speedFactor'] = 0.9,
            ['LongJump.forwardMultiplier'] = 0.92,
            ['LongJump.verticalBoost'] = 0.9,
            ['TicTac.upVelocity'] = 0.85,
            ['Roll.windowMs'] = 0.8,
            ['Roll.maxFall'] = 0.75,
            ['InputBuffer.duration'] = 0.75,
            ['CoyoteTime.duration'] = 0.6,
            ['Camera.maxFov'] = 0.6,
        },
        set = {},
    },
    balanced = {
        scale = {},
        set = {},
    },
    arcade = {
        scale = {
            ['Wallrun.maxDuration'] = 1.3,
            ['Wallrun.gravityScale'] = 0.8,
            ['Precision.maxDistance'] = 1.15,
            ['Precision.speedFactor'] = 1.15,
            ['LongJump.forwardMultiplier'] = 1.1,
            ['TicTac.upVelocity'] = 1.1,
            ['Roll.windowMs'] = 1.3,
            ['Roll.maxFall'] = 1.3,
            ['InputBuffer.duration'] = 1.3,
            ['CoyoteTime.duration'] = 1.4,
        },
        set = {
            ['Weapons.allowAdvancedTricks'] = true,
        },
    },
}

local resolve = function(path)
    local node, key = Config, nil
    for part in path:gmatch('[^%.]+') do
        if key then
            node = type(node) == 'table' and node[key] or nil
        end
        key = part
    end
    if type(node) ~= 'table' or node[key] == nil then return nil end
    return node, key
end

local applyPreset = function(name)
    local preset = Config.Presets[name]
    if not preset then return false end
    for path, factor in pairs(preset.scale or {}) do
        local node, key = resolve(path)
        if node and type(node[key]) == 'number' then node[key] = node[key] * factor end
    end
    for path, value in pairs(preset.set or {}) do
        local node, key = resolve(path)
        if node then node[key] = value end
    end
    return true
end

Config.ActivePreset = applyPreset(Config.Preset) and Config.Preset or 'balanced'
if Config.ActivePreset ~= Config.Preset then
    lib.print.warn(('[cr-parkour] unknown Config.Preset "%s", using "balanced"'):format(tostring(Config.Preset)))
end

local applyPerformance = function(name)
    local performance = Config.Performance
    local preset = performance.presets[name] or performance.presets.balanced
    for key, value in pairs(preset.scan) do Config.Scan[key] = value end
    Config.Detection.candidatePersistMs = preset.candidatePersistMs
    Config.Cache.geometryTTL = preset.geometryTTL
    Config.DebugPanel.textRefreshMs = preset.debugTextMs
    performance.active = preset
    return performance.presets[name] and name or 'balanced'
end

local requestedMode = Config.Performance.mode
Config.Performance.mode = applyPerformance(requestedMode)
if Config.Performance.mode ~= requestedMode then
    lib.print.warn(('[cr-parkour] unknown Config.Performance.mode "%s", using "balanced"'):format(tostring(requestedMode)))
end
