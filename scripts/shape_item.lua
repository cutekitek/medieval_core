-- Stairs, slabs, vertical slabs, roof slopes and columns are placed by
-- building/shapes (where the cursor hits; slabs merge)
local shapes = require "building/shapes"

function on_use_on_block(x, y, z, playerid, normal)
    return shapes.use_item(playerid, x, y, z, normal)
end
