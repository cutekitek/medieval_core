-- Chests. While a chest window is open its lid swings up: the block switches
-- to the variant without the lid (mw_chest_open) and the lid becomes an entity
-- (medieval_core:chest_lid) turning on the hinge. When the window closes the lid
-- swings down, then the block gets its lid back and the entity goes away.
local base_util = require "base:util"

local this = {}

local OPEN_VARIANT = 1
-- the hinge in block coordinates: back top edge of the body (local -Z)
local HINGE_Y = 0.625
local HINGE_BACK = 0.4375
local SOUND_PITCH = 1.3

-- "x,y,z" -> lid entity uid
this.lids = {}

local function key(x, y, z)
    return x .. "," .. y .. "," .. z
end

local function lid_of(x, y, z)
    local uid = this.lids[key(x, y, z)]
    local e = uid and entities.get(uid)
    if not e then
        this.lids[key(x, y, z)] = nil
        return nil
    end
    return e:get_component("medieval_core:chest_lid")
end

function this.is_chest(x, y, z)
    return block.get(x, y, z) == block.index("medieval_core:chest")
end

-- yaw of the chest's local frame (pane rotation: local -Z faces N, W, S, E)
function this.yaw(x, y, z)
    return (block.get_rotation(x, y, z) % 4) * 90
end

function this.hinge(x, y, z)
    local r = math.rad(this.yaw(x, y, z))
    return {x + 0.5 - HINGE_BACK * math.sin(r), y + HINGE_Y, z + 0.5 - HINGE_BACK * math.cos(r)}
end

local function sound(name, x, y, z)
    audio.play_sound("medieval_core/" .. name, x + 0.5, y + 0.5, z + 0.5, 0.6,
        SOUND_PITCH + math.random() * 0.1, "regular")
end

function this.open(x, y, z)
    if not this.is_chest(x, y, z) then
        return
    end
    local lid = lid_of(x, y, z)
    if lid then
        lid.set_open(true)
    else
        local e = entities.spawn("medieval_core:chest_lid", this.hinge(x, y, z), {
            medieval_core__chest_lid = {x = x, y = y, z = z, yaw = this.yaw(x, y, z)}
        })
        this.lids[key(x, y, z)] = e:get_uid()
        block.set_variant(x, y, z, OPEN_VARIANT)
    end
    sound("gate_open", x, y, z)
end

function this.close(x, y, z)
    local lid = lid_of(x, y, z)
    if lid then
        lid.set_open(false)
        sound("gate_close", x, y, z)
    end
end

-- the lid came down: the block shows its own lid again
function this.closed(x, y, z, uid)
    if this.lids[key(x, y, z)] == uid then
        this.lids[key(x, y, z)] = nil
    end
    if this.is_chest(x, y, z) and block.get_variant(x, y, z) == OPEN_VARIANT then
        block.set_variant(x, y, z, 0)
    end
end

function this.is_open(x, y, z)
    local lid = lid_of(x, y, z)
    return lid ~= nil and lid.is_open()
end

function this.lid_angle(x, y, z)
    local lid = lid_of(x, y, z)
    return lid and lid.get_angle() or 0
end

-- the chest is gone (broken, replaced)
function this.forget(x, y, z)
    local uid = this.lids[key(x, y, z)]
    this.lids[key(x, y, z)] = nil
    local e = uid and entities.get(uid)
    if e then
        e:despawn()
    end
end

-- loaded without its lid entity (e.g. saved while open): close it
function this.present(x, y, z)
    if block.get_variant(x, y, z) == OPEN_VARIANT and not lid_of(x, y, z) then
        block.set_variant(x, y, z, 0)
    end
end

-- throws out everything stored in the block (before it is broken: the
-- engine deletes a block's inventory together with the block)
function this.spill(x, y, z)
    local invid = inventory.get_block(x, y, z)
    if not invid or invid == 0 then
        return 0
    end
    local n = 0
    for slot = 0, inventory.size(invid) - 1 do
        local id, count = inventory.get(invid, slot)
        if id ~= 0 then
            local data = inventory.get_all_data(invid, slot)
            if data and next(data) == nil then
                data = nil
            end
            local e = base_util.drop({x + 0.5, y + 0.5, z + 0.5}, id, count, data)
            if e then
                e.rigidbody:set_vel(vec3.spherical_rand(2.0))
            end
            inventory.set(invid, slot, 0, 0)
            n = n + count
        end
    end
    return n
end

function this.reset()
    this.lids = {}
end

return this
