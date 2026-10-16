-- The player's body in the third person (models/mw_player): every bone is
-- posed each frame from what the player is doing - walking, crouching,
-- jumping, swimming, climbing a ladder, riding, sitting in a dugout,
-- lying in bed - and the right arm plays short actions over that: a swing
-- (digging, chopping, hitting) and a push (placing a block, using an item).
-- The held item sits in the right fist; a spear or a bow takes its pose and
-- the arms from combat/ranged_pose. The head turns to the view.
local ranged_pose = require "combat/ranged_pose"
local sleep = require "player/sleep"
local riding = require "riding/riding"
local boat = require "boat/boat"

local this = {}

-- actions of the right arm: seconds
local ACTIONS = {
    swing = 0.34,
    use = 0.22,
}

local actions = {}      -- pid -> {kind, t0}

-- the right arm swings (dig, chop, hit) or pushes (place, use); an action
-- of the same kind still under way is not restarted
function this.play(pid, kind)
    local now = time.uptime()
    local a = actions[pid]
    if a and a.kind == kind and now - a.t0 < ACTIONS[kind] then
        return
    end
    actions[pid] = {kind = kind, t0 = now}
end

-- the action under way and its progress 0..1, or nil
function this.action(pid)
    local a = actions[pid]
    if not a then
        return nil
    end
    local t = (time.uptime() - a.t0) / ACTIONS[a.kind]
    if t >= 1 then
        actions[pid] = nil
        return nil
    end
    return a.kind, t
end

function this.reset()
    actions = {}
end

-- skeleton -----------------------------------------------------------------

local BONES = {"body", "torso", "head", "arm_l", "arm_l_low", "arm_r", "arm_r_low",
               "leg_l", "leg_l_low", "leg_r", "leg_r_low"}
local LIMBS = {"arm_l", "arm_l_low", "arm_r", "arm_r_low", "leg_l", "leg_l_low", "leg_r", "leg_r_low"}
local HIP = {0, -0.08, 0}
local NECK = {0, 0.5, 0}          -- the head bone in the body
local NECK_IN_TORSO = {0, 0.58, 0}
local STRIDE = 4.2                -- walk cycle radians per metre
-- lying in bed: the body flat on its back, the head towards the pillow
local LIE = mat4.mul(mat4.translate({0, -0.2, 0}), mat4.rotate({1, 0, 0}, 90))
-- the item in the fist: the handle in the hand, the head ahead and up;
-- items lie along the icon's diagonal, the fist on its lower third (at)
local GRIP = {pos = {0, -0.02, -0.06}, pitch = -60, yaw = 90, roll = 0, scale = 0.8,
              at = {0.15, 0.15, 0}}
-- a block the engine shrank to a 0.2 cube for the item model
local BLOCK_GRIP = {pos = {0, -0.1, -0.15}, pitch = 0, yaw = 45, roll = 0, scale = 1.25}

local function rot(x, y, z)
    local m = mat4.rotate({0, 1, 0}, y or 0)
    if z and z ~= 0 then
        m = mat4.mul(m, mat4.rotate({0, 0, 1}, z))
    end
    if x and x ~= 0 then
        m = mat4.mul(m, mat4.rotate({1, 0, 0}, x))
    end
    return m
end

local function smooth(t)
    return t * t * (3 - 2 * t)
end

-- target angles of a pose: bone -> {x, y, z} degrees; x forward for
-- arms and legs (raises them ahead), negative x bends the knees back
local function rest()
    return {
        torso = {0, 0, 0}, arm_l = {0, 0, -4}, arm_l_low = {6, 0, 0},
        arm_r = {0, 0, 4}, arm_r_low = {6, 0, 0},
        leg_l = {0, 0, 0}, leg_l_low = {0, 0, 0}, leg_r = {0, 0, 0}, leg_r_low = {0, 0, 0},
    }
end

local function grip_matrix(g)
    local m = mat4.translate(g.pos)
    m = mat4.mul(m, rot(g.pitch, g.yaw, g.roll))
    m = mat4.scale(m, {g.scale, g.scale, g.scale})
    if g.at then
        m = mat4.mul(m, mat4.translate(g.at))
    end
    return m
end

-- the item model is the block itself (not a flat icon)
local function is_block_model(itemid)
    local placing = item.placing_block(itemid)
    return placing ~= 0 and item.model_name(itemid) == item.name(itemid) .. ".model"
        and block.get_model(placing) ~= "X"
end

-- the archer's arms: 3x3 rotations (rows), two-bone reach ----------------

local SHOULDER_L = {-0.29, 0.54, 0}   -- in the torso
local SHOULDER_R = {0.29, 0.54, 0}
local UPPER, LOWER = 0.3, 0.27        -- shoulder to elbow, elbow to fist

local function v_add(a, b) return {a[1] + b[1], a[2] + b[2], a[3] + b[3]} end
local function v_sub(a, b) return {a[1] - b[1], a[2] - b[2], a[3] - b[3]} end
local function v_mul(a, k) return {a[1] * k, a[2] * k, a[3] * k} end
local function v_dot(a, b) return a[1] * b[1] + a[2] * b[2] + a[3] * b[3] end
local function v_len(a) return math.sqrt(v_dot(a, a)) end
local function v_norm(a)
    local l = v_len(a)
    return l > 1e-6 and v_mul(a, 1 / l) or {0, 0, 0}
end
local function v_cross(a, b)
    return {a[2] * b[3] - a[3] * b[2], a[3] * b[1] - a[1] * b[3], a[1] * b[2] - a[2] * b[1]}
end
-- a vector without its part along the unit vector n
local function v_off(a, n) return v_sub(a, v_mul(n, v_dot(a, n))) end

local function m3_mul(a, b)
    local r = {}
    for i = 1, 3 do
        r[i] = {}
        for j = 1, 3 do
            r[i][j] = a[i][1] * b[1][j] + a[i][2] * b[2][j] + a[i][3] * b[3][j]
        end
    end
    return r
end

local function m3_apply(r, v)
    return {r[1][1] * v[1] + r[1][2] * v[2] + r[1][3] * v[3],
            r[2][1] * v[1] + r[2][2] * v[2] + r[2][3] * v[3],
            r[3][1] * v[1] + r[3][2] * v[2] + r[3][3] * v[3]}
end

local function m3_t(a)
    return {{a[1][1], a[2][1], a[3][1]}, {a[1][2], a[2][2], a[3][2]}, {a[1][3], a[2][3], a[3][3]}}
end

local function m3_cols(x, y, z)
    return {{x[1], y[1], z[1]}, {x[2], y[2], z[2]}, {x[3], y[3], z[3]}}
end

-- the bone rotation of rot(x, y, z): Ry * Rz * Rx
local function m3_euler(a)
    local x, y, z = math.rad(a[1]), math.rad(a[2]), math.rad(a[3])
    local ry = {{math.cos(y), 0, math.sin(y)}, {0, 1, 0}, {-math.sin(y), 0, math.cos(y)}}
    local rz = {{math.cos(z), -math.sin(z), 0}, {math.sin(z), math.cos(z), 0}, {0, 0, 1}}
    local rx = {{1, 0, 0}, {0, math.cos(x), -math.sin(x)}, {0, math.sin(x), math.cos(x)}}
    return m3_mul(ry, m3_mul(rz, rx))
end

-- quaternions {w, x, y, z}: the limbs ease along the shortest turn
local function q_of(r)
    local tr = r[1][1] + r[2][2] + r[3][3]
    local w, x, y, z
    if tr > 0 then
        local k = math.sqrt(tr + 1) * 2
        w, x, y, z = k / 4, (r[3][2] - r[2][3]) / k, (r[1][3] - r[3][1]) / k, (r[2][1] - r[1][2]) / k
    elseif r[1][1] > r[2][2] and r[1][1] > r[3][3] then
        local k = math.sqrt(1 + r[1][1] - r[2][2] - r[3][3]) * 2
        w, x, y, z = (r[3][2] - r[2][3]) / k, k / 4, (r[1][2] + r[2][1]) / k, (r[1][3] + r[3][1]) / k
    elseif r[2][2] > r[3][3] then
        local k = math.sqrt(1 + r[2][2] - r[1][1] - r[3][3]) * 2
        w, x, y, z = (r[1][3] - r[3][1]) / k, (r[1][2] + r[2][1]) / k, k / 4, (r[2][3] + r[3][2]) / k
    else
        local k = math.sqrt(1 + r[3][3] - r[1][1] - r[2][2]) * 2
        w, x, y, z = (r[2][1] - r[1][2]) / k, (r[1][3] + r[3][1]) / k, (r[2][3] + r[3][2]) / k, k / 4
    end
    return {w, x, y, z}
end

local function q_m3(q)
    local w, x, y, z = q[1], q[2], q[3], q[4]
    return {
        {1 - 2 * (y * y + z * z), 2 * (x * y - w * z), 2 * (x * z + w * y)},
        {2 * (x * y + w * z), 1 - 2 * (x * x + z * z), 2 * (y * z - w * x)},
        {2 * (x * z - w * y), 2 * (y * z + w * x), 1 - 2 * (x * x + y * y)},
    }
end

local function q_ease(a, b, t)
    local d = a[1] * b[1] + a[2] * b[2] + a[3] * b[3] + a[4] * b[4]
    local s = d < 0 and -1 or 1
    local q = {}
    local len = 0
    for i = 1, 4 do
        q[i] = a[i] + (b[i] * s - a[i]) * t
        len = len + q[i] * q[i]
    end
    len = math.sqrt(len)
    for i = 1, 4 do
        q[i] = q[i] / len
    end
    return q
end

-- a bone matrix (column-major) of a rotation, a scale and a shift
local function m4(r, k, t)
    t = t or {0, 0, 0}
    return {r[1][1] * k, r[2][1] * k, r[3][1] * k, 0,
            r[1][2] * k, r[2][2] * k, r[3][2] * k, 0,
            r[1][3] * k, r[2][3] * k, r[3][3] * k, 0,
            t[1], t[2], t[3], 1}
end

-- Rotations of the upper arm and the forearm that put the fist on target
-- (as near as the arm reaches), the elbow towards pole; and the fist.
local function reach(shoulder, target, pole)
    local d = v_sub(target, shoulder)
    local dist = math.max(0.05, math.min(UPPER + LOWER - 1e-3, v_len(d)))
    local dh = v_norm(d)
    local fist = v_add(shoulder, v_mul(dh, dist))
    local cos_a = (UPPER * UPPER + dist * dist - LOWER * LOWER) / (2 * UPPER * dist)
    local sin_a = math.sqrt(math.max(0, 1 - cos_a * cos_a))
    local side = v_norm(v_off(pole, dh))
    local u = v_add(v_mul(dh, cos_a), v_mul(side, sin_a))
    local elbow = v_add(shoulder, v_mul(u, UPPER))
    local f = v_norm(v_sub(fist, elbow))
    local w = v_off(f, u)
    if v_len(w) < 1e-4 then
        w = v_off(v_mul(side, -1), u)
    end
    local back = v_mul(v_norm(w), -1)          -- the bone's +z
    local y = v_mul(u, -1)
    local x = v_cross(y, back)
    local bend = math.deg(math.atan2(v_dot(f, v_mul(back, -1)), v_dot(f, u)))
    return m3_cols(x, y, back), m3_euler({bend, 0, 0}), fist
end

this.reach = reach              -- tests
this.euler = m3_euler

-- a rotation whose +z looks along back and +y up as near as it can
local function m3_facing(back, up)
    local z = v_norm(back)
    local y = v_norm(v_off(up, z))
    return m3_cols(v_cross(y, z), y, z)
end

local BOW_IDLE = {
    arm_l = {12, 0, -6}, arm_l_low = {34, 0, 0},
    back = {0.3, 0, 1}, up = {0.1, 1, -0.5},
}

-- A poser for one player entity. state() gives the component's view:
-- {water = "dry"|"wading"|"swimming"|"diving", ladder = bool}
function this.new(entity)
    local rig = entity.skeleton
    local tsf = entity.transform
    local body = entity.rigidbody
    local mob = entity:get_component("core:mob")
    local index = {}
    for _, name in ipairs(BONES) do
        index[name] = rig:index(name)
    end
    local item_bone = rig:index("item")
    local item_l_bone = rig:index("item_l")
    if not index.body or not item_bone or not item_l_bone then
        return nil
    end
    local angles = {torso = {0, 0, 0}}
    local limbs = {}        -- bone -> quaternion now
    local lean = 0
    local phase = 0
    local item_model = nil
    local item_l_model = nil
    local last_pos = nil

    local self = {}

    local function set_item_model(name)
        if name ~= item_model then
            item_model = name
            rig:set_model(item_bone, name)
        end
    end

    -- how fast the body moves over the ground (a seated one: not at all)
    local function ground_speed(delta, seated)
        local pos = tsf:get_pos()
        local speed = 0
        if last_pos and delta > 0 and not seated then
            speed = vec2.length({pos[1] - last_pos[1], pos[3] - last_pos[3]}) / delta
        end
        last_pos = pos
        return math.min(speed, 12)
    end

    local function walk(p, speed)
        local amp = math.min(1, speed / 3.5)
        local s, c = math.sin(phase), math.cos(phase)
        p.leg_l[1] = 34 * amp * s
        p.leg_r[1] = -34 * amp * s
        p.leg_l_low[1] = -32 * amp * math.max(0, -c)
        p.leg_r_low[1] = -32 * amp * math.max(0, c)
        p.arm_l[1] = -28 * amp * s
        p.arm_r[1] = 28 * amp * s
        p.arm_l_low[1] = 6 + 14 * amp
        p.arm_r_low[1] = 6 + 14 * amp
        p.torso[2] = 4 * amp * s
    end

    -- where the head bone goes when the torso leans (it hangs on the body)
    local function head_matrix(pid, lie)
        if lie then
            return mat4.translate({0, -0.02, 0})
        end
        local yaw, pitch = player.get_rot(pid, not hud or pid ~= hud.get_player())
        local view = mat4.mul(mat4.rotate({0, 1, 0}, yaw), mat4.rotate({1, 0, 0}, math.max(-80, math.min(80, pitch))))
        local local_view = mat4.mul(mat4.inverse(tsf:get_rot()), view)
        local t = mat4.rotate({1, 0, 0}, -lean)
        local neck = mat4.mul(t, NECK_IN_TORSO)
        local at = {HIP[1] + neck[1] - NECK[1], HIP[2] + neck[2] - NECK[2], HIP[3] + neck[3] - NECK[3]}
        return mat4.mul(mat4.translate(at), local_view)
    end

    -- the body faces the view, on a horse the way the horse goes
    local function face(pid)
        local horse = riding.horse_of(pid)
        if horse then
            local _, yaw = horse.get_ride()
            local a = math.rad(yaw)
            mob.set_dir({-math.sin(a), 0, -math.cos(a)})
            return
        end
        local yaw = player.get_rot(pid, not hud or pid ~= hud.get_player())
        local dir = vec2.rotate({0, -1}, -yaw)
        mob.set_dir({dir[1], 0, dir[2]})
    end

    function self.update(pid, delta, state)
        if mob then
            face(pid)
        end
        local lying = sleep.is_sleeping(pid)
        local horse = riding.seated_in(pid) ~= nil
        local seated = boat.seated_in(pid) ~= nil
        local speed = ground_speed(delta, horse or seated or lying)
        local flying = player.is_flight(pid)
        local grounded = body:is_grounded()
        local crouch = body:is_crouching() and grounded and not flying
        local invid, slot = player.get_inventory(pid)
        local itemid = inventory.get(invid, slot)
        local p = rest()
        local target_lean = 0

        if lying then
            -- straight, arms along the body
        elseif horse then
            -- astride, the feet in the stirrups, the hands on the reins
            p.leg_l = {34, 0, -44}
            p.leg_r = {34, 0, 44}
            p.leg_l_low = {-58, 0, 38}
            p.leg_r_low = {-58, 0, -38}
            p.arm_l = {34, 0, 4}
            p.arm_r = {34, 0, -4}
            p.arm_l_low = {40, 0, 0}
            p.arm_r_low = {40, 0, 0}
            target_lean = 6
        elseif seated then
            p.leg_l = {84, 0, -6}
            p.leg_r = {84, 0, 6}
            p.leg_l_low = {-84, 0, 0}
            p.leg_r_low = {-84, 0, 0}
            p.arm_l = {20, 0, -6}
            p.arm_r = {20, 0, 6}
            p.arm_l_low = {30, 0, 0}
            p.arm_r_low = {30, 0, 0}
        elseif state.ladder then
            local y = tsf:get_pos()[2] * 3.2
            local s = math.sin(y)
            p.arm_l = {150 + 16 * s, 0, 0}
            p.arm_r = {150 - 16 * s, 0, 0}
            p.arm_l_low = {20, 0, 0}
            p.arm_r_low = {20, 0, 0}
            p.leg_l = {30 + 22 * s, 0, 0}
            p.leg_r = {30 - 22 * s, 0, 0}
            p.leg_l_low = {-50, 0, 0}
            p.leg_r_low = {-50, 0, 0}
        elseif state.water == "swimming" or state.water == "diving" then
            local w = time.uptime() * 5
            local s = math.sin(w)
            p.arm_l = {150 + 25 * s, 0, -30 - 20 * s}
            p.arm_r = {150 + 25 * s, 0, 30 + 20 * s}
            p.arm_l_low = {25, 0, 0}
            p.arm_r_low = {25, 0, 0}
            p.leg_l = {12 * math.sin(w * 1.6), 0, 0}
            p.leg_r = {-12 * math.sin(w * 1.6), 0, 0}
            target_lean = 25
        elseif not grounded and not flying then
            -- in the air: one leg ahead, the arms out for balance
            p.leg_l = {28, 0, 0}
            p.leg_l_low = {-34, 0, 0}
            p.leg_r = {-10, 0, 0}
            p.leg_r_low = {-14, 0, 0}
            p.arm_l = {-18, 0, -22}
            p.arm_r = {18, 0, 22}
        else
            phase = phase + speed * delta * STRIDE
            walk(p, speed)
            if crouch then
                target_lean = 24
                p.leg_l[1] = p.leg_l[1] + 18
                p.leg_r[1] = p.leg_r[1] + 18
                p.leg_l_low[1] = p.leg_l_low[1] - 24
                p.leg_r_low[1] = p.leg_r_low[1] - 24
            end
            if flying then
                p.leg_l_low[1] = -12
                p.leg_r_low[1] = -12
            end
        end

        -- a spear: its own pose of the arms and the item; a bow goes to the
        -- left hand and the right one draws
        local ranged_m, ranged_model, arms, bow, draw = ranged_pose.third_person(pid)
        if lying then
            ranged_m, ranged_model, bow = nil, nil, nil
        end
        local bow_rot = nil
        local solved = {}       -- bone -> rotation set by reach()

        -- the item in the right fist: the arm a bit ahead
        local grip = nil
        if itemid ~= 0 and not lying and not bow then
            p.arm_r[1] = p.arm_r[1] * 0.5 + 14
            p.arm_r_low[1] = math.max(p.arm_r_low[1], 28)
            grip = is_block_model(itemid) and BLOCK_GRIP or GRIP
        end

        if ranged_m then
            for name, a in pairs(arms) do
                p[name] = a
            end
        elseif bow and draw then
            -- side-on: the torso turned, the bow arm out to the grip, the
            -- string to the cheek (the points turned into the torso)
            p.torso[2] = bow.tp_twist
            local unturn = m3_euler({0, -bow.tp_twist, 0})
            local grip_at = m3_apply(unturn, bow.tp_grip)
            local anchor = m3_apply(unturn, bow.tp_anchor)
            local up, low, fist = reach(SHOULDER_L, grip_at, {-1, -1, 0})
            solved.arm_l, solved.arm_l_low = up, low
            local back = v_norm(v_sub(anchor, fist))
            local stage = math.min(#bow.tp_nock, 1 + math.floor(draw * #bow.tp_nock))
            local nock = v_add(fist, v_mul(back, bow.tp_nock[stage] * bow.tp_scale))
            solved.arm_r, solved.arm_r_low = reach(SHOULDER_R, nock, bow.tp_elbow)
            bow_rot = m3_facing(back, {0, 1, 0})
        elseif bow then
            p.arm_l, p.arm_l_low = BOW_IDLE.arm_l, BOW_IDLE.arm_l_low
            bow_rot = m3_facing(BOW_IDLE.back, BOW_IDLE.up)
        end
        local busy = ranged_m or bow

        -- the action of the right arm on top
        local kind, t = this.action(pid)
        if kind == "swing" and not lying and not busy then
            local up = t < 0.3 and smooth(t / 0.3) or 1 - smooth((t - 0.3) / 0.7)
            p.arm_r = {p.arm_r[1] * (1 - up) + 150 * up - (t >= 0.3 and 30 * math.sin((t - 0.3) / 0.7 * math.pi) or 0),
                       0, 10 * up}
            p.arm_r_low = {12 + 20 * up, 0, 0}
            p.torso[2] = p.torso[2] - 14 * math.sin(t * math.pi)
        elseif kind == "use" and not lying and not busy then
            local k = math.sin(t * math.pi)
            p.arm_r = {p.arm_r[1] + 58 * k, 0, -6 * k}
            p.arm_r_low = {p.arm_r_low[1] * (1 - k), 0, 0}
            p.torso[2] = p.torso[2] - 8 * k
        end

        -- ease towards the pose (the actions faster)
        local k = 1 - math.exp(-delta * (kind and 30 or 14))
        local tz = angles.torso
        tz[2] = tz[2] + (p.torso[2] - tz[2]) * k
        for _, name in ipairs(LIMBS) do
            local goal = q_of(solved[name] or m3_euler(p[name]))
            limbs[name] = q_ease(limbs[name] or goal, goal, k)
        end
        lean = lean + (target_lean - lean) * (1 - math.exp(-delta * 10))

        rig:set_matrix(index.body, lying and LIE or mat4.idt())
        rig:set_matrix(index.torso, mat4.mul(rot(0, tz[2], 0), mat4.rotate({1, 0, 0}, -lean)))
        for _, name in ipairs(LIMBS) do
            rig:set_matrix(index[name], m4(q_m3(limbs[name]), 1))
        end
        rig:set_matrix(index.head, head_matrix(pid, lying))

        -- the bow in the left fist, turned as solved in the torso: the
        -- rotation left after the arm's own
        rig:set_visible(item_l_bone, bow_rot ~= nil)
        if bow_rot then
            if ranged_model ~= item_l_model then
                item_l_model = ranged_model
                rig:set_model(item_l_bone, ranged_model)
            end
            local chain = m3_mul(q_m3(limbs.arm_l), q_m3(limbs.arm_l_low))
            rig:set_matrix(item_l_bone, m4(m3_mul(m3_t(chain), bow_rot), bow.tp_scale))
        end

        if lying or itemid == 0 or bow then
            rig:set_visible(item_bone, false)
            return
        end
        rig:set_visible(item_bone, true)
        if ranged_m then
            set_item_model(ranged_model)
            rig:set_matrix(item_bone, ranged_m)
        else
            set_item_model(item.model_name(itemid))
            rig:set_matrix(item_bone, grip_matrix(grip))
        end
    end

    return self
end

return this
