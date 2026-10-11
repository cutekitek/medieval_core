-- Fish: swims between random points of the water around its home (the
-- spawn point), darts away from a player who comes close or hits it, flops
-- about and suffocates out of water. There are no water physics in the
-- engine: in water gravity is off and the velocity is steered by hand.
-- Species data: fauna/species (fish).
local species_list = require "fauna/species"
local base_util = require "base:util"
local flow = require "water/flow"
local fishing = require "fishing/fishing"

local tsf = entity.transform
local body = entity.rigidbody
local rig = entity.skeleton

local species = species_list.fish

health = SAVED_DATA.health or species.health

local LOOK_AHEAD = 0.45
local TURN_RATE = 2.5         -- velocity follows the wish this fast (1/s)
local HOVER_CHANCE = 0.35
local FLEE_TIME = 1.6
local HURT_FLASH = 0.25
local LAND_DAMPING = 2.0
local SENSE_INTERVAL = 0.25
local THINK_STEP = 0.1          -- seconds between AI updates
local SLEEP_STEP = 1.0          -- the same for a fish far from players
local ACTIVE_RADIUS = 48
local DETAIL_RADIUS = 20        -- closer: animated every frame
local RENDER_RADIUS = 64        -- further: not posed at all
local FAR_RENDER_STEP = 0.2

local variant = SAVED_DATA.variant or ARGS.variant or math.random(1, #species.variants)
variant = math.max(1, math.min(#species.variants, variant))
SAVED_DATA.variant = variant
for key, value in pairs(species.variants[variant]) do
    rig:set_texture(key, value)
end

if not SAVED_DATA.home then
    local p = tsf:get_pos()
    SAVED_DATA.home = {p[1], p[2], p[3]}
end

local state = "hover"         -- hover | swim | flee | land
local timer = math.random() * 2
local target = nil
local speed = 0
local air_time = 0
local flop_timer = 0
local sense_timer = 0
local hurt_timer = 0
local in_water = nil        -- nil until the first physics step sets the body up

-- a cell a fish may swim in: still water (not a thin flowing layer)
local function is_open_water(x, y, z)
    return block.get(math.floor(x), math.floor(y), math.floor(z)) == flow.ids().source
end

-- the straight way from a to b stays in water
local function clear_way(a, b)
    local d = vec3.sub(b, a)
    local len = vec3.length(d)
    local steps = math.max(1, math.ceil(len / 0.5))
    for i = 1, steps do
        local p = vec3.add(a, vec3.mul(d, i / steps))
        if not is_open_water(p[1], p[2], p[3]) then
            return false
        end
    end
    return true
end

-- a random reachable point of water around `center`; `away` (optional)
-- keeps only points further from it than the fish is now
local function pick_point(center, radius, away)
    local pos = tsf:get_pos()
    local best, best_d = nil, -1
    for _ = 1, 14 do
        local x = math.floor(center[1] + (math.random() * 2 - 1) * radius)
        local y = math.floor(center[2] + (math.random() * 2 - 1) * radius * 0.5)
        local z = math.floor(center[3] + (math.random() * 2 - 1) * radius)
        local p = {x + 0.5, y + 0.5, z + 0.5}
        if is_open_water(x, y, z) and clear_way(pos, p) then
            if not away then
                return p
            end
            local d = vec3.distance(p, away)
            if d > best_d then
                best, best_d = p, d
            end
        end
    end
    return best
end

local function next_move()
    if math.random() < HOVER_CHANCE then
        state, target = "hover", nil
        timer = 1.5 + math.random() * 3
        return
    end
    local home = SAVED_DATA.home
    local p = pick_point(home, species.roam_radius)
    if not p then
        -- carried off (or the pond changed): make the current place home
        p = pick_point(tsf:get_pos(), 3)
        if p then
            local pos = tsf:get_pos()
            SAVED_DATA.home = {pos[1], pos[2], pos[3]}
        end
    end
    if p then
        local s = species.swim_speed
        state, target = "swim", p
        speed = s[1] + math.random() * (s[2] - s[1])
        timer = 8
    else
        state, target = "hover", nil
        timer = 2
    end
end

local function flee(from)
    local pos = tsf:get_pos()
    local p = pick_point(pos, 5, from)
    if p then
        state, target, speed = "flee", p, species.flee_speed
        timer = FLEE_TIME
    end
end

local function nearest_player(radius)
    local pos = tsf:get_pos()
    local best, best_d = nil, radius
    for _, pid in ipairs(player.get_all()) do
        if not player.is_noclip(pid) then
            local x, y, z = player.get_pos(pid)
            local d = vec3.distance(pos, {x, y + 0.9, z})
            if d < best_d then
                best, best_d = {x, y + 0.9, z}, d
            end
        end
    end
    return best
end

-- the bait -------------------------------------------------------------------
-- A fish may notice a float resting on the water nearby, swim up to it and
-- take the hook; a hooked fish darts about and is pulled towards the angler
-- while the line is drawn in. See modules/fishing/fishing.lua.

local HOOK_DART = {0.5, 1.3}   -- seconds between changes of direction
local HOOK_SPEED = 2.2
local BITE_REACH = 0.55
local LOST_INTEREST = 15       -- seconds before a fish that refused bites again

local bait = nil               -- bobber uid it swims to or hangs on
local bored_until = 0
local hook_timer = 0
local hook_dir = {0, 0, 0}
local slack = 0
local splash_timer = 0

local function bobber_ai(uid)
    local e = uid and entities.get(uid)
    return e and e:get_component("medieval_core:bobber")
end

local function notice_bait(delta)
    if time.uptime() < bored_until then
        return false
    end
    local pos = tsf:get_pos()
    local now = time.uptime()
    for uid, b in pairs(fishing.bobbers) do
        if b.state == "floating" and not b.fish and not b.interest
           and now - b.since > fishing.SETTLE_TIME
           and vec3.distance(pos, b.pos) < fishing.NOTICE_RADIUS
           and math.random() < fishing.NOTICE_CHANCE * delta then
            b.interest = entity:get_uid()
            bait = uid
            state, target = "approach", nil
            speed = 0.8
            timer = 12
            return true
        end
    end
    return false
end

local function lose_interest()
    local b = bait and fishing.bobbers[bait]
    if b and b.interest == entity:get_uid() then
        b.interest = nil
    end
    bait = nil
    bored_until = time.uptime() + LOST_INTEREST
    state, target = "hover", nil
    timer = 1
end

-- returns true while it handles the fish
local function approach(delta)
    local b = bait and fishing.bobbers[bait]
    if not b or b.state ~= "floating" or b.fish or timer <= 0 then
        lose_interest()
        return false
    end
    local pos = tsf:get_pos()
    target = {b.pos[1], b.pos[2] - 0.35, b.pos[3]}
    if vec3.distance(pos, target) < BITE_REACH then
        local ai = bobber_ai(bait)
        if ai and math.random() < fishing.BITE_CHANCE then
            b.interest = nil
            ai.hook(entity:get_uid())
            b.fish = entity:get_uid()
            state, target = "hooked", nil
            hook_timer, slack, splash_timer = 0, 0, 0
            body:set_vel({0, -0.5, 0})
            return true
        end
        lose_interest()
        return false
    end
    return false
end

-- a fish on the line: darts about, pulled in while the line is drawn
local function hooked(delta, pos)
    local b = bait and fishing.bobbers[bait]
    if not b or b.fish ~= entity:get_uid() then
        bait = nil
        state, timer = "hover", 0.5
        return
    end
    local owner = b.owner
    local reeling = fishing.reeling(owner)
    hook_timer = hook_timer - delta
    if hook_timer <= 0 then
        hook_timer = HOOK_DART[1] + math.random() * (HOOK_DART[2] - HOOK_DART[1])
        local a = math.random() * math.pi * 2
        hook_dir = {math.cos(a) * HOOK_SPEED, (math.random() - 0.6) * 0.6, math.sin(a) * HOOK_SPEED}
    end
    splash_timer = splash_timer - delta
    if splash_timer <= 0 then
        splash_timer = 0.9 + math.random() * 1.2
        local s = b.pos
        audio.play_sound("medieval_core/fish_struggle", s[1], s[2], s[3], 0.7,
            0.9 + math.random() * 0.2, "regular")
        fishing.ripple(s[1], s[2], s[3], 1.2)
    end
    local wish = hook_dir
    if reeling then
        slack = 0
        local x, _, z = player.get_pos(owner)
        local d = {x - pos[1], 0, z - pos[3]}
        local len = vec3.length(d)
        if len < fishing.CATCH_DISTANCE then
            b.done = true
            fishing.catch(owner, entity)
            return
        end
        local pull = vec3.mul(d, fishing.FISH_PULL / math.max(len, 1e-3))
        wish = vec3.add(vec3.mul(hook_dir, 0.6), pull)
        -- dragged against the bank: yanked out of the water
        local ahead = vec3.add(pos, vec3.mul(pull, 0.6 / fishing.FISH_PULL))
        if len < 4 and not is_open_water(ahead[1], ahead[2], ahead[3])
           and not is_open_water(ahead[1], ahead[2] + 1, ahead[3]) then
            b.done = true
            fishing.catch(owner, entity)
            return
        end
        if math.random() < fishing.ESCAPE_CHANCE * delta then
            local ai = bobber_ai(bait)
            if ai then ai.unhook() end
            bait = nil
            fishing.escaped = (fishing.escaped or 0) + 1
            flee({x, pos[2], z})
            return
        end
    else
        slack = slack + delta
        if slack > fishing.SLACK_TIME then
            local ai = bobber_ai(bait)
            if ai then ai.unhook() end
            bait = nil
            state, timer = "hover", 0.5
            return
        end
    end
    -- stay in the water
    local wlen = vec3.length(wish)
    if wlen > 1e-3 then
        local ahead = vec3.add(pos, vec3.mul(wish, (LOOK_AHEAD + wlen * THINK_STEP) / wlen))
        if not is_open_water(ahead[1], ahead[2], ahead[3]) then
            hook_timer = 0
            if not reeling then
                wish = {0, 0, 0}
            end
        end
    end
    local vel = body:get_vel()
    local k = math.min(1, delta * TURN_RATE * 2)
    body:set_vel(vec3.add(vel, vec3.mul(vec3.sub(wish, vel), k)))
end

-- the bobber lets go of the fish (rod put away, line cut)
function unhook()
    bait = nil
    if state == "hooked" then
        state, timer = "hover", 0.5
    end
end

-- water ---------------------------------------------------------------------

local function swim(delta)
    local pos = tsf:get_pos()
    if state == "hooked" then
        hooked(delta, pos)
        return
    end
    if state == "approach" and approach(delta) then
        return
    end
    if (state == "hover" or state == "swim") and notice_bait(delta) then
        return
    end
    timer = timer - delta
    sense_timer = sense_timer - delta
    if sense_timer <= 0 then
        sense_timer = SENSE_INTERVAL
        if state ~= "flee" then
            local p = nearest_player(species.shy_radius)
            if p then
                flee(p)
            end
        end
    end
    if timer <= 0 or (target and vec3.distance(pos, target) < 0.4) then
        next_move()
    end

    local wish = {0, 0, 0}
    if target then
        local d = vec3.sub(target, pos)
        local len = vec3.length(d)
        if len > 1e-3 then
            wish = vec3.mul(d, math.min(speed, len * 2) / len)
        end
    else
        -- hovering: a slow drift, sinking or rising a little
        local t = time.uptime() + variant * 3.1
        wish = {math.sin(t * 0.7) * 0.08, math.sin(t * 0.43) * 0.05, math.cos(t * 0.6) * 0.08}
    end
    -- never swim out: the way ahead must be water
    local wlen = vec3.length(wish)
    if wlen > 1e-3 then
        -- far enough to cover the way until the next think step
        local reach = LOOK_AHEAD + wlen * THINK_STEP * 1.5
        local ahead = vec3.add(pos, vec3.mul(wish, reach / wlen))
        if not is_open_water(ahead[1], ahead[2], ahead[3]) then
            wish = {0, 0, 0}
            if state ~= "hover" then
                next_move()
            end
        end
    end
    local vel = body:get_vel()
    local k = math.min(1, delta * (state == "flee" and TURN_RATE * 3 or TURN_RATE))
    body:set_vel(vec3.add(vel, vec3.mul(vec3.sub(wish, vel), k)))
end

-- land ----------------------------------------------------------------------

-- the closest water cell within a few blocks, to flop towards
local function water_nearby(pos)
    for r = 1, 3 do
        for i = 0, 7 do
            local a = i / 8 * math.pi * 2
            local x, z = pos[1] + math.cos(a) * r, pos[3] + math.sin(a) * r
            for dy = 0, -2, -1 do
                if flow.is_water(block.get(math.floor(x), math.floor(pos[2]) + dy, math.floor(z))) then
                    return {x, pos[2], z}
                end
            end
        end
    end
    return nil
end

local function flop(delta)
    air_time = air_time + delta
    if air_time >= species.suffocate_every then
        air_time = air_time - species.suffocate_every
        damage(1)
        if health <= 0 then
            return
        end
    end
    flop_timer = flop_timer - delta
    if flop_timer <= 0 and body:is_grounded() then
        flop_timer = 0.5 + math.random() * 0.7
        local pos = tsf:get_pos()
        local w = water_nearby(pos)
        local dir
        if w and math.random() < 0.7 then
            dir = vec3.normalize(vec3.sub(w, pos))
        else
            local a = math.random() * math.pi * 2
            dir = {math.cos(a), 0, math.sin(a)}
        end
        body:set_vel({dir[1] * 1.8, 3.2 + math.random(), dir[3] * 1.8})
    end
end

-- distance to the closest player (any mode: spectators see fish too)
local function player_distance(pos)
    local best = math.huge
    for _, pid in ipairs(player.get_all()) do
        local x, y, z = player.get_pos(pid)
        local dx, dy, dz = x - pos[1], y - pos[2], z - pos[3]
        local d = dx * dx + dy * dy + dz * dz
        if d < best then
            best = d
        end
    end
    return math.sqrt(best)
end

-- The AI runs THINK_STEP apart, not every frame: the velocity it sets holds
-- in between (no gravity, no damping in water). Far from every player the
-- fish stops and only checks now and then whether someone came closer.
local think_acc = math.random() * THINK_STEP
local think_step = THINK_STEP
local near_distance = 0       -- read by on_render for the level of detail

function on_physics_update(delta)
    think_acc = think_acc + delta
    if think_acc < think_step then
        return
    end
    delta = math.min(think_acc, 1.0)
    think_acc = 0
    local pos = tsf:get_pos()
    near_distance = player_distance(pos)
    if near_distance > ACTIVE_RADIUS and in_water then
        if think_step ~= SLEEP_STEP then
            think_step = SLEEP_STEP
            body:set_vel({0, 0, 0})
        end
        return
    end
    think_step = THINK_STEP
    local wet = flow.in_water(pos[1], pos[2], pos[3])
    if wet ~= in_water then
        in_water = wet
        if wet then
            body:set_gravity_scale(0.0)
            body:set_linear_damping(0.0)
            body:set_vdamping(true)
            air_time = 0
            state = "hover"
            timer = 0.5
        else
            body:set_gravity_scale(1.0)
            body:set_linear_damping(LAND_DAMPING)
            body:set_vdamping(false)
            state = "land"
            flop_timer = 0.3
        end
    end
    if wet then
        swim(delta)
    else
        flop(delta)
    end
end

-- damage -------------------------------------------------------------------

local function die()
    local pos = tsf:get_pos()
    for _, drop in ipairs(base_util.calc_loot(species.loot)) do
        local e = base_util.drop(pos, drop.item, drop.count)
        if e then
            e.rigidbody:set_vel(vec3.spherical_rand(1.5))
        end
    end
    entity:despawn()
end

function damage(amount, from, pid, knockback)
    health = health - amount
    SAVED_DATA.health = health
    hurt_timer = HURT_FLASH
    if health <= 0 then
        die()
        return
    end
    if from then
        local pos = tsf:get_pos()
        local away = vec3.sub(pos, from)
        if vec3.length(away) > 1e-3 then
            body:set_vel(vec3.mul(vec3.normalize(away), 3 * (knockback or 1)))
        end
        if in_water then
            flee(from)
        end
    end
end

function on_attacked(attacker, pid)
    local from = nil
    if entities.exists(attacker) then
        from = entities.get(attacker).transform:get_pos()
    end
    local amount, knockback = 1, 1
    if pid ~= -1 then
        local invid, slot = player.get_inventory(pid)
        local itemid = inventory.get(invid, slot)
        local props = itemid ~= 0 and item.properties and item.properties[itemid]
        if props and props["medieval_core:damage"] then
            amount = props["medieval_core:damage"]
            knockback = props["medieval_core:knockback"] or 1
            if not player.is_infinite_items(pid) then
                inventory.use(invid, slot)
            end
        end
    end
    damage(amount, from, pid, knockback)
end

function get_state()
    return state
end

function get_variant()
    return variant
end

function get_home()
    return SAVED_DATA.home
end

-- rendering ------------------------------------------------------------------

local swim_track = nil
local phase = math.random()
local yaw, pitch, roll = math.random() * 360, 0, 0

local function approach_angle(a, b, k)
    local d = (b - a + 540) % 360 - 180
    return a + d * math.min(1, k)
end

-- level of detail: every frame close by, a few times a second further away
-- (turning only, the tail keeps its pose), nothing beyond RENDER_RADIUS
local render_acc = 0

function on_render(delta)
    if near_distance > RENDER_RADIUS then
        return
    end
    local detailed = near_distance <= DETAIL_RADIUS
    if not detailed then
        render_acc = render_acc + delta
        if render_acc < FAR_RENDER_STEP then
            return
        end
        delta = render_acc
    end
    render_acc = 0
    local vel = body:get_vel()
    local hspeed = vec2.length({vel[1], vel[3]})
    local spd = vec3.length(vel)
    if in_water then
        if spd > 0.05 then
            yaw = approach_angle(yaw, math.deg(math.atan2(-vel[1], -vel[3])), delta * 6)
            local goal = math.deg(math.atan2(vel[2], math.max(hspeed, 0.05)))
            pitch = pitch + (math.max(-35, math.min(35, goal)) - pitch) * math.min(1, delta * 4)
        else
            pitch = pitch * (1 - math.min(1, delta * 2))
        end
        roll = roll * (1 - math.min(1, delta * 5))
        phase = phase + delta * (0.8 + spd * 2.2)
    else
        -- lying on its side, beating the tail
        roll = roll + (80 - roll) * math.min(1, delta * 8)
        pitch = pitch * (1 - math.min(1, delta * 4))
        phase = phase + delta * 3.5
    end
    local m = mat4.rotate({0, 1, 0}, yaw)
    m = mat4.mul(m, mat4.rotate({1, 0, 0}, pitch))
    m = mat4.mul(m, mat4.rotate({0, 0, 1}, roll))
    tsf:set_rot(m)

    if not detailed then
        return
    end
    rig:reset_pose()
    if swim_track == nil then
        swim_track = animation.get_track("mw_fish_swim") or false
    end
    if swim_track then
        swim_track.func(rig, phase, 1.0)
    end
    if hurt_timer > 0 then
        hurt_timer = hurt_timer - delta
        rig:set_color(hurt_timer > 0 and {1, 0.45, 0.45} or {1, 1, 1})
    end
end
