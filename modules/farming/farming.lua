-- Farming: a hoe turns grass or dirt into farmland, seeds crafted from the
-- vegetables are planted on it, a bucket of water waters it.
--   farmland   variant 0 dry, 1 wet (darker); a watering keeps it wet for
--              WET_DAYS.
--   crops      four growth stages (variants 0..3, 3 = ripe). Crops that need
--              water (tomato, cucumber, cabbage) grow on wet farmland only;
--              on dry farmland they wilt (variants 4..7) and after DIE_DAYS
--              they are gone. The others grow anyway, faster when watered.
--   wild       vegetables grow wild here and there: picking or breaking one
--              gives the vegetable to make seeds from.
-- Times are game days of the world calendar (DAY seconds of the world
-- running, whatever the speed of the sun, plus the nights slept through).
-- The state lives in fields of the blocks
-- and is saved with their chunks:
--   crop       progress (stages, fractional), thirst (dry days in a row),
--              updated (the day it was brought up to date)
--   farmland   wet_until (the day it dries out)
-- A crop is brought up to date from the time passed whenever it is touched:
-- random block updates, a player nearby (refresh_around), watering,
-- harvesting. Growth goes on in unloaded chunks too.
local base_util = require "base:util"
local drops = require "survival/drops"
local calendar = require "world/calendar"

local this = {}

this.STAGES = 4
this.RIPE = 3
this.WILTED = 4             -- variant offset of the wilted stages
this.DAY = calendar.DAY     -- seconds of world time in a game day
this.WET_DAYS = 2           -- a watering keeps the farmland wet this long
this.REWATER_ABOVE = 0.8    -- wetter than this (share of WET_DAYS) needs no water
this.WILT_DAYS = 0.5        -- dry days until a thirsty crop wilts
this.DIE_DAYS = 1.5         -- and until it is gone
this.WET_BONUS = 1.5        -- growth speed of the hardy crops on wet farmland

this.FARMLAND = "medieval_core:farmland"
this.TILLABLE = {
    ["base:grass_block"] = true,
    ["base:dirt"] = true,
    ["medieval_core:podzol"] = true,
    ["medieval_core:tropical_grass_block"] = true,
}

-- crop block -> how it grows; days = from a seed to the harvest (three
-- stages of growth), regrow = the stage a picked plant goes back to
this.CROPS = {
    ["medieval_core:wheat_crop"] = {
        seed = "medieval_core:wheat_seeds", produce = "medieval_core:wheat", yield = {1, 3},
        days = 3, wild = "medieval_core:wild_wheat",
    },
    ["medieval_core:carrot_crop"] = {
        seed = "medieval_core:carrot_seeds", produce = "medieval_core:carrot", yield = {2, 4},
        days = 3, wild = "medieval_core:wild_carrot",
    },
    ["medieval_core:potato_crop"] = {
        seed = "medieval_core:potato_seeds", produce = "medieval_core:potato", yield = {2, 5},
        days = 4, wild = "medieval_core:wild_potato",
    },
    ["medieval_core:cabbage_crop"] = {
        seed = "medieval_core:cabbage_seeds", produce = "medieval_core:cabbage", yield = {1, 1},
        days = 4, wild = "medieval_core:wild_cabbage", thirsty = true,
    },
    ["medieval_core:tomato_crop"] = {
        seed = "medieval_core:tomato_seeds", produce = "medieval_core:tomato", yield = {2, 4},
        days = 5, wild = "medieval_core:wild_tomato", thirsty = true, regrow = 2,
    },
    ["medieval_core:cucumber_crop"] = {
        seed = "medieval_core:cucumber_seeds", produce = "medieval_core:cucumber", yield = {2, 3},
        days = 4, wild = "medieval_core:wild_cucumber", thirsty = true, regrow = 2,
    },
}

local by_seed = {}    -- seed item name -> crop block name
local by_wild = {}    -- wild block name -> crop block name
for name, c in pairs(this.CROPS) do
    by_seed[c.seed] = name
    by_wild[c.wild] = name
end

-- the world's calendar in game days (world/calendar: sleeping moves it on)
function this.now()
    return calendar.now()
end

-- moves the calendar on by some days (tests, debugging); refresh blocks to see it
function this.skip(days)
    calendar.skip(days)
end

function this.crop_of(blockid)
    return blockid and blockid > 0 and this.CROPS[block.name(blockid)] or nil
end

function this.crop_of_seed(itemid)
    return itemid and itemid ~= 0 and by_seed[item.name(itemid)] or nil
end

function this.is_farmland(blockid)
    return blockid and blockid > 0 and block.name(blockid) == this.FARMLAND
end

function this.is_wet(x, y, z)
    return this.is_farmland(block.get(x, y, z)) and block.get_variant(x, y, z) == 1
end

-- the day the farmland at x, y, z dries out (0 if it never was watered)
function this.wet_until(x, y, z)
    return block.get_field(x, y, z, "wet_until") or 0
end

-- growth stage 0..3 and whether it is wilted
function this.stage(x, y, z)
    local v = block.get_variant(x, y, z)
    return v % this.WILTED, v >= this.WILTED
end

local function set_stage(x, y, z, stage, wilted)
    local v = stage + (wilted and this.WILTED or 0)
    if block.get_variant(x, y, z) ~= v then
        block.set_variant(x, y, z, v)
    end
end

-- the stored state of a crop: progress, thirst, updated (nil if none yet)
function this.crop_state(x, y, z)
    local updated = block.get_field(x, y, z, "updated")
    if not updated or updated == 0 then
        return nil
    end
    return {
        progress = block.get_field(x, y, z, "progress") or 0,
        thirst = block.get_field(x, y, z, "thirst") or 0,
        updated = updated,
    }
end

local function store(x, y, z, progress, thirst, updated)
    block.set_field(x, y, z, "progress", progress)
    block.set_field(x, y, z, "thirst", thirst)
    block.set_field(x, y, z, "updated", updated)
end

local function puff(x, y, z, texture, count, speed)
    if not gfx then
        return
    end
    gfx.particles.emit({x + 0.5, y + 1.0, z + 0.5}, count, {
        texture = texture,
        lifetime = 0.7,
        spawn_interval = 0.0001,
        explosion = {speed, speed * 1.2, speed},
        size = {0.07, 0.07, 0.07},
        spawn_shape = "box",
        spawn_spread = {0.4, 0.05, 0.4},
    })
end

local function sound(name, x, y, z, volume)
    if gfx then
        audio.play_sound(name, x + 0.5, y + 0.5, z + 0.5, volume or 0.7, 0.9 + math.random() * 0.2, "regular")
    end
end

local function give(pid, x, y, z, name, count)
    if count <= 0 then
        return
    end
    local itemid = item.index(name)
    local rest = pid and inventory.add(player.get_inventory(pid), itemid, count) or count
    if rest > 0 then
        base_util.drop({x + 0.5, y + 0.5, z + 0.5}, itemid, rest)
    end
end

-- Farmland that has dried out shows it.
function this.refresh_farmland(x, y, z)
    if block.get_variant(x, y, z) == 1 and this.wet_until(x, y, z) <= this.now() then
        block.set_variant(x, y, z, 0)
    end
end

-- Brings the crop at x, y, z up to date. The farmland under it is wet from
-- the last update until wet_until at most (watering brings the crop up to
-- date first), so the time passed splits into a wet and a dry part.
function this.refresh_crop(x, y, z)
    local name = block.name(block.get(x, y, z))
    local c = this.CROPS[name]
    if not c then
        return
    end
    local now = this.now()
    local s = this.crop_state(x, y, z)
    local stage, wilted = this.stage(x, y, z)
    if not s then
        -- placed some other way (creative, a script): starts from what it shows
        store(x, y, z, stage, 0, now)
        return
    end
    local dt = now - s.updated
    if dt <= 0 then
        return
    end
    if not this.is_farmland(block.get(x, y - 1, z)) then
        store(x, y, z, s.progress, s.thirst, now)
        return
    end
    local wet_dt = math.max(0, math.min(dt, this.wet_until(x, y - 1, z) - s.updated))
    local dry_dt = dt - wet_dt
    this.refresh_farmland(x, y - 1, z)
    local rate = this.RIPE / c.days
    local progress, thirst = math.max(s.progress, stage), s.thirst
    if c.thirsty then
        if wet_dt > 0 then
            progress = progress + wet_dt * rate
            thirst = 0
        end
        thirst = thirst + dry_dt
        if thirst >= this.DIE_DAYS then
            block.set(x, y, z, 0, 0)
            puff(x, y - 1, z, "blocks:mw_dry_leaf", 8, 1.0)
            return
        end
    else
        progress = progress + (wet_dt * this.WET_BONUS + dry_dt) * rate
    end
    progress = math.min(progress, this.RIPE)
    set_stage(x, y, z, math.floor(progress), c.thirsty and thirst >= this.WILT_DAYS)
    store(x, y, z, progress, thirst, now)
end

-- whatever farming block is at x, y, z (random block updates)
function this.refresh(x, y, z)
    local id = block.get(x, y, z)
    if this.is_farmland(id) then
        this.refresh_farmland(x, y, z)
    elseif this.crop_of(id) then
        this.refresh_crop(x, y, z)
    end
end

-- Brings the fields around a point up to date (a player walking by).
function this.refresh_around(cx, cy, cz, radius, height)
    radius, height = radius or 6, height or 3
    cx, cy, cz = math.floor(cx), math.floor(cy), math.floor(cz)
    for x = cx - radius, cx + radius do
        for z = cz - radius, cz + radius do
            for y = cy - height, cy + height do
                local id = block.get(x, y, z)
                if id > 0 then
                    if this.crop_of(id) then
                        this.refresh_crop(x, y, z)
                    elseif this.is_farmland(id) then
                        this.refresh_farmland(x, y, z)
                    end
                end
            end
        end
    end
end

-- Hoeing: grass or dirt with nothing solid above becomes dry farmland
-- (grass and other small plants on top are cut away). Returns true if tilled.
function this.till(x, y, z)
    local id = block.get(x, y, z)
    if id <= 0 then
        return false
    end
    if not this.TILLABLE[block.name(id)] then
        -- aimed at a plant standing on the soil
        if block.is_replaceable_at(x, y, z) and not this.crop_of(id) then
            return this.till(x, y - 1, z)
        end
        return false
    end
    local above = block.get(x, y + 1, z)
    if above ~= 0 then
        if above < 0 or not block.is_replaceable_at(x, y + 1, z) or this.crop_of(above) then
            return false
        end
        block.set(x, y + 1, z, 0, 0)
    end
    block.set(x, y, z, block.index(this.FARMLAND), 0)
    block.set_field(x, y, z, "wet_until", 0)
    puff(x, y, z, "blocks:mw_dirt_clod", 10, 2.0)
    sound("medieval_core/till", x, y, z, 0.8)
    return true
end

-- Plants a seed item on the farmland at x, y, z. Returns true if planted.
function this.plant(x, y, z, seed_itemid)
    local name = this.crop_of_seed(seed_itemid)
    if not name or not this.is_farmland(block.get(x, y, z)) or block.get(x, y + 1, z) ~= 0 then
        return false
    end
    block.set(x, y + 1, z, block.index(name), 0)
    store(x, y + 1, z, 0, 0, this.now())
    sound("medieval_core/plant", x, y + 1, z, 0.6)
    return true
end

-- Waters the farmland at x, y, z (or under the crop there). Returns true if
-- the water was used: farmland that is still wet enough is skipped.
function this.water(x, y, z)
    if this.crop_of(block.get(x, y, z)) then
        y = y - 1
    end
    if not this.is_farmland(block.get(x, y, z)) then
        return false
    end
    local now = this.now()
    if this.wet_until(x, y, z) - now > this.WET_DAYS * this.REWATER_ABOVE then
        return false
    end
    -- the crop lived through the time before on the old water
    if this.crop_of(block.get(x, y + 1, z)) then
        this.refresh_crop(x, y + 1, z)
    end
    block.set_field(x, y, z, "wet_until", now + this.WET_DAYS)
    block.set_variant(x, y, z, 1)
    puff(x, y, z, "blocks:mw_water_drop", 14, 1.4)
    sound("medieval_core/splash", x, y, z, 0.5)
    return true
end

-- Picks a ripe crop or a wild vegetable with the use button. Tomatoes and
-- cucumbers stay and bear again, the rest is taken whole.
function this.harvest(x, y, z, pid)
    local id = block.get(x, y, z)
    local wild = by_wild[block.name(id)]
    if wild then
        local c = this.CROPS[wild]
        give(pid, x, y, z, c.produce, math.random(1, 2))
        block.set(x, y, z, 0, 0)
        sound("medieval_core/plant", x, y, z, 0.6)
        return true
    end
    local c = this.crop_of(id)
    if not c then
        return false
    end
    this.refresh_crop(x, y, z)
    if block.get(x, y, z) ~= id or this.stage(x, y, z) < this.RIPE then
        return false
    end
    give(pid, x, y, z, c.produce, math.random(c.yield[1], c.yield[2]))
    sound("medieval_core/plant", x, y, z, 0.7)
    if c.regrow then
        local s = this.crop_state(x, y, z)
        set_stage(x, y, z, c.regrow, false)
        store(x, y, z, c.regrow, s and s.thirst or 0, this.now())
    else
        block.set(x, y, z, 0, 0)
    end
    return true
end

-- A player uses a hoe on a block (scripts/hoe.lua): tills it, the hoe wears.
function this.use_hoe(pid, x, y, z)
    if not this.till(x, y, z) then
        return false
    end
    if not player.is_infinite_items(pid) then
        local invid, slot = player.get_inventory(pid)
        inventory.use(invid, slot)
    end
    return true
end

-- A player uses seeds on a block (scripts/seeds.lua): one is planted.
function this.use_seeds(pid, x, y, z)
    local invid, slot = player.get_inventory(pid)
    if not this.plant(x, y, z, inventory.get(invid, slot)) then
        return false
    end
    if not player.is_infinite_items(pid) then
        inventory.decrement(invid, slot, 1)
    end
    return true
end

-- what a broken crop drops: the vegetables when ripe, else its seed back
local function crop_loot(name)
    local c = this.CROPS[name]
    return function(variant)
        if (variant or 0) % this.WILTED >= this.RIPE then
            return {{item = c.produce, min = c.yield[1], max = c.yield[2]}}
        end
        return {{item = c.seed}}
    end
end
for name, c in pairs(this.CROPS) do
    drops.set(name, crop_loot(name))
    drops.set(c.wild, {{item = c.produce, min = 1, max = 2}})
end
drops.set(this.FARMLAND, {{item = "base:dirt.item"}})

function this.reset()
end

return this
