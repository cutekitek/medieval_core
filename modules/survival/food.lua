-- Edible items: item name -> {food, water, container}; the container (a
-- plate) is left in hand after eating
local stats = require "survival/stats"

local this = {}

local foods = {
    ["medieval_core:berries"] = {food = 2, water = 1},
    ["medieval_core:raw_beef"] = {food = 3},
    ["medieval_core:raw_chicken"] = {food = 2},
    ["medieval_core:raw_meat"] = {food = 3},
    ["medieval_core:raw_game"] = {food = 2},
    ["medieval_core:cooked_beef"] = {food = 8},
    ["medieval_core:cooked_chicken"] = {food = 6},
    ["medieval_core:cooked_meat"] = {food = 8},
    ["medieval_core:cooked_game"] = {food = 5},
    ["medieval_core:raw_mutton"] = {food = 2},
    ["medieval_core:cooked_mutton"] = {food = 6},
    ["medieval_core:raw_fish"] = {food = 2},
    ["medieval_core:cooked_fish"] = {food = 5},
    ["medieval_core:egg"] = {food = 2},
    ["medieval_core:blueberries"] = {food = 2, water = 1},
    ["medieval_core:cloudberries"] = {food = 2, water = 1},
    ["medieval_core:pineapple"] = {food = 4, water = 3},
    ["medieval_core:mushroom"] = {food = 2},
    ["medieval_core:carrot"] = {food = 3, water = 1},
    ["medieval_core:potato"] = {food = 2},
    ["medieval_core:cabbage"] = {food = 4, water = 2},
    ["medieval_core:tomato"] = {food = 2, water = 2},
    ["medieval_core:cucumber"] = {food = 1, water = 3},
    ["medieval_core:stew"] = {food = 12, water = 6, container = "medieval_core:clay_plate.item"},
}

function this.register(name, food, water)
    foods[name] = {food = food, water = water}
end

function this.get(itemid)
    if itemid == 0 then
        return nil
    end
    return foods[item.name(itemid)]
end

-- Returns true if the item was eaten
function this.eat(pid, itemid)
    local value = this.get(itemid)
    if not value then
        return false
    end
    local s = stats.get(pid)
    if s.food >= stats.MAX_FOOD and (value.water or 0) == 0 then
        return false
    end
    stats.feed(pid, value.food, value.water)
    return true
end

return this
