local Vec = require 'client.core.vec'
local State = require 'client.core.state'
local Movement = require 'client.core.movement'
local Animation = require 'client.systems.animation'

local AnimationDebug = {}

local settings = Config.Animations
local tools = Config.AnimationTools
local reasons = Constants.Reasons

local info = function(text)
    lib.print.info('[cr-parkour] ' .. text)
end

local waitDict = function(dict)
    local deadline = GetGameTimer() + settings.loadTimeout
    local state = Animation.Load(dict)
    while state == 'loading' and GetGameTimer() < deadline do
        Wait(0)
        state = Animation.Load(dict)
    end
    return state
end

local validate = function(dict, clip)
    local state = waitDict(dict)
    if state ~= 'loaded' then return state end
    return GetAnimDuration(dict, clip) > 0.0 and 'ok' or 'missing_clip'
end

local resolveWithin = function(name)
    local deadline = GetGameTimer() + settings.loadTimeout
    local spec, source = Animation.Resolve(name)
    while not spec and source == 'loading' and GetGameTimer() < deadline do
        Wait(0)
        spec, source = Animation.Resolve(name)
    end
    return spec, source
end

local customOf
customOf = function(name)
    local entry = Animation.Get(name)
    local custom = entry and entry.custom
    if type(custom) == 'string' then return customOf(custom) end
    return type(custom) == 'table' and custom or nil
end

AnimationDebug.Report = function()
    local manifest = lib.callback.await('cr-parkour:animationManifest', false)
    local listed = {}

    info('ANIMATION PACK (stream + TXT)')
    for i = 1, #(manifest and manifest.missing or {}) do
        lib.print.warn(('[cr-parkour] %s: %s'):format(reasons.ANIMATION_MANIFEST_MISSING, manifest.missing[i]))
    end
    if manifest then
        for i = 1, #manifest.entries do
            local item = manifest.entries[i]
            local key = item.dict .. '/' .. item.clip
            listed[key] = false
            local result = validate(item.dict, item.clip)
            if result == 'ok' then
                info(('  TXT %s -> ok (%.0f ms)'):format(key, GetAnimDuration(item.dict, item.clip) * 1000.0))
            else
                lib.print.warn(('[cr-parkour]   TXT %s -> %s (%s)'):format(key, reasons.ANIMATION_ASSET_MISSING, result))
            end
        end
    end

    info('CUSTOM ANIMATIONS FOUND')
    local names = Animation.List()
    local group
    for i = 1, #names do
        local name = names[i]
        local head = name:match('^[^%.]+')
        if head ~= group then
            group = head
            info(group .. ':')
        end
        local custom = customOf(name)
        local spec, source = resolveWithin(name)
        local used = spec and ('%s/%s'):format(spec.dict, spec.clip) or '-'
        if custom then
            local key = custom.dict .. '/' .. custom.clip
            if listed[key] ~= nil then listed[key] = true end
            local note = manifest and listed[key] == nil and ('  ' .. reasons.ANIMATION_NOT_IN_MANIFEST) or ''
            info(('  - %s -> %s [%s]%s'):format(name, used, source, note))
        else
            info(('  - %s -> %s [%s] (nessuna custom nel pack)'):format(name, used, source))
        end
    end

    for key, mapped in pairs(listed) do
        if not mapped then info(('  TXT non mappata nel registry: %s'):format(key)) end
    end
end

AnimationDebug.Measure = function(name)
    local ped = cache.ped
    if State.IsAbility() then return lib.print.warn('[cr-parkour] ability attiva, riprova da fermo') end
    local spec, source = resolveWithin(name)
    if not spec then return lib.print.warn(('[cr-parkour] %s non risolvibile (%s)'):format(name, source)) end

    local startCoords = GetEntityCoords(ped)
    local startHeading = GetEntityHeading(ped)
    local duration = math.min(GetAnimDuration(spec.dict, spec.clip) * 1000.0 / spec.playbackRate, tools.maxMeasureMs)
    Animation.Play(name, { restart = true })
    Wait(math.floor(duration))

    local moved = Vec.Distance2d(startCoords, GetEntityCoords(ped))
    local rise = GetEntityCoords(ped).z - startCoords.z
    local turned = math.abs(Movement.HeadingDelta(startHeading, GetEntityHeading(ped)))
    Animation.Stop(name)

    local rootMotion = moved >= settings.rootMotionThreshold
    info(('%s [%s] %s/%s  durata %.0fms  spostamento %.2fm  dz %.2fm  heading %.1f  headingOffset %.1f  -> rootMotion = %s%s'):format(
        name, source, spec.dict, spec.clip, duration, moved, rise, turned, spec.headingOffset, tostring(rootMotion),
        turned >= settings.headingThreshold and '  (modifica heading)' or ''))
end

return AnimationDebug
