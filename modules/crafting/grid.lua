-- A crafting grid stored in an inventory: slots 0 .. size*size-1 are the
-- grid (row-major from the top-left), slot size*size shows the result.
-- The result slot is only a preview; crafting consumes one item from every
-- occupied cell and hands out the result.
local recipes = require "crafting/recipes"
local base_util = require "base:util"

local this = {}

function this.result_slot(size)
    return size * size
end

function this.match(invid, size)
    local names = {}
    for i = 0, size * size - 1 do
        local id = inventory.get(invid, i)
        names[i + 1] = id ~= 0 and item.name(id) or nil
    end
    return recipes.match(names, size, size)
end

-- puts the matching recipe's result into the result slot (or clears it)
function this.refresh(invid, size)
    local recipe = this.match(invid, size)
    local slot = this.result_slot(size)
    local id, count = inventory.get(invid, slot)
    if recipe then
        local rid = item.index(recipe.result)
        if id ~= rid or count ~= recipe.count then
            inventory.set(invid, slot, rid, recipe.count)
        end
    elseif id ~= 0 then
        inventory.set(invid, slot, 0, 0)
    end
    return recipe
end

-- one of every ingredient is used up; tools only wear
local function consume(invid, size, recipe)
    for i = 0, size * size - 1 do
        local id = inventory.get(invid, i)
        if id ~= 0 then
            if recipe.tools[item.name(id)] then
                for _ = 1, recipe.wear do
                    if inventory.get(invid, i) ~= 0 then
                        inventory.use(invid, i)
                    end
                end
            else
                inventory.decrement(invid, i, 1)
            end
        end
    end
end

-- Crafts once into the stack dst_inv:dst_slot (the cursor stack when
-- clicking) if the result fits there. Returns true on success.
function this.craft_into(invid, size, dst_inv, dst_slot)
    local recipe = this.match(invid, size)
    if not recipe then
        return false
    end
    local rid = item.index(recipe.result)
    local id, count = inventory.get(dst_inv, dst_slot)
    if id == 0 then
        inventory.set(dst_inv, dst_slot, rid, recipe.count)
    elseif id == rid and count + recipe.count <= item.stack_size(rid) then
        inventory.set_count(dst_inv, dst_slot, count + recipe.count)
    else
        return false
    end
    consume(invid, size, recipe)
    this.refresh(invid, size)
    return true
end

-- free room for an item in an inventory
local function room(invid, itemid)
    local stack = item.stack_size(itemid)
    local free = 0
    for slot = 0, inventory.size(invid) - 1 do
        local id, count = inventory.get(invid, slot)
        if id == 0 then
            free = free + stack
        elseif id == itemid then
            free = free + stack - count
        end
    end
    return free
end

-- Shift-click: crafts as many times as the ingredients and the free room
-- in dst_inv allow. Returns the number of crafts.
function this.craft_all(invid, size, dst_inv)
    local made = 0
    while true do
        local recipe = this.match(invid, size)
        if not recipe then
            break
        end
        local rid = item.index(recipe.result)
        if room(dst_inv, rid) < recipe.count then
            break
        end
        inventory.add(dst_inv, rid, recipe.count)
        consume(invid, size, recipe)
        made = made + 1
    end
    this.refresh(invid, size)
    return made
end

-- Returns the grid contents to the player when the grid is closed;
-- what does not fit is dropped at the player's feet.
function this.give_back(invid, size, pid)
    local pinv = player.get_inventory(pid)
    inventory.set(invid, this.result_slot(size), 0, 0)
    for i = 0, size * size - 1 do
        if inventory.get(invid, i) ~= 0 then
            inventory.move_range(invid, i, pinv, 0)
            local id, count = inventory.get(invid, i)
            if id ~= 0 then
                local x, y, z = player.get_pos(pid)
                base_util.drop({x, y + 0.5, z}, id, count)
                inventory.set(invid, i, 0, 0)
            end
        end
    end
end

return this
