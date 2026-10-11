-- A finished dugout. Floats on still or flowing water, lies on the ground
-- otherwise. The use button on it in water: get in; on land with an empty
-- hand (or crouching, anywhere): lift it onto the shoulders. A carried boat
-- is put down in front with the use button. Seated, a paddle in hand rows
-- it (forward / back, left / right turn); crouch to get out.
local boat = require "boat/boat"
local flow = require "water/flow"

local tsf = entity.transform
local body = entity.rigidbody

local HALF_H = 0.36
local DRAFT = 0.12            -- the hull sits this deep (its floor stays dry)
local ROW_SPEED = 4.0         -- m/s forward
local BACK_SPEED = 1.6
local ACCEL = 2.4             -- m/s^2 with strokes
local DRAG = 0.7              -- share of speed lost per second when gliding
local TURN_RATE = 65          -- degrees per second
local STROKE_EVERY = 0.85
local SEAT = 0.55             -- rider's centre above the hull floor
local USE_COOLDOWN = 0.4

local yaw = SAVED_DATA.yaw or ARGS.yaw or 0
SAVED_DATA.yaw = yaw

local rider = nil
local carrier = nil
local speed = 0
local turning = 0
local stroke_timer = 0
local last_action = -10
local afloat = nil
local bob_t = math.random() * 10

local function forward_dir(a)
    local r = math.rad(a)
    return {-math.sin(r), 0, -math.cos(r)}
end

local function apply_rot(roll, pitch)
    local m = mat4.rotate({0, 1, 0}, yaw)
    if pitch and pitch ~= 0 then
        m = mat4.mul(m, mat4.rotate({1, 0, 0}, pitch))
    end
    if roll and roll ~= 0 then
        m = mat4.mul(m, mat4.rotate({0, 0, 1}, roll))
    end
    tsf:set_rot(m)
end
apply_rot()

-- height of the water surface under the boat, nil if it is not on water
local function water_surface(pos)
    local x, z = math.floor(pos[1]), math.floor(pos[3])
    local y0 = math.floor(pos[2] - HALF_H - 0.3)
    for y = y0 + 2, y0, -1 do
        local h = flow.surface(x, y, z)
        if h then
            return y + h
        end
    end
    return nil
end

local function player_entity(pid)
    return entities.get(player.get_entity(pid))
end

local function crouching(pid)
    local e = player_entity(pid)
    return e and e.rigidbody:is_crouching()
end

local function hand_empty(pid)
    local invid, slot = player.get_inventory(pid)
    return inventory.get(invid, slot) == 0
end

-- where the rider steps out: beside the boat, on something solid
local function exit_spot()
    local pos = tsf:get_pos()
    local f = forward_dir(yaw)
    local side = {-f[3], 0, f[1]}
    local tries = {side, {-side[1], 0, -side[3]}, f, {-f[1], 0, -f[3]}}
    for _, d in ipairs(tries) do
        for _, dist in ipairs({1.2, 2.0}) do
            local x = math.floor(pos[1] + d[1] * dist)
            local z = math.floor(pos[3] + d[3] * dist)
            for y = math.floor(pos[2]) + 1, math.floor(pos[2]) - 1, -1 do
                if block.is_solid_at(x, y - 1, z) and not block.is_solid_at(x, y, z)
                   and not block.is_solid_at(x, y + 1, z) then
                    return {x + 0.5, y + 0.9 + 0.05, z + 0.5}
                end
            end
        end
    end
    return {pos[1], pos[2] + HALF_H + 1.0, pos[3]}
end

-- actions -------------------------------------------------------------------

function board(pid)
    rider = pid
    speed, turning = 0, 0
    boat.seat(pid, entity:get_uid())
    last_action = time.uptime()
end

function leave(pid)
    if rider ~= pid then
        return
    end
    rider = nil
    boat.unseat(pid)
    local p = exit_spot()
    player.set_vel(pid, 0, 0, 0)
    player.set_pos(pid, p[1], p[2], p[3])
    last_action = time.uptime()
end

function pick_up(pid)
    carrier = pid
    rider = nil
    body:set_enabled(false)
    boat.carry(pid, entity:get_uid())
    audio.play_sound("blocks/wood_place", tsf:get_pos()[1], tsf:get_pos()[2], tsf:get_pos()[3], 0.8, 0.8, "regular")
    last_action = time.uptime()
end

function put_down(pid)
    if carrier ~= pid then
        return
    end
    local x, y, z = player.get_pos(pid)
    local rx = player.get_rot(pid)
    local f = forward_dir(rx)
    -- in front, at the height of the ground or the water there
    local px, pz = x + f[1] * 2.0, z + f[3] * 2.0
    local py = y - 0.9 + HALF_H + 0.05
    for yy = math.floor(y) + 1, math.floor(y) - 3, -1 do
        local h = flow.surface(math.floor(px), yy, math.floor(pz))
        if h then
            py = yy + h - DRAFT + HALF_H
            break
        elseif block.is_solid_at(math.floor(px), yy, math.floor(pz)) then
            py = yy + 1 + HALF_H + 0.02
            break
        end
    end
    carrier = nil
    boat.uncarry(pid)
    yaw = rx
    SAVED_DATA.yaw = yaw
    tsf:set_pos({px, py, pz})
    body:set_enabled(true)
    body:set_vel({0, 0, 0})
    apply_rot()
    afloat = nil
    audio.play_sound("blocks/wood_place", px, py, pz, 0.9, 0.85, "regular")
    last_action = time.uptime()
end

function on_used(pid)
    local now = time.uptime()
    if rider or carrier or now - last_action < USE_COOLDOWN then
        return
    end
    if boat.seated_in(pid) or boat.carried_by(pid) then
        return
    end
    local pos = tsf:get_pos()
    local wet = water_surface(pos) ~= nil
    if crouching(pid) or (not wet and hand_empty(pid)) then
        pick_up(pid)
    elseif wet then
        board(pid)
    end
end

-- physics ---------------------------------------------------------------------

local function carried(delta)
    if not player.get_entity(carrier) or player.get_entity(carrier) == 0 then
        carrier = nil
        body:set_enabled(true)
        return
    end
    local x, y, z = player.get_pos(carrier)
    local rx = player.get_rot(carrier)
    yaw = rx
    SAVED_DATA.yaw = yaw
    -- high on the shoulders, the bow raised: the way ahead stays in sight
    tsf:set_pos({x, y + 1.55, z})
    apply_rot(0, 12)
end

local function row(delta, pos)
    local fwd, back, left, right, out = boat.controls(rider)
    if out then
        leave(rider)
        return
    end
    local paddle = boat.holds_paddle(rider)
    local wish = 0
    if paddle and fwd then
        wish = ROW_SPEED
    elseif paddle and back then
        wish = -BACK_SPEED
    end
    if wish ~= 0 then
        speed = speed + math.max(-ACCEL * delta, math.min(ACCEL * delta, wish - speed))
    else
        speed = speed * (1 - math.min(1, DRAG * delta))
    end
    turning = 0
    if paddle and (left or right) then
        turning = (left and 1 or 0) - (right and 1 or 0)
        yaw = (yaw + turning * TURN_RATE * delta) % 360
        SAVED_DATA.yaw = yaw
    end
    if paddle and (wish ~= 0 or turning ~= 0) then
        stroke_timer = stroke_timer - delta
        if stroke_timer <= 0 then
            stroke_timer = STROKE_EVERY
            audio.play_sound("medieval_core/paddle", pos[1], pos[2], pos[3], 0.7,
                0.9 + math.random() * 0.2, "regular")
        end
    else
        stroke_timer = 0.2
    end
end

function on_physics_update(delta)
    if carrier then
        carried(delta)
        return
    end
    local pos = tsf:get_pos()
    local surface = water_surface(pos)
    local wet = surface ~= nil
    if wet ~= afloat then
        afloat = wet
        body:set_gravity_scale(wet and 0 or 1)
        body:set_vdamping(wet)
        body:set_linear_damping(wet and 0 or 4)
    end
    if rider then
        if not player.get_entity(rider) or player.get_entity(rider) == 0 then
            rider = nil
        else
            row(delta, pos)
        end
    elseif wet then
        speed = speed * (1 - math.min(1, DRAG * delta))
    end
    if wet then
        local f = forward_dir(yaw)
        local vel = body:get_vel()
        -- the hull keeps its heading: sideways drift dies out
        local target_y = surface - DRAFT + HALF_H
        body:set_vel({f[1] * speed, (target_y - pos[2]) * 5, f[3] * speed})
    elseif rider then
        speed = 0
    end
    if rider then
        -- the rider sits on the floor of the hull, pinned to it
        local p = tsf:get_pos()
        local floor = p[2] - HALF_H + 0.22
        player.set_vel(rider, 0, 0, 0)
        player.set_pos(rider, p[1], floor + SEAT, p[3])
    end
    apply_rot()
end

-- a gentle rocking on the water
function on_render(delta)
    if afloat and not carrier then
        bob_t = bob_t + delta
        local roll = math.sin(bob_t * 1.3) * 1.6 + turning * 4
        local pitch = math.sin(bob_t * 0.9 + 1.0) * 0.8 - speed * 0.6
        apply_rot(roll, pitch)
    end
end

function get_state()
    if carrier then return "carried" end
    if rider then return "ridden" end
    return afloat and "water" or "land"
end

function get_rider()
    return rider
end

function get_yaw()
    return yaw
end

function get_speed()
    return speed
end
