local settings = Config.Fall
local lastReport = {}

RegisterNetEvent('cr-parkour:server:fallImpact', function(distance, rolled)
    if not settings.serverHook then return end
    local source = source
    if type(distance) ~= 'number' or distance ~= distance then return end
    local now = GetGameTimer()
    if lastReport[source] and now - lastReport[source] < settings.reportCooldown then return end
    lastReport[source] = now
    distance = math.min(math.max(distance, 0.0), settings.maxReportedDistance)
    TriggerEvent('cr-parkour:fallImpact', source, distance, rolled == true)
end)

AddEventHandler('playerDropped', function()
    lastReport[source] = nil
end)

local parseManifest = function()
    local entries, missing = {}, {}
    local resource = GetCurrentResourceName()
    for _, path in ipairs(Config.AnimationPack.manifests) do
        local content = LoadResourceFile(resource, path)
        if content then
            for line in content:gmatch('[^\r\n]+') do
                local dict, clip = line:match('^%s*(%S+)%s+(%S+)%s*$')
                if dict then entries[#entries + 1] = { dict = dict, clip = clip, source = path } end
            end
        else
            missing[#missing + 1] = path
        end
    end
    return { entries = entries, missing = missing }
end

local manifest = parseManifest()

lib.callback.register('cr-parkour:animationManifest', function()
    return manifest
end)
