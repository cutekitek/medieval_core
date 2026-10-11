-- Bed: using it sets the respawn point and, at night, lies the player down
-- (player/sleep)
local sleep = require "player/sleep"

function on_interact(x, y, z, playerid)
    return sleep.use_bed(playerid, x, y, z) ~= nil
end
