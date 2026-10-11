-- Body temperature.
-- The air temperature comes from the biome (recognised from the ground
-- like the fauna habitats), the time of day, the height, water and nearby
-- fires. Clothing insulation shifts what the body feels in the cold (and a
-- little in the heat), a straw hat gives shade in the sun. The body drifts
-- towards cold or heat only outside the comfort range and recovers inside
-- it; hypothermia and heatstroke hurt, mild cold burns food, mild heat
-- makes thirsty.
local stats = require "survival/stats"
local clothing = require "survival/clothing"
local spawning = require "fauna/spawning"
local flow = require "water/flow"
local campfire = require "fire/campfire"

local this = {}

this.NORMAL = 37.0
this.MIN, this.MAX = 28.0, 44.0
-- comfort range of the felt temperature
this.COMFORT_LOW = 14
this.COMFORT_HIGH = 30
-- effects
this.CHILLY = 35.5        -- food burns faster
this.HYPOTHERMIA = 34.5   -- damage
this.SEVERE_COLD = 33.0   -- more damage
this.WARM = 38.0          -- thirst faster
this.HEATSTROKE = 39.0
this.SEVERE_HEAT = 40.5

local INSULATION_COLD = 2.2   -- degrees of warmth per insulation point
local INSULATION_HEAT = 0.6   -- and of extra heat
local DRIFT = 0.0007          -- body degrees per second per felt degree outside comfort
local RECOVERY = 0.012        -- back to normal per second when comfortable
local WET_TIME = 40           -- seconds a swimmer stays wet
local WET_CHILL = 5
local WET_DRIFT = 2.5         -- wet skin loses heat faster
local FIRE_RADIUS = 7
local FIRE_HEAT = 30

-- biome: mean air temperature and the day/night swing
this.BIOMES = {
    tundra = {mean = -10, swing = 6},
    taiga = {mean = 0, swing = 7},
    forest = {mean = 12, swing = 6},
    plains = {mean = 15, swing = 8},
    desert = {mean = 26, swing = 14},
    tropics = {mean = 27, swing = 4},
}
local DEFAULT_BIOME = "plains"
local SEA_LEVEL_HEIGHT = 80     -- colder above it
local LAPSE = 0.15              -- degrees per block

local habitats = {}  -- chunk key -> habitat name (false: not classified yet)

local function chunk_habitat(cx, cz)
    local k = cx .. "," .. cz
    local h = habitats[k]
    if h == nil then
        h = spawning.habitat(cx, cz) or false
        -- an unloaded chunk is asked again later
        if h or block.get(cx * 16 + 8, 64, cz * 16 + 8) ~= -1 then
            habitats[k] = h
        end
    end
    return h or nil
end

-- mean and swing at a column: the 3x3 chunks around, so borders blend
function this.climate(x, z)
    local cx, cz = math.floor(x / 16), math.floor(z / 16)
    local mean, swing, n = 0, 0, 0
    for dx = -1, 1 do
        for dz = -1, 1 do
            local b = this.BIOMES[chunk_habitat(cx + dx, cz + dz) or DEFAULT_BIOME]
            mean, swing, n = mean + b.mean, swing + b.swing, n + 1
        end
    end
    return mean / n, swing / n
end

-- 0..1 day time, warmest in the early afternoon
local function daily(t)
    return math.cos((t - 0.58) * math.pi * 2)
end

-- heat from burning fires nearby (the hottest one counts most)
function this.fire_heat(x, y, z)
    local best, extra = 0, 0
    for _, f in ipairs(campfire.lit_near(x, y, z, FIRE_RADIUS)) do
        local heat = FIRE_HEAT * (1 - f[4] / FIRE_RADIUS) ^ 1.2
        if heat > best then
            extra = extra + best * 0.3
            best = heat
        else
            extra = extra + heat * 0.3
        end
    end
    return best + extra
end

-- air temperature at a point (without fires)
function this.air(x, y, z, day_time)
    local mean, swing = this.climate(x, z)
    local t = mean + swing * daily(day_time or world.get_day_time())
    if y > SEA_LEVEL_HEIGHT then
        t = t - (y - SEA_LEVEL_HEIGHT) * LAPSE
    end
    return t
end

-- everything the player's body is exposed to; returns felt temperature
-- for the cold side, for the hot side and the air temperature
function this.felt(pid)
    local x, y, z = player.get_pos(pid)
    local s = stats.get(pid)
    local air = this.air(x, y, z)
    local t = air + this.fire_heat(x, y + 0.9, z)
    if flow.in_water(x, y + 0.3, z) then
        -- water is never warm, and takes the heat away
        local mean = this.climate(x, z)
        t = math.min(t, mean - 2)
    elseif (s.wet or 0) > 0 then
        t = t - WET_CHILL
    end
    local insulation, shade = clothing.totals(pid)
    local sun = math.max(0, daily(world.get_day_time()))
    local cold_side = t + insulation * INSULATION_COLD
    local hot_side = t + insulation * INSULATION_HEAT - shade * sun
    return cold_side, hot_side, air
end

function this.tick(pid, dt)
    local s = stats.get(pid)
    s.body_temp = s.body_temp or this.NORMAL
    local x, y, z = player.get_pos(pid)
    if flow.in_water(x, y + 0.3, z) then
        s.wet = WET_TIME
    elseif (s.wet or 0) > 0 then
        s.wet = math.max(0, s.wet - dt)
    end
    local cold_side, hot_side, air = this.felt(pid)
    s.air_temp = air
    local wet = (s.wet or 0) > 0 and WET_DRIFT or 1
    local body = s.body_temp
    if cold_side < this.COMFORT_LOW then
        body = body - DRIFT * wet * (this.COMFORT_LOW - cold_side) * dt
    elseif hot_side > this.COMFORT_HIGH then
        body = body + DRIFT * (hot_side - this.COMFORT_HIGH) * dt
    elseif body < this.NORMAL then
        -- warming up is faster at a fire
        local rate = RECOVERY + 0.001 * (cold_side - this.COMFORT_LOW)
        body = math.min(this.NORMAL, body + rate * dt)
    elseif body > this.NORMAL then
        body = math.max(this.NORMAL, body - RECOVERY * dt)
    end
    s.body_temp = math.max(this.MIN, math.min(this.MAX, body))
    this.effects(pid, s, dt)
end

local function hurt(pid, s, dt, period)
    s.temp_timer = (s.temp_timer or 0) + dt
    if s.temp_timer >= period then
        s.temp_timer = 0
        stats.damage(pid, 1)
    end
end

function this.effects(pid, s, dt)
    local body = s.body_temp
    if body < this.SEVERE_COLD or body > this.SEVERE_HEAT then
        hurt(pid, s, dt, 2)
    elseif body < this.HYPOTHERMIA or body > this.HEATSTROKE then
        hurt(pid, s, dt, 6)
    else
        s.temp_timer = 0
    end
    -- shivering burns food, sweating costs water
    if body < this.CHILLY then
        s.food_timer = s.food_timer + dt * 0.5
    elseif body > this.WARM then
        s.water_timer = s.water_timer + dt
    end
end

-- "cold", "chilly", "normal", "warm", "hot" for the HUD
function this.state(body)
    if body < this.HYPOTHERMIA then return "cold" end
    if body < this.CHILLY then return "chilly" end
    if body > this.HEATSTROKE then return "hot" end
    if body > this.WARM then return "warm" end
    return "normal"
end

function this.reset()
    habitats = {}
end

return this
