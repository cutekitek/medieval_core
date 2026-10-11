-- Campfire build stages, the fire and its ashes (see modules/fire/campfire.lua)
local campfire = require "fire/campfire"

function on_interact(x, y, z, playerid)
    return campfire.interact(x, y, z, playerid)
end

function on_broken(x, y, z, playerid)
    campfire.broken(nil, x, y, z)
end

function on_block_present(x, y, z)
    campfire.present(x, y, z)
end

function on_block_removed(x, y, z)
    campfire.unloaded(x, y, z)
end
