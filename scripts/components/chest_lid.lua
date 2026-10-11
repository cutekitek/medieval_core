-- The lid of an open chest (modules/storage/chest.lua): turns on the hinge
-- (the entity origin) up to OPEN_ANGLE and back. Back down, it hands the
-- lid over to the block and despawns. The swing is a function of time:
-- drawn in on_render, finished in on_physics_update (runs headless too).
local chest = require "storage/chest"

local tsf = entity.transform

local OPEN_ANGLE = 100          -- degrees
local OPEN_TIME = 0.35
local CLOSE_TIME = 0.3
local LINGER = 0.15             -- stays a moment while the block mesh updates

local pos = {ARGS.x, ARGS.y, ARGS.z}
local yaw = ARGS.yaw or 0
local open = true
local from_t = 0                -- 0 closed .. 1 open, when the swing began
local since = time.uptime()
local gone_at = nil

local function progress()
    local dt = time.uptime() - since
    if open then
        return math.min(1, from_t + dt / OPEN_TIME)
    end
    return math.max(0, from_t - dt / CLOSE_TIME)
end

-- ease in and out
local function ease(v)
    return v * v * (3 - 2 * v)
end

local function pose()
    local m = mat4.rotate({0, 1, 0}, yaw)
    -- the front (local +Z) goes up
    tsf:set_rot(mat4.mul(m, mat4.rotate({1, 0, 0}, -OPEN_ANGLE * ease(progress()))))
end
pose()

function set_open(flag)
    if flag == open and not gone_at then
        return
    end
    from_t = progress()
    since = time.uptime()
    open = flag
    gone_at = nil
end

function is_open()
    return open
end

function get_angle()
    return OPEN_ANGLE * ease(progress())
end

function on_physics_update(delta)
    if not pos[1] then
        entity:despawn()
        return
    end
    local now = time.uptime()
    if gone_at then
        if now >= gone_at then
            entity:despawn()
        end
    elseif not open and progress() == 0 then
        chest.closed(pos[1], pos[2], pos[3], entity:get_uid())
        gone_at = now + LINGER
    end
end

function on_render(delta)
    pose()
end
