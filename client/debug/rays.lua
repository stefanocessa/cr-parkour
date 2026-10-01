local Rays = {}

local colors = Constants.Colors
local panel = Config.DebugPanel
local enabled = Config.Debug
local drawing = Config.DebugFlags.rays
local primitives = {}
local shapes = {}

Rays.SetDrawing = function(value)
    drawing = value
    if not value then primitives, shapes = {}, {} end
end

Rays.IsDrawing = function()
    return drawing
end

Rays.SetEnabled = function(value)
    enabled = value
    if not value then primitives, shapes = {}, {} end
end

Rays.IsEnabled = function()
    return enabled
end

Rays.Line = function(from, to, kind)
    if not enabled or not drawing then return end
    primitives[#primitives + 1] = { from = from, to = to, color = colors[kind] or colors.valid, expires = GetGameTimer() + panel.persistMs }
end

Rays.Point = function(point, kind)
    if not enabled or not drawing or not point then return end
    local size = panel.pointSize
    Rays.Line(point - vector3(size, 0.0, 0.0), point + vector3(size, 0.0, 0.0), kind)
    Rays.Line(point - vector3(0.0, size, 0.0), point + vector3(0.0, size, 0.0), kind)
    Rays.Line(point - vector3(0.0, 0.0, size), point + vector3(0.0, 0.0, size), kind)
end

Rays.Shape = function(key, lines, ttl)
    if not enabled or not drawing then return end
    shapes[key] = { lines = lines, expires = GetGameTimer() + (ttl or panel.reasonTtl) }
end

Rays.Cross = function(lines, point, kind)
    if not point then return lines end
    local size = panel.pointSize
    lines[#lines + 1] = { point - vector3(size, 0.0, 0.0), point + vector3(size, 0.0, 0.0), kind }
    lines[#lines + 1] = { point - vector3(0.0, size, 0.0), point + vector3(0.0, size, 0.0), kind }
    lines[#lines + 1] = { point - vector3(0.0, 0.0, size), point + vector3(0.0, 0.0, size), kind }
    return lines
end

local drawShapes = function(now)
    for key, shape in pairs(shapes) do
        if shape.expires < now then
            shapes[key] = nil
        else
            for i = 1, #shape.lines do
                local line = shape.lines[i]
                local c = colors[line[3]] or colors.valid
                DrawLine(line[1].x, line[1].y, line[1].z, line[2].x, line[2].y, line[2].z, c[1], c[2], c[3], c[4])
            end
        end
    end
end

Rays.Draw = function()
    local now = GetGameTimer()
    drawShapes(now)
    local alive = {}
    for i = 1, #primitives do
        local item = primitives[i]
        if item.expires >= now then
            local c = item.color
            DrawLine(item.from.x, item.from.y, item.from.z, item.to.x, item.to.y, item.to.z, c[1], c[2], c[3], c[4])
            alive[#alive + 1] = item
        end
    end
    primitives = alive
end

return Rays
