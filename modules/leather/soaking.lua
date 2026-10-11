-- Hides and furs thrown into a river or a lake soak by themselves: the drop
-- is swapped for the soaked item after a while in the water.
local process = require "leather/process"
local flow = require "water/flow"
local base_util = require "base:util"

local this = {}

local SCAN_PERIOD = 1.0
local RADIUS = 48

local timers = {}   -- drop uid -> seconds in water
local clock = 0
local drop_def = nil

local function drops_near(pos)
    local out = {}
    for _, uid in ipairs(entities.get_all_in_radius(pos, RADIUS)) do
        if entities.get_def(uid) == drop_def then
            out[#out + 1] = uid
        end
    end
    return out
end

function this.tick(dt)
    clock = clock + dt
    if clock < SCAN_PERIOD then
        return
    end
    local step = clock
    clock = 0
    if not drop_def then
        local ok, def = pcall(entities.def_index, "base:drop")
        if not ok then
            return
        end
        drop_def = def
    end
    local seen = {}
    for _, pid in ipairs(player.get_all and player.get_all() or {}) do
        local x, y, z = player.get_pos(pid)
        for _, uid in ipairs(drops_near({x, y, z})) do
            if not seen[uid] then
                seen[uid] = true
                this.soak(uid, step)
            end
        end
    end
    for uid in pairs(timers) do
        if not seen[uid] then
            timers[uid] = nil
        end
    end
end

-- one drop: counts its time in water and swaps it when soaked
function this.soak(uid, dt)
    local e = entities.get(uid)
    local comp = e and e:get_component("base:drop")
    local d = comp and comp.dropitem
    if not d or not d.id then
        return
    end
    local soaked = process.in_water(item.name(d.id))
    if not soaked then
        return
    end
    local pos = e.transform:get_pos()
    if not flow.in_water(pos[1], pos[2], pos[3]) then
        timers[uid] = nil
        return
    end
    timers[uid] = (timers[uid] or 0) + dt
    if timers[uid] >= process.SOAK_TIME_WILD then
        timers[uid] = nil
        local count = d.count or 1
        e:despawn()
        local new = base_util.drop(pos, item.index(soaked), count)
        if new then
            new.rigidbody:set_vel({0, 0, 0})
        end
    end
end

function this.reset()
    timers = {}
    clock = 0
end

return this
