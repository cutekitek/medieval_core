-- Feeding troughs (blocks/trough.json): a 2x1 trough holds either feed or
-- water, up to CAPACITY portions. Feed comes from grass, plant fibre or wheat
-- (the use button with it in hand), water from full buckets of water. A
-- meal or a drink of a farm animal takes one portion.
--
-- The origin block keeps the portions in its "portions" field; its variant
-- shows what is inside and how full it is (0 empty, 1-3 feed, 4-6 water).
-- Loaded troughs are listed in this.sites for the animals to find.
local this = {}

this.CAPACITY = 12
this.LEVELS = 3
this.BUCKET = 4                   -- portions of water per bucket
-- portions of feed per item
this.FEED = {
    ["medieval_core:wheat"] = 3,
    ["medieval_core:plant_fiber"] = 2,
    ["base:grass.item"] = 2,
}

local WATER_BASE = 3              -- variant of water level 1 minus 1

-- "x,y,z" of the origin -> {x, y, z}
this.sites = {}

local function key(x, y, z)
    return x .. "," .. y .. "," .. z
end

local function trough_id()
    return block.index("medieval_core:trough")
end

function this.is_trough(x, y, z)
    return block.get(x, y, z) == trough_id()
end

local function origin(x, y, z)
    return block.seek_origin(x, y, z)
end

-- "feed", "water" or nil; portions
function this.get(x, y, z)
    if not this.is_trough(x, y, z) then
        return nil, 0
    end
    x, y, z = origin(x, y, z)
    local portions = block.get_field(x, y, z, "portions") or 0
    if portions <= 0 then
        return nil, 0
    end
    local variant = block.get_variant(x, y, z)
    return variant > WATER_BASE and "water" or "feed", portions
end

local function store(x, y, z, kind, portions)
    portions = math.max(0, math.min(this.CAPACITY, portions))
    block.set_field(x, y, z, "portions", portions)
    local variant = 0
    if portions > 0 then
        local level = math.ceil(portions / this.CAPACITY * this.LEVELS)
        variant = (kind == "water" and WATER_BASE or 0) + level
    end
    if block.get_variant(x, y, z) ~= variant then
        block.set_variant(x, y, z, variant)
    end
end

-- adds portions of kind; returns how many went in (0: full, or holds the
-- other kind)
function this.add(x, y, z, kind, portions)
    if not this.is_trough(x, y, z) then
        return 0
    end
    x, y, z = origin(x, y, z)
    local current, have = this.get(x, y, z)
    if current and current ~= kind then
        return 0
    end
    local added = math.min(portions, this.CAPACITY - have)
    if added > 0 then
        store(x, y, z, kind, have + added)
    end
    return added
end

-- an animal eats or drinks one portion; false if there is none of that kind
function this.take(x, y, z, kind)
    local current, have = this.get(x, y, z)
    if current ~= kind or have <= 0 then
        return false
    end
    x, y, z = origin(x, y, z)
    store(x, y, z, kind, have - 1)
    return true
end

-- the cells the trough covers: {x1, z1, x2, z2} (inclusive), y
function this.footprint(x, y, z)
    x, y, z = origin(x, y, z)
    local id = trough_id()
    for _, d in ipairs({{1, 0}, {-1, 0}, {0, 1}, {0, -1}}) do
        local nx, nz = x + d[1], z + d[2]
        if block.get(nx, y, nz) == id then
            local ox, _, oz = origin(nx, y, nz)
            if ox == x and oz == z then
                return {math.min(x, nx), math.min(z, nz), math.max(x, nx), math.max(z, nz)}, y
            end
        end
    end
    return {x, z, x, z}, y
end

-- the nearest listed trough with kind in it within radius of pos:
-- origin {x, y, z}, its footprint, distance
function this.find(pos, radius, kind)
    local best, best_rect, best_dist = nil, nil, radius
    for k, s in pairs(this.sites) do
        if not this.is_trough(s[1], s[2], s[3]) then
            this.sites[k] = nil
        else
            local rect = this.footprint(s[1], s[2], s[3])
            local cx = (rect[1] + rect[3] + 1) * 0.5
            local cz = (rect[2] + rect[4] + 1) * 0.5
            local d = vec3.distance(pos, {cx, s[2] + 0.5, cz})
            if d < best_dist and this.get(s[1], s[2], s[3]) == kind then
                best, best_rect, best_dist = s, rect, d
            end
        end
    end
    return best, best_rect, best_dist
end

function this.present(x, y, z)
    x, y, z = origin(x, y, z)
    this.sites[key(x, y, z)] = {x, y, z}
end

-- broken or unloaded (the voxel may be gone: no origin lookup; a segment's
-- event finds nothing, find() drops stale sites anyway)
function this.removed(x, y, z)
    this.sites[key(x, y, z)] = nil
end

local function sound(name, x, y, z, volume)
    audio.play_sound(name, x + 1, y + 0.4, z + 0.5, volume or 0.7, 0.9 + math.random() * 0.2, "regular")
end

local function held(pid)
    local invid, slot = player.get_inventory(pid)
    local id, count = inventory.get(invid, slot)
    return invid, slot, id, count
end

-- a bucket of water nobody has watered anything with
local function full_bucket(invid, slot, id)
    local uses = inventory.get_data(invid, slot, "uses")
    return uses == nil or uses >= item.uses(id)
end

-- the use button on the trough: pours a bucket of water or puts feed in.
-- Returns true when the click was taken.
function this.use(x, y, z, pid)
    if not this.is_trough(x, y, z) then
        return false
    end
    local ox, oy, oz = origin(x, y, z)
    local invid, slot, id, count = held(pid)
    if id == 0 then
        return false
    end
    local name = item.name(id)
    local infinite = player.is_infinite_items(pid)
    if name == "medieval_core:water_bucket" then
        if full_bucket(invid, slot, id) and this.add(ox, oy, oz, "water", this.BUCKET) > 0 then
            if not infinite then
                inventory.set(invid, slot, item.index("medieval_core:wooden_bucket"), 1)
            end
            sound("medieval_core/bucket_pour", ox, oy, oz, 0.8)
        end
        return true
    end
    local portions = this.FEED[name]
    if portions then
        if this.add(ox, oy, oz, "feed", portions) > 0 then
            if not infinite then
                inventory.set(invid, slot, count > 1 and id or 0, count - 1)
            end
            sound("medieval_core/dig_plant", ox, oy, oz, 0.6)
        end
        return true
    end
    return false
end

function this.reset()
    this.sites = {}
end

return this
