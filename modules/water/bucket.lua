-- Buckets (scripts/bucket.lua): the wooden bucket scoops a water source,
-- the full bucket pours it back. A bucket of water also waters farmland, a
-- little at a time: its uses run down with every watering and the empty
-- bucket is left. Only a full bucket can be poured out (or into a tanning
-- vat); a water source tops a partly used one up.
local flow = require "water/flow"
local vat = require "leather/vat"
local farming = require "farming/farming"
local campfire = require "fire/campfire"
local trough = require "husbandry/trough"

local this = {}

local EYE_HEIGHT = 0.7

local function swap_held(pid, name)
    local invid, slot = player.get_inventory(pid)
    inventory.set(invid, slot, item.index(name), 1)
end

-- where the player looks (replaceable in tests: headless players look ahead)
function this.dir_of(pid)
    return player.get_dir(pid)
end

local function look_ray(pid, liquids)
    local x, y, z = player.get_pos(pid)
    -- as far as the player reaches (water is not selected by the engine)
    return block.raycast({x, y + EYE_HEIGHT, z}, this.dir_of(pid),
        player.get_interaction_distance(pid), nil, {}, liquids)
end

local function scoop(pid)
    local hit = look_ray(pid, true)
    if not hit or hit.block ~= flow.ids().source then
        return false
    end
    local p = hit.iendpoint
    block.set(p[1], p[2], p[3], 0, 0)
    flow.notify(p[1], p[2], p[3])
    swap_held(pid, "medieval_core:water_bucket")
    audio.play_sound("medieval_core/bucket_fill", p[1] + 0.5, p[2] + 0.5, p[3] + 0.5, 0.8,
        0.95 + math.random() * 0.1, "regular")
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
    swap_held(pid, "medieval_core:wooden_bucket")
    audio.play_sound("medieval_core/bucket_pour", tx + 0.5, ty + 0.5, tz + 0.5, 0.8,
        0.95 + math.random() * 0.1, "regular")
    return true
end

local function held_name(pid)
    local invid, slot = player.get_inventory(pid)
    return item.name(inventory.get(invid, slot))
end

-- a bucket of water that has not been used for watering
local function is_full(pid)
    local invid, slot = player.get_inventory(pid)
    local itemid = inventory.get(invid, slot)
    local uses = inventory.get_data(invid, slot, "uses")
    return uses == nil or uses >= item.uses(itemid)
end

-- one watering: the bucket empties by one use
local function spend(pid)
    if player.is_infinite_items(pid) then
        return
    end
    local invid, slot = player.get_inventory(pid)
    inventory.use(invid, slot)
    if inventory.get(invid, slot) == 0 then
        inventory.set(invid, slot, item.index("medieval_core:wooden_bucket"), 1)
    end
end

local function needs_water(pid)
    local name = held_name(pid)
    return name == "medieval_core:wooden_bucket" or (name == "medieval_core:water_bucket" and not is_full(pid))
end

function this.use(pid)
    if needs_water(pid) then
        scoop(pid)
    end
end

function this.use_on_block(x, y, z, pid, normal)
    -- the item script runs before the block's on_interact, so a pot over a
    -- campfire and a trough are handed the bucket here
    if campfire.holds_food(block.get(x, y, z)) then
        campfire.interact(x, y, z, pid)
        return true
    end
    if trough.is_trough(x, y, z) then
        trough.use(x, y, z, pid)
        return true
    end
    -- a tanning vat is filled from the bucket and emptied into it
    if vat.liquid(block.get(x, y, z)) then
        if held_name(pid) == "medieval_core:water_bucket" then
            if not is_full(pid) then
                return true
            end
            if vat.fill(x, y, z) then
                swap_held(pid, "medieval_core:wooden_bucket")
            end
        elseif vat.scoop(x, y, z) then
            swap_held(pid, "medieval_core:water_bucket")
        end
        return true
    end
    if held_name(pid) == "medieval_core:water_bucket" and farming.water(x, y, z) then
        spend(pid)
        return true
    end
    if needs_water(pid) then
        scoop(pid)
    elseif is_full(pid) then
        pour(pid, x, y, z, normal)
    end
    return true
end

return this
