-- Who sits in or carries which dugout, the walking speed while doing it and
-- the rower's controls. The boat itself: scripts/components/dugout.lua.
local this = {}

this.WALK_SPEED = 27.0        -- core:mob default
this.JUMP_FORCE = 8.0         -- medieval_core:player
this.CARRY_SPEED = 0.45       -- share of the walking speed with a boat on the shoulders
this.CARRY_JUMP = 0.7
this.PADDLE = "medieval_core:paddle"

local seated = {}       -- pid -> boat entity uid
local carrying = {}     -- pid -> boat entity uid

-- tests drive the rower with this: {forward, back, left, right, leave}
this.input_override = nil

local function mob_of(pid)
    local e = entities.get(player.get_entity(pid))
    return e and e:get_component("core:mob")
end

local function set_pace(pid, speed_k, jump_k)
    local mob = mob_of(pid)
    if mob then
        mob.set_movement_speed(this.WALK_SPEED * speed_k)
        mob.set_jump_force(this.JUMP_FORCE * jump_k)
    end
end

function this.seat(pid, uid)
    seated[pid] = uid
    carrying[pid] = nil
    set_pace(pid, 0, 0)
end

function this.unseat(pid)
    seated[pid] = nil
    set_pace(pid, 1, 1)
end

function this.carry(pid, uid)
    carrying[pid] = uid
    seated[pid] = nil
    set_pace(pid, this.CARRY_SPEED, this.CARRY_JUMP)
end

function this.uncarry(pid)
    carrying[pid] = nil
    set_pace(pid, 1, 1)
end

function this.seated_in(pid)
    return seated[pid]
end

function this.carried_by(pid)
    return carrying[pid]
end

local function boat_component(uid)
    local e = uid and entities.get(uid)
    return e and e:get_component("medieval_core:dugout")
end

-- the use button pressed (hud callback): a carried boat is put down
function this.on_build(pid)
    local ai = boat_component(carrying[pid])
    if ai then
        ai.put_down(pid)
        return true
    end
    return false
end

function this.holds_paddle(pid)
    local invid, slot = player.get_inventory(pid)
    local itemid = inventory.get(invid, slot)
    return itemid ~= 0 and item.name(itemid) == this.PADDLE
end

-- forward, back, left, right, leave
function this.controls(pid)
    local o = this.input_override
    if o then
        return o.forward, o.back, o.left, o.right, o.leave
    end
    if not hud or pid ~= hud.get_player() or hud.is_inventory_open() or hud.is_paused() then
        return false, false, false, false, false
    end
    return input.is_active("movement.forward"), input.is_active("movement.back"),
        input.is_active("movement.left"), input.is_active("movement.right"),
        input.is_active("movement.crouch")
end

-- every player tick: forget boats that are gone and give the normal pace
-- back (the slowed speed is saved with the player and outlives a reload)
function this.tick(pid)
    if seated[pid] and not boat_component(seated[pid]) then
        this.unseat(pid)
    end
    if carrying[pid] and not boat_component(carrying[pid]) then
        this.uncarry(pid)
    end
    if not seated[pid] and not carrying[pid] then
        local mob = mob_of(pid)
        if mob and mob.get_movement_speed() < this.WALK_SPEED * 0.99 then
            set_pace(pid, 1, 1)
        end
    end
end

function this.reset()
    seated = {}
    carrying = {}
    this.input_override = nil
end

return this
