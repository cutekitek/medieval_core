-- Registration of the pack's kinetic parts
local parts = require "kinetics/parts"
local network = require "kinetics/network"
local millstone = require "machines/millstone"
require "kinetics/visual"

local WOOD = parts.MATERIALS.wood

parts.register("millwright:wooden_shaft", {
    entity = "millwright:rotor_shaft",
    stress = 0.1,
    max_rpm = WOOD.max_rpm,
})

parts.register("millwright:wooden_cogwheel", {
    entity = "millwright:rotor_cogwheel",
    gear = "spur",
    teeth = 14,
    stress = 0.2,
    max_rpm = WOOD.max_rpm,
})

parts.register("millwright:wooden_crown_wheel", {
    entity = "millwright:rotor_crown_wheel",
    gear = "crown",
    teeth = 16,
    stress = 0.2,
    max_rpm = WOOD.max_rpm,
})

parts.register("millwright:wooden_lantern", {
    entity = "millwright:rotor_lantern",
    gear = "lantern",
    teeth = 6,
    stress = 0.15,
    max_rpm = WOOD.max_rpm,
    phase = 30,
})

-- Undershot water wheel ------------------------------------------------------

local WHEEL_RPM = 8
local WHEEL_SU_PER_PADDLE = 32
local WHEEL_CHECK_TICKS = 20

local function is_water(x, y, z)
    local id = block.get(x, y, z)
    return id > 0 and block.name(id) == "base:water"
end

local function is_free(x, y, z)
    local id = block.get(x, y, z)
    return id == 0 or (id > 0 and block.is_replaceable_at(x, y, z))
end

-- Counts submerged paddle positions under the wheel; 0 if the wheel is
-- jammed by blocks inside its disc.
local function scan_wheel(node)
    if node.axis == 2 then
        return 0
    end
    local ux, uz = 0, 0
    if node.axis == 1 then uz = 1 else ux = 1 end
    for t = -1, 1 do
        for dy = 0, 1 do
            if not (t == 0 and dy == 0) and
               not is_free(node.x + ux * t, node.y + dy, node.z + uz * t) then
                return 0
            end
        end
    end
    local wet = 0
    for t = -1, 1 do
        local x, y, z = node.x + ux * t, node.y - 1, node.z + uz * t
        if is_water(x, y, z) then
            wet = wet + 1
        elseif not is_free(x, y, z) then
            return 0
        end
    end
    return wet
end

parts.register("millwright:undershot_wheel", {
    entity = "millwright:rotor_undershot_wheel",
    scale = 1.5,
    stress = 0,
    source = function(node, ticks)
        if not node.wet or ticks >= (node.next_scan or 0) then
            node.wet = scan_wheel(node)
            node.next_scan = ticks + WHEEL_CHECK_TICKS
        end
        if node.wet == 0 then
            return 0, 0
        end
        return WHEEL_RPM, WHEEL_SU_PER_PADDLE * node.wet
    end,
})

-- Hand crank: each use turns it for a few seconds -----------------------------

local CRANK_RPM = 12
local CRANK_SU = 32
local CRANK_TICKS = 60

parts.register("millwright:hand_crank", {
    entity = "millwright:rotor_hand_crank",
    ports = {front = false, back = true},
    stress = 0,
    source = function(node, ticks)
        if (node.crank_until or 0) > ticks then
            return CRANK_RPM, CRANK_SU
        end
        return 0, 0
    end,
    interact = function(node, playerid)
        node.crank_until = network.get_ticks() + CRANK_TICKS
        return true
    end,
})

-- Millstone: driven from below --------------------------------------------------

parts.register("millwright:millstone", {
    entity = "millwright:rotor_millstone_runner",
    ports = {front = false, back = true},
    stress = 1.5,
    max_rpm = 64,
    on_tick = millstone.on_tick,
})
