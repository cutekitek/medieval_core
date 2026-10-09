-- Integer 3D vector helpers for block-grid geometry
local this = {}

function this.add(a, b)
    return {a[1] + b[1], a[2] + b[2], a[3] + b[3]}
end

function this.sub(a, b)
    return {a[1] - b[1], a[2] - b[2], a[3] - b[3]}
end

function this.neg(a)
    return {-a[1], -a[2], -a[3]}
end

function this.dot(a, b)
    return a[1] * b[1] + a[2] * b[2] + a[3] * b[3]
end

function this.cross(a, b)
    return {
        a[2] * b[3] - a[3] * b[2],
        a[3] * b[1] - a[1] * b[3],
        a[1] * b[2] - a[2] * b[1],
    }
end

function this.eq(a, b)
    return a[1] == b[1] and a[2] == b[2] and a[3] == b[3]
end

-- 1, 2 or 3 for a unit axis-aligned vector (sign ignored), nil otherwise
function this.axis_index(v)
    local ax, ay, az = math.abs(v[1]), math.abs(v[2]), math.abs(v[3])
    if ax + ay + az ~= 1 then
        return nil
    end
    if ax == 1 then return 1 elseif ay == 1 then return 2 else return 3 end
end

local AXES = {{1, 0, 0}, {0, 1, 0}, {0, 0, 1}}

-- canonical (positive) unit vector of axis index
function this.axis_vec(index)
    return AXES[index]
end

-- 6 face neighbours followed by 12 edge-diagonal neighbours
this.NEIGHBOURS = {}
for dx = -1, 1 do
    for dy = -1, 1 do
        for dz = -1, 1 do
            local n = math.abs(dx) + math.abs(dy) + math.abs(dz)
            if n == 1 then
                table.insert(this.NEIGHBOURS, 1, {dx, dy, dz})
            elseif n == 2 then
                table.insert(this.NEIGHBOURS, {dx, dy, dz})
            end
        end
    end
end

return this
