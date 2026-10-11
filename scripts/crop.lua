-- Crops and wild vegetables: a ripe crop or a wild plant is picked with the
-- use button (modules/farming/farming.lua); random block updates bring
-- crops up to date.
local farming = require "farming/farming"

function on_interact(x, y, z, playerid)
    return farming.harvest(x, y, z, playerid)
end

function on_random_update(x, y, z)
    farming.refresh(x, y, z)
end
