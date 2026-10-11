-- Chest: 27 slots (layouts/chest.xml); the lid opens with the window
local chest = require "medieval_core:storage/chest"

function on_interact(x, y, z, playerid)
    if not hud then
        return false
    end
    hud.open_block(x, y, z)
    return true
end

function on_broken(x, y, z, playerid)
    chest.forget(x, y, z)
end

function on_block_present(x, y, z)
    chest.present(x, y, z)
end
