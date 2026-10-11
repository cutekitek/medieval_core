-- Player vital stats: health, hunger (food), thirst (water).
-- Ticked from world.lua on_player_tick, persisted in world:data/medieval_core/.
local this = {}

this.MAX_HEALTH = 20
this.MAX_FOOD = 20
this.MAX_WATER = 20
this.MAX_AIR = 20

-- seconds per one point
local FOOD_DECAY = 45
local WATER_DECAY = 30
local REGEN_PERIOD = 4       -- heal 1 point while well fed
local STARVE_PERIOD = 4      -- lose 1 point while starving or dehydrated
local WELL_FED = 16
local AIR_LOSS = 0.75         -- seconds per air point under water (15 s of breath)
local AIR_GAIN = 0.1          -- seconds per air point regained
local DROWN_PERIOD = 1.0      -- lose 1 health per second without air
-- moving fast burns food and water faster
local ACTIVE_SPEED = 3.5
local ACTIVE_MULT = 2.0

local SAVE_FILE = "players.json"

local players = {}  -- pid -> stats

-- listeners: on_damage(pid, amount), on_death(pid)
this.listeners = {}

local function new_stats()
    return {
        health = this.MAX_HEALTH,
        food = this.MAX_FOOD,
        water = this.MAX_WATER,
        food_timer = 0,
        water_timer = 0,
        regen_timer = 0,
        air = this.MAX_AIR,
        air_timer = 0,
    }
end

function this.get(pid)
    local stats = players[pid]
    if not stats then
        stats = new_stats()
        players[pid] = stats
    end
    return stats
end

local function clamp(v, lo, hi)
    return math.max(lo, math.min(hi, v))
end

local function die(pid)
    for _, listener in ipairs(this.listeners) do
        if listener.on_death then
            listener.on_death(pid)
        end
    end
    -- the bed (respawn point) outlives the player
    local bed = players[pid] and players[pid].bed
    players[pid] = new_stats()
    players[pid].bed = bed
end

function this.damage(pid, amount)
    local stats = this.get(pid)
    stats.health = clamp(stats.health - amount, 0, this.MAX_HEALTH)
    if amount > 0 then
        local x, y, z = player.get_pos(pid)
        audio.play_sound("medieval_core/hurt", x, y + 0.6, z, 0.8, 0.9 + math.random() * 0.2, "regular")
    end
    for _, listener in ipairs(this.listeners) do
        if listener.on_damage then
            listener.on_damage(pid, amount)
        end
    end
    if stats.health <= 0 then
        die(pid)
    end
end

function this.heal(pid, amount)
    local stats = this.get(pid)
    stats.health = clamp(stats.health + amount, 0, this.MAX_HEALTH)
end

function this.feed(pid, food, water)
    local stats = this.get(pid)
    stats.food = clamp(stats.food + (food or 0), 0, this.MAX_FOOD)
    stats.water = clamp(stats.water + (water or 0), 0, this.MAX_WATER)
end

function this.tick(pid, dt, speed)
    local stats = this.get(pid)
    local mult = (speed or 0) > ACTIVE_SPEED and ACTIVE_MULT or 1.0

    stats.food_timer = stats.food_timer + dt * mult
    if stats.food_timer >= FOOD_DECAY then
        stats.food_timer = stats.food_timer - FOOD_DECAY
        stats.food = math.max(0, stats.food - 1)
    end
    stats.water_timer = stats.water_timer + dt * mult
    if stats.water_timer >= WATER_DECAY then
        stats.water_timer = stats.water_timer - WATER_DECAY
        stats.water = math.max(0, stats.water - 1)
    end

    stats.regen_timer = stats.regen_timer + dt
    if stats.food == 0 or stats.water == 0 then
        if stats.regen_timer >= STARVE_PERIOD then
            stats.regen_timer = 0
            this.damage(pid, 1)
        end
    elseif stats.food >= WELL_FED and stats.water >= WELL_FED and
           stats.health < this.MAX_HEALTH then
        if stats.regen_timer >= REGEN_PERIOD then
            stats.regen_timer = 0
            this.heal(pid, 1)
        end
    else
        stats.regen_timer = 0
    end
end

-- breath: runs out with the head under water, then the player drowns
function this.tick_air(pid, dt, underwater)
    local stats = this.get(pid)
    stats.air = stats.air or this.MAX_AIR
    stats.air_timer = (stats.air_timer or 0) + dt
    if underwater then
        if stats.air > 0 then
            if stats.air_timer >= AIR_LOSS then
                stats.air_timer = 0
                stats.air = stats.air - 1
            end
        elseif stats.air_timer >= DROWN_PERIOD then
            stats.air_timer = 0
            this.damage(pid, 1)
        end
    elseif stats.air < this.MAX_AIR then
        if stats.air_timer >= AIR_GAIN then
            stats.air_timer = 0
            stats.air = stats.air + 1
        end
    else
        stats.air_timer = 0
    end
end

function this.load()
    players = {}
    local path = pack.data_file("medieval_core", SAVE_FILE)
    if not file.exists(path) then
        return
    end
    local data = json.parse(file.read(path))
    for key, saved in pairs(data) do
        local stats = new_stats()
        for name, value in pairs(saved) do
            stats[name] = value
        end
        players[tonumber(key)] = stats
    end
end

function this.save()
    local data = {}
    for pid, stats in pairs(players) do
        data[tostring(pid)] = stats
    end
    file.write(pack.data_file("medieval_core", SAVE_FILE), json.tostring(data, true))
end

function this.reset()
    players = {}
end

return this
