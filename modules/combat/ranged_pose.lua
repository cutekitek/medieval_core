-- How a held ranged weapon is posed: in first person (the 'hand' skeleton,
-- see hud.hand_controller in scripts/hud.lua) and on the player model in
-- third person (its 'item' bone, see the survivor component).
--   spear: rests low pointing ahead; the wind-up lifts it over the shoulder
--          and draws it back, at full power it trembles.
--   bow:   rests tilted low; drawing raises it upright in front of the eye,
--          an arrow is nocked and the string comes back (the bow model is
--          swapped for one of three draw stages), at full draw it trembles.
local ranged = require "combat/ranged"

local this = {}

-- first person: camera space (x right, y up, -z forward), metres/degrees;
-- the stock item sits at 0.06, -0.035, -0.1
-- third person: the item bone of the player model
local POSES = {
    spear = {
        fp_idle = {pos = {0.05, -0.046, -0.085}, pitch = 12, yaw = 10, roll = -10},
        fp_charged = {pos = {0.046, 0.002, -0.048}, pitch = 3, yaw = 7, roll = -30},
        -- thinner across: close to the eye the shaft would look like a log
        fp_scale = {0.032, 0.032, 0.045},
        fp_tremble = 0.0025,
        tp_idle = {pos = {0, -0.05, 0}, pitch = 72, roll = 0},
        tp_charged = {pos = {-0.02, 0.5, 0.3}, pitch = 8, roll = 25},
        tp_scale = 0.75,
        tp_tremble = 0.012,
    },
    bow = {
        fp_idle = {pos = {0.045, -0.036, -0.095}, pitch = 6, yaw = 22, roll = -38},
        -- the arrow points at the crosshair from just below and left
        fp_charged = {pos = {-0.002, -0.01, -0.115}, pitch = 1, yaw = 5, roll = -12},
        fp_scale = {0.028, 0.028, 0.028},
        fp_tremble = 0.0012,
        tp_idle = {pos = {0, -0.12, 0.02}, pitch = 0, yaw = 80, roll = -15},
        tp_charged = {pos = {-0.24, 0.45, -0.3}, pitch = 0, yaw = 0, roll = -8},
        tp_scale = 0.55,
        tp_tremble = 0.006,
        stages = {"mw_bow_drawn_1", "mw_bow_drawn_2", "mw_bow_drawn_3"},
    },
}

local function lerp(a, b, t)
    return a + (b - a) * t
end

local function smooth(t)
    return t * t * (3 - 2 * t)
end

local function blend(a, b, t)
    return {
        pos = {lerp(a.pos[1], b.pos[1], t), lerp(a.pos[2], b.pos[2], t), lerp(a.pos[3], b.pos[3], t)},
        pitch = lerp(a.pitch, b.pitch, t),
        yaw = lerp(a.yaw or 0, b.yaw or 0, t),
        roll = lerp(a.roll, b.roll, t),
    }
end

-- the weapon in hand, its pose set and the wind-up 0..1 (nil if none)
local function current(pid)
    local invid, slot = player.get_inventory(pid)
    local itemid = inventory.get(invid, slot)
    local weapon = ranged.weapon_of(itemid)
    if not weapon then
        return nil
    end
    local phase, t = ranged.phase(pid)
    local power = phase == "charging" and t or nil
    return weapon, POSES[weapon.kind], power, itemid
end

-- pose of the wind-up: idle .. fully drawn, trembling at the end
local function wind_up(idle, charged, power, tremble)
    if not power then
        return idle
    end
    local pose = blend(idle, charged, smooth(math.min(1, power * 1.6)))
    if power >= 1 then
        local w = time.uptime() * 40
        pose.pos[1] = pose.pos[1] + math.sin(w) * tremble
        pose.pos[2] = pose.pos[2] + math.cos(w * 1.3) * tremble
    end
    return pose
end

-- the model for a bow: drawn stages while drawing
local function model_of(p, power, itemid)
    if p.stages and power then
        local i = math.min(#p.stages, 1 + math.floor(power * #p.stages))
        return p.stages[i]
    end
    return item.model_name(itemid)
end

local function apply(m, pose, scale)
    mat4.rotate(m, {0, 1, 0}, pose.yaw or 0, m)
    mat4.rotate(m, {1, 0, 0}, pose.pitch, m)
    mat4.rotate(m, {0, 0, 1}, pose.roll, m)
    if type(scale) == "number" then
        scale = {scale, scale, scale}
    end
    mat4.scale(m, scale, m)
    return m
end

-- First-person matrix and model of the hand item for a ranged weapon,
-- or nil (then the default controller is used).
function this.first_person(pid)
    local weapon, p, power, itemid = current(pid)
    if not weapon then
        return nil
    end
    local pose = wind_up(p.fp_idle, p.fp_charged, power, p.fp_tremble)
    -- the hand skeleton lives in camera space, oriented like the world
    local rot = cameras.get("core:first-person"):get_rot()
    local m = mat4.translate(mat4.idt(), mat4.mul(rot, pose.pos))
    mat4.mul(m, rot, m)
    return apply(m, pose, p.fp_scale), model_of(p, power, itemid)
end

-- Item bone matrix and model of the player model holding a ranged weapon,
-- or nil.
function this.third_person(pid)
    local weapon, p, power, itemid = current(pid)
    if not weapon then
        return nil
    end
    local pose = wind_up(p.tp_idle, p.tp_charged, power, p.tp_tremble)
    local m = mat4.translate(mat4.idt(), pose.pos)
    return apply(m, pose, p.tp_scale), model_of(p, power, itemid)
end

return this
