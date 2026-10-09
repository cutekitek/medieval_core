-- Kinetic part definitions and the rules for how parts connect.
--
-- Conventions:
--   node.facing - block local +Y in world space (pipe rotation profile)
--   node.axis   - axis index 1..3, node.avec - canonical (positive) axis vector
--   node.fsign  - dot(facing, avec): +1 or -1
--   Angular speed (rpm) of a node is signed and measured about node.avec.
--   link(a, b) returns r such that rpm_b = r * rpm_a.
local vec = require "kinetics/vec"

local this = {}

local defs = {}

this.MATERIALS = {
    wood = {max_rpm = 48},
}

-- def fields:
--   entity     - rotor entity name (rotating visual)
--   ports      - {front=bool, back=bool}: axle ends along facing (+) / against it (-)
--   gear       - "spur" | "crown" | "lantern"; teeth - number of cogs/rods
--   stress     - load in SU per rpm (friction or work)
--   max_rpm    - breaks the network above this speed
--   phase      - visual angle offset in degrees (lets teeth interleave)
--   scale      - visual scale of the rotor entity
--   source(node, ticks) -> rpm about facing, capacity SU
--   on_tick(node, rpm, dt) - consumer work
--   interact(node, playerid) -> bool
function this.register(name, def)
    def.name = name
    def.ports = def.ports or {front = true, back = true}
    def.stress = def.stress or 0
    def.phase = def.phase or 0
    defs[name] = def
end

function this.get(name)
    return defs[name]
end

local function has_port(node, side)
    local ports = node.part.ports
    if side > 0 then
        return ports.front
    end
    return ports.back
end

-- Shaft-to-shaft along a common axis
local function axial(a, b, d)
    if a.axis ~= b.axis or vec.axis_index(d) ~= a.axis then
        return nil
    end
    if has_port(a, vec.dot(d, a.facing)) and has_port(b, -vec.dot(d, b.facing)) then
        return 1
    end
end

-- Spur cog wheel and lantern on parallel axes in adjacent blocks
local function spur(w, l, d)
    local i = vec.axis_index(d)
    if w.axis ~= l.axis or not i or i == w.axis then
        return nil
    end
    return -w.part.teeth / l.part.teeth
end

-- Crown (face) wheel and lantern at a right angle: the lantern stands
-- diagonally, one block in front of the cogged face and one block aside
-- (d = facing + n), its axis along n.
local function crown(w, l, d)
    local n = vec.sub(d, w.facing)
    local i = vec.axis_index(n)
    if not i or i == w.axis or l.axis ~= i then
        return nil
    end
    -- the face cog pushes the lantern rod lying on the wheel side
    local s = vec.dot(vec.cross(vec.axis_vec(i), w.facing), vec.cross(w.avec, n))
    return -(w.part.teeth / l.part.teeth) / s
end

local function gear(w, l, d)
    if w.part.gear == "spur" then
        return spur(w, l, d)
    elseif w.part.gear == "crown" then
        return crown(w, l, d)
    end
end

-- b is at a + d; returns r: rpm_b = r * rpm_a, or nil if not connected
function this.link(a, b, d)
    local r = axial(a, b, d)
    if r then
        return r
    end
    local ga, gb = a.part.gear, b.part.gear
    if not ga or not gb then
        return nil
    end
    if gb == "lantern" and ga ~= "lantern" then
        return gear(a, b, d)
    elseif ga == "lantern" and gb ~= "lantern" then
        local rb = gear(b, a, vec.neg(d))
        if rb then
            return 1 / rb
        end
    end
end

return this
