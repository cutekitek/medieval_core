-- Farm animals' needs and breeding (used by the medieval_core:animal component of
-- species with a `breed` table). An animal gets hungry and thirsty about
-- MEALS_PER_DAY times a game day, then looks for a trough (husbandry/trough)
-- with feed or water nearby and goes to eat or drink. Two grown animals of a
-- species that have eaten and drunk recently, rest from their last young and
-- are not too crowded now and then pair up and have a young one.
-- Plain fields: tests speed them up.
local calendar = require "world/calendar"

local this = {}

this.MEALS_PER_DAY = 3
this.MEAL_EVERY = calendar.DAY / this.MEALS_PER_DAY   -- seconds between meals (and drinks)
this.FED_FOR = this.MEAL_EVERY * 1.5                  -- counts as fed this long after a meal
this.CHECK_EVERY = {10, 20}         -- seconds between looks around
this.SEARCH_RADIUS = 16             -- troughs further away are not noticed
this.MEAL_TIME = 3.0                -- head in the trough
this.GIVE_UP = 25.0                 -- can't get to the trough this long: try later
this.BREED_CHANCE = 0.35            -- per look around when everything is right
this.MATE_RADIUS = 10
this.HERD_RADIUS = 12
this.HERD_LIMIT = 12                -- no young when this many of the species are around

-- a random time until the next look around
function this.next_check()
    local c = this.CHECK_EVERY
    return c[1] + math.random() * (c[2] - c[1])
end

return this
