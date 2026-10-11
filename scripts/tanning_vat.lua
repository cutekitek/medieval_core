-- Tanning vat: soaking and tanning hides (modules/leather/vat.lua)
local vat = require "leather/vat"

function on_interact(x, y, z, playerid)
    return vat.interact(x, y, z, playerid)
end

function on_broken(x, y, z, playerid)
    vat.broken(x, y, z)
end

function on_block_present(x, y, z)
    vat.present(x, y, z)
end

function on_block_removed(x, y, z)
    vat.unloaded(x, y, z)
end
