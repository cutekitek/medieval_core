-- Stairs: corner shapes follow the neighbouring stairs (building/shapes)
local shapes = require "building/shapes"

function on_placed(x, y, z)
    shapes.update_stairs(x, y, z)
end

function on_update(x, y, z)
    shapes.update_stairs(x, y, z)
end
