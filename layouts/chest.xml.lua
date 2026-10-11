-- The chest window: opening and closing it swings the chest's lid
local chest = require "medieval_core:storage/chest"

local current = nil

-- shift-click moves between the chest and the player inventory
share_func = require("core:inventory_utils").share_default_func

function on_open(invid, x, y, z)
    current = {x, y, z}
    chest.open(x, y, z)
end

function on_close(invid)
    if current then
        chest.close(current[1], current[2], current[3])
        current = nil
    end
end
