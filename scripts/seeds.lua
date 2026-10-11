-- Seeds: the use button on farmland plants them
local farming = require "farming/farming"

function on_use_on_block(x, y, z, playerid, normal)
    return farming.use_seeds(playerid, x, y, z)
end
