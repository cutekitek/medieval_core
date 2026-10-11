-- Beds and sleeping through the night, as in Minecraft:
--   * using a bed makes it the player's respawn point;
--   * at night the player lies down (no sleeping by day or with a dangerous
--     animal close by); once every player has been asleep for FALL_ASLEEP
--     seconds the night passes: the sun rises and the world calendar
--     (crops, farmland) moves on by the time skipped;
--   * the "leave bed" button, Esc, damage or a broken bed wake the player.
-- The bed block is 1x1x2: its origin is the foot, the second cell (local +Z,
-- turned by the pane rotation) the head.
local stats = require "survival/stats"
local calendar = require "world/calendar"
local notice = require "player/notice"

local this = {}

this.BED = "medieval_core:bed"
this.SLEEP_FROM = 0.77      -- 18:29: from here on it is night enough to sleep
this.SLEEP_UNTIL = 0.23     -- 05:31
this.WAKE_AT = 0.27         -- 6:29, just after sunrise (0.25 is still dusky)
this.FALL_ASLEEP = 5.0      -- seconds in bed before the night may pass
this.MATTRESS = 0.5625      -- height of the bed
this.DANGER_RADIUS = 8      -- no sleep with a hunting animal this close
this.DANGER_HEIGHT = 5
this.SLEEP_SIZE = {0.6, 0.6, 0.6}    -- hitbox while lying
this.STAND_SIZE = {0.6, 1.8, 0.6}

-- foot -> head offset by the bed rotation (pane profile, local +Z)
local HEAD = {[0] = {0, 0, 1}, {1, 0, 0}, {0, 0, -1}, {-1, 0, 0}}

local sleepers = {}     -- pid -> {foot, head, dir, time}

-- showcases: the HUD leaves the camera alone while lying
this.free_camera = false

local function bed_id()
    return block.index(this.BED)
end

-- the bed rotation that puts the head in direction dir (a unit axis vector)
function this.rotation_for(dir)
    for r = 0, 3 do
        if HEAD[r][1] == dir[1] and HEAD[r][3] == dir[3] then
            return r
        end
    end
    return 0
end

-- the horizontal axis the player looks along
local function facing(pid)
    local dir = player.get_dir(pid)
    if math.abs(dir[1]) > math.abs(dir[3]) then
        return {dir[1] > 0 and 1 or -1, 0, 0}
    end
    return {0, 0, dir[3] > 0 and 1 or -1}
end

local function placeable(x, y, z)
    return block.is_replaceable_at(x, y, z) and block.is_solid_at(x, y - 1, z)
end

-- Puts a bed from the player's hand on the clicked block: the foot in front
-- of the player, the head away from them (the engine itself would extend a
-- 1x2 block towards the player). Both cells need firm ground. Returns the
-- foot position or nil.
function this.place_bed(pid, x, y, z, normal)
    local fx, fy, fz = x, y, z
    if not block.is_replaceable_at(x, y, z) then
        fx, fy, fz = x + normal[1], y + normal[2], z + normal[3]
    end
    local dir = facing(pid)
    if not placeable(fx, fy, fz) or not placeable(fx + dir[1], fy, fz + dir[3]) then
        return nil
    end
    local id = bed_id()
    block.place(fx, fy, fz, id, this.rotation_for(dir), pid)
    if block.get(fx, fy, fz) ~= id then
        return nil
    end
    if not player.is_infinite_items(pid) then
        local invid, slot = player.get_inventory(pid)
        local itemid, count = inventory.get(invid, slot)
        inventory.set(invid, slot, count > 1 and itemid or 0, count - 1)
    end
    return {fx, fy, fz}
end

-- any cell of a bed -> foot cell, head cell, direction foot -> head
function this.bed_at(x, y, z)
    if block.get(x, y, z) ~= bed_id() then
        return nil
    end
    local ox, oy, oz = block.seek_origin(x, y, z)
    local d = HEAD[block.get_rotation(ox, oy, oz) % 4]
    return {ox, oy, oz}, {ox + d[1], oy, oz + d[3]}, d
end

function this.is_night(t)
    t = t or world.get_day_time()
    return t >= this.SLEEP_FROM or t < this.SLEEP_UNTIL
end

function this.is_sleeping(pid)
    return sleepers[pid] ~= nil
end

-- {foot, head, dir, time} of a sleeping player
function this.sleeper(pid)
    return sleepers[pid]
end

-- an animal hunting this player or a hostile one near the bed
function this.danger(pid, pos)
    local r = this.DANGER_RADIUS
    for _, uid in ipairs(entities.get_all_in_radius(pos, r * 1.5)) do
        local e = entities.get(uid)
        local ai = e and e:get_component("medieval_core:animal")
        if ai then
            local p = e.transform:get_pos()
            local near = math.abs(p[2] - pos[2]) <= this.DANGER_HEIGHT and
                vec2.length({p[1] - pos[1], p[3] - pos[3]}) <= r
            local state, prey = ai.get_state()
            if near and (ai.get_temper() == "hostile" or (state == "chase" and prey == pid)) then
                return true
            end
        end
    end
    return false
end

local function free(x, y, z)
    return not block.is_solid_at(x, y, z) and not block.is_solid_at(x, y + 1, z)
end

-- where to stand after leaving the bed: next to it on firm ground, or on
-- the bed itself
function this.stand_spot(foot, head)
    local cells = {}
    for _, c in ipairs({foot, head}) do
        for _, d in ipairs({{1, 0}, {-1, 0}, {0, 1}, {0, -1}}) do
            table.insert(cells, {c[1] + d[1], c[3] + d[2]})
        end
    end
    local bed = bed_id()
    for _, dy in ipairs({0, 1, -1}) do
        for _, c in ipairs(cells) do
            local x, y, z = c[1], foot[2] + dy, c[2]
            if block.get(x, y, z) ~= bed and free(x, y, z) and block.is_solid_at(x, y - 1, z) then
                return {x + 0.5, y, z + 0.5}
            end
        end
    end
    return {foot[1] + 0.5, foot[2] + this.MATTRESS, foot[3] + 0.5}
end

-- where a sleeping player lies: the middle of the bed, on the mattress
-- (centre of the small sleeping hitbox)
function this.lie_pos(s)
    return {
        s.foot[1] + 0.5 + s.dir[1] * 0.5,
        s.foot[2] + this.MATTRESS + this.SLEEP_SIZE[2] * 0.5 + 0.01,
        s.foot[3] + 0.5 + s.dir[3] * 0.5,
    }
end

local function set_size(pid, size)
    local e = entities.get(player.get_entity(pid))
    if e then
        e.rigidbody:set_size(size)
    end
end

local function lie_down(pid, foot, head, dir)
    local s = {foot = foot, head = head, dir = dir, time = 0}
    sleepers[pid] = s
    audio.play_sound("medieval_core/bed", foot[1] + 0.5 + dir[1] * 0.5, foot[2] + 0.6,
        foot[3] + 0.5 + dir[3] * 0.5, 0.8, 1.0, "regular")
    set_size(pid, this.SLEEP_SIZE)
    local p = this.lie_pos(s)
    player.set_vel(pid, 0, 0, 0)
    player.set_pos(pid, p[1], p[2], p[3])
    -- facing the foot of the bed: lying on the back, the head is on the pillow
    player.set_rot(pid, math.deg(math.atan2(dir[1], dir[3])), 0, 0)
end

-- Uses a bed: sets the respawn point and lies down at night.
-- Returns the outcome: "sleeping", "not_night", "danger", "occupied",
-- "obstructed" or nil (not a bed); shows it to the player.
function this.use_bed(pid, x, y, z)
    local foot, head, dir = this.bed_at(x, y, z)
    if not foot then
        return nil
    end
    if sleepers[pid] then
        return "sleeping"
    end
    local s = stats.get(pid)
    local moved = not s.bed or s.bed[1] ~= foot[1] or s.bed[2] ~= foot[2] or s.bed[3] ~= foot[3]
    s.bed = foot
    local spawn_note = moved and "medieval_core.bed.spawn_set" or nil
    local result
    if not this.is_night() then
        result = "not_night"
    elseif block.is_solid_at(foot[1], foot[2] + 1, foot[3]) or
           block.is_solid_at(head[1], head[2] + 1, head[3]) then
        result = "obstructed"
    else
        for other, o in pairs(sleepers) do
            if o.foot[1] == foot[1] and o.foot[2] == foot[2] and o.foot[3] == foot[3] then
                result = "occupied"
            end
        end
        if not result and this.danger(pid, {foot[1] + 0.5, foot[2] + 0.5, foot[3] + 0.5}) then
            result = "danger"
        end
    end
    if result then
        notice.show(pid, "medieval_core.bed." .. result, spawn_note)
        return result
    end
    notice.show(pid, spawn_note)
    lie_down(pid, foot, head, dir)
    return "sleeping"
end

-- gets the player out of bed and stands them next to it
function this.wake(pid)
    local s = sleepers[pid]
    if not s then
        return
    end
    sleepers[pid] = nil
    set_size(pid, this.STAND_SIZE)
    local spot = this.stand_spot(s.foot, s.head)
    player.set_vel(pid, 0, 0, 0)
    player.set_pos(pid, spot[1], spot[2] + this.STAND_SIZE[2] * 0.5 + 0.01, spot[3])
end

-- the night passes: sunrise, the calendar moves on, everybody gets up
function this.skip_night()
    local days = (this.WAKE_AT - world.get_day_time()) % 1
    world.set_day_time(this.WAKE_AT)
    calendar.skip(days)
    for pid in pairs(sleepers) do
        this.wake(pid)
    end
    return days
end

-- world tick: keeps sleepers in bed, wakes those whose bed is gone and lets
-- the night pass once all players sleep
function this.tick(dt)
    if next(sleepers) == nil then
        return
    end
    local bed = bed_id()
    for pid, s in pairs(sleepers) do
        if block.get(s.foot[1], s.foot[2], s.foot[3]) ~= bed then
            this.wake(pid)
        else
            s.time = s.time + dt
            local p = this.lie_pos(s)
            local x, y, z = player.get_pos(pid)
            if vec3.distance({x, y, z}, p) > 0.2 then
                player.set_pos(pid, p[1], p[2], p[3])
            end
            player.set_vel(pid, 0, 0, 0)
        end
    end
    if next(sleepers) == nil then
        return
    end
    for _, pid in ipairs(player.get_all()) do
        local s = sleepers[pid]
        if not s or s.time < this.FALL_ASLEEP then
            return
        end
    end
    -- in bed until morning, but with the sun already up there is nothing to skip
    if this.is_night() then
        this.skip_night()
    end
end

-- Where a player respawns: by their bed if it is still there. A missing bed
-- is forgotten (and the player told). Returns x, y, z of the feet or nil.
function this.respawn_point(pid)
    local s = stats.get(pid)
    if not s.bed then
        return nil
    end
    local foot, head = this.bed_at(s.bed[1], s.bed[2], s.bed[3])
    if not foot or foot[1] ~= s.bed[1] or foot[2] ~= s.bed[2] or foot[3] ~= s.bed[3] then
        s.bed = nil
        notice.show(pid, "medieval_core.bed.missing")
        return nil
    end
    local spot = this.stand_spot(foot, head)
    return spot[1], spot[2], spot[3]
end

table.insert(stats.listeners, {
    on_damage = function(pid, amount)
        if amount > 0 then
            this.wake(pid)
        end
    end,
    on_death = function(pid)
        this.wake(pid)
    end,
})

function this.reset()
    sleepers = {}
end

return this
