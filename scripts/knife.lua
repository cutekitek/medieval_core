-- Knives: hold the use button on a hide lying on a stripped log to scrape it
local beam = require "leather/beam"

function on_use_on_block(x, y, z, playerid, normal)
    return beam.scrape(playerid, x, y, z) ~= nil
end
