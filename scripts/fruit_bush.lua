-- Shared script of fruit bushes: harvest with the use button, regrow over time.
-- The fruit is the block property "medieval_core:fruit" = {item, min, max}.
local base_util = require "base:util"

local RIPE = 0
local EMPTY = 1
local REGROW_CHANCE = 0.3

function on_interact(x, y, z, playerid)
    if block.get_variant(x, y, z) ~= RIPE then
        return false
    end
    local fruit = block.properties[block.get(x, y, z)]["medieval_core:fruit"]
    local itemid = item.index(fruit.item)
    local count = math.random(fruit.min or 1, fruit.max or 1)
    local rest = inventory.add(player.get_inventory(playerid), itemid, count)
    if rest > 0 then
        base_util.drop({x + 0.5, y + 0.5, z + 0.5}, itemid, rest)
    end
    block.set_variant(x, y, z, EMPTY)
    return true
end

function on_random_update(x, y, z)
    if block.get_variant(x, y, z) == EMPTY and math.random() < REGROW_CHANCE then
        block.set_variant(x, y, z, RIPE)
    end
end
