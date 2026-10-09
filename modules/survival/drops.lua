-- What a block drops when broken in survival.
-- Overrides for base blocks live here; otherwise base:loot or the picking item.
local base_util = require "base:util"

local this = {}

-- block name -> loot table in base:loot format
local overrides = {
    ["base:grass"] = {
        {item = "millwright:plant_fiber", chance = 0.35},
    },
    ["base:flower"] = {
        {item = "base:flower.item"},
        {item = "millwright:plant_fiber", chance = 0.2},
    },
    ["base:leaves"] = {
        {item = "millwright:stick", chance = 0.3},
    },
    ["millwright:berry_bush"] = {{item = "millwright:stick", min = 1, max = 2}},
    ["millwright:blueberry_bush"] = {{item = "millwright:stick", min = 1, max = 2}},
    ["millwright:cloudberry_bush"] = {{item = "millwright:plant_fiber", min = 1, max = 2}},
    ["millwright:pineapple_plant"] = {{item = "millwright:plant_fiber", min = 1, max = 3}},
    ["millwright:spruce_leaves"] = {{item = "millwright:stick", chance = 0.3}},
    ["millwright:jungle_leaves"] = {{item = "millwright:stick", chance = 0.25}},
    ["millwright:palm_leaves"] = {{item = "millwright:plant_fiber", chance = 0.4}},
    ["millwright:fern"] = {{item = "millwright:plant_fiber", chance = 0.4}},
    ["millwright:tropical_fern"] = {{item = "millwright:plant_fiber", chance = 0.5}},
    ["millwright:lichen"] = {{item = "millwright:plant_fiber", chance = 0.2}},
    ["millwright:vine"] = {{item = "millwright:plant_fiber", chance = 0.6}},
    ["millwright:dead_bush"] = {{item = "millwright:stick", min = 1, max = 2}},
    ["millwright:brown_mushroom"] = {{item = "millwright:mushroom"}},
    ["millwright:snowy_dirt"] = {{item = "base:dirt.item"}},
    ["millwright:podzol"] = {{item = "base:dirt.item"}},
    ["millwright:tropical_grass_block"] = {{item = "base:dirt.item"}},
}

function this.set(name, loot)
    overrides[name] = loot
end

-- Returns a list of {item=id, count=n}
function this.roll(blockid)
    local loot = overrides[block.name(blockid)]
    if loot then
        return base_util.calc_loot(loot)
    end
    local result = base_util.block_loot(blockid)
    for i = #result, 1, -1 do
        if not result[i].item or result[i].item == 0 then
            table.remove(result, i)
        end
    end
    return result
end

function this.spawn(blockid, x, y, z)
    for _, drop in ipairs(this.roll(blockid)) do
        local entity = base_util.drop({x + 0.5, y + 0.5, z + 0.5}, drop.item, drop.count)
        if entity then
            entity.rigidbody:set_vel(vec3.spherical_rand(2.0))
        end
    end
end

return this
