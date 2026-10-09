local food = require "survival/food"

function on_use(playerid)
    local invid, slot = player.get_inventory(playerid)
    local itemid = inventory.get(invid, slot)
    if food.eat(playerid, itemid) then
        inventory.decrement(invid, slot)
    end
    return true
end
