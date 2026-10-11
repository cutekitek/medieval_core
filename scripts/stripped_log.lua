-- Stripped logs: the scraping beam for hides (modules/leather/beam.lua)
local beam = require "leather/beam"

function on_interact(x, y, z, playerid)
    return beam.interact(x, y, z, playerid)
end

function on_broken(x, y, z, playerid)
    beam.broken(x, y, z)
end

function on_block_present(x, y, z)
    beam.present(x, y, z)
end

function on_block_removed(x, y, z)
    beam.unloaded(x, y, z)
end
