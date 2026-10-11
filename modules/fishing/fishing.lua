-- Fishing with a rod: the use button casts the float (medieval_core:bobber);
-- with the float out, holding the button pulls it back. Fish swimming close
-- may notice a float that rests on the water, swim up and take the hook
-- (scripts/components/fish.lua); a hooked fish thrashes about and is pulled
-- in while the button is held, now and then it slips off. Pulled close to
-- the player (or onto the bank) it is caught.
local this = {}

this.ROD = "medieval_core:fishing_rod"
this.CAST_SPEED = 12.0
this.REEL_SPEED = 3.0          -- float pulled towards the player, m/s
this.FISH_PULL = 2.4           -- the same for a hooked fish
this.CATCH_DISTANCE = 1.9      -- horizontal, from the player
this.MAX_LINE = 26
this.NOTICE_RADIUS = 6.0
this.NOTICE_CHANCE = 0.08      -- per second for a fish near a resting float
this.SETTLE_TIME = 1.5         -- the float must rest this long to be noticed
this.BITE_CHANCE = 0.75        -- a fish that swam up takes the hook
this.ESCAPE_CHANCE = 0.035     -- per second of pulling
this.SLACK_TIME = 12.0         -- a hooked fish left alone this long gets free
this.ROD_TIP = {0, 0, -1.55}   -- dev/gen_boat_assets.py
local PRESS_GAP = 0.3          -- longer gaps between uses: a new press
local HOLD_GAP = 0.25

local rods = {}       -- pid -> {bobber uid, press, cast_press, last, reel_until}
this.bobbers = {}     -- bobber uid -> {pos, state, owner, fish, interest, since}

local function rod_of(pid)
    local r = rods[pid]
    if not r then
        r = {press = 0}
        rods[pid] = r
    end
    return r
end

function this.holds_rod(pid)
    local invid, slot = player.get_inventory(pid)
    local itemid = inventory.get(invid, slot)
    return itemid ~= 0 and item.name(itemid) == this.ROD
end

local function bobber_of(pid)
    local r = rods[pid]
    local e = r and r.bobber and entities.get(r.bobber)
    if not e then
        if r then
            r.bobber = nil
        end
        return nil
    end
    return e
end

function this.eye(pid)
    local x, y, z = player.get_pos(pid)
    return {x, y + 0.7, z}
end

local function cast(pid)
    local r = rod_of(pid)
    local eye = this.eye(pid)
    local dir = {player.get_dir(pid)}
    if type(dir[1]) == "table" then
        dir = dir[1]
    end
    local start = vec3.add(eye, vec3.mul(dir, 0.8))
    local e = entities.spawn("medieval_core:bobber", start, {medieval_core__bobber = {owner = pid}})
    if not e then
        return
    end
    local vel = vec3.mul(dir, this.CAST_SPEED)
    vel[2] = vel[2] + 3.0
    e.rigidbody:set_vel(vel)
    r.bobber = e:get_uid()
    r.cast_press = r.press
    audio.play_sound("medieval_core/rod_cast", eye[1], eye[2], eye[3], 0.8, 0.9 + math.random() * 0.2, "regular")
end

-- the use button with a rod in hand (repeats while held)
function this.use(pid)
    local now = time.uptime()
    local r = rod_of(pid)
    if not r.last or now - r.last > PRESS_GAP then
        r.press = r.press + 1
    end
    r.last = now
    if not bobber_of(pid) then
        if r.cast_press ~= r.press and r.retrieved_press ~= r.press then
            cast(pid)
        end
        return true
    end
    if r.cast_press ~= r.press then
        r.reel_until = now + HOLD_GAP
    end
    return true
end

-- the button state from the client every frame: letting go stops pulling
function this.update_local(pid, held)
    local r = rods[pid]
    if r and not held then
        r.reel_until = 0
    end
end

function this.reeling(pid)
    local r = rods[pid]
    return r ~= nil and (r.reel_until or 0) > time.uptime()
end

-- the float came back (or the line was cut)
function this.retrieved(pid)
    local r = rods[pid]
    if r then
        r.bobber = nil
        r.retrieved_press = r.press
    end
end

function this.bobber_uid(pid)
    local e = bobber_of(pid)
    return e and e:get_uid()
end

-- gives the caught fish to the player (or drops it at the feet)
function this.catch(pid, fish)
    local x, y, z = player.get_pos(pid)
    local itemid = item.index("medieval_core:raw_fish")
    local invid = player.get_inventory(pid)
    local left = inventory.add(invid, itemid, 1)
    if left and left > 0 then
        local base_util = require "base:util"
        base_util.drop({x, y, z}, itemid, left)
    end
    if fish then
        fish:despawn()
    end
    audio.play_sound("medieval_core/fish_struggle", x, y, z, 0.8, 1.1, "regular")
    this.caught = (this.caught or 0) + 1
end

-- rings on the water (entity medieval_core:ripple)
function this.ripple(x, y, z, size)
    entities.spawn("medieval_core:ripple", {x, y + 0.03, z}, {medieval_core__ripple = {size = size or 1.6}})
end

-- First-person position of the rod tip (world), or nil when not in first
-- person; `m` is the hand matrix set by the hand controller.
this.hand_matrix = nil

function this.rod_tip(pid)
    if hud and pid == hud.get_player() and this.hand_matrix then
        local cam = cameras.get("core:first-person")
        if player.get_camera(pid) == cam:get_index() then
            return vec3.add(cam:get_pos(), mat4.mul(this.hand_matrix, this.ROD_TIP))
        end
    end
    -- third person and other players: above the right hand
    local x, y, z = player.get_pos(pid)
    local yaw = math.rad((player.get_rot(pid)))
    local fx, fz = -math.sin(yaw), -math.cos(yaw)
    return {x + fx * 1.0 - fz * 0.3, y + 1.2, z + fz * 1.0 + fx * 0.3}
end

-- first-person pose of a held rod (camera space), nil if no rod in hand
local POSE = {pos = {0.055, -0.045, -0.09}, pitch = 28, yaw = 10, roll = -8}
local SCALE = {0.03, 0.03, 0.03}

function this.first_person(pid)
    if not this.holds_rod(pid) then
        this.hand_matrix = nil
        return nil
    end
    local pitch = POSE.pitch
    local e = bobber_of(pid)
    if this.reeling(pid) then
        pitch = pitch + 14
        local b = e and this.bobbers[e:get_uid()]
        if b and b.fish then
            -- a fish on: the rod jerks
            local w = time.uptime() * 23
            pitch = pitch + math.sin(w) * 3
        end
    end
    local rot = cameras.get("core:first-person"):get_rot()
    local m = mat4.translate(mat4.idt(), mat4.mul(rot, POSE.pos))
    mat4.mul(m, rot, m)
    mat4.rotate(m, {0, 1, 0}, POSE.yaw, m)
    mat4.rotate(m, {1, 0, 0}, pitch, m)
    mat4.rotate(m, {0, 0, 1}, POSE.roll, m)
    mat4.scale(m, SCALE, m)
    this.hand_matrix = m
    return m, "mw_fishing_rod_item"
end

function this.reset()
    rods = {}
    this.bobbers = {}
    this.hand_matrix = nil
end

return this
