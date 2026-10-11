-- World rule "medieval_core-flight-speed": flight speed multiplier of players.
-- The engine keeps it as the core:mob property flight_speed_mul (default 2.0,
-- relative to walking speed); the rule is numeric, so the built-in boolean
-- `rule.set` can't change it — use the `flight.speed` console command.
local this = {}

this.RULE = "medieval_core-flight-speed"
this.DEFAULT = 2.0
this.MIN = 0.1
this.MAX = 50.0

function this.init()
    rules.create(this.RULE, this.DEFAULT)
end

function this.get()
    local value = tonumber(rules.get(this.RULE))
    if not value or value <= 0 then
        return this.DEFAULT
    end
    return math.max(this.MIN, math.min(this.MAX, value))
end

function this.set(value)
    rules.set(this.RULE, math.max(this.MIN, math.min(this.MAX, value)))
end

-- Keeps the player's mob component in sync with the rule
function this.apply(pid)
    local entity = entities.get(player.get_entity(pid))
    local mob = entity and entity:get_component("core:mob")
    if not mob then
        return
    end
    local value = this.get()
    if math.abs(mob.get_flight_speed_mul() - value) > 1e-6 then
        mob.set_flight_speed_mul(value)
    end
end

return this
