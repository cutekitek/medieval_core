-- Wild animal: wanders, grazes, follows a player holding its favourite
-- food, runs from danger, fights (bears), flies (birds), drops loot on death.
-- Sheep also crop grass, grow wool back and are shorn with a knife. Farm
-- animals (species with `breed`) get hungry and thirsty, eat and drink from
-- troughs and breed when fed (husbandry/husbandry). Horses are saddled and
-- ridden (riding/riding); animals with `leash` are led and tied up with a
-- lasso (riding/leash). Species data and tempers: fauna/species.
local species_list = require "fauna/species"
local base_util = require "base:util"
local stats = require "survival/stats"
local mode = require "survival/mode"
local flow = require "water/flow"
local husbandry = require "husbandry/husbandry"
local trough = require "husbandry/trough"
local spawning = require "fauna/spawning"
local riding = require "riding/riding"
local leash = require "riding/leash"
local boat = require "boat/boat"
local notice = require "player/notice"
local lod = require "fauna/lod"

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
local FENCE_TAG, GATE_TAG = "medieval_core:fence", "medieval_core:gate"

local FOLLOW_RADIUS = 10
local REACHED = 1.2
local FLEE_TIME = 4.0
local HURT_FLASH = 0.25
local ATTACK_ANIM = 0.5
local CHASE_REPATH = 0.5
local AIR_DAMPING = 10.0      -- core:mob default
local GROUND_DAMPING = 10.0   -- core:mob default
local CALM_AFTER_LURE = 4.0   -- s a shy animal stays calm after the lure is put away
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

-- lambs: SAVED_DATA.age counts up to breed.grow_time (nil when grown up);
-- a newborn gets age = 0 from its spawn args
local breed = species.breed
local hitbox = entities.def_hitbox(entities.def_index(species.entity))
if not SAVED_DATA.aged then
    SAVED_DATA.aged = true
    SAVED_DATA.age = breed and ARGS.age or nil
end

local function young()
    return SAVED_DATA.age ~= nil
end

local function scale()
    return young() and breed.baby_scale or 1
end

if breed then
    local s = scale()
    tsf:set_size({s, s, s})
end

-- the hitbox as it is: rigidbody:get_size() leaves out the scale of a lamb
local function body_size()
    return vec3.mul(body:get_size(), tsf:get_size())
end

-- the fleece: every bone named wool* is hidden while shorn
local wool_bones = {}
if species.wool then
    for _, name in ipairs({"wool", "wool_head", "wool_leg_fl", "wool_leg_fr", "wool_leg_bl", "wool_leg_br"}) do
        local index = rig:index(name)
        if index then
            table.insert(wool_bones, index)
        end
    end
end

local function show_wool()
    for _, index in ipairs(wool_bones) do
        rig:set_visible(index, not SAVED_DATA.sheared)
    end
end
show_wool()

-- riding: the saddle and the bridle are shown while saddled, the reins
-- under a rider
local ride = species.ride
local rider = nil
local tack = {}
for _, name in ipairs({"saddle", "bridle", "reins"}) do
    tack[name] = rig:index(name)
end

local function show_tack()
    local on = SAVED_DATA.saddled == true
    for name, index in pairs(tack) do
        rig:set_visible(index, on and (name ~= "reins" or rider ~= nil))
    end
end
show_tack()
if ride then
    -- a horse saved under its rider kept the rider's damping
    mob.set_air_damping(AIR_DAMPING)
    mob.set_ground_damping(GROUND_DAMPING)
end

-- the lasso: who holds the other end ({pid = n} or {post = {x, y, z}})
local uid = entity:get_uid()
local holder = SAVED_DATA.leash
if holder then
    leash.register(uid, holder)
end
local calm = 0                -- s left without fear of players

local love = 0              -- seconds left looking for a mate
local heart_timer = 0
local breed_item = breed and item.index(breed.item) or 0

-- farm animals: seconds since the last meal and drink (a new one is hungry)
if breed then
    SAVED_DATA.hunger = SAVED_DATA.hunger or husbandry.FED_FOR
    SAVED_DATA.thirst = SAVED_DATA.thirst or husbandry.FED_FOR
end
local check_timer = husbandry.next_check() * math.random()
local visit = nil           -- the trough it goes to: {kind, site, rect}

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

-- is the chunk at this point loaded (over or under the world: its column)
local function loaded_at(x, y, z)
    y = math.max(0, math.min(255, math.floor(y)))
    return block.get(math.floor(x), y, math.floor(z)) ~= -1
end

-- out of the loaded world, far from players ------------------------------------

local VOID_Y = -64
-- frozen while outside the loaded world or far from every player (fauna/lod;
-- the switch is saved with the body)
local frozen = not body:is_enabled()
local far = false
local lod_timer = math.random() * lod.CHECK_EVERY

-- An animal in a chunk that is not loaded (it got there after that chunk
-- was saved and unloaded, e.g. a bird flying past the edge) is taken by the
-- physics for a body inside rock and pushed down under the world. There
-- every such body exhausts the physics' nearby lists, so the physics of all
-- entities slows down until the game stalls. It waits frozen until the
-- chunk is loaded again; one already under the world is gone. Far from
-- every player it rests the same way.
local function keep_out_of_void(delta)
    local pos = tsf:get_pos()
    if pos[2] < VOID_Y then
        entity:despawn()
        return true
    end
    lod_timer = lod_timer - delta
    if lod_timer <= 0 then
        lod_timer = lod.CHECK_EVERY
        local d = lod.player_distance(pos)
        far = (far and d > lod.SIM_DISTANCE - lod.WAKE_MARGIN) or d > lod.SIM_DISTANCE
    end
    local out = not rider and (far or not loaded_at(pos[1], pos[2], pos[3]))
    if out ~= frozen then
        frozen = out
        body:set_enabled(not out)
        if out then
            body:set_vel({0, 0, 0})
        end
    end
    return frozen
end

local stuck_time = 0         -- seconds pushing along a route without moving

local function set_state(name, duration, new_target)
    -- following a lure or a mate renews the state every second: while the
    -- target stays put the route is kept (dropping it stops the animal until
    -- the new one is found)
    local same = name == state and target and new_target and
        vec3.distance(target, new_target) < 1.5
    state = name
    state_timer = duration
    target = new_target
    if name ~= "trough" and name ~= "eat" then
        visit = nil
    end
    if not same then
        pf.reset_route()
        stuck_time = 0
    end
    pf.set_target(target)
    -- a chase re-plans the route often (the default is every 100 updates),
    -- a follow keeps up with a walking player
    pf.set_refresh_interval((name == "chase" and 10) or (name == "follow" and 20) or 100)
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

-- nearest grown animal of the same species (a lamb keeps close to it)
local function nearest_adult(radius)
    local pos = tsf:get_pos()
    local me = entity:get_uid()
    local best, best_dist = nil, radius
    for _, uid in ipairs(entities.get_all_in_radius(pos, radius)) do
        local e = uid ~= me and entities.get(uid)
        local ai = e and e:get_component("medieval_core:animal")
        if ai and ai.get_species() == species_name and not ai.is_baby() then
            local d = vec3.distance(pos, e.transform:get_pos())
            if d < best_dist then
                best, best_dist = e, d
            end
        end
    end
    return best
end

local function pick_wander_target()
    local pos = tsf:get_pos()
    -- a saddled horse grazes close by
    local r = SAVED_DATA.saddled and math.min(4, species.wander_radius) or species.wander_radius
    local parent = young() and nearest_adult(16)
    if holder and holder.post then
        -- round the post it is tied to
        local p = holder.post
        pos = {p[1] + 0.5, pos[2], p[3] + 0.5}
        r = leash.LENGTH - 1.5
    elseif parent then
        pos = parent.transform:get_pos()
        r = 3
    end
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

-- voice ---------------------------------------------------------------------

local VOICE_RANGE = 40        -- calls are only played this close to the player
local voice = species.voice
local voice_timer = 0

local function next_call()
    if voice then
        voice_timer = voice.every[1] + math.random() * (voice.every[2] - voice.every[1])
    end
end
next_call()

local function heard()
    if not gfx or not hud then
        return false
    end
    local pos = tsf:get_pos()
    local x, y, z = player.get_pos(hud.get_player())
    return vec3.distance(pos, {x, y, z}) < VOICE_RANGE
end

local function sound(name, volume, pitch)
    local pos = tsf:get_pos()
    audio.play_sound("medieval_core/" .. name, pos[1], pos[2] + 0.3, pos[3], volume,
        pitch * (0.92 + math.random() * 0.16), "regular")
end

-- the species' call; young ones sound higher
local function say(volume_k, pitch_k)
    if voice and heard() then
        sound(voice.name, (voice.volume or 0.8) * (volume_k or 1),
            (voice.pitch or 1) * (pitch_k or 1) * (young() and 1.35 or 1))
    end
end

local function tick_voice(dt)
    if not voice then
        return
    end
    voice_timer = voice_timer - dt
    if voice_timer <= 0 then
        next_call()
        if active_time() then
            say()
        end
    end
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
    if species.roar and prey ~= pid and heard() then
        sound(species.roar, species.roar_volume or 1.0, 1.0)
    end
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
    for y = math.min(from_y + 24, 255), math.max(from_y - 48, 0), -1 do
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
    -- only over loaded ground: past the edge of the loaded world a bird
    -- would fly into chunks the physics takes for solid rock and be pushed
    -- down through them under the world
    local alt = species.flight.altitude
    for try = 1, 8 do
        local dist = 8 + math.random() * 10
        local x = pos[1] + dir[1] * dist
        local z = pos[3] + dir[3] * dist
        local top = column_top(math.floor(x), math.floor(z), math.floor(pos[2]))
        if top then
            flight.wp = {x, top + 1 + alt[1] + math.random() * (alt[2] - alt[1]), z}
            return
        end
        angle = angle + math.pi * 0.25 * (try % 2 == 0 and try or -try)
        dir = {math.cos(angle), 0, math.sin(angle)}
    end
    -- nowhere to go: hover where it is
    flight.wp = {pos[1], pos[2], pos[3]}
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
        goal = {l[1], l[2] + math.min(6, hd * 0.6) + body_size()[2] * 0.5, l[3]}
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
        if not loaded_at(ax, pos[2], az) then
            -- the edge of the loaded world: turn back
            next_waypoint({ax, pos[2], az})
            return
        end
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

-- sheep: grazing, shearing, breeding -------------------------------------------

local MATE_RADIUS = 8
local MATE_REACH = 1.8
-- what grazing leaves of the ground
local GRAZED = {
    ["base:grass_block"] = "base:dirt",
    ["medieval_core:tropical_grass_block"] = "base:dirt",
}
local grass_plant = block.index("base:grass")

local function puff(texture, count, speed, size, lift)
    if not gfx then
        return
    end
    local pos = tsf:get_pos()
    local h = hitbox[2] * scale()
    gfx.particles.emit({pos[1], pos[2] + h * (lift or 0.5), pos[3]}, count, {
        texture = texture,
        lifetime = 0.9,
        spawn_interval = 0.0001,
        explosion = {speed, speed * 1.5, speed},
        acceleration = {0, -2, 0},
        size = {size, size, size},
        spawn_shape = "box",
        spawn_spread = {0.3, 0.1, 0.3},
    })
end

function hearts(count)
    puff("blocks:mw_heart", count, 0.6, 0.18, 0.9)
end

-- the grass the animal stands on: {x, y, z, kind} with kind "plant" (tall
-- grass in the feet cell) or "ground" (grass block under it)
local function grass_underfoot()
    local pos = tsf:get_pos()
    local feet = pos[2] - hitbox[2] * scale() * 0.5
    local x, y, z = math.floor(pos[1]), math.floor(feet + 0.05), math.floor(pos[3])
    if block.get(x, y, z) == grass_plant then
        return {x, y, z, "plant"}
    end
    local id = block.get(x, y - 1, z)
    if id > 0 and GRAZED[block.name(id)] then
        return {x, y - 1, z, "ground"}
    end
    return nil
end

function try_graze(dt)
    local graze = species.graze
    if not graze or not body:is_grounded() then
        return false
    end
    local interval = young() and graze.interval / 10 or graze.interval
    if math.random() >= dt / interval or not grass_underfoot() then
        return false
    end
    set_state("eat", graze.time)
    return true
end

function finish_grazing()
    local cell = grass_underfoot()
    if not cell then
        return false
    end
    local x, y, z = cell[1], cell[2], cell[3]
    if cell[4] == "plant" then
        block.set(x, y, z, 0, 0)
    else
        block.set(x, y, z, block.index(GRAZED[block.name(block.get(x, y, z))]), 0)
    end
    if gfx then
        puff("blocks:mw_dirt_clod", 6, 1.2, 0.07, 0.0)
    end
    -- a meal regrows the fleece and helps a lamb grow up
    if SAVED_DATA.sheared then
        SAVED_DATA.sheared = nil
        show_wool()
    end
    if young() then
        SAVED_DATA.age = SAVED_DATA.age + species.graze.lamb_growth
    end
    return true
end

-- the knife takes the fleece: wool drops, the knife wears
function shear(pid, invid, slot)
    if not species.wool or SAVED_DATA.sheared or young() then
        return false
    end
    SAVED_DATA.sheared = true
    show_wool()
    local pos = tsf:get_pos()
    local n = math.random(species.wool.shear[1], species.wool.shear[2])
    local e = base_util.drop({pos[1], pos[2] + 0.3, pos[3]}, item.index(species.wool.item), n)
    if e then
        e.rigidbody:set_vel({math.random() - 0.5, 3.5, math.random() - 0.5})
    end
    if pid and not player.is_infinite_items(pid) then
        inventory.use(invid, slot)
    end
    if gfx then
        puff("blocks:mw_wool_tuft", 10, 1.4, 0.12, 0.7)
        audio.play_sound("medieval_core/shear", pos[1], pos[2], pos[3], 0.8, 0.9 + math.random() * 0.2, "regular")
    end
    return true
end

-- its food from a hand: a meal for a grown animal (not right after one), a
-- young one grows. Returns true if it was eaten.
function feed()
    if not breed then
        return false
    end
    if young() then
        SAVED_DATA.age = SAVED_DATA.age + breed.grow_time * breed.feed_growth
        puff("blocks:mw_heart", 2, 0.4, 0.12, 0.9)
        return true
    end
    if SAVED_DATA.hunger < husbandry.MEAL_EVERY * 0.25 then
        return false
    end
    SAVED_DATA.hunger = 0
    puff("blocks:mw_heart", 2, 0.4, 0.12, 0.9)
    return true
end

-- troughs ----------------------------------------------------------------------

local function needs(kind)
    local since = kind == "feed" and SAVED_DATA.hunger or SAVED_DATA.thirst
    return since >= husbandry.MEAL_EVERY
end

-- a standing cell beside the trough (not at its corners), nearest first
local function trough_spot(rect, y)
    local pos = tsf:get_pos()
    local best, best_dist = nil, math.huge
    for x = rect[1] - 1, rect[3] + 1 do
        for z = rect[2] - 1, rect[4] + 1 do
            local out_x = x < rect[1] or x > rect[3]
            local out_z = z < rect[2] or z > rect[4]
            if out_x ~= out_z then
                local cell = ground_at(x, y, z, 1, 2)
                if cell then
                    local d = vec3.distance(pos, {cell[1] + 0.5, cell[2], cell[3] + 0.5})
                    if d < best_dist then
                        best, best_dist = cell, d
                    end
                end
            end
        end
    end
    return best
end

-- the point of the trough's footprint nearest to the animal, and the
-- horizontal distance to it
local function trough_point(rect)
    local pos = tsf:get_pos()
    local x = math.max(rect[1], math.min(rect[3] + 1, pos[1]))
    local z = math.max(rect[2], math.min(rect[4] + 1, pos[3]))
    return x, z, vec2.length({pos[1] - x, pos[3] - z})
end

local function at_trough(rect)
    local _, _, d = trough_point(rect)
    return d <= hitbox[1] * scale() * 0.5 + 1.0
end

-- hungry or thirsty: off to the nearest trough with feed or water in it
local function go_to_trough()
    local kinds = {"feed", "water"}
    if SAVED_DATA.thirst > SAVED_DATA.hunger then
        kinds = {"water", "feed"}
    end
    for _, kind in ipairs(kinds) do
        if needs(kind) then
            local site, rect = trough.find(tsf:get_pos(), husbandry.SEARCH_RADIUS, kind)
            local spot = site and trough_spot(rect, site[2])
            if spot then
                set_state("trough", husbandry.GIVE_UP, spot)
                visit = {kind = kind, site = site, rect = rect}
                return true
            end
        end
    end
    return false
end

local function start_meal()
    local x, z = trough_point(visit.rect)
    local pos = tsf:get_pos()
    local dx, dz = x - pos[1], z - pos[3]
    local len = math.sqrt(dx * dx + dz * dz)
    if len > 1e-3 then
        mob.set_dir({dx / len, 0, dz / len})
    end
    local v = visit
    set_state("eat", husbandry.MEAL_TIME)
    visit = v
end

local function finish_meal()
    local s = visit.site
    if not trough.take(s[1], s[2], s[3], visit.kind) then
        return false
    end
    if visit.kind == "feed" then
        SAVED_DATA.hunger = 0
        if heard() then
            sound("eat", 0.35, 1.0)
        end
    else
        SAVED_DATA.thirst = 0
        if heard() then
            sound("drink", 0.4, 1.0)
        end
    end
    return true
end

-- breeding ---------------------------------------------------------------------

-- grown, rested and has eaten and drunk lately
local function ready()
    return breed ~= nil and not young() and not SAVED_DATA.breed_cooldown and love <= 0
        and SAVED_DATA.hunger < husbandry.FED_FOR and SAVED_DATA.thirst < husbandry.FED_FOR
end

function is_ready()
    return ready()
end

function start_love()
    love = breed.love_time
    heart_timer = 0
end

-- now and then a ready animal finds a ready partner nearby: both look for
-- each other (seek_mate) and have a young one
local function try_breed()
    if not ready() or math.random() >= husbandry.BREED_CHANCE then
        return false
    end
    local pos = tsf:get_pos()
    local me = entity:get_uid()
    local herd, partner = 0, nil
    for _, uid in ipairs(entities.get_all_in_radius(pos, husbandry.HERD_RADIUS)) do
        local e = entities.get(uid)
        local ai = e and e:get_component("medieval_core:animal")
        if ai and ai.get_species() == species_name then
            herd = herd + 1
            if uid ~= me and not partner and ai.is_ready() and
               vec3.distance(pos, e.transform:get_pos()) <= husbandry.MATE_RADIUS then
                partner = ai
            end
        end
    end
    if not partner or herd >= husbandry.HERD_LIMIT then
        return false
    end
    partner.start_love()
    start_love()
    return true
end

local function find_mate()
    local pos = tsf:get_pos()
    local me = entity:get_uid()
    for _, uid in ipairs(entities.get_all_in_radius(pos, MATE_RADIUS)) do
        local e = uid ~= me and entities.get(uid)
        local ai = e and e:get_component("medieval_core:animal")
        if ai and ai.get_species() == species_name and ai.in_love() and not ai.is_baby() then
            return e, ai
        end
    end
    return nil
end

-- walks up to a mate in love; next to it a lamb is born
function seek_mate()
    local mate, ai = find_mate()
    if not mate then
        return false
    end
    local pos = tsf:get_pos()
    local mpos = mate.transform:get_pos()
    if vec3.distance(pos, mpos) > MATE_REACH then
        if state ~= "follow" or state_timer <= 0 then
            set_state("follow", 1.0, floor3(mpos))
        end
        return true
    end
    ai.end_love()
    end_love()
    -- on the ground beside the parents, not inside them (bodies are solid)
    local feet = math.floor(math.min(pos[2], mpos[2]) - hitbox[2] * 0.5 + 0.1)
    local mid = {(pos[1] + mpos[1]) * 0.5, (pos[3] + mpos[3]) * 0.5}
    local s = breed.baby_scale
    local spot = spawning.find_clear(math.floor(mid[1]), feet, math.floor(mid[2]),
        {hitbox[1] * s, hitbox[2] * s, hitbox[3] * s}, 3) or
        {mid[1], feet + hitbox[2] * s * 0.5 + 0.05, mid[2]}
    -- a herd shares its coat: the young one gets a parent's
    local variant = nil
    if species.variants then
        variant = math.random() < 0.5 and SAVED_DATA.variant or ai.get_variant()
    end
    entities.spawn(species.entity, spot, {medieval_core__animal = {species = species_name, age = 0, variant = variant}})
    hearts(6)
    set_state("idle", 3)
    return true
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
    local reach = body_size()[1] * 0.5 + 0.3 + atk.reach
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

-- led on a rope: walks after the holder, hurries when left behind
local function lead_think()
    local h = leash.anchor(holder)
    if not h then
        return
    end
    local pos = tsf:get_pos()
    local d = vec3.distance(h, pos)
    if d > leash.FOLLOW then
        if state ~= "follow" or state_timer <= 0 then
            local cell = ground_at(math.floor(h[1]), math.floor(h[2]), math.floor(h[3]), 1, 4)
            set_state("follow", 1.0, cell or floor3(h))
        end
        mob.set_movement_speed(d > leash.LENGTH - 1 and species.flee_speed or species.walk_speed * 1.5)
    elseif state ~= "idle" and state ~= "eat" then
        set_state("idle", 2.0)
    end
end

local function think(dt)
    state_timer = state_timer - dt
    attack_timer = attack_timer - dt
    calm = calm - dt

    if rider then
        return
    end
    if holder and holder.pid and state ~= "fly" then
        lead_think()
        return
    end
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
    -- a saddled horse, a caught animal or one just lured is not afraid
    local fearless = SAVED_DATA.saddled or holder or calm > 0
    if temper == "shy" and state ~= "flee" and not fearless then
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

    if state == "eat" then
        if state_timer <= 0 then
            if visit then
                finish_meal()
            else
                finish_grazing()
            end
            set_state("idle", 1 + math.random() * 2)
        end
        return
    end
    if state == "trough" then
        if at_trough(visit.rect) then
            start_meal()
        elseif state_timer <= 0 then
            set_state("idle", 2 + math.random() * 2)
        end
        return
    end
    if love > 0 and state ~= "flee" and seek_mate() then
        return
    end
    if breed and state ~= "flee" then
        check_timer = check_timer - dt
        if check_timer <= 0 then
            check_timer = husbandry.next_check()
            if not young() and (go_to_trough() or try_breed()) then
                return
            end
        end
    end
    if state ~= "flee" and state ~= "follow" and try_graze(dt) then
        return
    end

    local lurer = state ~= "flee" and nearest_player(FOLLOW_RADIUS, holds_lure)
    if lurer then
        calm = CALM_AFTER_LURE
        local ppos = {player.get_pos(lurer)}
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
    if not species.lay_interval or young() then
        return
    end
    local lo, hi = species.lay_interval[1], species.lay_interval[2]
    SAVED_DATA.egg_timer = (SAVED_DATA.egg_timer or (lo + math.random() * (hi - lo))) - dt
    if SAVED_DATA.egg_timer <= 0 then
        SAVED_DATA.egg_timer = lo + math.random() * (hi - lo)
        base_util.drop(tsf:get_pos(), item.index(species.lay_item), 1)
    end
end

local function grow_up()
    SAVED_DATA.age = nil
    local pos = tsf:get_pos()
    tsf:set_size({1, 1, 1})
    -- the hitbox grows from the middle: keep the feet on the ground
    tsf:set_pos({pos[1], pos[2] + hitbox[2] * (1 - breed.baby_scale) * 0.5 + 0.02, pos[3]})
end

local function tick_life(dt)
    if not breed then
        return
    end
    SAVED_DATA.hunger = SAVED_DATA.hunger + dt
    SAVED_DATA.thirst = SAVED_DATA.thirst + dt
    if love > 0 then
        love = love - dt
        heart_timer = heart_timer - dt
        if heart_timer <= 0 then
            heart_timer = 0.8
            hearts(1)
        end
    end
    if SAVED_DATA.breed_cooldown then
        SAVED_DATA.breed_cooldown = SAVED_DATA.breed_cooldown - dt
        if SAVED_DATA.breed_cooldown <= 0 then
            SAVED_DATA.breed_cooldown = nil
        end
    end
    if young() then
        SAVED_DATA.age = SAVED_DATA.age + dt
        if SAVED_DATA.age >= breed.grow_time then
            grow_up()
        end
    end
end

function on_update(tps)
    local dt = 1 / tps
    if frozen then
        return
    end
    think(dt)
    lay_egg(dt)
    tick_life(dt)
    tick_voice(dt)
end

local CLIMB_AIR_SPEED = 2.2   -- m/s towards the waypoint while jumping up
local STUCK_SPEED = 0.25      -- slower than this along a route = pushing in place
local STUCK_JUMP = 0.4        -- s pushing in place before trying a jump
local STUCK_JUMP_EVERY = 0.8
local STUCK_REPATH = 2.0      -- s before the route is planned anew
local STUCK_GIVE_UP = 4.0     -- s before the animal gives the target up
local NO_WAY = 1.0            -- s standing at the end of a route that falls short
local CLIMB_TIME = 1.0        -- s a jump onto a block lasts at most
local climbing = 0            -- s left of a jump onto a block
local stuck_jump_timer = 0

-- fences and gates hold animals in: no jumping onto them
local function fenced(waypoint)
    local under = block.get(waypoint[1], waypoint[2] - 1, waypoint[3])
    return under > 0 and (block.has_tag(under, FENCE_TAG) or block.has_tag(under, GATE_TAG))
end

-- room for the whole body at the waypoint (the route only keeps one free
-- block over the ground)
local function headroom(waypoint)
    for y = waypoint[2], waypoint[2] + math.ceil(body_size()[2]) - 1 do
        if block.get(waypoint[1], y, waypoint[3]) ~= 0 and
           not block.is_replaceable_at(waypoint[1], y, waypoint[3]) then
            return false
        end
    end
    return true
end

local function climb(waypoint)
    -- one jump at a time: the body may still count as grounded right after it
    if climbing > 0 or fenced(waypoint) then
        return
    end
    mob.jump()
    climbing = CLIMB_TIME
end

-- Steers along the pathfinding route (safe for zero-length steps)
local function follow_route(delta)
    local route = pf.get_route()
    climbing = climbing - delta
    if not route then
        return
    end
    local pos = tsf:get_pos()
    if #route == 0 then
        -- the route ended short of the target (no way up a cliff): give up
        -- instead of standing there until the state times out
        if vec3.distance(target, pos) >= REACHED + 1 then
            stuck_time = stuck_time + delta
            if stuck_time >= NO_WAY then
                stuck_time = 0
                set_state("idle", 1 + math.random() * 2)
            end
        end
        return
    end
    local waypoint = route[#route]
    local dx = waypoint[1] + 0.5 - pos[1]
    local dz = waypoint[3] + 0.5 - pos[3]
    if dx * dx + dz * dz < 0.25 then
        table.remove(route, #route)
        return
    end
    local len = math.sqrt(dx * dx + dz * dz)
    local dir = {dx / len, dz / len}
    mob.set_dir({dir[1], 0, dir[2]})
    local vel = body:get_vel()
    -- an animal caught on the edge of a block is not grounded but does not
    -- fall either: it may jump off
    local grounded = body:is_grounded()
    if not grounded and (climbing > 0 or math.abs(vel[2]) >= 0.05) then
        if climbing > 0 then
            -- the air damping of core:mob all but stops a jump: keep going
            -- over the edge, or the animal falls back in front of the block
            local speed = math.max(CLIMB_AIR_SPEED, vec2.length({vel[1], vel[3]}))
            body:set_vel({dir[1] * speed, vel[2], dir[2] * speed})
        else
            mob.go(dir, 1.0, false, false)
        end
        return
    end
    if grounded and vel[2] <= 0.1 then
        climbing = 0
    end
    mob.go(dir, 1.0, false, false)

    if vec2.length({vel[1], vel[3]}) < STUCK_SPEED then
        stuck_time = stuck_time + delta
    else
        stuck_time = math.max(0, stuck_time - delta * 2)
    end
    stuck_jump_timer = stuck_jump_timer - delta

    -- by the feet: the centre of a tall animal (a horse) is almost a block
    -- above them, and a step up to half a block needs no jump
    local feet = pos[2] - body_size()[2] * 0.5
    if waypoint[2] - feet > 0.55 then
        climb(waypoint)
    elseif stuck_time > STUCK_JUMP and stuck_jump_timer <= 0 and waypoint[2] > feet - 0.5 and
           headroom(waypoint) then
        -- caught on a corner or a ledge the route does not show (the engine
        -- plans routes under low branches too: a jump does not help there)
        stuck_jump_timer = STUCK_JUMP_EVERY
        climb(waypoint)
    elseif species.hop then
        mob.jump(0.55)
    end

    if stuck_time >= STUCK_GIVE_UP then
        stuck_time = 0
        set_state("idle", 1 + math.random() * 2)
    elseif stuck_time >= STUCK_REPATH and stuck_time - delta < STUCK_REPATH then
        pf.reset_route()
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
            if len < body_size()[1] * 0.5 + 0.8 and shore[2] > pos[2] - body_size()[2] * 0.5 then
                body:set_gravity_scale(1.0)
                body:set_vel({vel[1], 7.0, vel[3]})
                scramble = 0.5
            end
        end
    end
    return true
end

-- riding ----------------------------------------------------------------------

local ride_speed = 0          -- m/s along the heading (negative: backing up)
local ride_side = 0           -- m/s to the right
local ride_yaw = 0            -- heading, degrees like the player's view
local last_pos = nil
local moved_speed = 0         -- m/s the body really moved (into a wall: 0)
local rider_bob = 0           -- the back rising and falling (on_render)

-- how high the top of the block in a cell is above its floor (0: nothing
-- to stand on: air, grass, water)
local function block_top(x, y, z)
    local id = block.get(x, y, z)
    if id <= 0 or block.is_replaceable_at(x, y, z) then
        return 0
    end
    if block.is_solid_at(x, y, z) then
        return 1
    end
    local hb = block.get_hitbox(id, block.get_rotation(x, y, z))
    return hb[1][2] + hb[2][2]
end

local GRAVITY = 22.6
local STEP_MIN = 0.55         -- lower steps: the engine's own step height
local STEP_MAX = 1.05
local STEP_SAMPLE = 0.2       -- m between the probes along a ray

-- how high the ground in a column is above the feet; the cell it is in
local function rise_at(x, z, feet)
    local y = math.floor(feet + 0.05)
    local top = block_top(x, y, z)
    if top >= 1 then
        local up = block_top(x, y + 1, z)
        if up > 0 then
            return y + 1 + up - feet, y + 1
        end
    end
    return y + top - feet, y
end

-- room for the whole body on a ground this high
local function room_on(x, z, ground, height)
    for y = math.floor(ground - 0.05) + 1, math.floor(ground + height - 0.05) do
        if block_top(x, y, z) > 0 then
            return false
        end
    end
    return true
end

-- a step up to a block high on the way: true to hop now. The hop starts
-- this far ahead that the hooves clear the edge before they get there,
-- else the body runs into it and stands until it is up. Every ray across
-- the body is probed (it often comes at the edge at an angle); fences and
-- gates are jumped, not stepped on.
local function step_ahead(pos, dir, speed, delta)
    local size = body_size()
    local half = size[1] * 0.5
    local feet = pos[2] - size[2] * 0.5
    local v = ride.step
    local d = v * v - 2 * GRAVITY * STEP_MAX
    local rise_time = d > 0 and (v - math.sqrt(d)) / GRAVITY or v / GRAVITY
    local front = half * (math.abs(dir[1]) + math.abs(dir[3]))
    local reach = front + speed * (rise_time + delta)
    local sx, sz = -dir[3], dir[1]
    -- the nearest step and the nearest wall over all the rays
    local step, wall = math.huge, math.huge
    for _, k in ipairs({0, -0.9, 0.9}) do
        local ox, oz = pos[1] + sx * half * k, pos[3] + sz * half * k
        local lx, lz = nil, nil
        local dist = 0
        while dist <= reach do
            local x, z = math.floor(ox + dir[1] * dist), math.floor(oz + dir[3] * dist)
            if x ~= lx or z ~= lz then
                lx, lz = x, z
                local rise, y = rise_at(x, z, feet)
                if rise > STEP_MIN then
                    local id = block.get(x, y, z)
                    if rise > STEP_MAX or block.has_tag(id, FENCE_TAG) or block.has_tag(id, GATE_TAG)
                       or not room_on(x, z, feet + rise, size[2]) then
                        wall = math.min(wall, dist)
                    else
                        step = math.min(step, dist)
                    end
                    break
                end
            end
            dist = dist + STEP_SAMPLE
        end
    end
    if step == math.huge or wall <= step then
        return false
    end
    -- and over its own head while it rises
    local x, z = math.floor(pos[1]), math.floor(pos[3])
    for y = math.floor(feet + size[2]), math.floor(feet + size[2] + STEP_MAX + 0.2) do
        if block_top(x, y, z) > 0 then
            return false
        end
    end
    return true
end

-- stamina (species.ride.stamina): the gallop and the jumps take it, a trot
-- and rest give it back. Run out, the horse is winded: no gallop and no
-- jumps until it has its breath back.
local stamina_def = ride and ride.stamina
local winded = SAVED_DATA.winded == true

local function stamina()
    return SAVED_DATA.stamina or stamina_def.max
end

local function set_stamina(value)
    value = math.max(0, math.min(stamina_def.max, value))
    SAVED_DATA.stamina = value < stamina_def.max and value or nil
    if value <= 0 and not winded then
        winded = true
        SAVED_DATA.winded = true
        say(0.8, 0.8)
        if rider then
            notice.show(rider, "medieval_core.ride.winded")
        end
    elseif winded and value >= stamina_def.max * stamina_def.recover then
        winded = false
        SAVED_DATA.winded = nil
    end
end

-- per second: speed = m/s it goes now
local function tick_stamina(delta, speed, wet)
    if not stamina_def then
        return
    end
    local rate
    if wet then
        rate = -stamina_def.swim
    elseif speed > ride.trot + 0.5 then
        rate = -stamina_def.gallop
    elseif speed > 1.5 then
        rate = stamina_def.trot
    else
        rate = stamina_def.rest
    end
    if rate > 0 and not SAVED_DATA.stamina then
        return
    end
    set_stamina(stamina() + rate * delta)
end

local function yaw_of(dir)
    return math.deg(math.atan2(-dir[1], -dir[3]))
end

local function approach_to(value, goal, step)
    return value + math.max(-step, math.min(step, goal - value))
end

-- the rider's seat over the back, following the gait
local last_seat = nil

local function seat_rider()
    local s = ride.seat
    local p = mat4.mul(tsf:get_rot(), {s[1], s[2] + rider_bob, s[3]})
    local pos = tsf:get_pos()
    last_seat = {pos[1] + p[1], pos[2] + p[2], pos[3] + p[3]}
    player.set_vel(rider, 0, 0, 0)
    player.set_pos(rider, last_seat[1], last_seat[2], last_seat[3])
end

-- the rider was moved off the horse by something else (respawned after
-- death, teleported): out of the saddle where he is now
local function rider_moved()
    if not last_seat then
        return false
    end
    local x, y, z = player.get_pos(rider)
    return vec3.distance({x, y, z}, last_seat) > 2.5
end

-- where the rider gets off: beside the horse, on something solid
local function exit_spot()
    local pos = tsf:get_pos()
    local a = math.rad(ride_yaw)
    local f = {-math.sin(a), 0, -math.cos(a)}
    local side = {-f[3], 0, f[1]}
    local feet = math.floor(pos[2] - body_size()[2] * 0.5 + 0.1)
    -- the spot is the middle of a cell: clear of the body
    local clear = body_size()[1] * 0.5 + 0.35
    for _, d in ipairs({{-side[1], 0, -side[3]}, side, {-f[1], 0, -f[3]}, f}) do
        for _, dist in ipairs({1.0, 1.6, 2.2}) do
            local x = math.floor(pos[1] + d[1] * dist)
            local z = math.floor(pos[3] + d[3] * dist)
            if vec2.length({x + 0.5 - pos[1], z + 0.5 - pos[3]}) >= clear then
                for y = feet + 1, feet - 1, -1 do
                    if block_top(x, y - 1, z) > 0.5 and block_top(x, y, z) == 0 and block_top(x, y + 1, z) == 0 then
                        return {x + 0.5, y + 0.95, z + 0.5}
                    end
                end
            end
        end
    end
    return {pos[1], pos[2] + body_size()[2] * 0.5 + 1.0, pos[3]}
end

local afloat_ridden = false

local function ride_update(delta)
    local e = player.get_entity(rider)
    if not e or e == 0 or riding.seated_in(rider) ~= uid or rider_moved() then
        dismount(rider, true)
        return
    end
    local fwd_key, back_key, left_key, right_key, jump, sprint, out = riding.controls(rider)
    if out then
        dismount(rider)
        return
    end
    local pos = tsf:get_pos()
    if last_pos then
        moved_speed = vec2.length({pos[1] - last_pos[1], pos[3] - last_pos[3]}) / math.max(delta, 1e-4)
    end
    last_pos = {pos[1], pos[2], pos[3]}

    -- the horse turns where the rider looks
    local view = player.get_rot(rider)
    local diff = (view - ride_yaw + 540) % 360 - 180
    ride_yaw = (ride_yaw + math.max(-ride.turn * delta, math.min(ride.turn * delta, diff))) % 360
    local a = math.rad(ride_yaw)
    local f = {-math.sin(a), 0, -math.cos(a)}
    local side = {-f[3], 0, f[1]}
    mob.set_dir(f)

    local wet = flow.in_water(pos[1], pos[2], pos[3])
    local grounded = body:is_grounded()
    local vel = body:get_vel()
    if grounded or wet then
        local want = 0
        if fwd_key then
            want = (sprint and not winded) and ride.gallop or ride.trot
        elseif back_key then
            want = -ride.back
        end
        if wet then
            want = math.max(-ride.back, math.min(ride.swim, want))
        end
        local speeding_up = math.abs(want) > math.abs(ride_speed) and want * ride_speed >= 0
        ride_speed = approach_to(ride_speed, want, (speeding_up and ride.accel or ride.brake) * delta)
        -- pushing into a wall gets it nowhere
        if ride_speed > 0 then
            ride_speed = math.min(ride_speed, moved_speed + 2.0)
        end
        local want_side = ((right_key and 1 or 0) - (left_key and 1 or 0)) * ride.side
        ride_side = approach_to(ride_side, want_side, ride.accel * delta)
    end
    if wet then
        -- swims with the back at the surface; jump scrambles onto a bank
        afloat_ridden = true
        body:set_gravity_scale(0)
        local deep = flow.in_water(pos[1], pos[2] + 0.5, pos[3])
        vel[2] = jump and 7.0 or (deep and 2.5 or 1.0)
        if jump then
            body:set_gravity_scale(1)
        end
    else
        if afloat_ridden then
            afloat_ridden = false
            body:set_gravity_scale(1)
        end
        local hvel = {f[1] * ride_speed + side[1] * ride_side, 0, f[3] * ride_speed + side[3] * ride_side}
        local hspeed = vec3.length(hvel)
        if grounded and jump and winded then
            notice.show(rider, "medieval_core.ride.winded")
        elseif grounded and jump then
            vel[2] = ride.jump
            set_stamina(stamina() - stamina_def.jump)
            say(0.6, 1.0)
        elseif grounded and ride_speed > 0.5 and step_ahead(pos, {hvel[1] / hspeed, 0, hvel[3] / hspeed}, hspeed, delta) then
            vel[2] = math.max(vel[2], ride.step)
        end
    end
    tick_stamina(delta, ride_speed, wet)
    vel[1] = f[1] * ride_speed + side[1] * ride_side
    vel[3] = f[3] * ride_speed + side[3] * ride_side
    body:set_vel(vel)
end

-- the rope ------------------------------------------------------------------

local rope_uid = nil
local holder_missing = 0      -- s the holder's end has not been found

-- the rope comes off; drop = the lasso falls to the ground
local function rope_off(drop)
    if not holder then
        return
    end
    holder = nil
    SAVED_DATA.leash = nil
    leash.unregister(uid)
    if drop then
        leash.give_lasso(nil, tsf:get_pos())
    end
end

-- held on the rope: no further than its length from the other end
local function tick_rope(delta)
    if not holder then
        return
    end
    if not rope_uid or not entities.exists(rope_uid) then
        local e = entities.spawn("medieval_core:lasso_rope", tsf:get_pos(),
            {medieval_core__lasso_rope = {animal = uid}})
        rope_uid = e and e:get_uid()
    end
    if holder.post and not leash.is_post(holder.post[1], holder.post[2], holder.post[3]) then
        rope_off(true)
        return
    end
    local h = leash.anchor(holder)
    if not h then
        -- the player may not be there yet when the world is loading
        holder_missing = holder_missing + delta
        if holder_missing > 3 then
            rope_off(true)
        end
        return
    end
    holder_missing = 0
    local pos = tsf:get_pos()
    if vec3.distance(h, pos) > leash.BREAK then
        local pid = holder.pid
        rope_off(true)
        if pid then
            notice.show(pid, "medieval_core.leash.slipped")
        end
        return
    end
    local dx, dz = h[1] - pos[1], h[3] - pos[3]
    local dist = math.sqrt(dx * dx + dz * dz)
    if dist <= leash.LENGTH then
        return
    end
    local nx, nz = dx / dist, dz / dist
    local vel = body:get_vel()
    local away = -(vel[1] * nx + vel[3] * nz)
    if away > 0 then
        vel[1], vel[3] = vel[1] + nx * away, vel[3] + nz * away
    end
    local pull = (dist - leash.LENGTH) * 6
    body:set_vel({vel[1] + nx * pull, vel[2], vel[3] + nz * pull})
end

local function move(delta)
    if state ~= "fly" and swim(delta) then
        return
    end
    if state == "fly" and flight then
        fly_steer(delta)
    elseif state == "chase" and prey and charge() then
        return
    elseif target then
        follow_route(delta)
    end
end

function on_physics_update(delta)
    if keep_out_of_void(delta) then
        return
    end
    if rider then
        ride_update(delta)
    else
        move(delta)
        tick_stamina(delta, 0, false)
    end
    tick_rope(delta)
    if rider then
        seat_rider()
    end
end

-- damage -------------------------------------------------------------------

local hurt_timer = 0

local function die()
    local pos = tsf:get_pos()
    if rider then
        dismount(rider)
    end
    rope_off(true)
    if SAVED_DATA.saddled then
        SAVED_DATA.saddled = nil
        base_util.drop(pos, item.index(ride.saddle_item), 1)
    end
    local loot = species.loot
    if young() then
        loot = {}
    elseif species.wool and not SAVED_DATA.sheared then
        loot = {unpack(loot)}
        table.insert(loot, {item = species.wool.item, count = species.wool.drop})
    end
    for _, drop in ipairs(base_util.calc_loot(loot)) do
        local e = base_util.drop(pos, drop.item, drop.count)
        if e then
            e.rigidbody:set_vel(vec3.spherical_rand(2.0))
        end
    end
    entity:despawn()
end

-- knockback scales the push away from the attacker (weapons)
function damage(amount, from, pid, knockback)
    health = health - amount
    SAVED_DATA.health = health
    hurt_timer = HURT_FLASH
    if heard() then
        sound("animal_hurt", 0.8, 1.0)
        say(1.0, 1.2)
    end
    if health <= 0 then
        die()
        return
    end
    if rider then
        -- the rider keeps it in hand
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
    local push = (species.attack and 2 or 6) * (knockback or 1)
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
    if pid ~= -1 and pid == rider then
        -- the rider looking down hits his own horse
        return
    end
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
            -- weapons and tools wear out on every hit
            if not player.is_infinite_items(pid) then
                inventory.use(invid, slot)
            end
        end
    end
    damage(amount, from, pid, knockback)
end

function on_save()
    SAVED_DATA.health = health
end

function on_despawn()
    leash.unregister(uid)
    if rider then
        riding.unseat(rider)
        rider = nil
    end
end

-- saddle and rider ------------------------------------------------------------

local function sound_at(name, volume, pitch)
    local pos = tsf:get_pos()
    audio.play_sound(name, pos[1], pos[2] + 0.3, pos[3], volume, pitch, "regular")
end

-- a saddle from the hand onto a grown horse
function put_saddle(pid)
    if not ride or SAVED_DATA.saddled or young() then
        return false
    end
    local invid, slot = player.get_inventory(pid)
    local itemid, count = inventory.get(invid, slot)
    if itemid == 0 or item.name(itemid) ~= ride.saddle_item then
        return false
    end
    SAVED_DATA.saddled = true
    show_tack()
    if not player.is_infinite_items(pid) then
        inventory.set(invid, slot, count > 1 and itemid or 0, count - 1)
    end
    sound_at("medieval_core/bed", 0.8, 0.8)
    say(0.6, 1.0)
    return true
end

-- the saddle back into the player's inventory (dropped if it is full)
function take_saddle(pid)
    if not SAVED_DATA.saddled or rider then
        return false
    end
    SAVED_DATA.saddled = nil
    show_tack()
    local id = item.index(ride.saddle_item)
    if player.is_infinite_items(pid) or inventory.add(player.get_inventory(pid), id, 1) > 0 then
        if not player.is_infinite_items(pid) then
            base_util.drop(tsf:get_pos(), id, 1)
        end
    end
    sound_at("medieval_core/bed", 0.7, 0.9)
    return true
end

function is_saddled()
    return SAVED_DATA.saddled == true
end

function mount(pid)
    if not ride or not SAVED_DATA.saddled or rider or riding.seated_in(pid) or
       boat.seated_in(pid) or boat.carried_by(pid) then
        return false
    end
    -- whoever leads it on the rope lets go: the lasso is back in the hand
    if holder and holder.pid then
        local lead = holder.pid
        rope_off(false)
        leash.give_lasso(lead, tsf:get_pos())
    end
    rider = pid
    riding.seat(pid, uid)
    state = "ridden"
    target, prey, visit, flight = nil, nil, nil, nil
    pf.reset_route()
    pf.set_target(nil)
    -- the rider sets the speed: no damping of its own
    mob.set_ground_damping(0)
    mob.set_air_damping(0)
    ride_speed, ride_side = 0, 0
    ride_yaw = yaw_of(mob.get_dir())
    last_pos = nil
    show_tack()
    say(0.7, 1.0)
    notice.show(pid, "medieval_core.ride.how",
        holder and holder.post and "medieval_core.ride.tied" or nil)
    seat_rider()
    return true
end

-- stay = the rider is left where he is (not set down beside the horse)
function dismount(pid, stay)
    if not rider or rider ~= pid then
        return false
    end
    rider = nil
    last_seat = nil
    riding.unseat(pid)
    mob.set_ground_damping(GROUND_DAMPING)
    mob.set_air_damping(AIR_DAMPING)
    body:set_gravity_scale(1)
    afloat_ridden = false
    ride_speed, ride_side = 0, 0
    show_tack()
    if not stay and player.get_entity(pid) and player.get_entity(pid) ~= 0 then
        local p = exit_spot()
        player.set_vel(pid, 0, 0, 0)
        player.set_pos(pid, p[1], p[2], p[3])
    end
    set_state("idle", 3)
    return true
end

function get_rider()
    return rider
end

-- m/s along the heading and the heading (tests)
function get_ride()
    return ride_speed, ride_yaw
end

-- stamina, its full value and whether the horse is winded (nil: no riding)
function get_stamina()
    if not stamina_def then
        return nil
    end
    return stamina(), stamina_def.max, winded
end

function set_stamina_to(value)
    set_stamina(value)
end

-- leash -------------------------------------------------------------------------

function can_leash()
    return species.leash ~= nil and state ~= "fly"
end

local function hold_by(new_holder)
    holder = new_holder
    SAVED_DATA.leash = new_holder
    leash.register(uid, new_holder)
    holder_missing = 0
    if state == "flee" or state == "chase" then
        prey = nil
        set_state("idle", 1)
    end
end

function leash_to(pid)
    hold_by({pid = pid})
end

function tie_to(x, y, z)
    hold_by({post = {x, y, z}})
    set_state("idle", 2)
end

-- let go: the rope is taken off (the caller gives the lasso back)
function unleash()
    rope_off(false)
end

function get_leash()
    return holder
end

-- the end of the rope at the animal: the halter, following the head
local leash_bone = species.leash and rig:index(species.leash.bone)
local body_bone = rig:index("body")

function rope_point()
    local l = species.leash
    local p = l.point
    if leash_bone then
        p = mat4.mul(rig:get_matrix(leash_bone), p)
    end
    p = vec3.add(p, l.offset)
    if body_bone then
        p = mat4.mul(rig:get_matrix(body_bone), p)
    end
    local s = tsf:get_size()
    p = mat4.mul(tsf:get_rot(), {p[1] * s[1], p[2] * s[2], p[3] * s[3]})
    return vec3.add(tsf:get_pos(), p)
end

-- read-only views for tests and debugging
function get_state()
    return state, prey
end

function get_variant()
    return SAVED_DATA.variant
end

function get_species()
    return species_name
end

function get_temper()
    return species.temper
end

function is_baby()
    return young()
end

function get_age()
    return SAVED_DATA.age
end

function is_sheared()
    return SAVED_DATA.sheared == true
end

-- seconds since the last meal and drink (farm animals)
function get_needs()
    return SAVED_DATA.hunger, SAVED_DATA.thirst
end

function set_needs(hunger, thirst)
    SAVED_DATA.hunger = hunger or SAVED_DATA.hunger
    SAVED_DATA.thirst = thirst or SAVED_DATA.thirst
end

function get_cooldown()
    return SAVED_DATA.breed_cooldown
end

-- tests: look around now
function check_now()
    check_timer = 0
end

function in_love()
    return love > 0
end

function end_love()
    love = 0
    if breed then
        SAVED_DATA.breed_cooldown = breed.cooldown
    end
end

-- tests: skips the lamb's growing up (nil) or makes it a lamb of that age
function set_age(age)
    if age == nil then
        if young() then
            grow_up()
        end
    else
        SAVED_DATA.age = age
        tsf:set_size({breed.baby_scale, breed.baby_scale, breed.baby_scale})
    end
end

-- the use button on the animal: a knife shears it, its breeding food makes
-- it look for a mate (or a lamb grow)
function on_used(pid)
    -- the lasso has just caught or let go of it
    if leash.consume_click(pid, uid) or rider then
        return
    end
    local invid, slot = player.get_inventory(pid)
    local itemid, count = inventory.get(invid, slot)
    if ride then
        local name = itemid ~= 0 and item.name(itemid)
        local e = entities.get(player.get_entity(pid))
        if e and e.rigidbody:is_crouching() then
            -- crouching, an empty hand unsaddles it
            if itemid == 0 then
                take_saddle(pid)
            end
            return
        end
        if name == ride.saddle_item then
            put_saddle(pid)
            return
        end
        if name ~= leash.ITEM and itemid ~= breed_item then
            if SAVED_DATA.saddled then
                mount(pid)
                return
            elseif itemid == 0 and not young() then
                notice.show(pid, "medieval_core.ride.no_saddle")
            end
        end
    end
    if itemid == 0 then
        return
    end
    local props = item.properties and item.properties[itemid]
    local tool = props and props["medieval_core:tool"]
    if tool and tool.type == "knife" then
        shear(pid, invid, slot)
    elseif itemid == breed_item then
        if feed() and not player.is_infinite_items(pid) then
            inventory.set(invid, slot, count > 1 and itemid or 0, count - 1)
        end
    end
end

-- animation (client) ---------------------------------------------------------

local tracks = {}
local weights = {walk = 0, trot = 0, gallop = 0, idle = 0, air = 0, fly = 0, eat = 0}
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

-- 0 below a, 1 above b, smooth between
local function smooth(v, a, b)
    local t = math.max(0, math.min(1, (v - a) / (b - a)))
    return t * t * (3 - 2 * t)
end

-- gait cycles per second at this speed (species.stride)
local function stride_at(speed)
    local curve = species.stride
    for i = 2, #curve do
        local a, b = curve[i - 1], curve[i]
        if speed <= b[1] then
            return a[2] + (b[2] - a[2]) * (speed - a[1]) / (b[1] - a[1])
        end
    end
    return curve[#curve][2]
end

-- shares of walk, trot and gallop at this speed (species.gaits)
local function gait_mix(speed)
    local g = species.gaits
    if not g then
        return 1, 0, 0
    end
    local gallop = smooth(speed, g.trot - 0.6, g.trot + 0.6)
    local trot = smooth(speed, g.walk - 0.5, g.walk + 0.5) * (1 - gallop)
    return 1 - trot - gallop, trot, gallop
end

-- hooves on the ground: the step sound of the block under the animal at
-- every footfall of the leading gait
local HOOF_RANGE = 24
local HOOF_VOLUME = {walk = 0.22, trot = 0.35, gallop = 0.5}

local function hoofbeats(from, to, mix, speed)
    if not species.hooves or speed < 0.4 or not body:is_grounded() or not gfx or not hud then
        return
    end
    local pos = tsf:get_pos()
    local x, y, z = player.get_pos(hud.get_player())
    if vec3.distance(pos, {x, y, z}) > HOOF_RANGE then
        return
    end
    local gait = "walk"
    if mix.gallop >= mix.trot and mix.gallop >= mix.walk then
        gait = "gallop"
    elseif mix.trot >= mix.walk then
        gait = "trot"
    end
    local feet = pos[2] - body_size()[2] * 0.5
    for _, f in ipairs(species.hooves[gait]) do
        if math.floor(from - f) ~= math.floor(to - f) then
            local id = block.get(math.floor(pos[1]), math.floor(feet - 0.05), math.floor(pos[3]))
            local mat = id > 0 and block.materials[block.material(id)]
            if mat and mat.stepsSound and mat.stepsSound ~= "" then
                audio.play_sound(mat.stepsSound, pos[1], feet, pos[3], HOOF_VOLUME[gait],
                    0.62 + math.random() * 0.1, "regular")
            end
        end
    end
end

local DRAW_DISTANCE = species.draw_distance or lod.DRAW_DISTANCE
local hidden = false
local view_timer = math.random() * lod.CHECK_EVERY

function on_render(delta)
    -- not drawn far from the camera, not posed while resting
    view_timer = view_timer - delta
    if view_timer <= 0 then
        view_timer = lod.CHECK_EVERY
        local hide = lod.view_distance(tsf:get_pos()) > DRAW_DISTANCE
        if hide ~= hidden then
            hidden = hide
            rig:set_visible(not hide)
        end
    end
    if hidden or frozen then
        return
    end
    local vel = body:get_vel()
    -- a ridden horse: how fast it really goes (its velocity is set every
    -- frame, also when it runs into a wall)
    local speed = rider and moved_speed or vec2.length({vel[1], vel[3]})
    local grounded = body:is_grounded()
    local flying = state == "fly"
    local walk_k, trot_k, gallop_k = gait_mix(speed)
    local moving = flying and 0 or math.min(1, speed / (species.gaits and 1.2 or 2.5))

    weights.walk = approach(weights.walk, moving * walk_k, delta * 8)
    weights.trot = approach(weights.trot, moving * trot_k, delta * 6)
    weights.gallop = approach(weights.gallop, moving * gallop_k, delta * 6)
    -- at a trough the species without an eating animation graze or peck
    local resting = state == "idle" or (state == "eat" and not species.tracks.eat)
    weights.idle = approach(weights.idle, (resting and speed < 0.3) and 1 or 0, delta * 3)
    -- a horse goes down a step without the jump pose
    local in_air = not grounded and not flying and (not species.gaits or math.abs(vel[2]) > 1.5)
    weights.air = approach(weights.air, in_air and 1 or 0, delta * 10)
    weights.fly = approach(weights.fly, flying and 1 or 0, delta * 6)
    weights.eat = approach(weights.eat, state == "eat" and 1 or 0, delta * 5)
    local prev_phase = gait_phase
    if species.stride then
        gait_phase = gait_phase + stride_at(speed) * delta
    else
        gait_phase = gait_phase + speed * species.gait * delta
    end
    idle_time = idle_time + delta
    hoofbeats(prev_phase, gait_phase, weights, speed)

    -- out of the camera view the gaits and the steps go on, the pose is
    -- not needed (the engine marks it before on_render; older engines
    -- have no is_culled)
    local culled = rig.is_culled ~= nil and rig:is_culled()
    if not culled then
        rig:reset_pose()
        apply("walk", gait_phase, weights.walk)
        apply("trot", gait_phase, weights.trot)
        apply("gallop", gait_phase, weights.gallop)
        apply("idle", idle_time, weights.idle)
        apply("air", idle_time, weights.air)
        apply("fly", idle_time, weights.fly)
        apply("eat", idle_time, weights.eat)
    end
    if ride then
        -- over a jump: the nose up while rising, down when coming down
        if not culled and weights.air > 0.01 and body_bone then
            local pitch = math.max(-14, math.min(14, vel[2] * 2.2)) * weights.air
            rig:set_matrix(body_bone, mat4.mul(rig:get_matrix(body_bone), mat4.rotate({1, 0, 0}, pitch)))
        end
        -- the rider rises and falls with the back (the same curves as the
        -- body bone in mw_horse_trot / mw_horse_gallop)
        local tau = math.pi * 2
        rider_bob = -ride.bob.trot * weights.trot * math.cos((gait_phase - 0.21) * tau * 2)
            + ride.bob.gallop * weights.gallop * math.cos((gait_phase - 0.87) * tau)
    end
    if attack_anim > 0 then
        attack_anim = math.max(0, attack_anim - delta)
        if not culled then
            apply("attack", 1 - attack_anim / ATTACK_ANIM, 1)
        end
    end

    if hurt_timer > 0 then
        hurt_timer = hurt_timer - delta
        rig:set_color(hurt_timer > 0 and {1, 0.45, 0.45} or {1, 1, 1})
    end
end
