-- Ranged weapons: throwing spears and bows. Holding the use button winds
-- up or draws (the engine repeats the item's use every ~0.16 s while it is
-- held), letting it go throws or shoots; the longer the wind-up (up to the
-- weapon's charge time) the faster the projectile flies.
-- Projectiles are entities (scripts/components/projectile.lua).
-- Per-player phases drive the hand animations (modules/combat/ranged_pose.lua).
local this = {}

this.RELEASE_GAP = 0.3     -- no use for this long means the button was let go
this.THROW_TIME = 0.35     -- follow-through after the release
this.EYE_HEIGHT = 0.7

-- weapon item -> how it works
this.WEAPONS = {
    ["medieval_core:stone_spear"] = {
        kind = "spear",
        charge = 0.9,          -- seconds to full power
        min_charge = 0.3,      -- shorter presses do not throw
        speed = {11, 28},      -- m/s at no and at full power
        projectile = "medieval_core:thrown_spear",
        sound = "spear_throw",
        side = 0.2,            -- leaves the hand a little to the right
    },
    ["medieval_core:bow"] = {
        kind = "bow",
        charge = 1.0,
        min_charge = 0.25,
        speed = {20, 55},
        projectile = "medieval_core:flying_arrow",
        ammo = "medieval_core:arrow",
        sound = "bow_shoot",
        draw_sound = "bow_draw",
        side = 0.05,
    },
}

local states = {}  -- pid -> {phase = "charging"|"throwing", start, last, released, weapon}

-- scripts (showcases) can hold the button for a player: pid -> true
this.scripted_hold = {}

function this.weapon_of(itemid)
    return itemid ~= 0 and this.WEAPONS[item.name(itemid)] or nil
end

local function held(pid)
    local invid, slot = player.get_inventory(pid)
    return invid, slot, inventory.get(invid, slot)
end

-- the slot holding ammo for a weapon, or nil
local function ammo_slot(pid, weapon)
    if not weapon.ammo then
        return nil
    end
    local invid = player.get_inventory(pid)
    return inventory.find_by_item(invid, item.index(weapon.ammo))
end

function this.has_ammo(pid, weapon)
    return not weapon.ammo or player.is_infinite_items(pid) or ammo_slot(pid, weapon) ~= nil
end

local function play(name, pid, volume, pitch)
    if not gfx or not name then
        return
    end
    local x, y, z = player.get_pos(pid)
    audio.play_sound("medieval_core/" .. name, x, y + this.EYE_HEIGHT, z, volume, pitch or 1.0, "regular")
end

-- one repeated use while the button is held
function this.charge(pid)
    local _, _, itemid = held(pid)
    local weapon = this.weapon_of(itemid)
    if not weapon or not this.has_ammo(pid, weapon) then
        return false
    end
    local now = time.uptime()
    local s = states[pid]
    if not s or s.phase ~= "charging" or s.weapon ~= weapon then
        states[pid] = {phase = "charging", start = now, last = now, weapon = weapon}
        play(weapon.draw_sound, pid, 0.6, 0.95 + math.random() * 0.1)
    else
        s.last = now
    end
    return true
end

-- 0..1 wind-up of a charging player
function this.power(pid, now)
    local s = states[pid]
    if not s or s.phase ~= "charging" then
        return 0
    end
    return math.min(1, ((now or time.uptime()) - s.start) / s.weapon.charge)
end

-- what the hand animations show: phase, its progress 0..1, the weapon
function this.phase(pid)
    local s = states[pid]
    if not s then
        return nil, 0
    end
    local now = time.uptime()
    if s.phase == "charging" then
        return "charging", this.power(pid, now), s.weapon
    end
    local t = (now - s.released) / this.THROW_TIME
    if t >= 1 then
        states[pid] = nil
        return nil, 0
    end
    return "throwing", t, s.weapon
end

local function right_of(dir)
    local r = {-dir[3], 0, dir[1]}
    local len = math.sqrt(r[1] * r[1] + r[3] * r[3])
    if len < 1e-4 then
        return {1, 0, 0}
    end
    return {r[1] / len, 0, r[3] / len}
end

-- Throws the held spear or shoots an arrow with the given power (0..1);
-- returns the projectile entity.
function this.throw(pid, power)
    local invid, slot, itemid = held(pid)
    local weapon = this.weapon_of(itemid)
    if not weapon or not this.has_ammo(pid, weapon) then
        return nil
    end
    local infinite = player.is_infinite_items(pid)
    local x, y, z = player.get_pos(pid)
    local dir = player.get_dir(pid)
    local right = right_of(dir)
    local start = {x + dir[1] * 0.9 + right[1] * weapon.side, y + this.EYE_HEIGHT + dir[2] * 0.9 - 0.05,
                   z + dir[3] * 0.9 + right[3] * weapon.side}
    local speed = weapon.speed[1] + (weapon.speed[2] - weapon.speed[1]) * power
    local pvx, pvy, pvz = player.get_vel(pid)
    local vel = {dir[1] * speed + pvx * 0.5, dir[2] * speed + pvy * 0.3, dir[3] * speed + pvz * 0.5}
    local args = {vel = vel, owner = pid, power = power, kind = weapon.ammo and "arrow" or weapon.kind}
    if weapon.ammo then
        -- an arrow leaves the quiver, the bow wears
        args.item = weapon.ammo
        if not infinite then
            inventory.decrement(invid, ammo_slot(pid, weapon), 1)
            inventory.use(invid, slot)
        end
    else
        -- the weapon itself flies
        args.item = item.name(itemid)
        args.uses = (inventory.get_data(invid, slot, "uses") or item.uses(itemid)) - 1
        if not infinite then
            inventory.set(invid, slot, 0, 0)
        end
    end
    local e = entities.spawn(weapon.projectile, start, {medieval_core__projectile = args})
    play(weapon.sound, pid, 0.4 + 0.5 * power, 0.9 + power * 0.3)
    return e
end

-- the button was let go: throw or shoot if wound up enough
function this.release(pid, now)
    local s = states[pid]
    if not s or s.phase ~= "charging" then
        return nil
    end
    now = now or time.uptime()
    if now - s.start < s.weapon.min_charge then
        states[pid] = nil
        return nil
    end
    local e = this.throw(pid, this.power(pid, now))
    states[pid] = {phase = "throwing", released = now, weapon = s.weapon}
    return e
end

-- called every frame by the local player's HUD with the button state
function this.update_local(pid, button_held)
    local s = states[pid]
    if s and s.phase == "charging" then
        local _, _, itemid = held(pid)
        if this.weapon_of(itemid) ~= s.weapon then
            states[pid] = nil   -- switched to another item
        elseif not button_held and not this.scripted_hold[pid] then
            this.release(pid)
        end
    end
end

-- fallback for players without a HUD (tests, other players): a pause in
-- the repeated uses is the release
function this.tick()
    local now = time.uptime()
    for pid, s in pairs(states) do
        if s.phase == "charging" and now - s.last > this.RELEASE_GAP then
            this.release(pid, s.last + 0.16)
        end
    end
end

function this.reset()
    states = {}
end

return this
