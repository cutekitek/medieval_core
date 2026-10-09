-- Edible items: item name -> {food, water}
local stats = require "survival/stats"

local this = {}

local foods = {
    ["millwright:berries"] = {food = 2, water = 1},
    ["millwright:raw_beef"] = {food = 4},
    ["millwright:raw_chicken"] = {food = 3},
    ["millwright:raw_meat"] = {food = 4},
    ["millwright:raw_game"] = {food = 2},
    ["millwright:egg"] = {food = 2},
    ["millwright:blueberries"] = {food = 2, water = 1},
    ["millwright:cloudberries"] = {food = 2, water = 1},
    ["millwright:pineapple"] = {food = 4, water = 3},
    ["millwright:mushroom"] = {food = 2},
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
