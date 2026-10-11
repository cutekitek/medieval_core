-- Placing a bed: the foot where the player clicks, the head away from them
local sleep = require "player/sleep"

function on_use_on_block(x, y, z, playerid, normal)
    sleep.place_bed(playerid, x, y, z, normal)
    return true
end
