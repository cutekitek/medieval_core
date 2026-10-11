-- The float of a fishing rod and the line to the rod tip. Flies when cast,
-- rests on the water (rings spread when it lands), is pulled back while
-- its owner holds the use button, follows a hooked fish. Gone when the rod
-- leaves the hand, the line gets too long or the float is pulled in.
-- Not kept over a reload (no owner then). Logic: modules/fishing/fishing.lua
local fishing = require "fishing/fishing"
local flow = require "water/flow"

local tsf = entity.transform
local body = entity.rigidbody
local rig = entity.skeleton

local SEGMENTS = 6
local BOX_THICKNESS = 0.01    -- of a line segment in the model
local FLOAT_TOP = 0.11        -- the line is tied here

local owner = ARGS and ARGS.owner
local uid = entity:get_uid()
local state = "flying"        -- flying | floating | ground | hooked
local info = {pos = tsf:get_pos(), state = state, owner = owner, since = 0}
fishing.bobbers[uid] = info
local dip = 0
local pull_timer = 0

local function gone(release_fish)
    fishing.bobbers[uid] = nil
    if release_fish and info.fish then
        local f = entities.get(info.fish)
        local ai = f and f:get_component("medieval_core:fish")
        if ai then
            ai.unhook()
        end
    end
    if owner then
        fishing.retrieved(owner)
    end
    entity:despawn()
end

local function surface_at(pos)
    local x, z = math.floor(pos[1]), math.floor(pos[3])
    local y0 = math.floor(pos[2])
    for y = y0 + 1, y0 - 1, -1 do
        local h = flow.surface(x, y, z)
        if h then
            return y + h
        end
    end
    return nil
end

local function set_state(s)
    state = s
    info.state = s
    info.since = time.uptime()
end

local function towards_player(pos, speed)
    local x, _, z = player.get_pos(owner)
    local d = {x - pos[1], 0, z - pos[3]}
    local len = vec3.length(d)
    if len < 1e-3 then
        return {0, 0, 0}, len
    end
    return vec3.mul(d, speed / len), len
end

function on_physics_update(delta)
    if not owner or not player.get_entity(owner) or player.get_entity(owner) == 0 then
        gone(true)
        return
    end
    if info.done then
        gone(false)
        return
    end
    if not fishing.holds_rod(owner) then
        gone(true)
        return
    end
    local pos = tsf:get_pos()
    local px, py, pz = player.get_pos(owner)
    if vec3.distance(pos, {px, py, pz}) > fishing.MAX_LINE then
        gone(true)
        return
    end
    info.pos = pos
    local surface = surface_at(pos)
    local reeling = fishing.reeling(owner)
    if reeling and state ~= "flying" then
        pull_timer = pull_timer - delta
        if pull_timer <= 0 then
            pull_timer = 1.3
            local ex, ey, ez = player.get_pos(owner)
            audio.play_sound("medieval_core/line_pull", ex, ey + 0.7, ez, 0.5,
                0.9 + math.random() * 0.2, "regular")
        end
    else
        pull_timer = 0
    end

    if state == "flying" then
        if surface and pos[2] < surface + 0.05 then
            set_state("floating")
            body:set_gravity_scale(0)
            body:set_vel({0, 0, 0})
            audio.play_sound("medieval_core/bobber_plop", pos[1], surface, pos[3], 0.8,
                0.9 + math.random() * 0.2, "regular")
            fishing.ripple(pos[1], surface, pos[3], 1.8)
            fishing.ripple(pos[1], surface, pos[3], 1.0)
        elseif body:is_grounded() then
            set_state("ground")
        end
        return
    end

    if state == "hooked" then
        local f = info.fish and entities.get(info.fish)
        if not f then
            info.fish = nil
            set_state(surface and "floating" or "ground")
            return
        end
        local fp = f.transform:get_pos()
        local s = surface_at(fp) or fp[2] + 0.3
        dip = math.max(0.03, math.min(0.12, dip + (math.random() - 0.5) * 0.08))
        local target = {fp[1], s - dip, fp[3]}
        body:set_vel(vec3.mul(vec3.sub(target, pos), 12))
        return
    end

    if surface then
        if state == "ground" then
            set_state("floating")
            body:set_gravity_scale(0)
        end
        local vel = {0, (surface - pos[2]) * 6, 0}
        if reeling then
            local h, len = towards_player(pos, fishing.REEL_SPEED)
            if len < fishing.CATCH_DISTANCE then
                gone(false)
                return
            end
            vel[1], vel[3] = h[1], h[3]
            info.since = time.uptime()   -- a moving float scares fish off
        end
        body:set_vel(vel)
    else
        if state == "floating" then
            set_state("ground")
            body:set_gravity_scale(1)
        end
        if reeling then
            local h, len = towards_player(pos, fishing.REEL_SPEED)
            if len < fishing.CATCH_DISTANCE then
                gone(false)
                return
            end
            local vel = body:get_vel()
            body:set_vel({h[1], body:is_grounded() and 1.5 or vel[2], h[3]})
        end
    end
end

-- the fish component hooks and frees fish through these
function hook(fish_uid)
    info.fish = fish_uid
    set_state("hooked")
    body:set_gravity_scale(0)
end

function unhook()
    info.fish = nil
    set_state("floating")
end

function get_state()
    return state
end

-- the line -------------------------------------------------------------------

local bones = nil

local function segment_matrix(a, b, origin, thickness)
    local d = vec3.sub(b, a)
    local len = vec3.length(d)
    if len < 1e-4 then
        return mat4.scale({0, 0, 0})
    end
    local yaw = math.deg(math.atan2(d[1], d[3]))
    local pitch = -math.deg(math.atan2(d[2], math.sqrt(d[1] * d[1] + d[3] * d[3])))
    local k = thickness / BOX_THICKNESS
    local m = mat4.translate(vec3.sub(a, origin))
    m = mat4.mul(m, mat4.rotate({0, 1, 0}, yaw))
    m = mat4.mul(m, mat4.rotate({1, 0, 0}, pitch))
    return mat4.mul(m, mat4.scale({k, k, len}))
end

function on_render(delta)
    if not owner then
        return
    end
    if not bones then
        bones = {}
        for i = 0, SEGMENTS - 1 do
            bones[i + 1] = rig:index("line" .. i)
        end
    end
    local pos = tsf:get_pos()
    local tip = fishing.rod_tip(owner)
    local tie = {pos[1], pos[2] + FLOAT_TOP, pos[3]}
    local len = vec3.distance(tip, tie)
    -- a slack line sags, a pulled one is nearly straight
    local tight = fishing.reeling(owner) or state == "hooked"
    local sag = math.min(1.2, len * (tight and 0.02 or (state == "flying" and 0.01 or 0.07)))
    local eye = hud and fishing.eye(hud.get_player()) or tip
    local prev = tip
    for i = 1, SEGMENTS do
        local t = (i / SEGMENTS) ^ 2
        local p = {
            tip[1] + (tie[1] - tip[1]) * t,
            tip[2] + (tie[2] - tip[2]) * t - sag * 4 * t * (1 - t),
            tip[3] + (tie[3] - tip[3]) * t,
        }
        -- about the same width on screen near and far
        local th = math.max(0.0004, math.min(0.012, vec3.distance(eye, prev) * 0.0028))
        rig:set_matrix(bones[i], segment_matrix(prev, p, pos, th))
        prev = p
    end
end
