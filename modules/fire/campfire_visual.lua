-- Campfire looks and sounds: flame, spark and smoke particles and a looped
-- crackling over a lit fire, and the roasting skewers (non-saved static
-- entities) with the food on them.
-- Particles and sounds only exist on a client (gfx); skewers are spawned
-- everywhere.
local this = {}

local FLAMES = {
    frames = {"blocks:mw_flame_0", "blocks:mw_flame_1", "blocks:mw_flame_2",
              "blocks:mw_flame_3", "blocks:mw_flame_4", "blocks:mw_flame_5"},
    lighting = false,
    collision = false,
    max_distance = 64,
    spawn_interval = 0.02,
    lifetime = 0.6,
    lifetime_spread = 0.35,
    velocity = {0, 0.7, 0},
    acceleration = {0, 1.2, 0},
    explosion = {0.12, 0.1, 0.12},
    size = {0.42, 0.6, 0.42},
    size_spread = 0.5,
    spawn_shape = "box",
    spawn_spread = {0.14, 0.02, 0.14},
    spawn_offset = {0, -0.32, 0},
    global_up_vector = true,
}

local SPARKS = {
    texture = "blocks:mw_spark",
    lighting = false,
    collision = false,
    max_distance = 48,
    spawn_interval = 0.18,
    lifetime = 1.3,
    lifetime_spread = 0.5,
    velocity = {0, 1.4, 0},
    acceleration = {0, 0.2, 0},
    explosion = {0.7, 0.5, 0.7},
    size = {0.035, 0.035, 0.035},
    size_spread = 0.5,
    spawn_shape = "box",
    spawn_spread = {0.15, 0.05, 0.15},
    spawn_offset = {0, -0.2, 0},
}

local SMOKE = {
    frames = {"blocks:mw_smoke_0", "blocks:mw_smoke_1", "blocks:mw_smoke_2",
              "blocks:mw_smoke_3", "blocks:mw_smoke_4", "blocks:mw_smoke_5"},
    collision = false,
    max_distance = 96,
    spawn_interval = 0.2,
    lifetime = 3.5,
    lifetime_spread = 0.3,
    velocity = {0, 0.9, 0},
    acceleration = {0.06, 0.05, 0.03},
    explosion = {0.18, 0.05, 0.18},
    size = {0.55, 0.55, 0.55},
    size_spread = 0.4,
    angle_spread = 1.0,
    min_angular_vel = 0.1,
    max_angular_vel = 0.6,
    spawn_shape = "box",
    spawn_spread = {0.1, 0.0, 0.1},
    spawn_offset = {0, 0.45, 0},
}

-- the drill makes a thin wisp from the tinder, denser as it gets hotter
local WISP = {
    frames = {"blocks:mw_smoke_0", "blocks:mw_smoke_2", "blocks:mw_smoke_4", "blocks:mw_smoke_5"},
    collision = false,
    max_distance = 32,
    spawn_interval = 0.02,
    lifetime = 1.6,
    velocity = {0, 0.5, 0},
    acceleration = {0, 0.2, 0},
    explosion = {0.08, 0.02, 0.08},
    size = {0.22, 0.22, 0.22},
    size_spread = 0.4,
    spawn_offset = {0, -0.38, 0},
}

-- skewers stand at the corners and lean towards the fire
local SKEWER_RADIUS = 0.43
local SKEWER_TILT = 16
local SKEWER_YAWS = {45, 225, 135, 315}

local fires = {}  -- "x,y,z" -> {emitters, loop (speaker), skewers = {[slot] = {uid, item}}}

-- sounds (sounds/medieval_core/*.wav, made by dev/gen_fire_sounds.py)
local LOOP_VOLUME = 0.8
local HEAR_DISTANCE = 20   -- the loop fades out over this distance

local function sound(name, x, y, z, volume, pitch, loop)
    if not gfx then
        return 0
    end
    return audio.play_sound("medieval_core/" .. name, x + 0.5, y + 0.4, z + 0.5,
        volume, pitch or (0.92 + math.random() * 0.16), "regular", loop or false)
end

local function key(x, y, z)
    return x .. "," .. y .. "," .. z
end

local function stop_emitters(f)
    if f.emitters and gfx then
        for _, e in ipairs(f.emitters) do
            gfx.particles.stop(e)
        end
    end
    if f.loop and f.loop ~= 0 then
        audio.stop(f.loop)
    end
    f.emitters = nil
    f.loop = nil
end

local function despawn(uid)
    local e = entities and entities.get(uid)
    if e then
        e:despawn()
    end
end

-- skewered food: which bone of mw_campfire_food shows it and its surface
local FOOD_LOOKS = {
    ["medieval_core:raw_beef"] = {"beef", "raw"},
    ["medieval_core:cooked_beef"] = {"beef", "cooked"},
    ["medieval_core:raw_meat"] = {"meat", "raw"},
    ["medieval_core:cooked_meat"] = {"meat", "cooked"},
    ["medieval_core:raw_chicken"] = {"chicken", "raw"},
    ["medieval_core:cooked_chicken"] = {"chicken", "cooked"},
    ["medieval_core:raw_game"] = {"game", "raw"},
    ["medieval_core:cooked_game"] = {"game", "cooked"},
    ["medieval_core:raw_fish"] = {"game", "raw"},
    ["medieval_core:cooked_fish"] = {"game", "cooked"},
}
local FOOD_BONES = {"beef", "meat", "chicken", "game"}

local function dress_skewer(e, name)
    local look = FOOD_LOOKS[name] or {"meat", "cooked"}
    local rig = e.skeleton
    for _, bone in ipairs(FOOD_BONES) do
        local index = rig:index(bone)
        if index then
            rig:set_visible(index, bone == look[1])
        end
    end
    rig:set_texture("$flesh", "blocks:mw_roast_" .. look[1] .. "_" .. look[2])
end

local function place_skewer(x, y, z, slot, name)
    local yaw = SKEWER_YAWS[slot]
    local a = math.rad(yaw)
    local pos = {x + 0.5 + math.cos(a) * SKEWER_RADIUS, y, z + 0.5 + math.sin(a) * SKEWER_RADIUS}
    local e = entities.spawn("medieval_core:campfire_food", pos)
    if not e then
        return nil
    end
    -- face the fire: local -z ... turn so the top leans inwards
    local m = mat4.rotate({0, 1, 0}, 90 - yaw)
    m = mat4.mul(m, mat4.rotate({1, 0, 0}, -SKEWER_TILT))
    e.transform:set_rot(m)
    dress_skewer(e, name)
    return e:get_uid()
end

-- the pot over the fire: a static entity (frame of forked sticks, the pole,
-- the pot with its liquid and floating bits), bubbles and steam while it boils
local LIQUIDS = {
    water = "blocks:mw_pot_water",
    boiling = "blocks:mw_pot_water_boil",
    broth = "blocks:mw_pot_broth",
    stew = "blocks:mw_pot_stew",
}
local BITS = {veg = "blocks:mw_pot_bit_veg", green = "blocks:mw_pot_bit_green", meat = "blocks:mw_pot_bit_meat"}
local POT_BITS = 6
-- the liquid's surface above the block's bottom
local SURFACE = 1.08

local BUBBLES = {
    texture = "blocks:mw_bubble",
    collision = false,
    max_distance = 32,
    spawn_interval = 0.06,
    lifetime = 0.35,
    lifetime_spread = 0.3,
    velocity = {0, 0.25, 0},
    acceleration = {0, 0.1, 0},
    explosion = {0.05, 0.05, 0.05},
    size = {0.05, 0.05, 0.05},
    size_spread = 0.6,
    spawn_shape = "box",
    spawn_spread = {0.17, 0.0, 0.17},
}

local STEAM = {
    frames = {"blocks:mw_steam_0", "blocks:mw_steam_1", "blocks:mw_steam_2", "blocks:mw_steam_3"},
    collision = false,
    max_distance = 64,
    spawn_interval = 0.3,
    lifetime = 2.2,
    lifetime_spread = 0.3,
    velocity = {0, 0.5, 0},
    acceleration = {0.04, 0.08, 0.02},
    explosion = {0.1, 0.03, 0.1},
    size = {0.26, 0.26, 0.26},
    size_spread = 0.4,
    angle_spread = 1.0,
    spawn_shape = "box",
    spawn_spread = {0.12, 0.0, 0.12},
}

local function dress_pot(e, look)
    local rig = e.skeleton
    local liquid = rig:index("liquid")
    rig:set_visible(liquid, look.liquid ~= nil)
    if look.liquid then
        rig:set_texture("$liquid", LIQUIDS[look.liquid])
    end
    for i = 1, POT_BITS do
        local kind = look.bits[i]
        rig:set_visible(rig:index("bit_" .. i), kind ~= nil)
        if kind then
            rig:set_texture("$bit" .. i, BITS[kind])
        end
    end
end

local function sync_pot(f, x, y, z, pot, lit)
    if not pot then
        if f.pot then
            despawn(f.pot)
            f.pot = nil
        end
        if f.steam and gfx then
            for _, em in ipairs(f.steam) do gfx.particles.stop(em) end
        end
        f.steam = nil
        return
    end
    local cooking = require "fire/cooking_pot"
    local look = cooking.look(pot)
    local e = f.pot and entities.get(f.pot)
    if not e then
        e = entities.spawn("medieval_core:campfire_pot", {x + 0.5, y, z + 0.5})
        f.pot = e and e:get_uid()
    end
    if e then
        dress_pot(e, look)
    end
    local boils = look.boiling and lit
    if boils and not f.steam and gfx then
        local c = {x + 0.5, y + SURFACE, z + 0.5}
        f.steam = {
            gfx.particles.emit(c, -1, BUBBLES),
            gfx.particles.emit({c[1], c[2] + 0.1, c[3]}, -1, STEAM),
        }
    elseif not boils and f.steam then
        if gfx then
            for _, em in ipairs(f.steam) do gfx.particles.stop(em) end
        end
        f.steam = nil
    end
end

-- brings particles and skewers in line with the block and the site state
function this.sync(x, y, z, site)
    local k = key(x, y, z)
    local f = fires[k] or {skewers = {}}
    fires[k] = f
    local campfire = require "fire/campfire"
    local blockid = block.get(x, y, z)
    local lit = campfire.is_lit(blockid)

    if lit and not f.emitters and gfx then
        local c = {x + 0.5, y + 0.5, z + 0.5}
        f.emitters = {
            gfx.particles.emit(c, -1, FLAMES),
            gfx.particles.emit(c, -1, SPARKS),
            gfx.particles.emit(c, -1, SMOKE),
        }
        f.loop = sound("fire_loop", x, y, z, 0, nil, true)
        f.pos = {x + 0.5, y + 0.5, z + 0.5}
        -- fires next to each other should not crackle in unison
        if f.loop ~= 0 then
            audio.set_time(f.loop, math.random() * 7.5)
        end
    elseif not lit then
        stop_emitters(f)
    end

    local holds = campfire.holds_food(blockid)
    for slot = 1, campfire.SLOTS do
        local food = holds and site and site.food[slot]
        local sk = f.skewers[slot]
        if food then
            if not sk then
                local uid = place_skewer(x, y, z, slot, food.item)
                f.skewers[slot] = uid and {uid = uid, item = food.item}
            elseif sk.item ~= food.item then
                local e = entities.get(sk.uid)
                if e then
                    dress_skewer(e, food.item)
                end
                sk.item = food.item
            end
        elseif sk then
            despawn(sk.uid)
            f.skewers[slot] = nil
        end
    end
    sync_pot(f, x, y, z, holds and site and site.pot, lit)
    if not f.emitters and next(f.skewers) == nil and not f.pot then
        fires[k] = nil
    end
end

function this.clear(x, y, z)
    local k = key(x, y, z)
    local f = fires[k]
    if not f then
        return
    end
    stop_emitters(f)
    for _, sk in pairs(f.skewers) do
        despawn(sk.uid)
    end
    sync_pot(f, x, y, z, nil)
    fires[k] = nil
end

-- A fire that is no campfire (a burning pit kiln): flames, sparks and smoke
-- spread over the cell by shape = {spread, offset} (x/z half size, height
-- of the flames above the block's bottom), and the crackling.
function this.kindle(x, y, z, shape)
    local k = key(x, y, z)
    local f = fires[k] or {skewers = {}}
    fires[k] = f
    if f.emitters or not gfx then
        return
    end
    local c = {x + 0.5, y + 0.5, z + 0.5}
    local s, h = shape.spread, shape.offset - 0.5
    f.emitters = {
        gfx.particles.emit(c, -1, FLAMES, {spawn_spread = {s, 0.04, s},
            spawn_offset = {0, h, 0}, spawn_interval = 0.012}),
        gfx.particles.emit(c, -1, SPARKS, {spawn_spread = {s, 0.05, s},
            spawn_offset = {0, h + 0.1, 0}}),
        gfx.particles.emit(c, -1, SMOKE, {spawn_spread = {s * 0.7, 0, s * 0.7},
            spawn_offset = {0, h + 0.7, 0}, spawn_interval = 0.12}),
    }
    f.loop = sound("fire_loop", x, y, z, 0, nil, true)
    f.pos = c
    if f.loop ~= 0 then
        audio.set_time(f.loop, math.random() * 7.5)
    end
end

-- the loops fade with distance from the listener (called every frame)
function this.update_sounds(lx, ly, lz)
    for _, f in pairs(fires) do
        if f.loop and f.loop ~= 0 then
            local dx, dy, dz = f.pos[1] - lx, f.pos[2] - ly, f.pos[3] - lz
            local d = math.sqrt(dx * dx + dy * dy + dz * dz)
            local k = math.max(0, 1 - d / HEAR_DISTANCE)
            audio.set_volume(f.loop, LOOP_VOLUME * k * k)
        end
    end
end

function this.drill_smoke(x, y, z, heat)
    if not gfx then
        return
    end
    gfx.particles.emit({x + 0.5, y + 0.5, z + 0.5}, math.floor(2 + heat * 6), WISP)
    sound("fire_drill", x, y, z, 0.6)
end

function this.ignite(x, y, z)
    sound("fire_ignite", x, y, z, 0.9)
end

function this.burn_out(x, y, z)
    sound("fire_out", x, y, z, 0.7)
end

-- a burst of sparks and crackles when fuel is added
function this.puff(x, y, z)
    if not gfx then
        return
    end
    gfx.particles.emit({x + 0.5, y + 0.5, z + 0.5}, 14, SPARKS,
        {spawn_interval = 0.005, explosion = {1.6, 1.2, 1.6}})
    sound("fire_add", x, y, z, 0.8)
end

-- read-only view for tests
function this.get(x, y, z)
    return fires[key(x, y, z)]
end

return this
