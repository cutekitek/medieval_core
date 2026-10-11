-- Carving a dugout: three logs lying in a line along their axis, open from
-- above, are hollowed out with an axe (hold the use button on any of them).
-- Logs -> rough hewn blank (stage 1) -> shallow hollow (2) -> deep hollow (3)
-- -> the finished boat (entity medieval_core:dugout). Stages are the blocks
-- medieval_core:dugout_end (both ends, tip outwards) and dugout_mid with the
-- stage in their user bits.
local drops = require "survival/drops"

local this = {}

this.STAGE_TIME = 3.0         -- seconds of carving per stage
this.STAGES = 3               -- block stages before the boat
local CHOP_EVERY = 0.42       -- a blow (sound, chips) this often
local MAX_STEP = 0.25         -- longer gaps: the player paused

local LOGS = {
    "base:wood", "medieval_core:spruce_log", "medieval_core:jungle_log", "medieval_core:palm_log",
    "medieval_core:stripped_oak_log", "medieval_core:stripped_spruce_log",
    "medieval_core:stripped_jungle_log", "medieval_core:stripped_palm_log",
}

-- pane/pipe rotation -> direction of local -Z
local DIRS = {[0] = {0, 0, -1}, [1] = {-1, 0, 0}, [2] = {0, 0, 1}, [3] = {1, 0, 0}}

local ids = nil
local function init()
    if ids then
        return ids
    end
    ids = {logs = {}, ["end"] = block.index("medieval_core:dugout_end"),
           mid = block.index("medieval_core:dugout_mid")}
    for _, name in ipairs(LOGS) do
        local ok, id = pcall(block.index, name)
        if ok and id then
            ids.logs[id] = true
        end
    end
    drops.set("medieval_core:dugout_end", {{item = "base:wood.item"}})
    drops.set("medieval_core:dugout_mid", {{item = "base:wood.item"}})
    return ids
end

local work = {}   -- "x:y:z" of the middle block -> {progress, last, next_chop}

local function key(p)
    return p[1] .. ":" .. p[2] .. ":" .. p[3]
end

local function add(p, d, k)
    return {p[1] + d[1] * k, p[2] + d[2] * k, p[3] + d[3] * k}
end

local function open_above(p)
    local id = block.get(p[1], p[2] + 1, p[3])
    return id == 0 or block.is_replaceable_at(p[1], p[2] + 1, p[3])
end

-- a horizontal log: its axis (unit vector along X or Z), else nil
local function log_axis(x, y, z)
    if not init().logs[block.get(x, y, z)] then
        return nil
    end
    local rot = block.get_rotation(x, y, z)
    if rot > 3 then
        return nil
    end
    return (rot % 2 == 0) and {0, 0, 1} or {1, 0, 0}
end

-- three logs in a line through (x, y, z): the middle one and the axis
local function find_logs(x, y, z)
    local axis = log_axis(x, y, z)
    if not axis then
        return nil
    end
    local function same(p)
        local a = log_axis(p[1], p[2], p[3])
        return a and a[1] == axis[1] and a[3] == axis[3]
    end
    local p = {x, y, z}
    -- the clicked log as the middle, else as one of the ends
    for _, shift in ipairs({0, -1, 1}) do
        local mid = add(p, axis, shift)
        local a, b = add(mid, axis, -1), add(mid, axis, 1)
        if same(mid) and same(a) and same(b) and open_above(a) and open_above(mid) and open_above(b) then
            return mid, axis
        end
    end
    return nil
end

-- the middle block of a dugout in progress and its axis
local function find_dugout(x, y, z)
    local ids = init()
    local id = block.get(x, y, z)
    local p = {x, y, z}
    if id == ids.mid then
        local d = DIRS[block.get_rotation(x, y, z) % 4]
        return p, {math.abs(d[1]), 0, math.abs(d[3])}
    elseif id == ids["end"] then
        local d = DIRS[block.get_rotation(x, y, z) % 4]
        local mid = add(p, d, -1)
        if block.get(mid[1], mid[2], mid[3]) == ids.mid then
            return mid, {math.abs(d[1]), 0, math.abs(d[3])}
        end
    end
    return nil
end

function this.stage_at(x, y, z)
    local ids = init()
    local id = block.get(x, y, z)
    if id == ids.mid or id == ids["end"] then
        return math.floor(block.get_states(x, y, z) / 256) + 1
    end
    return 0
end

-- rotation of an end block whose tip points along `out`
local function rot_of(out)
    for r = 0, 3 do
        local d = DIRS[r]
        if d[1] == out[1] and d[3] == out[3] then
            return r
        end
    end
    return 0
end

local function set_stage(mid, axis, stage)
    local ids = init()
    local bits = (stage - 1) * 256
    local back = {-axis[1], 0, -axis[3]}
    local a, b = add(mid, axis, -1), add(mid, axis, 1)
    block.set(a[1], a[2], a[3], ids["end"], rot_of(back) + bits)
    block.set(mid[1], mid[2], mid[3], ids.mid, rot_of(back) + bits)
    block.set(b[1], b[2], b[3], ids["end"], rot_of(axis) + bits)
end

local function finish(mid, axis)
    local a, b = add(mid, axis, -1), add(mid, axis, 1)
    for _, p in ipairs({a, mid, b}) do
        block.set(p[1], p[2], p[3], 0, 0)
    end
    local yaw = axis[1] ~= 0 and 90 or 0
    return entities.spawn("medieval_core:dugout", {mid[1] + 0.5, mid[2] + 0.4, mid[3] + 0.5},
        {medieval_core__dugout = {yaw = yaw}})
end

local function chop_effects(mid)
    local x, y, z = mid[1] + 0.5, mid[2] + 0.7, mid[3] + 0.5
    audio.play_sound("medieval_core/dig_wood", x, y, z, 0.7, 0.85 + math.random() * 0.25, "regular")
    if gfx and gfx.particles then
        gfx.particles.emit({x, y, z}, 5, {
            texture = "blocks:mw_bark_chip",
            lifetime = 0.8,
            spawn_shape = "box",
            spawn_spread = {0.6, 0.1, 0.6},
            explosion = {2.5, 3.0, 2.5},
            size = {0.07, 0.07, 0.07},
            acceleration = {0, -14, 0},
        })
    end
end

-- One step of carving at a block (called while the use button is held with
-- an axe). Returns true if the block is part of a dugout or its logs.
-- dt may be given explicitly (tests).
function this.carve(x, y, z, pid, dt)
    local mid, axis = find_dugout(x, y, z)
    local stage = 0
    if mid then
        stage = this.stage_at(mid[1], mid[2], mid[3])
    else
        mid, axis = find_logs(x, y, z)
        if not mid then
            return false
        end
    end
    local now = time.uptime()
    local k = key(mid)
    local w = work[k]
    if not w or w.stage ~= stage then
        w = {progress = 0, last = now, next_chop = now, stage = stage}
        work[k] = w
        dt = dt or 0.16
    else
        dt = dt or math.min(now - w.last, MAX_STEP)
    end
    w.last = now
    w.progress = w.progress + dt
    if now >= w.next_chop then
        w.next_chop = now + CHOP_EVERY
        chop_effects(mid)
    end
    if w.progress >= this.STAGE_TIME then
        work[k] = nil
        if not player.is_infinite_items(pid) then
            local invid, slot = player.get_inventory(pid)
            inventory.use(invid, slot)
        end
        if stage >= this.STAGES then
            finish(mid, axis)
            audio.play_sound("medieval_core/dig_wood", mid[1] + 0.5, mid[2] + 0.5, mid[3] + 0.5, 1.0, 0.7, "regular")
        else
            set_stage(mid, axis, stage + 1)
        end
    end
    return true
end

function this.progress(x, y, z)
    local mid = find_dugout(x, y, z) or find_logs(x, y, z)
    local w = mid and work[key(mid)]
    return w and w.progress / this.STAGE_TIME or 0
end

function this.reset()
    work = {}
    ids = nil
end

return this
