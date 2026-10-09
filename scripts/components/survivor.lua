-- Survival hooks on the player entity: fall damage and swimming
local stats = require "survival/stats"
local mode = require "survival/mode"
local flow = require "water/flow"

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

-- read by tests and the HUD: "dry", "wading", "swimming", "diving"
water_state = "dry"
-- tests (no keyboard in headless mode) set {jump = bool, crouch = bool}
input_override = nil

local climb_timer = 0

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
        return input_override.jump, input_override.crouch
    end
    if not vc.is_client() or not hud or pid ~= hud.get_player() or
       hud.is_inventory_open() or menu.page ~= "" then
        return false, false
    end
    return input.is_active("movement.jump"), input.is_active("movement.crouch")
end

-- runs after core:mob and core:player, so the water settings win
function on_physics_update(delta)
    local pid = entity:get_player()
    if pid == -1 or player.is_flight(pid) or player.is_noclip(pid) then
        water_state = "dry"
        return
    end
    -- jumping out onto a bank: plain physics for a moment
    if climb_timer > 0 then
        climb_timer = climb_timer - delta
        return
    end
    local pos = tsf:get_pos()
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
