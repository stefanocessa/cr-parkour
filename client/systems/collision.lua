local Vec = require 'client.core.vec'
local Raycast = require 'client.detection.raycast'

local Collision = {}

local body = Config.Body
local heights = Config.Heights
local traversalSettings = Config.CollisionTraversal
local protected = false
local traversal = { mode = 'NORMAL', startedAt = 0, deadline = 0 }

Collision.Protect = function(ped, value)
    if protected == value then return end
    protected = value
    SetPedCanRagdoll(ped, not value)
end

Collision.IsProtected = function()
    return protected
end

Collision.BeginTraversal = function(ped, mode, durationMs)
    local now = GetGameTimer()
    traversal = { mode = mode, startedAt = now, deadline = now + (durationMs or 0) + traversalSettings.graceMs }
    Collision.Protect(ped, true)
end

Collision.EndTraversal = function()
    if traversal.mode == 'NORMAL' then return end
    traversal = { mode = 'NORMAL', startedAt = 0, deadline = 0 }
end

Collision.TraversalMode = function()
    return traversal.mode
end

Collision.TraversalExpired = function(now)
    return traversal.mode ~= 'NORMAL' and now > traversal.deadline
end

Collision.BodyBlocked = function(root, dir, distance, names)
    local origin = { coords = root, feetZ = root.z - body.rootHeight }
    local list = names or { 'knees', 'chest', 'head' }
    for i = 1, #list do
        local from = Vec.WithZ(root, origin.feetZ + heights[list[i]])
        if Raycast.Direction(from, dir, distance + body.radius).hit then return true end
    end
    return false
end

Collision.Ground = function(root, depth)
    local result = Raycast.Down(root, body.rootHeight + depth)
    if not Raycast.IsFloor(result) then return nil end
    return result
end

Collision.HeadRoom = function(root, height)
    local from = Vec.WithZ(root, root.z - body.rootHeight + body.headHeight)
    return Raycast.Up(from, height)
end

Collision.CeilingBlocked = function(root)
    local feetZ = root.z - body.rootHeight
    local from = Vec.WithZ(root, feetZ + heights.knees)
    return Raycast.Up(from, body.height - heights.knees).hit
end

return Collision
