-- Raw clay pieces and the burning pit kiln (see modules/fire/pit_kiln.lua)
local pit_kiln = require "fire/pit_kiln"

function on_interact(x, y, z, playerid)
    return pit_kiln.interact(x, y, z, playerid)
end

function on_broken(x, y, z, playerid)
    if pit_kiln.get(x, y, z) then
        pit_kiln.broken(x, y, z)
    end
end

function on_block_present(x, y, z)
    pit_kiln.present(x, y, z)
end

function on_block_removed(x, y, z)
    pit_kiln.unloaded(x, y, z)
end
