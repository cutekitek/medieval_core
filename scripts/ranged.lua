-- Spears and bows: hold the use button to wind up or draw, let go to throw
-- or shoot (modules/combat/ranged.lua).
local ranged = require "combat/ranged"

function on_use(playerid)
    return ranged.charge(playerid)
end

function on_use_on_block(x, y, z, playerid, normal)
    return ranged.charge(playerid)
end
