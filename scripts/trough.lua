-- Feeding trough: feed or water for farm animals (modules/husbandry/trough.lua)
local trough = require "husbandry/trough"

function on_interact(x, y, z, playerid)
    return trough.use(x, y, z, playerid)
end

function on_placed(x, y, z, playerid)
    trough.present(x, y, z)
end

function on_broken(x, y, z, playerid)
    trough.removed(x, y, z)
end

function on_block_present(x, y, z)
    trough.present(x, y, z)
end

function on_block_removed(x, y, z)
    trough.removed(x, y, z)
end
