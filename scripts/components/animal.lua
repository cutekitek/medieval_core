-- Wild animal: wanders, grazes, follows a player holding its favourite
-- food, runs from danger, fights (bears), flies (birds), drops loot on death.
-- Species data and tempers: fauna/species.
local species_list = require "fauna/species"
local base_util = require "base:util"
local stats = require "survival/stats"
local mode = require "survival/mode"
local flow = require "water/flow"

local tsf = entity.transform
local body = entity.rigidbody
local rig = entity.skeleton
local mob = entity:require_component("core:mob")
local pf = entity:require_component("core:pathfinding")

local species_name = SAVED_DATA.species or ARGS.species or "cow"
SAVED_DATA.species = species_name
local species = species_list[species_name]

health = SAVED_DATA.health or species.health
local lure_item = species.lure_item and item.index(species.lure_item) or 0
local water = block.index("base:water")

local FOLLOW_RADIUS = 10
local REACHED = 1.2
local FLEE_TIME = 4.0
local HURT_FLASH = 0.25
local ATTACK_ANIM = 0.5
local CHASE_REPATH = 0.5
local AIR_DAMPING = 10.0      -- core:mob default
local FLIGHT_DAMPING = 1.0
local MAX_FLIGHT_TIME = 45.0

-- coat / plumage variant
if species.variants then
    local index = SAVED_DATA.variant or ARGS.variant or math.random(1, #species.variants)
    index = math.max(1, math.min(#species.variants, index))
    SAVED_DATA.variant = index
    for key, value in pairs(species.variants[index]) do
        rig:set_texture(key, value)
    end
end

-- behaviour state
local state = "idle"
local state_timer = math.random() * 4
local target = nil
local prey = nil              -- player being chased
local chase_time = 0
local attack_timer = 0
local attack_anim = 0
local flight = nil            -- flight plan while flying
if species.flight then
    -- a bird saved in the air must not keep the flight damping
    mob.set_air_damping(AIR_DAMPING)
end

local function floor3(p)
    return {math.floor(p[1]), math.floor(p[2]), math.floor(p[3])}
end

local function set_state(name, duration, new_target)
    state = name
    state_timer = duration
    target = new_target
    pf.reset_route()
    pf.set_target(target)
    -- a chase re-plans the route often (the default is every 100 updates)
    pf.set_refresh_interval(name == "chase" and 10 or 100)
    local speed = species.walk_speed
    if name == "flee" then
        speed = species.flee_speed
    elseif name == "chase" then
        speed = species.chase_speed or species.flee_speed
    end
    mob.set_movement_speed(speed)
end

-- standing cell (air above solid ground) near height y
local function ground_at(x, y, z, up, down)
    for dy = up or 3, -(down or 4), -1 do
        local id = block.get(x, y + dy, z)
        if id > 0 and block.is_solid_at(x, y + dy, z) and block.get(x, y + dy + 1, z) == 0 then
            return {x, y + dy + 1, z}
        end
    end
    return nil
end

local function pick_wander_target()
    local pos = tsf:get_pos()
    local r = species.wander_radius
    local x = math.floor(pos[1] + (math.random() * 2 - 1) * r)
    local z = math.floor(pos[3] + (math.random() * 2 - 1) * r)
    return ground_at(x, math.floor(pos[2]), z)
end

local function holds_lure(pid)
    if lure_item == 0 then
        return false
    end
    local invid, slot = player.get_inventory(pid)
    return inventory.get(invid, slot) == lure_item
end

-- players are iterated by hand: player.get_all_in_radius compares squared
-- distance with the radius (engine bug)
local function nearest_player(radius, filter)
    local pos = tsf:get_pos()
    local best, best_dist, best_pos = nil, radius, nil
    for _, pid in ipairs(player.get_all()) do
        local x, y, z = player.get_pos(pid)
        local d = vec3.distance(pos, {x, y, z})
        if d <= best_dist and (not filter or filter(pid)) then
            best, best_dist, best_pos = pid, d, {x, y, z}
        end
    end
    return best, best_dist, best_pos
end

-- can this player be attacked at all
local function valid_prey(pid)
    return mode.enabled() and not player.is_noclip(pid) and not player.is_flight(pid)
end

local function is_night()
    local t = world.get_day_time()
    return t < 0.22 or t > 0.78
end

-- birds are active by day, owls at night
local function active_time()
    if species.nocturnal then
        return is_night()
    end
    return not is_night()
end

local function shy_radius()
    if species.flight and species.nocturnal and not is_night() then
        return 2          -- dozing owl
    end
    return species.shy_radius
end

-- ground movement ---------------------------------------------------------

local function flee_from(from, duration)
    local pos = tsf:get_pos()
    local away = vec3.sub(pos, from)
    away[2] = 0
    if vec3.length(away) < 1e-3 then
        away = {math.random() - 0.5, 0, math.random() - 0.5}
    end
    vec3.normalize(away, away)
    local dest = vec3.add(pos, vec3.mul(away, 10))
    local cell = ground_at(math.floor(dest[1]), math.floor(pos[2]), math.floor(dest[3]), 5, 6)
    set_state("flee", duration or FLEE_TIME, cell or floor3(dest))
end

local function start_chase(pid)
    prey = pid
    chase_time = 0
    local x, y, z = player.get_pos(pid)
    set_state("chase", CHASE_REPATH, floor3({x, y, z}))
end

local function calm_down()
    prey = nil
    set_state("idle", 2 + math.random() * 3)
end

-- flight --------------------------------------------------------------------

-- top block of a column: y, id (nil if the chunk is not loaded)
local function column_top(x, z, from_y)
    for y = from_y + 24, from_y - 48, -1 do
        local id = block.get(x, y, z)
        if id == -1 then
            return nil
        end
        if id == water or (id > 0 and block.is_solid_at(x, y, z)) then
            return y, id
        end
    end
    return nil
end

local function is_leaves(id)
    return block.name(id):find("leaves") ~= nil
end

local function next_waypoint(away)
    local pos = tsf:get_pos()
    local angle = math.random() * math.pi * 2
    local dir = {math.cos(angle), 0, math.sin(angle)}
    if away then
        local a = vec3.sub(pos, away)
        a[2] = 0
        if vec3.length(a) > 1e-3 then
            vec3.normalize(a, a)
            dir = vec3.normalize(vec3.add(vec3.mul(a, 2), dir))
        end
    end
    local dist = 8 + math.random() * 10
    local x = pos[1] + dir[1] * dist
    local z = pos[3] + dir[3] * dist
    local top = column_top(math.floor(x), math.floor(z), math.floor(pos[2])) or math.floor(pos[2]) - 4
    local alt = species.flight.altitude
    flight.wp = {x, top + 1 + alt[1] + math.random() * (alt[2] - alt[1]), z}
end

-- picks a landing spot nearby: a tree crown for perching birds if there is
-- one, otherwise any dry ground
local function choose_landing()
    local pos = tsf:get_pos()
    local fallback = nil
    for _ = 1, 32 do
        local x = math.floor(pos[1] + (math.random() * 2 - 1) * 12)
        local z = math.floor(pos[3] + (math.random() * 2 - 1) * 12)
        local y, id = column_top(x, z, math.floor(pos[2]))
        if y and id ~= water and block.get(x, y + 1, z) == 0 then
            local spot = {x + 0.5, y + 1, z + 0.5}
            if species.flight.perch ~= "leaves" or is_leaves(id) then
                if species.flight.perch == "leaves" or not is_leaves(id) then
                    flight.landing = spot
                    return true
                end
            end
            fallback = fallback or spot
        end
    end
    flight.landing = fallback
    return fallback ~= nil
end

local function take_off(away)
    target = nil
    prey = nil
    pf.reset_route()
    pf.set_target(nil)
    state = "fly"
    local w = species.flight.waypoints
    flight = {left = math.random(w[1], w[2]), time = 0, landing = nil}
    mob.set_flight(true)
    mob.set_air_damping(FLIGHT_DAMPING)
    next_waypoint(away)
    local vel = body:get_vel()
    body:set_vel({vel[1], math.max(vel[2], 4), vel[3]})
end

local function land()
    flight = nil
    mob.set_flight(false)
    mob.set_air_damping(AIR_DAMPING)
    local rest = species.flight.rest
    set_state("idle", rest[1] + math.random() * (rest[2] - rest[1]))
end

local function fly_think(dt)
    flight.time = flight.time + dt
    if flight.time > MAX_FLIGHT_TIME then
        land()
        return
    end
    local pos = tsf:get_pos()
    if flight.landing then
        return
    end
    if vec3.distance(pos, flight.wp) < 2.0 then
        flight.left = flight.left - 1
        if flight.left > 0 or not choose_landing() then
            next_waypoint()
        end
    end
end

local function fly_steer(delta)
    local pos = tsf:get_pos()
    local goal = flight.wp
    local speed = species.flight.speed
    if flight.landing then
        local l = flight.landing
        local hd = vec2.length({l[1] - pos[1], l[3] - pos[3]})
        -- come in from above, then drop onto the spot
        goal = {l[1], l[2] + math.min(6, hd * 0.6) + body:get_size()[2] * 0.5, l[3]}
        speed = speed * math.max(0.35, math.min(1, hd / 6))
        if hd < 0.6 and pos[2] - l[2] < 2.5 then
            land()
            return
        end
    end
    local d = vec3.sub(goal, pos)
    local dist = vec3.length(d)
    if dist < 1e-3 then
        return
    end
    local desired = vec3.mul(d, speed / dist)
    local hlen = vec2.length({desired[1], desired[3]})
    if hlen > 1e-3 then
        -- climb over trees and hills in the way
        local ax = pos[1] + desired[1] / hlen * 1.5
        local az = pos[3] + desired[3] / hlen * 1.5
        if block.is_solid_at(math.floor(ax), math.floor(pos[2]), math.floor(az)) or
           block.is_solid_at(math.floor(ax), math.floor(pos[2]) - 1, math.floor(az)) then
            desired[2] = math.max(desired[2], speed * 0.8)
            desired[1], desired[3] = desired[1] * 0.4, desired[3] * 0.4
        end
        mob.set_dir({desired[1] / hlen, 0, desired[3] / hlen})
    end
    local vel = body:get_vel()
    local k = math.min(1, delta * 4)
    body:set_vel(vec3.add(vel, vec3.mul(vec3.sub(desired, vel), k)))
end

-- thinking ------------------------------------------------------------------

local function chase_think(dt)
    chase_time = chase_time + dt
    if not prey or not valid_prey(prey) then
        calm_down()
        return
    end
    local ppos = {player.get_pos(prey)}
    local dist = vec3.distance(ppos, tsf:get_pos())
    if dist > (species.lose_radius or 16) or
       (species.temper == "neutral" and chase_time > 30) then
        calm_down()
        return
    end
    if state_timer <= 0 then
        -- keep the current route while the next one is being planned
        state_timer = CHASE_REPATH
        target = floor3(ppos)
        pf.set_target(target)
    end
    local atk = species.attack
    local pos = tsf:get_pos()
    local hdist = vec2.length({ppos[1] - pos[1], ppos[3] - pos[3]})
    local reach = body:get_size()[1] * 0.5 + 0.3 + atk.reach
    if attack_timer <= 0 and hdist <= reach and math.abs(ppos[2] - pos[2]) < 2.0 then
        attack_timer = atk.cooldown
        attack_anim = ATTACK_ANIM
        stats.damage(prey, atk.damage)
        local pentity = entities.get(player.get_entity(prey))
        if pentity then
            local away = {ppos[1] - pos[1], 0, ppos[3] - pos[3]}
            if vec3.length(away) > 1e-3 then
                vec3.normalize(away, away)
                pentity.rigidbody:set_vel(vec3.add(vec3.mul(away, atk.knockback), {0, 5, 0}))
            end
        end
    end
end

local function think(dt)
    state_timer = state_timer - dt
    attack_timer = attack_timer - dt

    if state == "fly" then
        fly_think(dt)
        return
    end
    if state == "chase" then
        chase_think(dt)
        return
    end

    local temper = species.temper
    if (temper == "hostile" or temper == "neutral") and state ~= "flee" then
        local pid = nearest_player(species.aggro_radius, valid_prey)
        if pid then
            start_chase(pid)
            return
        end
    end
    if temper == "shy" and state ~= "flee" then
        local radius = shy_radius()
        local pid, _, ppos = nearest_player(radius, function (p)
            return not holds_lure(p) and not player.is_noclip(p)
        end)
        if pid then
            if species.flight then
                take_off(ppos)
            else
                flee_from(ppos, 3)
            end
            return
        end
    end

    local holder = state ~= "flee" and nearest_player(FOLLOW_RADIUS, holds_lure)
    if holder then
        local ppos = {player.get_pos(holder)}
        if vec3.distance(ppos, tsf:get_pos()) > 2.0 then
            if state ~= "follow" or state_timer <= 0 then
                set_state("follow", 1.0, floor3(ppos))
            end
        elseif state ~= "idle" then
            set_state("idle", 2.0)
        end
        return
    end

    if target and vec3.distance(target, tsf:get_pos()) < REACHED then
        set_state("idle", 3 + math.random() * 6)
        return
    end
    if state_timer > 0 then
        return
    end
    if species.flight and state == "idle" and active_time() and math.random() < 0.6 then
        take_off()
        return
    end
    if state == "idle" then
        local below = block.get(math.floor(tsf:get_pos()[1]), math.floor(tsf:get_pos()[2]) - 1,
                                math.floor(tsf:get_pos()[3]))
        -- a bird on a tree crown stays put
        local dest = not (species.flight and below > 0 and is_leaves(below)) and pick_wander_target()
        if dest then
            set_state("wander", 10, dest)
        else
            set_state("idle", 2 + math.random() * 3)
        end
    else
        set_state("idle", 3 + math.random() * 6)
    end
end

local function lay_egg(dt)
    if not species.lay_interval then
        return
    end
    local lo, hi = species.lay_interval[1], species.lay_interval[2]
    SAVED_DATA.egg_timer = (SAVED_DATA.egg_timer or (lo + math.random() * (hi - lo))) - dt
    if SAVED_DATA.egg_timer <= 0 then
        SAVED_DATA.egg_timer = lo + math.random() * (hi - lo)
        base_util.drop(tsf:get_pos(), item.index(species.lay_item), 1)
    end
end

function on_update(tps)
    local dt = 1 / tps
    think(dt)
    lay_egg(dt)
end

-- Steers along the pathfinding route (safe for zero-length steps)
local function follow_route()
    local route = pf.get_route()
    if not route or #route == 0 then
        return
    end
    local pos = tsf:get_pos()
    local waypoint = route[#route]
    local dx = waypoint[1] + 0.5 - pos[1]
    local dz = waypoint[3] + 0.5 - pos[3]
    if dx * dx + dz * dz < 0.25 then
        table.remove(route, #route)
        return
    end
    local len = math.sqrt(dx * dx + dz * dz)
    mob.set_dir({dx / len, 0, dz / len})
    mob.go({dx / len, dz / len}, 1.0, false, false)
    if body:is_grounded() then
        if waypoint[2] > math.floor(pos[2]) then
            mob.jump()
        elseif species.hop then
            mob.jump(0.55)
        end
    end
end

-- the last metres of a chase go straight at the player
local function charge()
    local pos = tsf:get_pos()
    local x, _, z = player.get_pos(prey)
    local dx, dz = x - pos[1], z - pos[3]
    local len = math.sqrt(dx * dx + dz * dz)
    if len < 2.5 and len > 0.05 then
        mob.set_dir({dx / len, 0, dz / len})
        mob.go({dx / len, dz / len}, 1.0, false, false)
        return true
    end
    return false
end

-- swimming --------------------------------------------------------------------

local SHORE_SEARCH = 10
local shore = nil
local shore_timer = 0
local afloat = false

-- nearest dry standing cell around the water surface
local function find_shore()
    local pos = tsf:get_pos()
    local y = math.floor(pos[2])
    for r = 1, SHORE_SEARCH do
        for i = 0, 15 do
            local a = i / 16 * math.pi * 2
            local x = math.floor(pos[1] + math.cos(a) * r)
            local z = math.floor(pos[3] + math.sin(a) * r)
            for dy = 1, -2, -1 do
                local id = block.get(x, y + dy, z)
                if id > 0 and not flow.is_water(id) and block.is_solid_at(x, y + dy, z) and
                   block.get(x, y + dy + 1, z) == 0 then
                    return {x + 0.5, y + dy + 1, z + 0.5}
                end
            end
        end
    end
    return nil
end

-- floats with the back at the surface and paddles to the nearest shore;
-- returns true while swimming
local scramble = 0

local function swim(delta)
    local pos = tsf:get_pos()
    if scramble > 0 then
        -- mid-jump onto the bank: plain physics, keep pushing forward
        scramble = scramble - delta
        if shore then
            local dx, dz = shore[1] - pos[1], shore[3] - pos[3]
            local len = math.sqrt(dx * dx + dz * dz)
            if len > 0.1 then
                mob.go({dx / len, dz / len}, 1.0, false, false)
            end
        end
        return true
    end
    if not flow.in_water(pos[1], pos[2], pos[3]) then
        if afloat then
            afloat = false
            body:set_gravity_scale(1.0)
        end
        return false
    end
    afloat = true
    body:set_gravity_scale(0.0)
    body:set_vdamping(true)
    -- rise fast when deep, gently near the surface
    local vel = body:get_vel()
    local deep = flow.in_water(pos[1], pos[2] + 0.5, pos[3])
    vel[2] = deep and 2.5 or 1.0
    body:set_vel(vel)
    shore_timer = shore_timer - delta
    if shore_timer <= 0 then
        shore_timer = 2.0
        shore = find_shore()
    end
    if shore then
        local dx, dz = shore[1] - pos[1], shore[3] - pos[3]
        local len = math.sqrt(dx * dx + dz * dz)
        if len > 0.1 then
            mob.set_dir({dx / len, 0, dz / len})
            mob.go({dx / len, dz / len}, 0.6, false, false)
            -- scramble onto the bank
            if len < body:get_size()[1] * 0.5 + 0.8 and shore[2] > pos[2] - body:get_size()[2] * 0.5 then
                body:set_gravity_scale(1.0)
                body:set_vel({vel[1], 7.0, vel[3]})
                scramble = 0.5
            end
        end
    end
    return true
end

function on_physics_update(delta)
    if state ~= "fly" and swim(delta) then
        return
    end
    if state == "fly" and flight then
        fly_steer(delta)
    elseif state == "chase" and prey and charge() then
        return
    elseif target then
        follow_route()
    end
end

-- damage -------------------------------------------------------------------

local hurt_timer = 0

local function die()
    local pos = tsf:get_pos()
    for _, drop in ipairs(base_util.calc_loot(species.loot)) do
        local e = base_util.drop(pos, drop.item, drop.count)
        if e then
            e.rigidbody:set_vel(vec3.spherical_rand(2.0))
        end
    end
    entity:despawn()
end

function damage(amount, from, pid)
    health = health - amount
    SAVED_DATA.health = health
    hurt_timer = HURT_FLASH
    if health <= 0 then
        die()
        return
    end
    local pos = tsf:get_pos()
    local away = {0, 0, 1}
    if from then
        away = vec3.sub(pos, from)
        away[2] = 0
        if vec3.length(away) < 1e-3 then
            away = {1, 0, 0}
        end
        vec3.normalize(away, away)
    end
    if species.flight then
        if state ~= "fly" then
            take_off(from)
        end
        return
    end
    local push = species.attack and 2 or 6
    body:set_vel(vec3.add(vec3.mul(away, push), {0, push * 0.8, 0}))
    local fights = species.temper == "hostile" or species.temper == "neutral"
    if fights and pid and pid ~= -1 and valid_prey(pid) and health > species.health * 0.25 then
        start_chase(pid)
        return
    end
    -- badly wounded predators retreat as well
    local dest = vec3.add(pos, vec3.mul(away, 10))
    prey = nil
    set_state("flee", FLEE_TIME * (fights and 2 or 1), floor3(dest))
end

function on_attacked(attacker, pid)
    local from = nil
    if entities.exists(attacker) then
        from = entities.get(attacker).transform:get_pos()
    end
    local amount = 1
    if pid ~= -1 then
        local invid, slot = player.get_inventory(pid)
        local itemid = inventory.get(invid, slot)
        local props = itemid ~= 0 and item.properties and item.properties[itemid]
        amount = props and props["millwright:damage"] or 1
    end
    damage(amount, from, pid)
end

function on_save()
    SAVED_DATA.health = health
end

-- read-only views for tests and debugging
function get_state()
    return state, prey
end

function get_variant()
    return SAVED_DATA.variant
end

-- animation (client) ---------------------------------------------------------

local tracks = {}
local weights = {walk = 0, idle = 0, air = 0, fly = 0}
local gait_phase = 0
local idle_time = math.random() * 10

local function track(key)
    local name = species.tracks[key]
    if not name then
        return nil
    end
    local t = tracks[key]
    if t == nil then
        t = animation.get_track(name) or false
        tracks[key] = t
    end
    return t or nil
end

local function approach(value, goal, rate)
    return value + (goal - value) * math.min(1, rate)
end

local function apply(key, t, weight)
    local tr = track(key)
    if tr and weight > 0.01 then
        tr.func(rig, t, weight)
    end
end

function on_render(delta)
    local vel = body:get_vel()
    local speed = vec2.length({vel[1], vel[3]})
    local grounded = body:is_grounded()
    local flying = state == "fly"

    weights.walk = approach(weights.walk, flying and 0 or math.min(1, speed / 2.5), delta * 8)
    weights.idle = approach(weights.idle, (state == "idle" and speed < 0.3) and 1 or 0, delta * 3)
    weights.air = approach(weights.air, (grounded or flying) and 0 or 1, delta * 10)
    weights.fly = approach(weights.fly, flying and 1 or 0, delta * 6)
    gait_phase = gait_phase + speed * species.gait * delta
    idle_time = idle_time + delta

    rig:reset_pose()
    apply("walk", gait_phase, weights.walk)
    apply("idle", idle_time, weights.idle)
    apply("air", idle_time, weights.air)
    apply("fly", idle_time, weights.fly)
    if attack_anim > 0 then
        attack_anim = math.max(0, attack_anim - delta)
        apply("attack", 1 - attack_anim / ATTACK_ANIM, 1)
    end

    if hurt_timer > 0 then
        hurt_timer = hurt_timer - delta
        rig:set_color(hurt_timer > 0 and {1, 0.45, 0.45} or {1, 1, 1})
    end
end
