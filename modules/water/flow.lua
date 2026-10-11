-- Minecraft-like flowing water.
--
-- base:water is the source block. Flowing water has a block per level:
-- medieval_core:falling_water (level 0, a falling column) and
-- medieval_core:flowing_water_1..7 (distance from the source, 1 is the highest
-- sheet). Separate blocks instead of variants let the renderer cull the
-- faces between neighbouring levels while keeping each top face visible. The simulation is event driven: a changed cell
-- schedules itself and its neighbours, and every STEP ticks all scheduled
-- cells recompute what they should hold from their neighbours:
--   * water above -> falling water
--   * two horizontal sources and solid ground (or a source) below -> source
--   * otherwise the lowest neighbour level + 1 (up to 7), taken only from
--     neighbours that may spread sideways (sources always; flowing water only
--     when it rests on solid ground) and that prefer this direction - water
--     heads for the nearest drop within HOLE_SEARCH blocks, like in Minecraft
--   * nothing feeds it -> it dries up
-- Generated seas stay still until something next to them changes.
local this = {}

this.STEP = 5                 -- ticks between flow steps (4 steps a second)
this.MAX_LEVEL = 7
this.FALLING = 0

local MAX_UPDATES = 4096      -- per step, the rest waits for the next one
local HOLE_SEARCH = 4
local SAVE_FILE = "water.json"

local SOURCE, FLOWING, EMPTY, SOLID, UNLOADED = 1, 2, 3, 4, 5
local DIRS = {{1, 0}, {-1, 0}, {0, 1}, {0, -1}}

local ids = nil
local washable = {}

local function init_ids()
    if ids then
        return ids
    end
    ids = {
        source = block.index("base:water"),
        by_level = {[0] = block.index("medieval_core:falling_water")},
        level = {},
    }
    for level = 1, this.MAX_LEVEL do
        ids.by_level[level] = block.index("medieval_core:flowing_water_" .. level)
    end
    for level = 0, this.MAX_LEVEL do
        ids.level[ids.by_level[level]] = level
    end
    -- plants (X-shaped sprites) are washed away
    for i = 0, block.defs_count() - 1 do
        if block.get_model(i) == "X" then
            washable[i] = true
        end
    end
    return ids
end

function this.ids()
    return init_ids()
end

function this.is_water(id)
    init_ids()
    return id == ids.source or ids.level[id] ~= nil
end

-- flowing water level of a block id (0 = falling), nil for anything else
function this.level_of(id)
    init_ids()
    return ids.level[id]
end

-- surface height of a water cell (0..1), nil if the cell holds no water
function this.surface(x, y, z)
    init_ids()
    local id = block.get(x, y, z)
    if id == ids.source then
        return 1.0
    end
    local level = ids.level[id]
    if level == nil then
        return nil
    elseif level == this.FALLING then
        return 1.0
    end
    return (8 - level) / 8
end

-- is the point (world coordinates) inside water
function this.in_water(x, y, z)
    local bx, by, bz = math.floor(x), math.floor(y), math.floor(z)
    local h = this.surface(bx, by, bz)
    return h ~= nil and y - by < h
end

local function read(x, y, z)
    local id = block.get(x, y, z)
    if id == -1 then
        return UNLOADED
    elseif id == 0 or washable[id] then
        return EMPTY
    elseif id == ids.source then
        return SOURCE, 0
    end
    local level = ids.level[id]
    if level then
        return FLOWING, level
    end
    return SOLID
end

-- water can pass into this kind of cell (or already flows there)
local function passable(kind)
    return kind == EMPTY or kind == FLOWING
end

-- flowing water spreads sideways only when it can't go down
local function can_spread(x, y, z, kind)
    if kind == SOURCE then
        return true
    end
    local below = read(x, y - 1, z)
    return below == SOLID or below == UNLOADED
end

-- queue -------------------------------------------------------------------

local queue = {}
local queued = {}
local timer = 0

local function key(x, y, z)
    return x .. "," .. y .. "," .. z
end

function this.schedule(x, y, z)
    local k = key(x, y, z)
    if not queued[k] then
        queued[k] = true
        queue[#queue + 1] = {x, y, z}
    end
end

-- something changed at (x, y, z): the cell and its neighbours re-check
function this.notify(x, y, z)
    this.schedule(x, y, z)
    this.schedule(x + 1, y, z)
    this.schedule(x - 1, y, z)
    this.schedule(x, y + 1, z)
    this.schedule(x, y - 1, z)
    this.schedule(x, y, z + 1)
    this.schedule(x, y, z - 1)
end

function this.pending()
    return #queue
end

-- direction preference ------------------------------------------------------

-- distance to the nearest drop reachable from (x, y, z) without going back
local function slope_distance(x, y, z, depth, back)
    local best = 1000
    for i, d in ipairs(DIRS) do
        if i ~= back then
            local nx, nz = x + d[1], z + d[2]
            if passable(read(nx, y, nz)) then
                if passable(read(nx, y - 1, nz)) then
                    return depth
                end
                if depth < HOLE_SEARCH then
                    -- the opposite of direction i
                    local dist = slope_distance(nx, y, nz, depth + 1, i % 2 == 1 and i + 1 or i - 1)
                    best = math.min(best, dist)
                end
            end
        end
    end
    return best
end

local preferred_cache = {}

-- set of direction indices the cell at (x, y, z) wants to spread to
local function preferred(x, y, z)
    local k = key(x, y, z)
    local cached = preferred_cache[k]
    if cached then
        return cached
    end
    local dists = {}
    local best = 1000
    for i, d in ipairs(DIRS) do
        local nx, nz = x + d[1], z + d[2]
        local dist = 1000
        if passable(read(nx, y, nz)) then
            if passable(read(nx, y - 1, nz)) then
                dist = 0
            else
                dist = slope_distance(nx, y, nz, 1, i % 2 == 1 and i + 1 or i - 1)
            end
        end
        dists[i] = dist
        best = math.min(best, dist)
    end
    local result = {}
    for i = 1, 4 do
        result[i] = dists[i] == best
    end
    preferred_cache[k] = result
    return result
end

-- update ------------------------------------------------------------------------

-- what a non-source cell should hold: "source", a level (0 = falling) or nil
local function desired(x, y, z)
    local above = read(x, y + 1, z)
    if above == SOURCE or above == FLOWING then
        return this.FALLING
    end
    local sources = 0
    local best = nil
    for i, d in ipairs(DIRS) do
        local nx, nz = x + d[1], z + d[2]
        local kind, level = read(nx, y, nz)
        if kind == SOURCE then
            sources = sources + 1
        end
        if (kind == SOURCE or kind == FLOWING) then
            local value = level + 1
            if value <= this.MAX_LEVEL and (not best or value < best) and
               can_spread(nx, y, nz, kind) then
                -- the neighbour looks at us from the opposite direction
                local back = i % 2 == 1 and i + 1 or i - 1
                if preferred(nx, y, nz)[back] then
                    best = value
                end
            end
        end
    end
    if sources >= 2 then
        local below = read(x, y - 1, z)
        if below == SOLID or below == SOURCE then
            return "source"
        end
    end
    return best
end

local function put(x, y, z, value)
    if value == nil then
        block.set(x, y, z, 0, 0, true)
    elseif value == "source" then
        block.set(x, y, z, ids.source, 0, true)
    else
        block.set(x, y, z, ids.by_level[value], 0, true)
    end
end

local function update(x, y, z)
    local kind, level = read(x, y, z)
    if kind ~= EMPTY and kind ~= FLOWING then
        return
    end
    local want = desired(x, y, z)
    if kind == EMPTY then
        if want == nil then
            return
        end
    elseif want == level then
        return
    end
    put(x, y, z, want)
    this.notify(x, y, z)
end

-- runs every world tick
function this.tick()
    timer = timer + 1
    if timer < this.STEP or #queue == 0 then
        return
    end
    timer = 0
    this.step()
end

-- one flow step: processes everything scheduled before it
function this.step()
    init_ids()
    local current = queue
    queue = {}
    queued = {}
    preferred_cache = {}
    for i, p in ipairs(current) do
        if i > MAX_UPDATES then
            this.schedule(p[1], p[2], p[3])
        else
            update(p[1], p[2], p[3])
        end
    end
end

-- persistence ------------------------------------------------------------------

function this.save()
    local data = {}
    for _, p in ipairs(queue) do
        data[#data + 1] = p
    end
    file.write(pack.data_file("medieval_core", SAVE_FILE), json.tostring(data))
end

function this.load()
    this.reset()
    local path = pack.data_file("medieval_core", SAVE_FILE)
    if file.exists(path) then
        for _, p in ipairs(json.parse(file.read(path))) do
            this.schedule(p[1], p[2], p[3])
        end
    end
end

function this.reset()
    queue = {}
    queued = {}
    preferred_cache = {}
    timer = 0
end

return this
