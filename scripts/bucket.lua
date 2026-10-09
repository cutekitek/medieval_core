-- Wooden bucket: scoops a water source, the full bucket pours it back
local flow = require "water/flow"

local REACH = 5.0
local EYE_HEIGHT = 0.7

local function swap_held(pid, name)
    local invid, slot = player.get_inventory(pid)
    inventory.set(invid, slot, item.index(name), 1)
end

local function look_ray(pid, liquids)
    local x, y, z = player.get_pos(pid)
    return block.raycast({x, y + EYE_HEIGHT, z}, player.get_dir(pid), REACH, nil, {}, liquids)
end

local function scoop(pid)
    local hit = look_ray(pid, true)
    if not hit or hit.block ~= flow.ids().source then
        return false
    end
    local p = hit.iendpoint
    block.set(p[1], p[2], p[3], 0, 0)
    flow.notify(p[1], p[2], p[3])
    swap_held(pid, "millwright:water_bucket")
    audio.play_sound_2d("events/pickup", 0.5, 0.8)
    return true
end

local function pour(pid, x, y, z, normal)
    local tx, ty, tz = x, y, z
    if not block.is_replaceable_at(tx, ty, tz) then
        tx, ty, tz = x + normal[1], y + normal[2], z + normal[3]
    end
    if not block.is_replaceable_at(tx, ty, tz) then
        return false
    end
    block.set(tx, ty, tz, flow.ids().source, 0)
    flow.notify(tx, ty, tz)
    swap_held(pid, "millwright:wooden_bucket")
    return true
end

local function held_name(pid)
    local invid, slot = player.get_inventory(pid)
    return item.name(inventory.get(invid, slot))
end

function on_use(pid)
    if held_name(pid) == "millwright:wooden_bucket" then
        scoop(pid)
    end
end

function on_use_on_block(x, y, z, pid, normal)
    if held_name(pid) == "millwright:wooden_bucket" then
        scoop(pid)
    else
        pour(pid, x, y, z, normal)
    end
    return true
end
