local Vec = require 'client.core.vec'
local Profiler = require 'client.debug.profiler'

local Camera = {}

local settings = Config.Camera
local rotationOrder = Constants.CameraRotationOrder
local noCam = -1
local effects = {}
local current = { roll = 0.0, fov = 0.0 }
local cam = nil
local running = false
local generation = 0

local profiles = {
    wallrun = 'wallrun',
    slide = 'slide',
    roll = 'roll',
    wallflip = 'wallflip',
    precision = 'precision',
    longjump = 'longJump',
    ledge = 'ledgeGrab',
}

local shakes = {
    hardLanding = { profile = 'landing', key = 'shake', name = 'shakeName' },
    heavyLanding = { profile = 'landing', key = 'heavyShake', name = 'heavyShakeName' },
    roll = { profile = 'roll', key = 'shake', name = 'shakeName' },
    walljump = { profile = 'walljump', key = 'shake', name = 'shakeName' },
    ledgeGrab = { profile = 'ledgeGrab', key = 'shake', name = 'shakeName' },
}

Camera.Shake = function(key)
    if not settings.enabled then return end
    local shake = shakes[key]
    local profile = shake and settings[shake.profile]
    local intensity = profile and profile[shake.key]
    if not intensity or intensity <= 0.0 then return end
    ShakeGameplayCam(settings[shake.name], intensity)
end

local destroy = function()
    if not cam then return end
    RenderScriptCams(false, false, 0, true, false)
    DestroyCam(cam, false)
    cam = nil
end

local foreignCam = function()
    local rendering = GetRenderingCam()
    return rendering ~= noCam and rendering ~= cam
end

local render = function()
    if foreignCam() then return destroy() end
    local coords = GetGameplayCamCoord()
    local rot = GetGameplayCamRot(rotationOrder)
    local fov = GetGameplayCamFov()
    if not cam then
        cam = CreateCamWithParams('DEFAULT_SCRIPTED_CAMERA', coords.x, coords.y, coords.z, rot.x, rot.y, rot.z, fov, true, rotationOrder)
        SetCamAffectsAiming(cam, false)
        RenderScriptCams(true, false, 0, true, false)
    end
    SetCamCoord(cam, coords.x, coords.y, coords.z)
    SetCamRot(cam, rot.x, rot.y + current.roll, rot.z, rotationOrder)
    SetCamFov(cam, fov + current.fov)
end

local target = function(now)
    local roll, fov = 0.0, 0.0
    for key, effect in pairs(effects) do
        if effect.expires and now >= effect.expires then
            effects[key] = nil
        else
            roll, fov = roll + effect.roll, fov + effect.fov
        end
    end
    return Vec.Clamp(roll, -settings.maxRoll, settings.maxRoll), Vec.Clamp(fov, -settings.maxFov, settings.maxFov)
end

local settled = function()
    local epsilon = settings.settleEpsilon
    return next(effects) == nil and math.abs(current.roll) < epsilon and math.abs(current.fov) < epsilon
end

local loop = function(id)
    Profiler.Loop('camera', true)
    while id == generation do
        local now = GetGameTimer()
        local roll, fov = target(now)
        local gain = next(effects) and settings.blendIn or settings.blendOut
        local k = Vec.Clamp(gain * GetFrameTime(), 0.0, 1.0)
        current.roll = current.roll + (roll - current.roll) * k
        current.fov = current.fov + (fov - current.fov) * k
        if settled() then break end
        render()
        Wait(0)
    end
    if id ~= generation then return end
    running = false
    current.roll, current.fov = 0.0, 0.0
    destroy()
    Profiler.Loop('camera', false)
end

Camera.Push = function(key, roll, fov, duration)
    if not settings.enabled or not settings.overlay then return end
    if math.abs(roll) < settings.settleEpsilon and math.abs(fov) < settings.settleEpsilon then return end
    effects[key] = { roll = roll, fov = fov, expires = duration and GetGameTimer() + duration or nil }
    if running then return end
    running = true
    generation = generation + 1
    local id = generation
    CreateThread(function() loop(id) end)
end

Camera.Release = function(key)
    effects[key] = nil
end

Camera.OnAbility = function(name, state, payload)
    local key = profiles[name]
    local profile = key and settings[key]
    if not profile then return end
    if name == 'ledge' and state ~= Constants.States.LEDGE_GRAB then return end
    local roll = profile.roll or 0.0
    if name == 'wallrun' and payload and payload.wall then
        roll = payload.wall.side == Constants.Sides.right and roll or -roll
    end
    Camera.Push(name, roll, profile.fovBoost or 0.0, profile.duration)
end

Camera.OnAbilityEnd = function(name)
    local profile = profiles[name] and settings[profiles[name]]
    if profile and profile.duration then return end
    Camera.Release(name)
end

Camera.Reset = function()
    effects = {}
    running = false
    generation = generation + 1
    current.roll, current.fov = 0.0, 0.0
    StopGameplayCamShaking(true)
    destroy()
    Profiler.Loop('camera', false)
end

Camera.State = function()
    local names = {}
    for key in pairs(effects) do names[#names + 1] = key end
    table.sort(names)
    return { roll = current.roll, fov = current.fov, effects = names, overlay = cam ~= nil }
end

return Camera
