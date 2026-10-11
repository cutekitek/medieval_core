-- Wild animal: wanders, grazes, follows a player holding its favourite
-- food, runs from danger, fights (bears), flies (birds), drops loot on death.
-- Sheep also crop grass, grow wool back and are shorn with a knife. Farm
-- animals (species with `breed`) get hungry and thirsty, eat and drink from
-- troughs and breed when fed (husbandry/husbandry). Species data and
-- tempers: fauna/species.
local species_list = require "fauna/species"
local base_util = require "base:util"
local stats = require "survival/stats"
local mode = require "survival/mode"
local flow = require "water/flow"
local husbandry = require "husbandry/husbandry"
local trough = require "husbandry/trough"

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

local function set_state(name, duration, new_target)
    state = name
    state_timer = duration
    target = new_target
    if name ~= "trough" and name ~= "eat" then
        visit = nil
    end
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
    local r = species.wander_radius
    local parent = young() and nearest_adult(16)
    if parent then
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
    local spot = {(pos[1] + mpos[1]) * 0.5, math.max(pos[2], mpos[2]), (pos[3] + mpos[3]) * 0.5}
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
    think(dt)
    lay_egg(dt)
    tick_life(dt)
    tick_voice(dt)
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
            -- fences and gates hold animals in: no jumping onto them
            local under = block.get(waypoint[1], waypoint[2] - 1, waypoint[3])
            if under > 0 and (block.has_tag(under, FENCE_TAG) or block.has_tag(under, GATE_TAG)) then
                return
            end
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
    local invid, slot = player.get_inventory(pid)
    local itemid, count = inventory.get(invid, slot)
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
local weights = {walk = 0, idle = 0, air = 0, fly = 0, eat = 0}
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
    -- at a trough the species without an eating animation graze or peck
    local resting = state == "idle" or (state == "eat" and not species.tracks.eat)
    weights.idle = approach(weights.idle, (resting and speed < 0.3) and 1 or 0, delta * 3)
    weights.air = approach(weights.air, (grounded or flying) and 0 or 1, delta * 10)
    weights.fly = approach(weights.fly, flying and 1 or 0, delta * 6)
    weights.eat = approach(weights.eat, state == "eat" and 1 or 0, delta * 5)
    gait_phase = gait_phase + speed * species.gait * delta
    idle_time = idle_time + delta

    rig:reset_pose()
    apply("walk", gait_phase, weights.walk)
    apply("idle", idle_time, weights.idle)
    apply("air", idle_time, weights.air)
    apply("fly", idle_time, weights.fly)
    apply("eat", idle_time, weights.eat)
    if attack_anim > 0 then
        attack_anim = math.max(0, attack_anim - delta)
        apply("attack", 1 - attack_anim / ATTACK_ANIM, 1)
    end

    if hurt_timer > 0 then
        hurt_timer = hurt_timer - delta
        rig:set_color(hurt_timer > 0 and {1, 0.45, 0.45} or {1, 1, 1})
    end
end
