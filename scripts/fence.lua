-- Fences: rails towards fences, gates and solid blocks (building/shapes)
local shapes = require "building/shapes"

function on_placed(x, y, z)
    shapes.update_fence(x, y, z)
end

function on_update(x, y, z)
    shapes.update_fence(x, y, z)
end
