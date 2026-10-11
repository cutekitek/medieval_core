-- Loose rocks, flint and sticks: picked up with the use button.
-- A stick used on loose sticks starts a campfire teepee instead.
local flow = require "water/flow"
local campfire = require "fire/campfire"

function on_interact(x, y, z, playerid)
    local id = block.get(x, y, z)
    if campfire.stage(id) > 0 and campfire.interact(x, y, z, playerid) then
        return true
    end
    local itemid = block.get_picking_item(id)
    local invid = player.get_inventory(playerid)
    if inventory.add(invid, itemid, 1) > 0 then
        return true
    end
    block.set(x, y, z, 0, 0)
    flow.notify(x, y, z)
    return true
end
