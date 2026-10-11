-- Axes: holding the use button on three logs in a line carves a dugout,
-- on any other log it strips the bark
local wood = require "leather/wood"
local dugout = require "boat/dugout"

function on_use_on_block(x, y, z, playerid, normal)
    if dugout.carve(x, y, z, playerid) then
        return true
    end
    if not wood.strip(x, y, z, playerid) then
        return false
    end
    if not player.is_infinite_items(playerid) then
        local invid, slot = player.get_inventory(playerid)
        inventory.use(invid, slot)
    end
    return true
end
