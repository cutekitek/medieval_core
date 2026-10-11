-- Fishing rod: cast, pull in (modules/fishing/fishing.lua)
local fishing = require "fishing/fishing"

function on_use(playerid)
    return fishing.use(playerid)
end

function on_use_on_block(x, y, z, playerid, normal)
    return fishing.use(playerid)
end
