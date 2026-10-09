-- Rotating visuals: one non-saved static entity per kinetic block,
-- posed every frame from a single loop (no per-entity on_render).
local network = require "kinetics/network"

local this = {}

-- how fast the visual speed follows the real one (1/s)
local SPIN_RESPONSE = 4.0

local rotors = {}  -- node key -> {entity, bone, node}

local function orientation(x, y, z)
    local ax = {block.get_X(x, y, z)}
    local ay = {block.get_Y(x, y, z)}
    local az = {block.get_Z(x, y, z)}
    return {
        ax[1], ax[2], ax[3], 0,
        ay[1], ay[2], ay[3], 0,
        az[1], az[2], az[3], 0,
        0, 0, 0, 1
    }
end

local function despawn(k)
    local rotor = rotors[k]
    if not rotor then
        return
    end
    rotors[k] = nil
    local uid = rotor.uid
    -- entity wrappers are already gone while the world is closing
    local entity = entities and entities.get(uid)
    if entity then
        entity:despawn()
    end
end

local function spawn(node)
    despawn(node.key)
    local name = node.part.entity
    if not name then
        return
    end
    local entity = entities.spawn(name, {node.x + 0.5, node.y + 0.5, node.z + 0.5})
    if not entity then
        return
    end
    local tsf = entity.transform
    tsf:set_rot(orientation(node.x, node.y, node.z))
    local scale = node.part.scale
    if scale then
        tsf:set_size({scale, scale, scale})
    end
    rotors[node.key] = {
        uid = entity:get_uid(),
        rig = entity.skeleton,
        bone = entity.skeleton:index("rotor") or 0,
        node = node,
    }
end

table.insert(network.listeners, {
    on_node_added = spawn,
    on_node_removed = function(node)
        despawn(node.key)
    end,
})

function this.render(delta)
    for _, net in pairs(network.get_networks()) do
        local target = net.speed
        local k = math.min(1.0, delta * SPIN_RESPONSE)
        net.visual_speed = net.visual_speed + (target - net.visual_speed) * k
        if math.abs(net.visual_speed) < 1e-3 and target == 0 then
            net.visual_speed = 0
        end
        -- rpm -> degrees per second
        net.theta = net.theta + net.visual_speed * 6.0 * delta
    end
    for k, rotor in pairs(rotors) do
        local node = rotor.node
        local net = node.net
        if net and entities.exists(rotor.uid) then
            local angle = (net.theta * node.ratio + node.part.phase) * node.fsign
            rotor.rig:set_matrix(rotor.bone, mat4.rotate({0, 1, 0}, angle % 360))
        end
    end
end

function this.reset()
    for k in pairs(rotors) do
        despawn(k)
    end
    rotors = {}
end

return this
