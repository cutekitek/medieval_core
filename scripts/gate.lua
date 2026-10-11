-- Fence gates open and close on use (building/shapes)
local shapes = require "building/shapes"

function on_interact(x, y, z, playerid)
    return shapes.toggle_gate(x, y, z, playerid)
end
