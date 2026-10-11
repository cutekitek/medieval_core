-- The carpentry table (wood) and the mason table (stone): an input slot
-- and the list of everything its material can be cut into. A click on an
-- option uses up one input item and gives the shown count.
-- Block inventory: slot 0 = input, slots 1..OPTIONS = the options (shown
-- only; the window fills them).
local shapes = require "building/shapes"
local base_util = require "base:util"

local this = {}

this.INPUT = 0
this.OPTIONS = 12

this.STATIONS = {
    ["medieval_core:carpentry_table"] = "wood",
    ["medieval_core:mason_table"] = "stone",
}

-- what one input item is worth: wood in planks, stone in blocks
local VALUE = {log = 4, hewn = 4, planks = 1, raw = 1, bricks = 1}
local STONE_VALUE = {hewn = 1}
-- the price of one product
local COST = {
    wood = {planks = 1, hewn = 4, stairs = 1, slab = 0.5, vslab = 0.5, column = 1,
            roof = 1, fence = 1, gate = 1, ladder = 0.5},
    stone = {hewn = 1, bricks = 1, stairs = 1, slab = 0.5, vslab = 0.5, column = 1, roof = 1},
}

-- item name -> {mat, form}
local inputs = {}
for name, m in pairs(shapes.materials) do
    for itemname, form in pairs(m.inputs) do
        inputs[itemname] = {mat = name, form = form}
    end
    for _, form in ipairs({"planks", "hewn", "bricks"}) do
        inputs[shapes.block_name(name, form) .. ".item"] = {mat = name, form = form}
    end
end

-- material and form of an input item, if the station takes it
function this.input_of(kind, itemid)
    if itemid == 0 then
        return nil
    end
    local inp = inputs[item.name(itemid)]
    if not inp or shapes.materials[inp.mat].kind ~= kind then
        return nil
    end
    return inp
end

-- {{item = name, count = n}, ...} for an input item at a station
function this.options(kind, itemid)
    local inp = this.input_of(kind, itemid)
    if not inp then
        return {}
    end
    local value = VALUE[inp.form]
    if kind == "stone" and STONE_VALUE[inp.form] then
        value = STONE_VALUE[inp.form]
    end
    local list = {}
    for _, form in ipairs(shapes.FORMS[kind]) do
        local count = math.floor(value / COST[kind][form] + 1e-6)
        if form ~= inp.form and count >= 1 then
            table.insert(list, {item = shapes.block_name(inp.mat, form) .. ".item", count = count})
        end
    end
    return list
end

-- fills the option slots from the input
function this.refresh(invid, kind)
    local list = this.options(kind, inventory.get(invid, this.INPUT))
    for i = 1, this.OPTIONS do
        local opt = list[i]
        local id, count = inventory.get(invid, i)
        if opt then
            local oid = item.index(opt.item)
            if id ~= oid or count ~= opt.count then
                inventory.set(invid, i, oid, opt.count)
            end
        elseif id ~= 0 then
            inventory.set(invid, i, 0, 0)
        end
    end
    return list
end

-- Cuts option slot into the stack dst_inv:dst_slot (the cursor when
-- clicking). Returns true on success.
function this.cut_into(invid, kind, slot, dst_inv, dst_slot)
    local opt = this.refresh(invid, kind)[slot]
    if not opt then
        return false
    end
    local oid = item.index(opt.item)
    local id, count = inventory.get(dst_inv, dst_slot)
    if id == 0 then
        inventory.set(dst_inv, dst_slot, oid, opt.count)
    elseif id == oid and count + opt.count <= item.stack_size(oid) then
        inventory.set_count(dst_inv, dst_slot, count + opt.count)
    else
        return false
    end
    inventory.decrement(invid, this.INPUT, 1)
    this.refresh(invid, kind)
    return true
end

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

-- Shift-click: cuts the whole input into dst_inv while there is room.
-- Returns the number of input items used.
function this.cut_all(invid, kind, slot, dst_inv)
    local opt = this.refresh(invid, kind)[slot]
    if not opt then
        return 0
    end
    local oid = item.index(opt.item)
    local used = 0
    while inventory.get(invid, this.INPUT) ~= 0 and room(dst_inv, oid) >= opt.count do
        inventory.add(dst_inv, oid, opt.count)
        inventory.decrement(invid, this.INPUT, 1)
        used = used + 1
    end
    this.refresh(invid, kind)
    return used
end

-- the window closes: the input goes back to the player, the list is wiped
function this.give_back(invid, pid)
    for i = 1, this.OPTIONS do
        inventory.set(invid, i, 0, 0)
    end
    if inventory.get(invid, this.INPUT) ~= 0 then
        local pinv = player.get_inventory(pid)
        inventory.move_range(invid, this.INPUT, pinv, 0)
        local id, count = inventory.get(invid, this.INPUT)
        if id ~= 0 then
            local x, y, z = player.get_pos(pid)
            base_util.drop({x, y + 0.5, z}, id, count)
            inventory.set(invid, this.INPUT, 0, 0)
        end
    end
end

return this
