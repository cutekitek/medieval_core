-- Spawn eggs (medieval_core:spawn_egg_<species>): use on a block to release
-- the animal on top of it. Not used up with infinite items (creative).
local PREFIX = "medieval_core:spawn_egg_"

local function held(pid)
    local invid, slot = player.get_inventory(pid)
    local itemid, count = inventory.get(invid, slot)
    return invid, slot, itemid, count
end

function on_use_on_block(x, y, z, pid, normal)
    local invid, slot, itemid, count = held(pid)
    local name = item.name(itemid)
    if name:sub(1, #PREFIX) ~= PREFIX then
        return false
    end
    local species = name:sub(#PREFIX + 1)
    local entity = "medieval_core:" .. species
    -- def_index throws for an unknown entity
    local ok, def = pcall(entities.def_index, entity)
    if not ok then
        return true
    end
    -- grass and other replaceable blocks don't need to be stepped over
    local tx, ty, tz = x, y, z
    if not block.is_replaceable_at(x, y, z) then
        tx, ty, tz = x + normal[1], y + normal[2], z + normal[3]
    end
    local hitbox = entities.def_hitbox(def)
    entities.spawn(entity, {tx + 0.5, ty + hitbox[2] * 0.5 + 0.05, tz + 0.5},
        {medieval_core__animal = {species = species}, medieval_core__fish = {}})
    if not player.is_infinite_items(pid) then
        inventory.set(invid, slot, count > 1 and itemid or 0, count - 1)
    end
    return true
end
