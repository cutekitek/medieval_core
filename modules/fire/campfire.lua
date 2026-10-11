-- Campfire, built on the ground step by step:
--   loose sticks (1) -> frame of 2, 3, 4 sticks leaning into a teepee
--   -> tinder (plant fibre) -> lit with a bow drill -> burns its fuel
--   -> ashes. Sticks on the ashes start a new teepee.
-- A lit fire takes more sticks and logs as fuel and roasts up to four
-- pieces of food on skewers around it.
-- A clay pot hangs over the fire on a pole to cook stew (fire/cooking_pot).
-- State per fire (fuel, food, pot) lives here and is saved with the world;
-- fires in unloaded chunks are frozen.
local visual = require "fire/campfire_visual"
local cooking = require "fire/cooking_pot"
local notice = require "player/notice"

local this = {}

local SAVE_FILE = "campfires.json"
-- Times in seconds of world time; a game day is 1440 s (calendar.DAY), so
-- a second is a game minute and the numbers are about real-life ones.
this.START_FUEL = 180      -- the teepee and kindling burn about 3 hours
this.MAX_FUEL = 720        -- piled up with logs it lasts a night
this.COOK_TIME = 25        -- meat roasts on a skewer in about 25 minutes
this.DRILL_TIME = 2.4      -- seconds of bow drilling to light the tinder
this.SLOTS = 4

local FUEL = {
    ["medieval_core:stick"] = 20,           -- a stick: 20 minutes
    ["medieval_core:plant_fiber"] = 3,
}
-- logs and planks: items placing a block of wood material
local WOOD_FUEL = 150    -- a log: 2.5 hours

this.COOKED = {
    ["medieval_core:raw_beef"] = "medieval_core:cooked_beef",
    ["medieval_core:raw_meat"] = "medieval_core:cooked_meat",
    ["medieval_core:raw_chicken"] = "medieval_core:cooked_chicken",
    ["medieval_core:raw_game"] = "medieval_core:cooked_game",
    ["medieval_core:raw_mutton"] = "medieval_core:cooked_mutton",
    ["medieval_core:raw_fish"] = "medieval_core:cooked_fish",
}

local STICK = "medieval_core:stick"
local FIBER = "medieval_core:plant_fiber"
local POT = "medieval_core:clay_pot.item"
local PLATE = "medieval_core:clay_plate.item"
local WATER_BUCKET = "medieval_core:water_bucket"
local EMPTY_BUCKET = "medieval_core:wooden_bucket"
local STAGES = {"medieval_core:loose_sticks", "medieval_core:campfire_frame_2",
    "medieval_core:campfire_frame_3", "medieval_core:campfire_frame_4"}

local ids = nil
local function id(name)
    return ids[name]
end
local function init_ids()
    if ids then
        return
    end
    ids = {}
    for _, name in ipairs({"medieval_core:loose_sticks", "medieval_core:campfire_frame_2",
            "medieval_core:campfire_frame_3", "medieval_core:campfire_frame_4",
            "medieval_core:campfire", "medieval_core:campfire_lit", "medieval_core:campfire_ashes"}) do
        ids[name] = block.index(name)
    end
end

local sites = {}   -- "x,y,z" -> {x, y, z, fuel, food = {[slot] = {item, t}}}

local function key(x, y, z)
    return x .. "," .. y .. "," .. z
end

function this.is_lit(blockid)
    init_ids()
    return blockid == id("medieval_core:campfire_lit")
end

-- blocks that keep a site: the finished fire in any state
function this.holds_food(blockid)
    init_ids()
    return blockid == id("medieval_core:campfire") or blockid == id("medieval_core:campfire_lit")
        or blockid == id("medieval_core:campfire_ashes")
end

-- number of sticks in a build stage (0 = not a stage)
function this.stage(blockid)
    init_ids()
    for i, name in ipairs(STAGES) do
        if id(name) == blockid then
            return i
        end
    end
    return 0
end

function this.get(x, y, z)
    return sites[key(x, y, z)]
end

-- burning fires within radius of a point: list of {x, y, z, distance}
function this.lit_near(px, py, pz, radius)
    init_ids()
    local lit = id("medieval_core:campfire_lit")
    local out = {}
    for _, s in pairs(sites) do
        local dx, dy, dz = s.x + 0.5 - px, s.y + 0.5 - py, s.z + 0.5 - pz
        local d = math.sqrt(dx * dx + dy * dy + dz * dz)
        if d <= radius and block.get(s.x, s.y, s.z) == lit then
            out[#out + 1] = {s.x, s.y, s.z, d}
        end
    end
    return out
end

local function site(x, y, z)
    local k = key(x, y, z)
    local s = sites[k]
    if not s then
        s = {x = x, y = y, z = z, fuel = 0, food = {}}
        sites[k] = s
    end
    return s
end

local function set(x, y, z, name)
    block.set(x, y, z, id(name), 0)
    visual.sync(x, y, z, sites[key(x, y, z)])
end

local function held(pid)
    local invid, slot = player.get_inventory(pid)
    local itemid, count = inventory.get(invid, slot)
    return invid, slot, itemid, itemid ~= 0 and item.name(itemid) or nil
end

local function take_one(pid, invid, slot)
    if not player.is_infinite_items(pid) then
        inventory.decrement(invid, slot, 1)
    end
end

local function drop(x, y, z, name, count)
    local base_util = require "base:util"
    local e = base_util.drop({x + 0.5, y + 0.6, z + 0.5}, item.index(name), count or 1)
    if e then
        e.rigidbody:set_vel(vec3.spherical_rand(1.5))
    end
end

-- Food from the skewers goes to the player (or drops if it doesn't fit):
-- the roasted pieces, or the raw ones when nothing is ready yet.
-- everything = true takes all of it (the fire is broken).
local function collect(x, y, z, pid, everything)
    local s = this.get(x, y, z)
    if not s then
        return false
    end
    local ready = false
    for slot = 1, this.SLOTS do
        local f = s.food[slot]
        if f and not this.COOKED[f.item] then
            ready = true
        end
    end
    local any = false
    local invid = pid and player.get_inventory(pid)
    for slot = 1, this.SLOTS do
        local f = s.food[slot]
        if f and (everything or not ready or not this.COOKED[f.item]) then
            local left = 1
            if invid then
                left = inventory.add(invid, item.index(f.item), 1)
            end
            if left > 0 then
                drop(x, y, z, f.item)
            end
            s.food[slot] = nil
            any = true
        end
    end
    if any then
        visual.sync(x, y, z, s)
    end
    return any
end

-- the pot over a fire (nil if none)
function this.pot(x, y, z)
    local s = this.get(x, y, z)
    return s and s.pot
end

local function give(x, y, z, pid, name)
    local left = inventory.add(player.get_inventory(pid), item.index(name), 1)
    if left > 0 then
        drop(x, y, z, name)
    end
end

local function swap_held(pid, invid, slot, name)
    if not player.is_infinite_items(pid) then
        inventory.set(invid, slot, item.index(name), 1)
    end
end

local function pot_sound(name, x, y, z, volume)
    if gfx then
        audio.play_sound("medieval_core/" .. name, x + 0.5, y + 1.0, z + 0.5, volume,
            0.9 + math.random() * 0.2, "regular")
    end
end

-- the pot comes off with the fire: dropped as an item, what was in it is lost
local function drop_pot(x, y, z)
    local s = this.get(x, y, z)
    if s and s.pot then
        s.pot = nil
        drop(x, y, z, POT)
    end
end

-- Right click on a fire with a pot in hand or at a fire with a pot over it.
-- Returns true/false if handled, nil to go on with the fire's own clicks.
local function pot_interact(x, y, z, pid, invid, slot, name)
    local s = this.get(x, y, z)
    local pot = s and s.pot
    if not pot then
        if name ~= POT then
            return nil
        end
        site(x, y, z).pot = cooking.new()
        take_one(pid, invid, slot)
        visual.sync(x, y, z, this.get(x, y, z))
        pot_sound("chisel", x, y, z, 0.5)
        return true
    end
    if name == POT then
        return true
    end
    if name == WATER_BUCKET then
        if cooking.add_water(pot) then
            swap_held(pid, invid, slot, EMPTY_BUCKET)
            visual.sync(x, y, z, s)
            pot_sound("bucket_pour", x, y, z, 0.7)
        end
        return true
    end
    if name == EMPTY_BUCKET then
        if cooking.take_water(pot) then
            swap_held(pid, invid, slot, WATER_BUCKET)
            visual.sync(x, y, z, s)
            pot_sound("bucket_fill", x, y, z, 0.7)
        end
        return true
    end
    if name == PLATE then
        local stew = cooking.serve(pot)
        if stew then
            take_one(pid, invid, slot)
            give(x, y, z, pid, stew)
            visual.sync(x, y, z, s)
            pot_sound("splash", x, y, z, 0.4)
        end
        return true
    end
    if name and cooking.INGREDIENTS[name] then
        if cooking.add(pot, name) then
            take_one(pid, invid, slot)
            visual.sync(x, y, z, s)
            pot_sound("splash", x, y, z, 0.5)
            return true
        end
        -- meat that does not go into the pot goes onto a skewer
        if this.COOKED[name] then
            return nil
        end
        if not pot.water then
            notice.show(pid, "medieval_core.pot.water")
        end
        return true
    end
    if not name then
        -- an empty hand takes the skewered food first, then an empty pot
        if collect(x, y, z, pid) then
            return true
        end
        if cooking.is_empty(pot) then
            s.pot = nil
            give(x, y, z, pid, POT)
            visual.sync(x, y, z, s)
            return true
        end
    end
    return nil
end

function this.fuel_value(name)
    if FUEL[name] then
        return FUEL[name]
    end
    local itemid = item.index(name)
    local placing = item.placing_block(itemid)
    if placing and placing ~= 0 and block.material(placing) == "base:wood" then
        return WOOD_FUEL
    end
    return nil
end

-- puts a raw food item on a free skewer; returns true if it was taken
function this.add_food(x, y, z, name)
    if not this.COOKED[name] or not this.holds_food(block.get(x, y, z)) then
        return false
    end
    local s = site(x, y, z)
    for slot = 1, this.SLOTS do
        if not s.food[slot] then
            s.food[slot] = {item = name, t = 0}
            visual.sync(x, y, z, s)
            return true
        end
    end
    return false
end

function this.light(x, y, z)
    init_ids()
    if block.get(x, y, z) ~= id("medieval_core:campfire") then
        return false
    end
    local s = site(x, y, z)
    s.fuel = this.START_FUEL
    set(x, y, z, "medieval_core:campfire_lit")
    visual.ignite(x, y, z)
    return true
end

function this.extinguish(x, y, z)
    local s = this.get(x, y, z)
    if s then
        s.fuel = 0
    end
    set(x, y, z, "medieval_core:campfire_ashes")
    visual.burn_out(x, y, z)
end

-- Right click on a stage, a fire or ashes. Returns true if handled.
function this.interact(x, y, z, pid)
    init_ids()
    local blockid = block.get(x, y, z)
    local invid, slot, itemid, name = held(pid)
    local n = this.stage(blockid)
    if this.holds_food(blockid) then
        local handled = pot_interact(x, y, z, pid, invid, slot, name)
        if handled ~= nil then
            return handled
        end
    end
    if blockid == id("medieval_core:campfire_ashes") then
        if collect(x, y, z, pid) then
            return true
        end
        if name == STICK then
            drop_pot(x, y, z)
            sites[key(x, y, z)] = nil
            take_one(pid, invid, slot)
            set(x, y, z, "medieval_core:loose_sticks")
            return true
        end
        return false
    end
    if n > 0 then
        if name == STICK and n < #STAGES then
            take_one(pid, invid, slot)
            set(x, y, z, STAGES[n + 1])
            return true
        end
        if name == FIBER and n == #STAGES then
            take_one(pid, invid, slot)
            set(x, y, z, "medieval_core:campfire")
            return true
        end
        return false
    end
    if blockid == id("medieval_core:campfire_lit") then
        local value = name and this.fuel_value(name)
        if value then
            local s = site(x, y, z)
            if s.fuel + value <= this.MAX_FUEL then
                s.fuel = s.fuel + value
                take_one(pid, invid, slot)
                visual.puff(x, y, z)
            end
            return true
        end
    end
    if this.holds_food(blockid) then
        if name and this.COOKED[name] then
            if this.add_food(x, y, z, name) then
                take_one(pid, invid, slot)
            end
            return true
        end
        return collect(x, y, z, pid)
    end
    return false
end

-- what is left when a player breaks a stage or a fire
function this.broken(blockid, x, y, z)
    init_ids()
    collect(x, y, z, nil, true)
    drop_pot(x, y, z)
    sites[key(x, y, z)] = nil
    visual.clear(x, y, z)
end

-- bow drilling: progress per player like block breaking --------------------
local drills = {}  -- pid -> {x, y, z, progress, last}
local DRILL_GAP = 0.4

-- one call per repeated use (~0.16 s apart); returns "lit", "drilling" or nil
function this.drill(pid, x, y, z, dt)
    init_ids()
    if block.get(x, y, z) ~= id("medieval_core:campfire") then
        drills[pid] = nil
        return nil
    end
    if this.drill_progress(pid, x, y, z, dt) then
        this.light(x, y, z)
        return "lit"
    end
    return "drilling"
end

-- Bow drilling at a block (whatever is lit there): smokes the tinder and
-- returns true once it catches fire.
function this.drill_progress(pid, x, y, z, dt)
    local now = time.uptime()
    local d = drills[pid]
    if not d or d.x ~= x or d.y ~= y or d.z ~= z or (not dt and now - d.last > DRILL_GAP) then
        d = {x = x, y = y, z = z, progress = 0, last = now}
        drills[pid] = d
        dt = dt or 0.16
    else
        dt = dt or math.min(now - d.last, DRILL_GAP)
    end
    d.last = now
    d.progress = d.progress + dt
    visual.drill_smoke(x, y, z, d.progress / this.DRILL_TIME)
    if d.progress >= this.DRILL_TIME then
        drills[pid] = nil
        return true
    end
    return false
end

-- simulation ------------------------------------------------------------------
function this.tick(dt)
    init_ids()
    for k, s in pairs(sites) do
        local blockid = block.get(s.x, s.y, s.z)
        if blockid == -1 then
            -- unloaded chunk: frozen
        elseif blockid == id("medieval_core:campfire_lit") then
            s.fuel = s.fuel - dt
            for slot = 1, this.SLOTS do
                local f = s.food[slot]
                if f and this.COOKED[f.item] then
                    f.t = f.t + dt
                    if f.t >= this.COOK_TIME then
                        f.item = this.COOKED[f.item]
                        f.t = 0
                        visual.sync(s.x, s.y, s.z, s)
                    end
                end
            end
            if s.fuel <= 0 then
                this.extinguish(s.x, s.y, s.z)
            end
        elseif not this.holds_food(blockid) then
            -- the block went away without a player breaking it
            drop_pot(s.x, s.y, s.z)
            sites[k] = nil
            visual.clear(s.x, s.y, s.z)
        end
        if sites[k] and s.pot and blockid ~= -1
                and cooking.tick(s.pot, block.get(s.x, s.y, s.z) == id("medieval_core:campfire_lit"), dt) then
            visual.sync(s.x, s.y, s.z, s)
        end
    end
end

-- a fire block appeared (loaded or placed): show it; a lit fire placed
-- by other means than lighting (creative, scripts) gets the start fuel
function this.present(x, y, z)
    init_ids()
    local blockid = block.get(x, y, z)
    local s = this.get(x, y, z)
    if blockid == id("medieval_core:campfire_lit") and not s then
        s = site(x, y, z)
        s.fuel = this.START_FUEL
    end
    visual.sync(x, y, z, s)
end

function this.unloaded(x, y, z)
    visual.clear(x, y, z)
end

function this.save()
    local list = {}
    for _, s in pairs(sites) do
        local food = {}
        for slot = 1, this.SLOTS do
            local f = s.food[slot]
            food[slot] = f and {f.item, f.t} or false
        end
        list[#list + 1] = {s.x, s.y, s.z, s.fuel, food, s.pot and cooking.encode(s.pot) or false}
    end
    file.write(pack.data_file("medieval_core", SAVE_FILE), json.tostring(list))
end

function this.load()
    this.reset()
    local path = pack.data_file("medieval_core", SAVE_FILE)
    if not file.exists(path) then
        return
    end
    for _, e in ipairs(json.parse(file.read(path))) do
        local s = site(e[1], e[2], e[3])
        s.fuel = e[4]
        for slot, f in ipairs(e[5] or {}) do
            if f then
                s.food[slot] = {item = f[1], t = f[2]}
            end
        end
        if e[6] then
            s.pot = cooking.decode(e[6])
        end
    end
end

function this.reset()
    for _, s in pairs(sites) do
        visual.clear(s.x, s.y, s.z)
    end
    sites = {}
    drills = {}
end

return this
