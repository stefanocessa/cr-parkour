local Profiler = {
    raycastsThisFrame = 0,
    raycastsPerSecond = 0,
    cachedThisFrame = 0,
}

local clock = os and os.clock or function() return GetGameTimer() / 1000.0 end
local smoothing = 0.1
local enabled = Config.Profiler.enabled == true
local timings = {}
local rays = { tick = 0, cached = 0, second = 0, windowStart = 0 }
local loops = {}
local sections = {
    { key = 'context', label = 'Context' },
    { key = 'scanner', label = 'Scanner' },
    { key = 'body', label = '  body scan' },
    { key = 'top', label = '  top detection' },
    { key = 'under', label = '  under scan' },
    { key = 'through', label = '  through scan' },
    { key = 'resolver', label = 'Resolver' },
    { key = 'ability', label = 'Ability' },
}

local reset = function()
    timings = {}
    rays.tick, rays.cached, rays.second, rays.windowStart = 0, 0, 0, 0
    Profiler.raycastsThisFrame, Profiler.raycastsPerSecond, Profiler.cachedThisFrame = 0, 0, 0
end

Profiler.IsEnabled = function()
    return enabled
end

Profiler.SetEnabled = function(value)
    enabled = value == true
    reset()
end

Profiler.Start = function()
    if not enabled then return nil end
    return clock()
end

Profiler.Stop = function(key, started)
    if not started then return end
    local ms = (clock() - started) * 1000.0
    local entry = timings[key]
    if not entry then
        timings[key] = { avg = ms, peak = ms }
        return
    end
    entry.avg = entry.avg + (ms - entry.avg) * smoothing
    entry.peak = math.max(entry.peak * (1.0 - smoothing * 0.1), ms)
end

Profiler.Ray = function(cached)
    if not enabled then return end
    if cached then
        rays.cached = rays.cached + 1
        return
    end
    rays.tick = rays.tick + 1
    rays.second = rays.second + 1
end

Profiler.Tick = function(now)
    if not enabled then return end
    Profiler.raycastsThisFrame, rays.tick = rays.tick, 0
    Profiler.cachedThisFrame, rays.cached = rays.cached, 0
    if now - rays.windowStart >= 1000 then
        Profiler.raycastsPerSecond, rays.second = rays.second, 0
        rays.windowStart = now
    end
end

Profiler.Loop = function(name, active)
    loops[name] = active and true or nil
end

Profiler.Lines = function(info)
    local lines = { { 'CR-PARKOUR PROFILER', Constants.Colors.landing } }
    for i = 1, #sections do
        local entry = timings[sections[i].key]
        if entry then
            lines[#lines + 1] = { ('%s: %.3fms  (peak %.3f)'):format(sections[i].label, entry.avg, entry.peak) }
        end
    end
    lines[#lines + 1] = { ('Raycasts/frame: %d  (cache %d)'):format(Profiler.raycastsThisFrame, Profiler.cachedThisFrame) }
    lines[#lines + 1] = { ('Raycasts/sec: %d'):format(Profiler.raycastsPerSecond) }
    if info then
        lines[#lines + 1] = { ('Parkour held: %s'):format(info.held and 'YES' or 'NO') }
        lines[#lines + 1] = { ('Traversal: %s'):format(info.traversal or 'NONE') }
        lines[#lines + 1] = { ('Ability: %s'):format(info.ability or '-') }
        lines[#lines + 1] = { ('State: %s  tick %sms  mode %s'):format(info.state or '-', info.wait or '-', Config.Performance.mode) }
    end
    local active = {}
    for name in pairs(loops) do active[#active + 1] = name end
    table.sort(active)
    lines[#lines + 1] = { ('Loops: %s'):format(#active > 0 and table.concat(active, ', ') or '-') }
    return lines
end

return Profiler
