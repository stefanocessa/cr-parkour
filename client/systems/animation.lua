local Vec = require 'client.core.vec'
local Rays = require 'client.debug.rays'
local DebugState = require 'client.debug.state'

local Animation = {}

local settings = Config.Animations
local defaults = settings.defaults
local flagValues = Constants.AnimFlags
local reasons = Constants.Reasons
local anyTask = Constants.AnyAnimTask

local dicts = {}
local clips = {}
local normalized = {}
local warned = {}
local played = {}
local track = nil
local tick = 0
local pose = { heading = 0.0, forward = 0.0, right = 0.0, up = 0.0, logicalHeading = nil }
local zeroOffset = { forward = 0.0, right = 0.0, up = 0.0, heading = 0.0 }
local extraOffsets = {}

local buildExtraOffsets = function()
    extraOffsets = {}
    for name, offset in pairs(Config.AnimationOffsets or {}) do extraOffsets[name] = offset end
    local ledge = Config.Ledge
    for key, animationKey in pairs(ledge.offsetAnimation) do
        local name = ledge.animation[animationKey]
        if name and ledge.Offsets[key] then extraOffsets[name] = ledge.Offsets[key] end
    end
    local wallrun = Config.Wallrun
    for side, name in pairs(wallrun.animation) do
        if wallrun.Offsets[side] then extraOffsets[name] = wallrun.Offsets[side] end
    end
end

buildExtraOffsets()

local warn = function(code, detail)
    DebugState.SetReason('anim', code, detail)
    if not settings.debugMissing or not Rays.IsEnabled() then return end
    local key = code .. detail
    if warned[key] then return end
    warned[key] = true
    lib.print.warn(('[cr-parkour] %s: %s'):format(code, detail))
end

local lookup = function(name)
    local node = Config.AnimationRegistry
    for part in name:gmatch('[^%.]+') do
        node = type(node) == 'table' and node[part] or nil
    end
    if type(node) ~= 'table' then return nil end
    local override = Config.AnimationOverrides[name]
    if not override then return node end
    local merged = {}
    for key, value in pairs(node) do merged[key] = value end
    for key, value in pairs(override) do merged[key] = value end
    return merged
end

local normalize = function(spec)
    if normalized[spec] then return normalized[spec] end
    local result = {}
    for key, value in pairs(defaults) do result[key] = value end
    for key, value in pairs(spec) do result[key] = value end
    local flag = result.flag
    for i = 1, #(spec.flags or {}) do flag = flag | (flagValues[spec.flags[i]] or 0) end
    result.flag = flag
    normalized[spec] = result
    return result
end

local collect
collect = function(name, list, depth)
    local entry = lookup(name)
    if not entry or depth > settings.maxAliasDepth then return list end
    for _, kind in ipairs({ 'custom', 'native' }) do
        local spec = entry[kind]
        local allowed = (kind == 'custom' and settings.enabled)
            or (kind == 'native' and (settings.fallbackToNative or not entry.custom))
        if allowed and type(spec) == 'string' then
            collect(spec, list, depth + 1)
        elseif allowed and type(spec) == 'table' and spec.dict and spec.clip then
            list[#list + 1] = { spec = normalize(spec), source = kind }
        end
    end
    return list
end

local clipExists = function(spec)
    local key = spec.dict .. '/' .. spec.clip
    if clips[key] == nil then clips[key] = GetAnimDuration(spec.dict, spec.clip) > 0.0 end
    return clips[key]
end

local clipDuration = function(spec)
    return GetAnimDuration(spec.dict, spec.clip) * 1000.0 / spec.playbackRate
end

local isEntry = function(node)
    return node.custom ~= nil or node.native ~= nil or next(node) == nil
end

local eachEntry
eachEntry = function(node, path, callback)
    if type(node) ~= 'table' then return end
    if isEntry(node) then return callback(path) end
    for key, child in pairs(node) do eachEntry(child, path == '' and key or path .. '.' .. key, callback) end
end

Animation.Get = lookup

Animation.Meta = function(name)
    local entry = lookup(name)
    return entry and entry.meta or nil
end

Animation.Load = function(dict)
    local now = GetGameTimer()
    local entry = dicts[dict]
    if HasAnimDictLoaded(dict) then
        if not entry or entry.state ~= 'loaded' then dicts[dict] = { state = 'loaded', at = now } end
        return 'loaded'
    end
    if entry and entry.state == 'missing' then return 'missing' end
    if entry and entry.state == 'failed' and now - entry.at < settings.retryMs then return 'failed' end
    if entry and entry.state == 'loading' then
        if now - entry.at <= settings.loadTimeout then return 'loading' end
        dicts[dict] = { state = 'failed', at = now }
        warn(reasons.ANIM_LOAD_TIMEOUT, dict)
        return 'failed'
    end
    if not DoesAnimDictExist(dict) then
        dicts[dict] = { state = 'missing', at = now }
        warn(reasons.ANIM_MISSING_DICT, dict)
        return 'missing'
    end
    RequestAnimDict(dict)
    dicts[dict] = { state = 'loading', at = now }
    return 'loading'
end

Animation.Resolve = function(name)
    local list = collect(name, {}, 0)
    local pending = false
    for i = 1, #list do
        local candidate = list[i]
        local state = Animation.Load(candidate.spec.dict)
        if state == 'loaded' then
            if clipExists(candidate.spec) then return candidate.spec, candidate.source end
            warn(reasons.ANIM_MISSING_CLIP, candidate.spec.dict .. '/' .. candidate.spec.clip)
        elseif state == 'loading' then
            pending = true
        end
    end
    return nil, pending and 'loading' or 'safe'
end

Animation.Pick = function(names)
    local fallback
    for i = 1, #names do
        local spec, source = Animation.Resolve(names[i])
        if spec and source == 'custom' then return names[i] end
        if spec and not fallback then fallback = names[i] end
    end
    return fallback or names[1]
end

Animation.Duration = function(name)
    local spec = Animation.Resolve(name)
    return spec and clipDuration(spec) or nil
end

Animation.SyncedDuration = function(name, fallback)
    local entry = lookup(name)
    if not entry or not entry.syncDuration then return fallback end
    return Animation.Duration(name) or fallback
end

Animation.Preload = function()
    eachEntry(Config.AnimationRegistry, '', function(name)
        local list = collect(name, {}, 0)
        for i = 1, #list do Animation.Load(list[i].spec.dict) end
    end)
end

Animation.List = function()
    local result = {}
    eachEntry(Config.AnimationRegistry, '', function(name) result[#result + 1] = name end)
    table.sort(result)
    return result
end

Animation.Play = function(name, options)
    options = options or {}
    local ped = cache.ped
    if track and track.name == name and not options.restart and track.spec
        and IsEntityPlayingAnim(ped, track.spec.dict, track.spec.clip, anyTask) then
        return true
    end

    local entry = lookup(name)
    local spec, source = nil, 'safe'
    if entry then spec, source = Animation.Resolve(name) end
    if not spec then warn(source == 'loading' and reasons.ANIM_NOT_LOADED or reasons.ANIM_MISSING, name) end

    local reason = 'custom_ok'
    if source ~= 'custom' then
        if not entry then
            reason = 'animation_not_registered'
        elseif entry.custom then
            reason = 'custom_animation_not_found'
        elseif spec then
            reason = 'no_custom_in_pack'
        else
            reason = 'animation_not_found'
        end
    end

    local events = {}
    for key, value in pairs(settings.events) do events[key] = value end
    for key, value in pairs(entry and entry.events or {}) do events[key] = value end

    track = {
        name = name,
        spec = spec,
        source = spec and source or 'safe',
        reason = reason,
        startedAt = GetGameTimer(),
        duration = options.duration or (spec and clipDuration(spec)) or nil,
        looping = spec ~= nil and spec.flag & flagValues.LOOPING ~= 0,
        events = events,
        callbacks = {},
        progress = options.startPhase or 0.0,
        seek = options.startPhase and options.startPhase > 0.0 and options.startPhase or nil,
        rate = (options.rate or 1.0) * (spec and spec.playbackRate or 1.0),
    }

    if not spec then return false end
    TaskPlayAnim(ped, spec.dict, spec.clip, options.blendIn or spec.blendIn, options.blendOut or spec.blendOut, spec.duration, spec.flag, settings.startPhase, spec.lockX, spec.lockY, spec.lockZ)
    if track.rate ~= 1.0 then SetEntityAnimSpeed(ped, spec.dict, spec.clip, track.rate) end
    played[spec.dict .. '/' .. spec.clip] = spec
    return true
end

local stopSpec = function(spec, blendOut)
    if spec and IsEntityPlayingAnim(cache.ped, spec.dict, spec.clip, anyTask) then
        StopAnimTask(cache.ped, spec.dict, spec.clip, blendOut or spec.blendOut)
    end
end

Animation.CrossFade = function(name, options)
    options = options or {}
    local previous = track and track.spec
    local fade = settings.crossFade
    local ok = Animation.Play(name, {
        duration = options.duration,
        restart = options.restart,
        blendIn = options.blendIn or (previous and fade.blendIn) or nil,
        blendOut = options.blendOut,
    })
    local nextSpec = track and track.spec
    if previous and (not nextSpec or nextSpec.dict ~= previous.dict or nextSpec.clip ~= previous.clip) then
        stopSpec(previous, options.blendOut or fade.blendOut)
    end
    return ok
end

local resetPose = function()
    if pose.logicalHeading and math.abs(pose.heading) > Constants.Epsilon then
        SetEntityHeading(cache.ped, pose.logicalHeading)
    end
    pose.heading, pose.forward, pose.right, pose.up, pose.logicalHeading = 0.0, 0.0, 0.0, 0.0, nil
end

Animation.Stop = function(name, options)
    if not track or (name and track.name ~= name) then return end
    stopSpec(track.spec, options and options.blendOut)
    track = nil
    resetPose()
end

Animation.StopAllParkour = function(immediate)
    local blendOut = immediate and settings.instantBlend or nil
    for _, spec in pairs(played) do stopSpec(spec, blendOut) end
    played = {}
    track = nil
    resetPose()
end

Animation.StopAll = Animation.StopAllParkour

Animation.IsCancelable = function()
    return not track or not track.spec or track.spec.cancelable ~= false
end

Animation.IsLooping = function()
    return track ~= nil and track.looping
end

Animation.ExtraOffset = function(name)
    return extraOffsets[name or (track and track.name)] or zeroOffset
end

Animation.Apply = function(position, heading)
    local spec = track and track.spec
    local offset = spec and spec.positionOffset or defaults.positionOffset
    local extra = Animation.ExtraOffset()
    pose.heading = (spec and spec.headingOffset or 0.0) + (extra.heading or 0.0)
    pose.forward = (offset.forward or 0.0) + (extra.forward or 0.0)
    pose.right = (offset.right or 0.0) + (extra.right or 0.0)
    pose.up = (offset.up or 0.0) + (extra.up or 0.0)
    pose.logicalHeading = heading
    local forward = Vec.FromHeading(heading)
    local adjusted = position + forward * pose.forward + Vec.Right(forward) * pose.right + Vec.Up * pose.up
    return adjusted, (heading + pose.heading) % 360.0
end

Animation.Pose = function()
    return pose
end

Animation.IsPlaying = function(name)
    if not track or (name and track.name ~= name) then return false end
    if track.spec then return IsEntityPlayingAnim(cache.ped, track.spec.dict, track.spec.clip, anyTask) end
    return track.duration ~= nil and GetGameTimer() - track.startedAt < track.duration
end

Animation.Current = function()
    return track and track.name
end

Animation.Progress = function(name)
    if not track or (name and track.name ~= name) then return nil end
    if track.progressTick == tick then return track.progress end
    local spec = track.spec
    local value
    if spec and IsEntityPlayingAnim(cache.ped, spec.dict, spec.clip, anyTask) then
        value = GetEntityAnimCurrentTime(cache.ped, spec.dict, spec.clip)
    elseif track.duration and track.duration > 0.0 then
        value = (GetGameTimer() - track.startedAt) / track.duration
    else
        value = 1.0
    end
    value = math.min(math.max(value, 0.0), 1.0)
    if not track.looping then value = math.max(value, track.progress) end
    track.progress = value
    track.progressTick = tick
    return value
end

local eventTime = function(at)
    if type(at) == 'number' then return at end
    return track and track.events[at] or settings.events[at] or 1.0
end

Animation.EventTime = eventTime

Animation.Reached = function(at, name)
    local progress = Animation.Progress(name)
    return progress ~= nil and progress >= eventTime(at)
end

Animation.OnProgress = function(name, at, callback)
    if not track or track.name ~= name then return false end
    track.callbacks[#track.callbacks + 1] = { at = eventTime(at), callback = callback, fired = false }
    return true
end

local applyTiming = function()
    local spec = track.spec
    if not spec or (not track.seek and track.rate == 1.0) then return end
    if not IsEntityPlayingAnim(cache.ped, spec.dict, spec.clip, anyTask) then return end
    if track.seek then
        SetEntityAnimCurrentTime(cache.ped, spec.dict, spec.clip, track.seek)
        track.seek = nil
    end
    if track.rate ~= 1.0 then SetEntityAnimSpeed(cache.ped, spec.dict, spec.clip, track.rate) end
end

Animation.Update = function()
    tick = tick + 1
    if not track then return end
    applyTiming()
    if #track.callbacks == 0 then return end
    local current = track
    local progress = Animation.Progress()
    for i = 1, #current.callbacks do
        local item = current.callbacks[i]
        if not item.fired and progress >= item.at then
            item.fired = true
            item.callback(current.name, progress)
        end
    end
end

Animation.Assist = function()
    if track and track.spec and track.spec.rootMotion then return settings.rootMotionAssist end
    return 1.0
end

local sourceLabel = function()
    local entry = lookup(track.name)
    if track.source == 'custom' then return 'CUSTOM', false end
    if entry and entry.custom then return 'FALLBACK', true end
    if track.source == 'native' then return 'NATIVE', false end
    return 'SAFE', false
end

Animation.RebuildOffsets = function()
    buildExtraOffsets()
end

Animation.Reload = function(content)
    if content then
        local chunk = load(content, '@cr-parkour/shared/animations.lua', 't')
        if chunk then chunk() end
    end
    normalized = {}
    clips = {}
    warned = {}
    for dict, entry in pairs(dicts) do
        if entry.state ~= 'loaded' then dicts[dict] = nil end
    end
    buildExtraOffsets()
    Animation.Preload()
end

Animation.State = function()
    if not track then return nil end
    local label, bug = sourceLabel()
    return {
        label = label,
        fallbackBug = bug,
        extraOffset = Animation.ExtraOffset(),
        name = track.name,
        dict = track.spec and track.spec.dict,
        clip = track.spec and track.spec.clip,
        source = track.source,
        reason = track.reason,
        headingOffset = track.spec and track.spec.headingOffset or 0.0,
        appliedHeadingOffset = pose.heading,
        progress = Animation.Progress(),
        rootMotion = track.spec ~= nil and track.spec.rootMotion,
        rate = track.rate,
    }
end

return Animation
