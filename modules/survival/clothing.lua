-- Clothing: four slots per player (head, body, legs, feet), kept with the
-- player's stats (players.json) and shown in the inventory panel
-- (layouts/crafting.xml). Insulation keeps the body warm in the cold
-- (and makes the heat worse); a straw hat gives shade in the sun.
local stats = require "survival/stats"
local base_util = require "base:util"

local this = {}

this.SLOTS = {"head", "body", "legs", "feet"}

-- item -> where it is worn, insulation points, shade (degrees of sun heat)
local CLOTHES = {
    ["medieval_core:fur_hat"] = {slot = "head", insulation = 3},
    ["medieval_core:straw_hat"] = {slot = "head", insulation = 0, shade = 6},
    ["medieval_core:fur_coat"] = {slot = "body", insulation = 6},
    ["medieval_core:leather_tunic"] = {slot = "body", insulation = 2},
    ["medieval_core:leather_trousers"] = {slot = "legs", insulation = 3},
    ["medieval_core:leather_boots"] = {slot = "feet", insulation = 2},
}

function this.register(name, def)
    CLOTHES[name] = def
end

function this.def(name)
    return name and CLOTHES[name]
end

-- can this item be worn in that slot
function this.fits(name, slot)
    local def = CLOTHES[name]
    return def ~= nil and def.slot == slot
end

local function worn(pid)
    local s = stats.get(pid)
    s.clothing = s.clothing or {}
    return s.clothing
end

-- item name in a slot or nil
function this.get(pid, slot)
    local name = worn(pid)[slot]
    if name and not pcall(item.index, name) then
        return nil  -- the item does not exist any more
    end
    return name
end

function this.set(pid, slot, name)
    worn(pid)[slot] = name
end

-- total insulation and shade of everything worn
function this.totals(pid)
    local insulation, shade = 0, 0
    for _, slot in ipairs(this.SLOTS) do
        local def = CLOTHES[this.get(pid, slot)]
        if def then
            insulation = insulation + (def.insulation or 0)
            shade = shade + (def.shade or 0)
        end
    end
    return insulation, shade
end

-- Inventory panel: the slots first..first+3 of a panel inventory show
-- head, body, legs and feet.

-- puts what the player wears into the panel slots
function this.load_into(invid, first, pid)
    for i, slot in ipairs(this.SLOTS) do
        local name = this.get(pid, slot)
        inventory.set(invid, first + i - 1, name and item.index(name) or 0, name and 1 or 0)
    end
end

-- what is in the panel slots becomes what the player wears; clear = true
-- also empties the slots (the panel is closing)
function this.store_from(invid, first, pid, clear)
    for i, slot in ipairs(this.SLOTS) do
        local id = inventory.get(invid, first + i - 1)
        local name = id ~= 0 and item.name(id) or nil
        this.set(pid, slot, this.fits(name, slot) and name or nil)
        if clear then
            inventory.set(invid, first + i - 1, 0, 0)
        end
    end
end

local function swap(inv_a, slot_a, inv_b, slot_b)
    local a_id, a_count = inventory.get(inv_a, slot_a)
    local b_id, b_count = inventory.get(inv_b, slot_b)
    local a_data = a_id ~= 0 and inventory.get_all_data(inv_a, slot_a) or nil
    local b_data = b_id ~= 0 and inventory.get_all_data(inv_b, slot_b) or nil
    inventory.set(inv_a, slot_a, b_id, b_count)
    inventory.set(inv_b, slot_b, a_id, a_count)
    if b_data then inventory.set_all_data(inv_a, slot_a, b_data, true) end
    if a_data then inventory.set_all_data(inv_b, slot_b, a_data, true) end
end

-- After a click on a clothing slot: something that can't be worn there
-- goes back to the cursor (cursor_inv slot 0). Returns true if it was kept.
function this.check_slot(invid, index, first, cursor_inv)
    local slot = this.SLOTS[index - first + 1]
    local id = inventory.get(invid, index)
    if id == 0 or this.fits(item.name(id), slot) then
        return true
    end
    swap(invid, index, cursor_inv, 0)
    return false
end

-- clothes fall off a dead player like the rest of the inventory
table.insert(stats.listeners, 1, {
    on_death = function(pid)
        local pos = {player.get_pos(pid)}
        for _, slot in ipairs(this.SLOTS) do
            local name = this.get(pid, slot)
            if name then
                local drop = base_util.drop(pos, item.index(name), 1)
                if drop then
                    drop.rigidbody:set_vel(vec3.spherical_rand(4.0))
                end
            end
        end
        stats.get(pid).clothing = {}
    end,
})

return this
