-- Pit firing of raw clay pieces. A raw piece (a block placed from its item)
-- is put into a pit - a hole with solid ground under it and on all four
-- sides - covered with grass (COVER handfuls, the block's variant counts
-- them), and lit with a bow drill. The heap (medieval_core:pit_kiln) burns for
-- BURN_TIME seconds, settling as it goes; when the grass has burnt away the
-- fired piece is left in the pit.
-- Burning kilns (the raw piece, time burnt) live here and are saved with
-- the world; kilns in unloaded chunks are frozen.
local base_util = require "base:util"
local campfire = require "fire/campfire"
local visual = require "fire/campfire_visual"
local notice = require "player/notice"

local this = {}

local SAVE_FILE = "pit_kilns.json"
local KILN = "medieval_core:pit_kiln"
this.COVER = 4             -- handfuls of grass over a piece
this.BURN_TIME = 90        -- seconds

-- raw block -> fired block
this.FIRED = {
    ["medieval_core:raw_clay_pot"] = "medieval_core:clay_pot",
    ["medieval_core:raw_clay_plate"] = "medieval_core:clay_plate",
}
local DEFAULT_RAW = "medieval_core:raw_clay_pot"

-- what a piece is covered with
this.STRAW = {
    ["medieval_core:plant_fiber"] = true,
    ["base:grass.item"] = true,
    ["medieval_core:wheat"] = true,
}

-- the burning heap settles: its variant by the share of the time burnt
local SETTLE = {0.45, 0.8}
-- where the flames dance at each stage: over the top of the heap as it settles
local FLAMES = {
    [0] = {spread = 0.22, offset = 1.4},
    [1] = {spread = 0.3, offset = 0.92},
    [2] = {spread = 0.34, offset = 0.25},
}

local sites = {}   -- "x,y,z" -> {x, y, z, raw, t}

local function key(x, y, z)
    return x .. "," .. y .. "," .. z
end

local function name_at(x, y, z)
    local id = block.get(x, y, z)
    return id >= 0 and block.name(id) or nil
end

-- the fired block a raw piece turns into, nil for anything else
function this.fired_of(name)
    return name and this.FIRED[name]
end

function this.get(x, y, z)
    return sites[key(x, y, z)]
end

-- solid ground under the cell and all round it
function this.in_pit(x, y, z)
    return block.is_solid_at(x, y - 1, z)
        and block.is_solid_at(x - 1, y, z) and block.is_solid_at(x + 1, y, z)
        and block.is_solid_at(x, y, z - 1) and block.is_solid_at(x, y, z + 1)
end

-- handfuls of grass on a raw piece (0 for anything else)
function this.cover(x, y, z)
    if not this.fired_of(name_at(x, y, z)) then
        return 0
    end
    return block.get_variant(x, y, z)
end

local function sound(name, x, y, z, volume)
    if gfx then
        audio.play_sound(name, x + 0.5, y + 0.5, z + 0.5, volume, 0.9 + math.random() * 0.2, "regular")
    end
end

-- Right click on a raw piece: grass in hand covers it (only in a pit).
-- Returns true if the click is taken.
function this.interact(x, y, z, pid)
    if not this.fired_of(name_at(x, y, z)) then
        return false
    end
    local invid, slot = player.get_inventory(pid)
    local itemid = inventory.get(invid, slot)
    if itemid == 0 or not this.STRAW[item.name(itemid)] then
        return false
    end
    local cover = block.get_variant(x, y, z)
    if cover >= this.COVER then
        return true
    end
    if not this.in_pit(x, y, z) then
        notice.show(pid, "medieval_core.kiln.pit")
        return true
    end
    block.set_variant(x, y, z, cover + 1)
    if not player.is_infinite_items(pid) then
        inventory.decrement(invid, slot, 1)
    end
    sound("medieval_core/dig_plant", x, y, z, 0.7)
    return true
end

-- sets the heap alight: the raw piece goes under the burning kiln
function this.light(x, y, z)
    local raw = name_at(x, y, z)
    if not this.fired_of(raw) then
        return false
    end
    block.set(x, y, z, block.index(KILN), 0)
    sites[key(x, y, z)] = {x = x, y = y, z = z, raw = raw, t = 0}
    visual.kindle(x, y, z, FLAMES[0])
    visual.ignite(x, y, z)
    return true
end

-- Bow drilling a covered piece; returns "lit", "drilling", or nil when there
-- is nothing to light here (an uncovered piece, not in a pit).
function this.drill(pid, x, y, z, dt)
    if this.cover(x, y, z) < this.COVER then
        return nil
    end
    if not this.in_pit(x, y, z) then
        notice.show(pid, "medieval_core.kiln.pit")
        return nil
    end
    if campfire.drill_progress(pid, x, y, z, dt) then
        this.light(x, y, z)
        return "lit"
    end
    return "drilling"
end

local function finish(k, s)
    sites[k] = nil
    visual.clear(s.x, s.y, s.z)
    visual.burn_out(s.x, s.y, s.z)
    block.set(s.x, s.y, s.z, block.index(this.FIRED[s.raw] or this.FIRED[DEFAULT_RAW]), 0)
end

function this.tick(dt)
    local kiln = block.index(KILN)
    for k, s in pairs(sites) do
        local blockid = block.get(s.x, s.y, s.z)
        if blockid == -1 then
            -- unloaded chunk: frozen
        elseif blockid == kiln then
            s.t = s.t + dt
            local share = s.t / this.BURN_TIME
            if share >= 1 then
                finish(k, s)
            else
                local stage = 0
                for i, edge in ipairs(SETTLE) do
                    if share >= edge then
                        stage = i
                    end
                end
                if block.get_variant(s.x, s.y, s.z) ~= stage then
                    block.set_variant(s.x, s.y, s.z, stage)
                    visual.clear(s.x, s.y, s.z)
                    visual.kindle(s.x, s.y, s.z, FLAMES[stage])
                end
            end
        else
            -- the kiln went away without a player breaking it
            sites[k] = nil
            visual.clear(s.x, s.y, s.z)
        end
    end
end

-- a player broke the burning heap: the raw piece is rescued unfired
function this.broken(x, y, z)
    local k = key(x, y, z)
    local s = sites[k]
    sites[k] = nil
    visual.clear(x, y, z)
    local raw = s and s.raw or DEFAULT_RAW
    local e = base_util.drop({x + 0.5, y + 0.5, z + 0.5}, item.index(raw .. ".item"), 1)
    if e then
        e.rigidbody:set_vel(vec3.spherical_rand(1.5))
    end
end

-- a kiln block appeared (loaded, or placed by other means than lighting)
function this.present(x, y, z)
    if name_at(x, y, z) ~= KILN then
        return
    end
    local k = key(x, y, z)
    if not sites[k] then
        sites[k] = {x = x, y = y, z = z, raw = DEFAULT_RAW, t = 0}
    end
    visual.kindle(x, y, z, FLAMES[block.get_variant(x, y, z)] or FLAMES[0])
end

function this.unloaded(x, y, z)
    if sites[key(x, y, z)] then
        visual.clear(x, y, z)
    end
end

function this.save()
    local list = {}
    for _, s in pairs(sites) do
        list[#list + 1] = {s.x, s.y, s.z, s.raw, s.t}
    end
    file.write(pack.data_file("medieval_core", SAVE_FILE), json.tostring(list))
end

function this.load()
    this.reset()
    local path = pack.data_file("medieval_core", SAVE_FILE)
    if not file.exists(path) then
        return
    end
    for _, e in ipairs(json.parse(file.read(path))) do
        sites[key(e[1], e[2], e[3])] = {x = e[1], y = e[2], z = e[3], raw = e[4], t = e[5]}
    end
end

function this.reset()
    for _, s in pairs(sites) do
        visual.clear(s.x, s.y, s.z)
    end
    sites = {}
end

return this
