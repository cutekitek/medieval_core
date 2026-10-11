-- What a block drops when broken in survival.
-- Overrides for base blocks live here; otherwise base:loot or the picking item.
local base_util = require "base:util"

local this = {}

-- a raw clay piece in a pit: the piece and its grass cover (the variant)
local function raw_piece(name)
    return function(variant)
        local loot = {{item = name}}
        if variant > 0 then
            table.insert(loot, {item = "medieval_core:plant_fiber", count = variant})
        end
        return loot
    end
end

-- block name -> loot table in base:loot format, or a function of the block
-- variant returning one (e.g. crops by growth stage)
local overrides = {
    ["base:grass"] = {
        {item = "medieval_core:plant_fiber", chance = 0.35},
    },
    ["base:flower"] = {
        {item = "base:flower.item"},
        {item = "medieval_core:plant_fiber", chance = 0.2},
    },
    ["base:leaves"] = {
        {item = "medieval_core:stick", chance = 0.3},
    },
    ["medieval_core:berry_bush"] = {{item = "medieval_core:stick", min = 1, max = 2}},
    ["medieval_core:blueberry_bush"] = {{item = "medieval_core:stick", min = 1, max = 2}},
    ["medieval_core:cloudberry_bush"] = {{item = "medieval_core:plant_fiber", min = 1, max = 2}},
    ["medieval_core:pineapple_plant"] = {{item = "medieval_core:plant_fiber", min = 1, max = 3}},
    ["medieval_core:spruce_leaves"] = {{item = "medieval_core:stick", chance = 0.3}},
    ["medieval_core:jungle_leaves"] = {{item = "medieval_core:stick", chance = 0.25}},
    ["medieval_core:palm_leaves"] = {{item = "medieval_core:plant_fiber", chance = 0.4}},
    ["medieval_core:fern"] = {{item = "medieval_core:plant_fiber", chance = 0.4}},
    ["medieval_core:tropical_fern"] = {{item = "medieval_core:plant_fiber", chance = 0.5}},
    ["medieval_core:lichen"] = {{item = "medieval_core:plant_fiber", chance = 0.2}},
    ["medieval_core:vine"] = {{item = "medieval_core:plant_fiber", chance = 0.6}},
    ["medieval_core:dead_bush"] = {{item = "medieval_core:stick", min = 1, max = 2}},
    ["medieval_core:brown_mushroom"] = {{item = "medieval_core:mushroom"}},
    ["medieval_core:snowy_dirt"] = {{item = "base:dirt.item"}},
    ["medieval_core:podzol"] = {{item = "base:dirt.item"}},
    ["medieval_core:tropical_grass_block"] = {{item = "base:dirt.item"}},
    ["medieval_core:campfire_frame_2"] = {{item = "medieval_core:stick", count = 2}},
    ["medieval_core:campfire_frame_3"] = {{item = "medieval_core:stick", count = 3}},
    ["medieval_core:campfire_frame_4"] = {{item = "medieval_core:stick", count = 4}},
    ["medieval_core:campfire"] = {{item = "medieval_core:stick", count = 4}, {item = "medieval_core:plant_fiber"}},
    ["medieval_core:campfire_lit"] = {},
    ["medieval_core:campfire_ashes"] = {},
    ["medieval_core:tanning_vat"] = {{item = "medieval_core:tanning_vat.item"}},
    ["medieval_core:tanning_vat_water"] = {{item = "medieval_core:tanning_vat.item"}},
    ["medieval_core:tanning_vat_tannin"] = {{item = "medieval_core:tanning_vat.item"}},
    ["medieval_core:workbench"] = {{item = "medieval_core:workbench.item"}},
    -- a raw piece gives its grass cover back; the piece under a burning kiln
    -- comes out by fire/pit_kiln
    ["medieval_core:raw_clay_pot"] = raw_piece("medieval_core:raw_clay_pot.item"),
    ["medieval_core:raw_clay_plate"] = raw_piece("medieval_core:raw_clay_plate.item"),
    ["medieval_core:pit_kiln"] = {},
}

function this.set(name, loot)
    overrides[name] = loot
end

-- a knife cuts plants cleanly: their fibre always drops
local function with_knife(loot)
    local out = {}
    for i, entry in ipairs(loot) do
        out[i] = entry
        if entry.item == "medieval_core:plant_fiber" and entry.chance then
            out[i] = {item = entry.item, count = entry.count, min = entry.min, max = entry.max}
        end
    end
    return out
end

-- Returns a list of {item=id, count=n}; tool is the type of a suitable tool,
-- variant the state variant the block had
function this.roll(blockid, tool, variant)
    local loot = overrides[block.name(blockid)]
    if type(loot) == "function" then
        loot = loot(variant)
    end
    if loot then
        if tool == "knife" then
            loot = with_knife(loot)
        end
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

function this.spawn(blockid, x, y, z, tool, variant)
    for _, drop in ipairs(this.roll(blockid, tool, variant)) do
        local entity = base_util.drop({x + 0.5, y + 0.5, z + 0.5}, drop.item, drop.count)
        if entity then
            entity.rigidbody:set_vel(vec3.spherical_rand(2.0))
        end
    end
end

return this
