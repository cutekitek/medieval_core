-- A projectile (a thrown spear or an arrow): flies along a ballistic arc
-- pointing where it goes, hurts the first creature in its way (bouncing off
-- it), sticks into the first solid block and can then be picked up (use
-- button or walking over it).
-- The body is static: the flight is integrated here every frame, with a
-- ray between frames so a fast projectile cannot skip through a target.
local flow = require "medieval_core:water/flow"
local stats = require "medieval_core:survival/stats"

local tsf = entity.transform
local body = entity.rigidbody

local GRAVITY = 17
local WATER_DRAG = 2.5
local PICKUP_DISTANCE = 1.4
local OWNER_GRACE = 0.25     -- the shooter can't be hit right after the shot
local MAX_FLIGHT = 30

local KINDS = {
    spear = {
        half = 0.92,              -- from the middle to the tip
        embed = 0.3,              -- how deep the tip goes in
        drag = 0.12,              -- share of speed lost per second
        damage = {3, 9},          -- at rest .. at full speed
        full_speed = 28,
        knockback = 0.6,
        hit_block = "spear_hit_block", hit_block_pitch = 1.0,
        keeps_wear = true,        -- comes back with its uses
        break_on_hit = 0,         -- chance to break on a creature
        break_on_block = 0,
    },
    arrow = {
        half = 0.38,
        embed = 0.14,
        drag = 0.05,
        damage = {2, 7},
        full_speed = 55,
        knockback = 0.3,
        hit_block = "arrow_hit", hit_block_pitch = 1.0,
        keeps_wear = false,
        break_on_hit = 0.35,
        break_on_block = 0.15,
    },
}

local args = ARGS or {}
kind = SAVED_DATA.kind or args.kind or "spear"
local K = KINDS[kind] or KINDS.spear
local HALF = K.half
local EMBED = K.embed
local AIR_DRAG = K.drag
state = SAVED_DATA.state or "flying"
vel = SAVED_DATA.vel or args.vel or {0, 0, 0}
uses = SAVED_DATA.uses or args.uses or 1
item_name = SAVED_DATA.item or args.item or "medieval_core:stone_spear"
power = args.power or SAVED_DATA.power or 1
local owner = args.owner
local age = 0
local hit = {}               -- entities already hurt by this throw

body:set_body_type("static")

local function cross(a, b)
    return {a[2] * b[3] - a[3] * b[2], a[3] * b[1] - a[1] * b[3], a[1] * b[2] - a[2] * b[1]}
end

-- rotation whose -z axis points along dir
local function facing(dir)
    local f = vec3.normalize(dir)
    local up = math.abs(f[2]) > 0.98 and {1, 0, 0} or {0, 1, 0}
    local r = vec3.normalize(cross(f, up))
    local u = cross(r, f)
    return {
        r[1], r[2], r[3], 0,
        u[1], u[2], u[3], 0,
        -f[1], -f[2], -f[3], 0,
        0, 0, 0, 1,
    }
end

local function sound(name, volume, pitch)
    if gfx then
        local p = tsf:get_pos()
        audio.play_sound("medieval_core/" .. name, p[1], p[2], p[3], volume, pitch or (0.9 + math.random() * 0.2),
            "regular")
    end
end

local function shatter()
    local p = tsf:get_pos()
    if gfx then
        gfx.particles.emit(p, 14, {
            texture = "blocks:mw_bark_chip",
            lifetime = 0.9, spawn_interval = 0.0001, explosion = {3, 3, 3},
            size = {0.07, 0.07, 0.07},
        })
    end
    sound(K.hit_block, 0.8, 0.7 * K.hit_block_pitch)
    entity:despawn()
end

local function stick(point, dir)
    if (K.keeps_wear and uses <= 0) or math.random() < K.break_on_block then
        shatter()
        return
    end
    local f = vec3.normalize(dir)
    tsf:set_pos(vec3.sub(point, vec3.mul(f, HALF - EMBED)))
    tsf:set_rot(facing(f))
    vel = {0, 0, 0}
    state = "stuck"
    if gfx then
        gfx.particles.emit(point, 8, {
            texture = "blocks:mw_bark_chip",
            lifetime = 0.6, spawn_interval = 0.0001, explosion = {1.5, 2, 1.5},
            size = {0.05, 0.05, 0.05},
        })
    end
    sound(K.hit_block, 0.5 + 0.4 * power, K.hit_block_pitch * (0.9 + math.random() * 0.2))
end

local function hurt(uid, from)
    local e = entities.get(uid)
    if not e then
        return
    end
    hit[uid] = true
    local speed = vec3.length(vel)
    local d = K.damage
    local damage = math.floor(d[1] + (d[2] - d[1]) * math.min(1, speed / K.full_speed) + 0.5)
    local pid = e:get_player()
    if pid and pid ~= -1 then
        stats.damage(pid, damage)
    else
        local animal = e:get_component("medieval_core:animal") or e:get_component("medieval_core:fish")
        if animal and animal.damage then
            animal.damage(damage, from, owner, K.knockback)
        end
    end
    sound("spear_hit", 0.8, kind == "arrow" and 1.3 or 1.0)
    if math.random() < K.break_on_hit then
        shatter()
        return
    end
    -- it glances off and falls
    vel = {vel[1] * -0.12, math.max(2, math.abs(vel[2]) * 0.2), vel[3] * -0.12}
end

-- the first thing a ray from a to b runs into: solid block or creature
local function sweep(a, b)
    local d = vec3.sub(b, a)
    local len = vec3.length(d)
    if len < 1e-5 then
        return nil
    end
    local dir = vec3.mul(d, 1 / len)
    local start = a
    local left = len
    for _ = 1, 6 do
        local r = world.raycast({start = start, dir = dir, distance = left, ignore_uid = entity:get_uid()})
        if not r then
            return nil
        end
        if r.entity then
            local e = entities.get(r.entity)
            local is_owner = e and owner and e:get_player() == owner and age < OWNER_GRACE
            if e and not hit[r.entity] and not is_owner then
                return {entity = r.entity, point = r.endpoint, dir = dir}
            end
        elseif r.block then
            local p = r.iendpoint
            if not block.is_replaceable_at(p[1], p[2], p[3]) then
                return {block = r.block, point = r.endpoint, dir = dir}
            end
        else
            return nil
        end
        -- passes through grass, its owner or an animal already hit
        local step = r.length + 0.05
        start = vec3.add(start, vec3.mul(dir, step))
        left = left - step
        if left <= 0 then
            return nil
        end
    end
    return nil
end

local function fly(dt)
    age = age + dt
    local pos = tsf:get_pos()
    local f = vec3.length(vel) > 1e-4 and vec3.normalize(vel) or {0, -1, 0}
    local tip = vec3.add(pos, vec3.mul(f, HALF))
    -- integrate
    local drag = flow.in_water(tip[1], tip[2], tip[3]) and WATER_DRAG or AIR_DRAG
    vel = vec3.mul(vel, math.max(0, 1 - drag * dt))
    vel[2] = vel[2] - GRAVITY * dt
    local step = vec3.mul(vel, dt)
    local new_pos = vec3.add(pos, step)
    local nf = vec3.length(vel) > 1e-4 and vec3.normalize(vel) or f
    local new_tip = vec3.add(new_pos, vec3.mul(nf, HALF))
    local h = sweep(tip, new_tip)
    if h and h.entity then
        hurt(h.entity, tip)
        if not entities.exists(entity:get_uid()) then
            return
        end
        tsf:set_pos(vec3.sub(h.point, vec3.mul(nf, HALF + 0.05)))
        return
    elseif h and h.block then
        stick(h.point, nf)
        return
    end
    tsf:set_pos(new_pos)
    tsf:set_rot(facing(nf))
    if age > MAX_FLIGHT or new_pos[2] < -64 then
        entity:despawn()
    end
end

-- picking up: back into the inventory (a spear with its wear)
function pick_up(pid)
    if state ~= "stuck" then
        return false
    end
    local invid = player.get_inventory(pid)
    local id = item.index(item_name)
    if K.keeps_wear then
        local slot = inventory.find_by_item(invid, 0)
        if not slot then
            return false
        end
        inventory.set(invid, slot, id, 1)
        inventory.set_data(invid, slot, "uses", uses)
    elseif inventory.add(invid, id, 1) > 0 then
        return false
    end
    if gfx then
        audio.play_sound_2d("events/pickup", 0.5, 0.8)
    end
    entity:despawn()
    return true
end

function on_used(pid)
    pick_up(pid)
end

function on_physics_update(delta)
    if state == "flying" then
        -- long frames are split so the arc stays smooth
        local n = math.max(1, math.ceil(delta / 0.02))
        for _ = 1, n do
            if state ~= "flying" or not entities.exists(entity:get_uid()) then
                break
            end
            fly(delta / n)
        end
    end
end

function on_update(tps)
    if state ~= "stuck" then
        return
    end
    -- walking over a stuck projectile picks it up
    local p = tsf:get_pos()
    for _, pid in ipairs(player.get_all()) do
        local x, y, z = player.get_pos(pid)
        local dx, dy, dz = x - p[1], y + 0.5 - p[2], z - p[3]
        if dx * dx + dy * dy + dz * dz < PICKUP_DISTANCE * PICKUP_DISTANCE and pick_up(pid) then
            return
        end
    end
end

function on_save()
    SAVED_DATA.state = state
    SAVED_DATA.vel = vel
    SAVED_DATA.uses = uses
    SAVED_DATA.item = item_name
    SAVED_DATA.power = power
    SAVED_DATA.kind = kind
end

-- a fresh throw faces its flight from the first frame
if state == "flying" and vec3.length(vel) > 1e-4 then
    tsf:set_rot(facing(vel))
end
