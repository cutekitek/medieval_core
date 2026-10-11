-- A clay pot hung over a campfire on a pole (fire/campfire keeps it in the
-- fire's site as site.pot). A bucket of water fills it; vegetables and meat
-- go in (up to CAPACITY). Over a burning fire the water heats up and boils
-- after BOIL_TIME; with at least MIN ingredients boiling for COOK_TIME it
-- turns into a stew, one portion per ingredient. A clay plate scoops a
-- portion out. Off the fire the pot cools down and stops boiling.
local this = {}

this.CAPACITY = 6
this.MIN = 3
-- seconds of world time = game minutes (a game day is 1440 s)
this.BOIL_TIME = 25        -- a pot of water over a campfire boils in ~25 minutes
this.COOK_TIME = 120       -- the stew simmers for two hours
this.COOL_RATE = 0.5       -- heat lost per second away from the fire

this.STEW = "medieval_core:stew"

-- what goes into the pot and how it looks floating there
this.INGREDIENTS = {
    ["medieval_core:carrot"] = "veg",
    ["medieval_core:potato"] = "veg",
    ["medieval_core:tomato"] = "veg",
    ["medieval_core:cabbage"] = "green",
    ["medieval_core:cucumber"] = "green",
    ["medieval_core:mushroom"] = "veg",
    ["medieval_core:raw_beef"] = "meat",
    ["medieval_core:raw_meat"] = "meat",
    ["medieval_core:raw_chicken"] = "meat",
    ["medieval_core:raw_game"] = "meat",
    ["medieval_core:raw_mutton"] = "meat",
    ["medieval_core:raw_fish"] = "meat",
    ["medieval_core:cooked_beef"] = "meat",
    ["medieval_core:cooked_meat"] = "meat",
    ["medieval_core:cooked_chicken"] = "meat",
    ["medieval_core:cooked_game"] = "meat",
    ["medieval_core:cooked_mutton"] = "meat",
    ["medieval_core:cooked_fish"] = "meat",
}

function this.new()
    return {water = false, items = {}, heat = 0, cook = 0, soup = 0}
end

function this.boiling(pot)
    return pot.water and pot.heat >= this.BOIL_TIME
end

-- nothing in it: it can be taken off the fire
function this.is_empty(pot)
    return not pot.water and #pot.items == 0 and pot.soup == 0
end

function this.add_water(pot)
    if pot.water then
        return false
    end
    pot.water = true
    return true
end

-- plain water goes back into a bucket (not once anything is in it)
function this.take_water(pot)
    if not pot.water or #pot.items > 0 or pot.soup > 0 then
        return false
    end
    pot.water = false
    pot.heat = 0
    return true
end

-- puts an ingredient in; false if the pot has no water, is full or the stew
-- is done already
function this.add(pot, name)
    if not this.INGREDIENTS[name] or not pot.water or pot.soup > 0 or #pot.items >= this.CAPACITY then
        return false
    end
    table.insert(pot.items, name)
    return true
end

-- a plate's worth of stew; the pot is empty after the last one
function this.serve(pot)
    if pot.soup <= 0 then
        return nil
    end
    pot.soup = pot.soup - 1
    if pot.soup == 0 then
        pot.water = false
        pot.heat = 0
    end
    return this.STEW
end

-- the share of the cooking done (0..1), 1 for a finished stew
function this.progress(pot)
    if pot.soup > 0 then
        return 1
    end
    return pot.cook / this.COOK_TIME
end

-- what the pot shows: the liquid's look ("water", "boiling", "broth",
-- "stew" or nil), how many bits float in it and whether it boils
function this.look(pot)
    local liquid = nil
    if pot.soup > 0 then
        liquid = "stew"
    elseif pot.water then
        if pot.cook >= this.COOK_TIME * 0.5 then
            liquid = "broth"
        elseif this.boiling(pot) then
            liquid = "boiling"
        else
            liquid = "water"
        end
    end
    local kinds = {}
    if pot.soup == 0 then
        for i, name in ipairs(pot.items) do
            kinds[i] = this.INGREDIENTS[name]
        end
    end
    return {liquid = liquid, bits = kinds, boiling = this.boiling(pot)}
end

local function look_key(pot)
    local l = this.look(pot)
    return tostring(l.liquid) .. "/" .. table.concat(l.bits, ",") .. "/" .. tostring(l.boiling)
end

-- Heats or cools the pot; returns true when its look has changed.
function this.tick(pot, lit, dt)
    local before = look_key(pot)
    if lit and pot.water then
        pot.heat = math.min(this.BOIL_TIME, pot.heat + dt)
    else
        pot.heat = math.max(0, pot.heat - dt * this.COOL_RATE)
    end
    if this.boiling(pot) and pot.soup == 0 and #pot.items >= this.MIN then
        pot.cook = pot.cook + dt
        if pot.cook >= this.COOK_TIME then
            pot.soup = #pot.items
            pot.items = {}
            pot.cook = 0
        end
    end
    return look_key(pot) ~= before
end

function this.encode(pot)
    return {pot.water, pot.items, pot.heat, pot.cook, pot.soup}
end

function this.decode(e)
    return {water = e[1], items = e[2] or {}, heat = e[3] or 0, cook = e[4] or 0, soup = e[5] or 0}
end

return this
