-- Hoes: the use button on grass or dirt makes farmland
local farming = require "farming/farming"

function on_use_on_block(x, y, z, playerid, normal)
    return farming.use_hoe(playerid, x, y, z)
end
