-- Mechanical millstone: grinds the input slot item while the runner turns.
-- Slot 0 - input, slot 1 - output. Progress (0..1) is kept in the block field.
local this = {}

local INPUT = 0
local OUTPUT = 1

-- input item name -> {result, count, revolutions}
local recipes = {}

function this.add_recipe(input, result, count, revolutions)
    recipes[input] = {result = result, count = count or 1, revolutions = revolutions}
end

function this.get_recipe(itemid)
    if itemid == 0 then
        return nil
    end
    return recipes[item.name(itemid)]
end

this.add_recipe("base:stone.item", "base:sand.item", 1, 6)
this.add_recipe("base:bazalt.item", "base:sand.item", 2, 12)

local function set_progress(x, y, z, value)
    if block.get_field(x, y, z, "progress") ~= value then
        block.set_field(x, y, z, "progress", value)
    end
end

function this.get_progress(x, y, z)
    return block.get_field(x, y, z, "progress") or 0
end

function this.on_tick(node, rpm, dt)
    local x, y, z = node.x, node.y, node.z
    local invid = inventory.get_block(x, y, z)
    if invid == 0 then
        return
    end
    local id, count = inventory.get(invid, INPUT)
    local recipe = this.get_recipe(id)
    if not recipe then
        set_progress(x, y, z, 0)
        return
    end
    local resultid = item.index(recipe.result)
    local outid, outcount = inventory.get(invid, OUTPUT)
    if outid ~= 0 and (outid ~= resultid or
        outcount + recipe.count > item.stack_size(resultid)) then
        return
    end
    if rpm == 0 then
        return
    end
    local progress = this.get_progress(x, y, z)
    progress = progress + math.abs(rpm) / 60 * dt / recipe.revolutions
    if progress >= 1.0 then
        progress = 0
        if count > 1 then
            inventory.set_count(invid, INPUT, count - 1)
        else
            inventory.set(invid, INPUT, 0, 0)
        end
        inventory.set(invid, OUTPUT, resultid, outcount + recipe.count)
    end
    set_progress(x, y, z, progress)
end

return this
