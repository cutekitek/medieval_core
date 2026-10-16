-- Survival hooks on the player entity: fall damage and swimming
local stats = require "survival/stats"
local mode = require "survival/mode"
local flow = require "water/flow"
local ranged_pose = require "combat/ranged_pose"
local sleep = require "player/sleep"
local shapes = require "building/shapes"
local boat = require "boat/boat"
local riding = require "riding/riding"

local tsf = entity.transform
local body = entity.rigidbody

-- landing speed (m/s) that is still safe and damage per extra m/s
local FALL_SAFE_SPEED = 13.0
local FALL_DAMAGE_PER_SPEED = 0.7

-- swimming
local SWIM_GRAVITY = 0.3      -- slow sinking
local SWIM_DAMPING = 16.0     -- core:mob uses 10: swimming is ~60% of walking
local WADE_DAMPING = 13.0     -- only the feet in water
local SWIM_UP = 4.0           -- m/s with jump held under water
local SWIM_DOWN = -4.0        -- m/s with crouch held
local SURFACE_UP = 1.0        -- keeps the head above the surface
local CLIMB_OUT = 7.0         -- jump out of the water onto a bank
local EYE_HEIGHT = 0.7

-- ladders
local LADDER_UP = 3.0         -- m/s with jump or forward held
local LADDER_DOWN = -2.2      -- sliding down, nothing held
local LADDER_STEP = 0.6       -- metres climbed per creak of a rung

-- read by tests and the HUD: "dry", "wading", "swimming", "diving"
water_state = "dry"
-- read by tests: the player holds on to a ladder
on_ladder = false
-- tests (no keyboard in headless mode) set {jump = bool, crouch = bool,
-- forward = bool}
input_override = nil

local climb_timer = 0
local ladder_climbed = 0

local function feet_y()
    return tsf:get_pos()[2] - body:get_size()[2] * 0.5
end

function on_grounded(force)
    local pid = entity:get_player()
    if pid == -1 or not mode.enabled() or player.is_flight(pid) then
        return
    end
    local pos = tsf:get_pos()
    -- water breaks the fall
    if flow.in_water(pos[1], feet_y() + 0.1, pos[3]) then
        return
    end
    if force > FALL_SAFE_SPEED then
        stats.damage(pid, math.floor((force - FALL_SAFE_SPEED) * FALL_DAMAGE_PER_SPEED + 0.5))
    end
end

local function approach(value, goal, k)
    return value + (goal - value) * math.min(1, k)
end

-- a bank in front of the player at the water surface
local function bank_ahead(pid, pos)
    local dir = player.get_dir(pid)
    local len = math.sqrt(dir[1] * dir[1] + dir[3] * dir[3])
    if len < 1e-3 then
        return false
    end
    local x = math.floor(pos[1] + dir[1] / len * 0.8)
    local z = math.floor(pos[3] + dir[3] / len * 0.8)
    local y = math.floor(feet_y() + 0.2)
    return block.is_solid_at(x, y, z) and not block.is_solid_at(x, y + 1, z)
end

local function controls(pid)
    if input_override then
        return input_override.jump, input_override.crouch, input_override.forward
    end
    if not vc.is_client() or not hud or pid ~= hud.get_player() or
       hud.is_inventory_open() or menu.page ~= "" then
        return false, false, false
    end
    return input.is_active("movement.jump"), input.is_active("movement.crouch"),
        input.is_active("movement.forward")
end

-- On a ladder (in the cell of the feet or the body): no gravity; jump or
-- forward climbs, crouch holds on, otherwise the player slides down slowly
-- (which also stops a fall). Returns true while climbing.
local function climb(pid, pos, delta)
    local feet = feet_y()
    if not shapes.is_ladder_at(pos[1], feet + 0.1, pos[3]) and
       not shapes.is_ladder_at(pos[1], feet + 0.9, pos[3]) then
        on_ladder = false
        return false
    end
    if not on_ladder then
        ladder_climbed = 0
    end
    on_ladder = true
    body:set_gravity_scale(0)
    local jump, crouch, forward = controls(pid)
    local vel = body:get_vel()
    if jump or forward then
        vel[2] = LADDER_UP
    elseif crouch then
        vel[2] = 0
    else
        vel[2] = LADDER_DOWN
    end
    body:set_vel(vel)
    -- a rung creaks every step up or down
    ladder_climbed = ladder_climbed + math.abs(vel[2]) * delta
    if ladder_climbed >= LADDER_STEP then
        ladder_climbed = 0
        audio.play_sound("medieval_core/ladder", pos[1], feet + 0.2, pos[3], 0.6,
            0.9 + math.random() * 0.2, "regular")
    end
    return true
end

-- runs after core:mob and core:player, so the water settings win
function on_physics_update(delta)
    local pid = entity:get_player()
    if pid == -1 or player.is_flight(pid) or player.is_noclip(pid) or boat.seated_in(pid) or
       riding.seated_in(pid) then
        water_state = "dry"
        on_ladder = false
        return
    end
    -- jumping out onto a bank: plain physics for a moment
    if climb_timer > 0 then
        climb_timer = climb_timer - delta
        return
    end
    local pos = tsf:get_pos()
    if climb(pid, pos, delta) then
        water_state = "dry"
        return
    end
    local feet = feet_y()
    local wet_feet = flow.in_water(pos[1], feet + 0.1, pos[3])
    local wet_body = flow.in_water(pos[1], feet + 0.8, pos[3])
    local wet_eyes = flow.in_water(pos[1], pos[2] + EYE_HEIGHT, pos[3])
    if not wet_feet and not wet_body then
        water_state = "dry"
        return
    end
    if not wet_body then
        water_state = "wading"
        body:set_linear_damping(WADE_DAMPING)
        return
    end
    water_state = wet_eyes and "diving" or "swimming"
    body:set_gravity_scale(SWIM_GRAVITY)
    body:set_vdamping(true)
    body:set_linear_damping(SWIM_DAMPING)

    local jump, crouch = controls(pid)
    local vel = body:get_vel()
    local k = delta * 10
    if jump then
        if not wet_eyes and bank_ahead(pid, pos) then
            vel[2] = math.max(vel[2], CLIMB_OUT)
            climb_timer = 0.35
        elseif wet_eyes then
            vel[2] = approach(vel[2], SWIM_UP, k)
        else
            vel[2] = approach(vel[2], SURFACE_UP, k)
        end
    elseif crouch then
        vel[2] = approach(vel[2], SWIM_DOWN, k)
    end
    body:set_vel(vel)
end

-- third person: a held spear or bow is posed (and wound up) on the
-- model's item bone; base:player_animator only sets the bone when the item
-- changes
local rig = entity.skeleton
local item_bone = rig:index("item")
local body_bone = rig:index("body")

-- lying on the back in bed: the body turned flat (the head towards the
-- pillow, the entity faces the foot of the bed), nothing in hand
-- (the body model is 0.14 thick: it rests on the blanket; core:mob turns
-- the head every frame, here it lies face up, sunk into the pillow)
local LIE = mat4.mul(mat4.translate({0, -0.24, 0}), mat4.rotate({1, 0, 0}, 90))
local HEAD_LIE = mat4.translate({0, 0, -0.15})
local head_bone = rig:index("head")
local lying = false

local function pose_sleep(pid)
    local asleep = sleep.is_sleeping(pid)
    if asleep and head_bone then
        rig:set_matrix(head_bone, HEAD_LIE)
    end
    -- the sleeper's own model would stand in the view from the pillow
    local own = asleep and hud and pid == hud.get_player() and not sleep.free_camera
    rig:set_visible(not own)
    if asleep == lying or not body_bone then
        return asleep
    end
    lying = asleep
    rig:set_matrix(body_bone, asleep and LIE or mat4.idt())
    rig:set_visible(item_bone, not asleep)
    return asleep
end

-- in the saddle: the body with the legs astride (models/mw_rider)
local body_model = body_bone and rig:get_model(body_bone)
local astride = false

local function pose_rider(pid)
    local on = riding.seated_in(pid) ~= nil
    if on ~= astride and body_bone then
        astride = on
        rig:set_model(body_bone, on and "mw_rider" or body_model)
    end
end

function on_render(delta)
    local pid = entity:get_player()
    if pid == -1 or not item_bone then
        return
    end
    pose_rider(pid)
    if pose_sleep(pid) then
        return
    end
    local m, model = ranged_pose.third_person(pid)
    if m then
        rig:set_matrix(item_bone, m)
        rig:set_model(item_bone, model)
        weapon_held = true
    elseif weapon_held then
        -- back to how the animator holds other items
        weapon_held = false
        local invid, slot = player.get_inventory(pid)
        rig:set_model(item_bone, item.model_name(inventory.get(invid, slot)))
        rig:set_matrix(item_bone, mat4.rotate({0, 1, 0}, -80))
    end
end
