local food = require "survival/food"
local campfire = require "fire/campfire"
local farming = require "farming/farming"

function on_use(playerid)
    local invid, slot = player.get_inventory(playerid)
    local itemid = inventory.get(invid, slot)
    if food.eat(playerid, itemid) then
        inventory.decrement(invid, slot)
        -- a plate of stew leaves the plate
        local container = food.get(itemid).container
        if container then
            local left = inventory.add(invid, item.index(container), 1)
            if left > 0 then
                local x, y, z = player.get_pos(playerid)
                require("base:util").drop({x, y + 0.5, z}, item.index(container), left)
            end
        end
        local x, y, z = player.get_pos(playerid)
        audio.play_sound("medieval_core/eat", x, y + 0.6, z, 0.8, 0.9 + math.random() * 0.2, "regular")
    end
    return true
end

-- The item script runs before the block's on_interact, so the block's own use
-- comes first here: a campfire takes food into its pot or onto the skewers,
-- a ripe crop or bush is picked. Otherwise the food is eaten as usual.
function on_use_on_block(x, y, z, playerid, normal)
    local invid, slot = player.get_inventory(playerid)
    local itemid = inventory.get(invid, slot)
    local blockid = block.get(x, y, z)
    if campfire.holds_food(blockid) then
        if campfire.interact(x, y, z, playerid) then
            return true
        end
        if campfire.COOKED[item.name(itemid)] then
            if campfire.add_food(x, y, z, item.name(itemid)) and not player.is_infinite_items(playerid) then
                inventory.decrement(invid, slot)
            end
            return true
        end
    end
    if farming.harvest(x, y, z, playerid) then
        return true
    end
    local props = block.properties[blockid]
    if props and props["medieval_core:fruit"] and block.get_variant(x, y, z) == 0 then
        return false  -- a ripe bush: its own on_interact picks it
    end
    return on_use(playerid)
end
