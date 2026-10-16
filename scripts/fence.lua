-- Fences: rails towards fences, gates and solid blocks (building/shapes).
-- The use button ties the animals led on a lasso to the post or takes the
-- ones tied there (riding/leash).
local shapes = require "building/shapes"
local leash = require "riding/leash"

function on_placed(x, y, z)
    shapes.update_fence(x, y, z)
end

function on_update(x, y, z)
    shapes.update_fence(x, y, z)
end

function on_interact(x, y, z, pid)
    return leash.use_post(pid, x, y, z)
end
