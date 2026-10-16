-- Who rides which horse and the rider's controls. The horse itself (saddle,
-- steering, jumps): scripts/components/animal.lua (species.ride).
local boat = require "boat/boat"

local this = {}

this.SADDLE = "medieval_core:saddle"

local seated = {}       -- pid -> horse entity uid
local jump_held = {}    -- pid -> the jump key was down last frame

-- tests drive the rider with this: {forward, back, left, right, jump,
-- sprint, leave}
this.input_override = nil

local function mob_of(pid)
    local e = entities.get(player.get_entity(pid))
    return e and e:get_component("core:mob")
end

-- the rider's own legs do nothing in the saddle. The rider's body is taken
-- out of the physics there (the horse carries it): near the solid horse a
-- body slows its jumps down. The switch is saved with the player: tick()
-- gives the body back to one loaded on foot.
local function set_pace(pid, k)
    local mob = mob_of(pid)
    if mob then
        mob.set_movement_speed(boat.WALK_SPEED * k)
        mob.set_jump_force(boat.JUMP_FORCE * k)
    end
    local e = entities.get(player.get_entity(pid))
    if e then
        e.rigidbody:set_enabled(k > 0)
    end
end

function this.seat(pid, uid)
    seated[pid] = uid
    jump_held[pid] = true       -- no jump from the key that is still down
    set_pace(pid, 0)
end

function this.unseat(pid)
    seated[pid] = nil
    set_pace(pid, 1)
end

function this.seated_in(pid)
    return seated[pid]
end

local function horse_component(uid)
    local e = uid and entities.get(uid)
    return e and e:get_component("medieval_core:animal")
end

-- the horse a player rides (its animal component), nil when on foot
function this.horse_of(pid)
    return horse_component(seated[pid])
end

function this.holds(pid, name)
    local invid, slot = player.get_inventory(pid)
    local itemid = inventory.get(invid, slot)
    return itemid ~= 0 and item.name(itemid) == name
end

-- forward, back, left, right, jump (just pressed), sprint, leave
function this.controls(pid)
    local o = this.input_override
    local f, b, l, r, j, s, out
    if o then
        f, b, l, r, j, s, out = o.forward, o.back, o.left, o.right, o.jump, o.sprint, o.leave
    elseif not hud or pid ~= hud.get_player() or hud.is_inventory_open() or hud.is_paused() then
        return false, false, false, false, false, false, false
    else
        f, b = input.is_active("movement.forward"), input.is_active("movement.back")
        l, r = input.is_active("movement.left"), input.is_active("movement.right")
        j, s = input.is_active("movement.jump"), input.is_active("movement.sprint")
        out = input.is_active("movement.crouch")
    end
    local pressed = j and not jump_held[pid]
    jump_held[pid] = j
    return f, b, l, r, pressed, s, out
end

-- every player tick: a horse that is gone (killed, unloaded) leaves its
-- rider on foot; a player saved in the saddle gets the body back
function this.tick(pid)
    if seated[pid] and not horse_component(seated[pid]) then
        this.unseat(pid)
    end
    if not seated[pid] then
        local e = entities.get(player.get_entity(pid))
        if e and not e.rigidbody:is_enabled() then
            set_pace(pid, 1)
        end
    end
end

function this.reset()
    seated = {}
    jump_held = {}
    this.input_override = nil
end

return this
