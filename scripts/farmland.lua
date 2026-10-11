-- Farmland: random block updates let watered farmland dry out in time
-- (modules/farming/farming.lua)
local farming = require "farming/farming"

function on_random_update(x, y, z)
    farming.refresh(x, y, z)
end
