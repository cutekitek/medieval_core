-- Bow drill: hold the use button on a campfire with tinder, or on a raw clay
-- piece covered with grass in a pit, to light it.
-- The engine repeats the use every ~0.16 s while the button is held.
local campfire = require "fire/campfire"
local pit_kiln = require "fire/pit_kiln"

function on_use_on_block(x, y, z, playerid, normal)
    local result = pit_kiln.drill(playerid, x, y, z) or campfire.drill(playerid, x, y, z)
    if result == "lit" and not player.is_infinite_items(playerid) then
        local invid, slot = player.get_inventory(playerid)
        inventory.use(invid, slot)
    end
    return result ~= nil
end
