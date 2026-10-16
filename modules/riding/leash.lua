-- The lasso: a rope from an animal to the player who leads it or to a
-- fence post it is tied to. The animal keeps its end (SAVED_DATA.leash =
-- {pid = n} or {post = {x, y, z}}, components/animal.lua) and registers it
-- here, so a player's or a post's animals can be found. The rope itself is
-- drawn by the lasso_rope entity (components/lasso_rope.lua).
local base_util = require "base:util"

local this = {}

this.ITEM = "medieval_core:lasso"
this.LENGTH = 5.0       -- m of rope: the animal is held this close
this.BREAK = 14.0       -- pulled further than this, the rope slips off
this.FOLLOW = 3.0       -- a led animal walks after its holder beyond this
this.THROW = 10.0       -- m the loop is thrown
this.FENCE_TAG = "medieval_core:fence"

local holders = {}      -- animal uid -> {pid = n} | {post = {x, y, z}}
local clicked = {}      -- pid -> {uid, time}: the animal the lasso just caught

function this.register(uid, holder)
    holders[uid] = holder
end

function this.unregister(uid)
    holders[uid] = nil
end

function this.holder(uid)
    return holders[uid]
end

local function animal(uid)
    local e = entities.get(uid)
    return e and e:get_component("medieval_core:animal")
end

-- uids of the animals a player leads
function this.led_by(pid)
    local list = {}
    for uid, h in pairs(holders) do
        if h.pid == pid and animal(uid) then
            table.insert(list, uid)
        end
    end
    table.sort(list)
    return list
end

-- uids of the animals tied to a post
function this.tied_at(x, y, z)
    local list = {}
    for uid, h in pairs(holders) do
        local p = h.post
        if p and p[1] == x and p[2] == y and p[3] == z and animal(uid) then
            table.insert(list, uid)
        end
    end
    table.sort(list)
    return list
end

function this.is_post(x, y, z)
    local id = block.get(x, y, z)
    return id > 0 and block.has_tag(id, this.FENCE_TAG)
end

-- where the rope ends at the post: wound round its top
function this.post_point(p)
    return {p[1] + 0.5, p[2] + 0.82, p[3] + 0.5}
end

-- the held end: in the right hand (in first person a little below and to
-- the right of the eyes), nil if the player is gone
function this.hand_point(pid)
    if not player.get_entity(pid) or player.get_entity(pid) == 0 then
        return nil
    end
    local x, y, z = player.get_pos(pid)
    if hud and pid == hud.get_player() then
        local cam = cameras.get("core:first-person")
        if player.get_camera(pid) == cam:get_index() then
            local p, f, r, u = cam:get_pos(), cam:get_front(), cam:get_right(), cam:get_up()
            return {p[1] + f[1] * 0.5 + r[1] * 0.28 - u[1] * 0.3,
                    p[2] + f[2] * 0.5 + r[2] * 0.28 - u[2] * 0.3,
                    p[3] + f[3] * 0.5 + r[3] * 0.28 - u[3] * 0.3}
        end
    end
    local yaw = math.rad((player.get_rot(pid)))
    local fx, fz = -math.sin(yaw), -math.cos(yaw)
    return {x + fx * 0.25 - fz * 0.3, y + 0.05, z + fz * 0.25 + fx * 0.3}
end

-- the holder's end of the rope (nil: the holder is gone)
function this.anchor(holder)
    if holder.post then
        return this.post_point(holder.post)
    end
    return this.hand_point(holder.pid)
end

-- one lasso from the hand (not in creative)
function this.take_lasso(pid)
    if player.is_infinite_items(pid) then
        return true
    end
    local invid, slot = player.get_inventory(pid)
    local itemid, count = inventory.get(invid, slot)
    if itemid == 0 or item.name(itemid) ~= this.ITEM then
        return false
    end
    inventory.set(invid, slot, count > 1 and itemid or 0, count - 1)
    return true
end

-- a lasso back into the player's inventory (dropped at pos if it is
-- full or there is no player)
function this.give_lasso(pid, pos)
    local id = item.index(this.ITEM)
    if pid then
        if player.is_infinite_items(pid) then
            return
        end
        if inventory.add(player.get_inventory(pid), id, 1) == 0 then
            return
        end
    end
    local e = base_util.drop(pos, id, 1)
    if e then
        e.rigidbody:set_vel({math.random() - 0.5, 2.5, math.random() - 0.5})
    end
end

-- the animal component on_used skips the click that the lasso has just
-- handled (the engine calls the item first, then the entity)
function this.mark_click(pid, uid)
    clicked[pid] = {uid = uid, time = time.uptime()}
end

function this.consume_click(pid, uid)
    local c = clicked[pid]
    if c and c.uid == uid and c.time == time.uptime() then
        clicked[pid] = nil
        return true
    end
    return false
end

-- the animal the player aims at within the throw (blocks stop the loop)
function this.aimed_animal(pid)
    local x, y, z = player.get_pos(pid)
    local eye = {x, y + 0.7, z}
    local dir = player.get_dir(pid)
    local hit = entities.raycast(eye, dir, this.THROW, player.get_entity(pid))
    if not hit or not hit.entity then
        return nil
    end
    local e = entities.get(hit.entity)
    local ai = e and e:get_component("medieval_core:animal")
    if ai and ai.can_leash() then
        return e, ai
    end
    return nil
end

-- The lasso in hand, the use button: a free animal is caught (one lasso
-- used), an animal tied to a post is taken from it, one led by this player
-- is let go (the lasso is back). Returns true if anything happened.
function this.use_lasso(pid)
    local e, ai = this.aimed_animal(pid)
    if not e then
        return false
    end
    local uid = e:get_uid()
    local h = holders[uid]
    local pos = e.transform:get_pos()
    if h and h.pid == pid then
        ai.unleash()
        this.give_lasso(pid, pos)
    elseif h then
        ai.leash_to(pid)
    elseif this.take_lasso(pid) then
        ai.leash_to(pid)
        local x, y, z = player.get_pos(pid)
        audio.play_sound("medieval_core/rod_cast", x, y + 0.7, z, 0.8, 0.8 + math.random() * 0.15, "regular")
    else
        return false
    end
    this.mark_click(pid, uid)
    return true
end

-- The use button on a fence: the animals the player leads are tied to it;
-- leading none, the ones tied there are taken. Returns true if any.
function this.use_post(pid, x, y, z)
    if not this.is_post(x, y, z) then
        return false
    end
    local led = this.led_by(pid)
    if #led > 0 then
        for _, uid in ipairs(led) do
            animal(uid).tie_to(x, y, z)
        end
        audio.play_sound("medieval_core/line_pull", x + 0.5, y + 0.8, z + 0.5, 0.7, 0.9, "regular")
        return true
    end
    local tied = this.tied_at(x, y, z)
    for _, uid in ipairs(tied) do
        animal(uid).leash_to(pid)
    end
    return #tied > 0
end

function this.reset()
    holders = {}
    clicked = {}
end

return this
