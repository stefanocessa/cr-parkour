local Vec = {}

local epsilon = Constants.Epsilon

Vec.Up = vector3(0.0, 0.0, 1.0)
Vec.Zero = vector3(0.0, 0.0, 0.0)

Vec.Clamp = function(value, lower, upper)
    if value < lower then return lower end
    if value > upper then return upper end
    return value
end

Vec.Flat = function(v)
    return vector3(v.x, v.y, 0.0)
end

Vec.Length2d = function(v)
    return math.sqrt(v.x * v.x + v.y * v.y)
end

Vec.Distance2d = function(a, b)
    return Vec.Length2d(a - b)
end

Vec.Dot = function(a, b)
    return a.x * b.x + a.y * b.y + a.z * b.z
end

Vec.Normalize = function(v)
    local length = #v
    if length < epsilon then return nil, 0.0 end
    return v / length, length
end

Vec.Normalize2d = function(v)
    local length = Vec.Length2d(v)
    if length < epsilon then return nil, 0.0 end
    return vector3(v.x / length, v.y / length, 0.0), length
end

Vec.Right = function(dir)
    return vector3(dir.y, -dir.x, 0.0)
end

Vec.Negate = function(v)
    return vector3(-v.x, -v.y, -v.z)
end

Vec.WithZ = function(v, z)
    return vector3(v.x, v.y, z)
end

Vec.Lerp = function(a, b, t)
    return a + (b - a) * t
end

Vec.Bezier = function(a, control, b, t)
    local u = 1.0 - t
    return a * (u * u) + control * (2.0 * u * t) + b * (t * t)
end

Vec.ProjectOnPlane = function(v, normal)
    return v - normal * Vec.Dot(v, normal)
end

Vec.Angle2d = function(a, b)
    local na, nb = Vec.Normalize2d(a), Vec.Normalize2d(b)
    if not na or not nb then return 180.0 end
    return math.deg(math.acos(Vec.Clamp(Vec.Dot(na, nb), -1.0, 1.0)))
end

Vec.Heading = function(dir)
    return GetHeadingFromVector_2d(dir.x, dir.y)
end

Vec.FromHeading = function(heading)
    local rad = math.rad(heading)
    return vector3(-math.sin(rad), math.cos(rad), 0.0)
end

Vec.Format = function(v)
    return ('%.2f %.2f %.2f'):format(v.x, v.y, v.z)
end

return Vec
