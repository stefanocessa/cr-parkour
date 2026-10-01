local Tuning = {}

local originals = {}
local order = {}
local menuId = 'cr-parkour:tuning'
local fields = {
    ledge = { 'forward', 'right', 'up', 'heading' },
    wallrun = { 'heading', 'wallOffset', 'up' },
}

local groups = {
    {
        id = 'vault',
        title = 'Vault',
        params = {
            { path = 'Vault.maxDistance', label = 'Distanza massima dall\'ostacolo' },
            { path = 'Vault.minSpeed', label = 'Velocità minima' },
            { path = 'Vault.minHeight', label = 'Altezza minima' },
            { path = 'Vault.maxHeight', label = 'Altezza massima' },
            { path = 'Vault.maxDepth', label = 'Profondità massima' },
            { path = 'Vault.bodyClearance', label = 'Clearance corpo sopra il top' },
            { path = 'Vault.liftClearance', label = 'Clearance bacino (altezza di progetto clip)' },
            { path = 'Vault.maxLower', label = 'Abbassamento massimo entity' },
            { path = 'Vault.maxRaise', label = 'Innalzamento massimo entity' },
            { path = 'Vault.score.minAdvanced', label = 'Score minimo vault avanzato' },
            { path = 'Vault.HeightCorrection.low', label = 'Correzione altezza low' },
            { path = 'Vault.HeightCorrection.medium', label = 'Correzione altezza medium' },
            { path = 'Vault.HeightCorrection.high', label = 'Correzione altezza high' },
        },
    },
    {
        id = 'wallrun',
        title = 'Wallrun',
        params = {
            { path = 'Wallrun.wallDistance', label = 'Distanza dal muro' },
            { path = 'Wallrun.minSpeed', label = 'Velocità minima' },
            { path = 'Wallrun.gravityScale', label = 'Moltiplicatore gravità' },
            { path = 'Wallrun.maxDuration', label = 'Durata massima (ms)' },
            { path = 'Wallrun.speedDecay', label = 'Perdita velocità (m/s²)' },
            { path = 'Wallrun.initialLift', label = 'Spinta verticale iniziale' },
        },
    },
    {
        id = 'ledge',
        title = 'Ledge',
        params = {
            { path = 'Ledge.reach', label = 'Reach orizzontale' },
            { path = 'Ledge.hangDistance', label = 'Distanza hang dal muro' },
            { path = 'Ledge.verticalOffset', label = 'Offset verticale hang' },
            { path = 'Ledge.handAlign.enabled', label = 'Allineamento automatico mani' },
            { path = 'Ledge.handAlign.heightOffset', label = 'Mani: altezza sopra il bordo' },
            { path = 'Ledge.handAlign.wallDistance', label = 'Mani: distanza dal muro' },
        },
    },
    {
        id = 'slide',
        title = 'Slide',
        params = {
            { path = 'Slide.minSpeed', label = 'Velocità minima' },
            { path = 'Slide.deceleration', label = 'Attrito (decelerazione)' },
            { path = 'Slide.minDuration', label = 'Durata minima (ms)' },
            { path = 'Slide.maxDuration', label = 'Durata massima (ms)' },
        },
    },
    {
        id = 'roll',
        title = 'Roll',
        params = {
            { path = 'Roll.windowMs', label = 'Finestra prima dell\'impatto (ms)' },
            { path = 'Roll.lateGraceMs', label = 'Finestra tardiva (ms)' },
            { path = 'Roll.minFall', label = 'Caduta minima (m)' },
            { path = 'Roll.maxFall', label = 'Caduta massima (m)' },
        },
    },
    {
        id = 'longjump',
        title = 'Long jump',
        params = {
            { path = 'LongJump.forwardMultiplier', label = 'Boost in avanti' },
            { path = 'LongJump.verticalBoost', label = 'Boost verticale' },
            { path = 'LongJump.maxHorizontalSpeed', label = 'Velocità orizzontale massima' },
            { path = 'LongJump.minSpeed', label = 'Velocità minima' },
        },
    },
}

local sortedKeys = function(tbl)
    local keys = {}
    for key in pairs(tbl) do keys[#keys + 1] = key end
    table.sort(keys)
    return keys
end

local buildOffsetGroups = function()
    local ledgeParams = {}
    for _, key in ipairs(sortedKeys(Config.Ledge.Offsets)) do
        for _, field in ipairs(fields.ledge) do
            ledgeParams[#ledgeParams + 1] = { path = ('Ledge.Offsets.%s.%s'):format(key, field), label = ('%s %s'):format(key, field) }
        end
    end
    local wallrunParams = {}
    for _, side in ipairs({ 'left', 'right' }) do
        for _, field in ipairs(fields.wallrun) do
            wallrunParams[#wallrunParams + 1] = { path = ('Wallrun.Offsets.%s.%s'):format(side, field), label = ('%s %s'):format(side, field) }
        end
    end
    groups[#groups + 1] = { id = 'ledgeOffsets', title = 'Offset animazioni ledge (up/forward: disattiva allineamento mani)', params = ledgeParams }
    groups[#groups + 1] = { id = 'wallrunOffsets', title = 'Offset wallrun sinistro/destro (wallOffset > 0 = lontano dal muro)', params = wallrunParams }
end

buildOffsetGroups()

local resolve = function(path)
    local node, key = Config, nil
    for part in path:gmatch('[^%.]+') do
        if key then node = type(node) == 'table' and node[key] or nil end
        key = part
    end
    if type(node) ~= 'table' then return nil end
    return node, key
end

local format = function(value)
    if type(value) == 'number' then
        local text = ('%.3f'):format(value):gsub('0+$', ''):gsub('%.$', '')
        return text
    end
    return tostring(value)
end

Tuning.Get = function(path)
    local node, key = resolve(path)
    return node and node[key]
end

Tuning.Set = function(path, value)
    local node, key = resolve(path)
    if not node then return false end
    if originals[path] == nil then
        originals[path] = node[key] == nil and false or node[key]
        order[#order + 1] = path
    end
    node[key] = value
    return true
end

Tuning.SetAnimationOffset = function(name, offset)
    Config.AnimationOffsets = Config.AnimationOffsets or {}
    local path = ('AnimationOffsets.%s'):format(name)
    if originals[path] == nil then
        originals[path] = Config.AnimationOffsets[name] or false
        order[#order + 1] = path
    end
    Config.AnimationOffsets[name] = offset
end

Tuning.Changes = function()
    local list = {}
    for i = 1, #order do
        local path = order[i]
        local now = path:find('^AnimationOffsets%.') and Config.AnimationOffsets[path:sub(18)] or Tuning.Get(path)
        if type(now) == 'table' then
            now = ('f %.2f r %.2f u %.2f h %.1f'):format(now.forward or 0, now.right or 0, now.up or 0, now.heading or 0)
        end
        local before = originals[path]
        list[#list + 1] = ('%s: %s -> %s'):format(path, type(before) == 'table' and 'tabella' or format(before), format(now))
    end
    return list
end

Tuning.ResetAll = function()
    for i = #order, 1, -1 do
        local path = order[i]
        local before = originals[path]
        if path:find('^AnimationOffsets%.') then
            Config.AnimationOffsets[path:sub(18)] = before or nil
        else
            local node, key = resolve(path)
            if node then node[key] = before end
        end
    end
    originals, order = {}, {}
end

local editParam = function(param, reopen)
    local current = Tuning.Get(param.path)
    if type(current) == 'boolean' then
        Tuning.Set(param.path, not current)
        return reopen()
    end
    local input = lib.inputDialog(param.label, {
        { type = 'input', label = param.path, default = format(current), description = ('originale %s'):format(format(originals[param.path] ~= nil and originals[param.path] or current)), required = true },
    })
    local value = input and tonumber(input[1])
    if value then Tuning.Set(param.path, value) end
    reopen()
end

local openGroup
openGroup = function(group, actions)
    local options = {}
    for _, param in ipairs(group.params) do
        local current = Tuning.Get(param.path)
        local original = originals[param.path]
        local changed = original ~= nil and original ~= current
        options[#options + 1] = {
            title = param.label,
            description = ('runtime %s  |  originale %s'):format(format(current), format(original ~= nil and original or current)),
            icon = changed and 'pen' or 'sliders',
            iconColor = changed and '#FFB458' or nil,
            onSelect = function() editParam(param, function() openGroup(group, actions) end) end,
        }
    end
    lib.registerContext({ id = menuId .. ':' .. group.id, title = group.title, menu = menuId, options = options })
    lib.showContext(menuId .. ':' .. group.id)
end

local animationOffset = function(actions, reopen)
    local input = lib.inputDialog('Offset animazione (voce registry)', {
        { type = 'input', label = 'Voce registry', placeholder = 'vault.monkey', required = true },
        { type = 'input', label = 'forward', default = '0' },
        { type = 'input', label = 'right', default = '0' },
        { type = 'input', label = 'up', default = '0' },
        { type = 'input', label = 'heading', default = '0' },
    })
    if input and input[1] and input[1] ~= '' then
        Tuning.SetAnimationOffset(input[1], {
            forward = tonumber(input[2]) or 0.0,
            right = tonumber(input[3]) or 0.0,
            up = tonumber(input[4]) or 0.0,
            heading = tonumber(input[5]) or 0.0,
        })
        actions.rebuildOffsets()
    end
    reopen()
end

local onOff = function(value)
    return value and 'ON' or 'OFF'
end

Tuning.Open = function(actions)
    local reopen = function() Tuning.Open(actions) end
    local flags = actions.flags()
    local options = {
        { title = ('Debug rays: %s'):format(onOff(flags.rays)), icon = 'route', onSelect = function() actions.toggle('rays') reopen() end },
        { title = ('Debug state: %s'):format(onOff(flags.state)), icon = 'table-list', onSelect = function() actions.toggle('state') reopen() end },
        { title = ('Debug animations: %s'):format(onOff(flags.animations)), icon = 'person-running', onSelect = function() actions.toggle('animations') reopen() end },
        { title = ('Debug performance: %s'):format(onOff(flags.performance)), icon = 'gauge', onSelect = function() actions.toggle('performance') reopen() end },
        { title = 'Reload animation config', icon = 'rotate', onSelect = function() actions.reloadAnimations() reopen() end },
        { title = 'Reset parkour state', icon = 'eraser', onSelect = actions.reset },
        { title = 'Force recovery', icon = 'life-ring', onSelect = actions.recover },
        { title = 'Copy current debug info', icon = 'copy', onSelect = actions.snapshot },
    }
    for _, group in ipairs(groups) do
        options[#options + 1] = { title = group.title, icon = 'sliders', arrow = true, onSelect = function() openGroup(group, actions) end }
    end
    options[#options + 1] = { title = 'Offset animazione (registry)', icon = 'arrows-up-down-left-right', onSelect = function() animationOffset(actions, reopen) end }
    local changes = Tuning.Changes()
    options[#options + 1] = {
        title = ('Valori modificati: %d'):format(#changes),
        icon = 'list',
        description = #changes > 0 and 'Seleziona per stamparli in F8 e copiarli' or 'Nessuna modifica runtime',
        disabled = #changes == 0,
        onSelect = function()
            local text = table.concat(changes, '\n')
            print(('[cr-parkour] tuning runtime\n%s'):format(text))
            lib.setClipboard(text)
            reopen()
        end,
    }
    options[#options + 1] = {
        title = 'Ripristina valori originali',
        icon = 'clock-rotate-left',
        disabled = #changes == 0,
        onSelect = function()
            Tuning.ResetAll()
            actions.reloadAnimations()
            reopen()
        end,
    }
    lib.registerContext({ id = menuId, title = ('Parkour tuning (%s)'):format(Config.ActivePreset or 'balanced'), options = options })
    lib.showContext(menuId)
end

return Tuning
