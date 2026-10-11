-- Columns: a base and a capital at the free ends (building/shapes)
local shapes = require "building/shapes"

function on_placed(x, y, z)
    shapes.update_column(x, y, z)
end

function on_update(x, y, z)
    shapes.update_column(x, y, z)
end
