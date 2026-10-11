-- Ambient sound loops around the local player (client side, from hud):
--   * the biome's day or night loop (habitat of the player's chunk, the
--     same classification as the fauna and the temperature), crossfaded at
--     dusk and dawn;
--   * flowing water when water is close;
--   * a cave hum deep under a roof of rock (the surface loops fade out).
-- Each loop plays on the "ambient" channel and is faded in and out by hand.
local spawning = require "fauna/spawning"
local flow = require "water/flow"

local this = {}

this.CHECK_INTERVAL = 0.5     -- seconds between looking at the surroundings
this.FADE = 0.35              -- volume change per second
this.BIOME_VOLUME = 0.18
this.WATER_VOLUME = 0.25
this.CAVE_VOLUME = 0.25
this.WATER_RADIUS = 7
this.CAVE_DEPTH = 58          -- below this height a covered place is a cave

-- habitat -> {day loop, night loop, night volume factor}
local LOOPS = {
    forest = {"amb_forest_day", "amb_night", 1.0},
    plains = {"amb_plains_day", "amb_night", 1.0},
    taiga = {"amb_taiga_day", "amb_night", 0.8},
    tundra = {"amb_tundra", "amb_tundra", 1.0},
    desert = {"amb_desert", "amb_desert", 0.7},
    tropics = {"amb_tropics_day", "amb_tropics_night", 1.0},
}
local DEFAULT = "plains"

local speakers = {}     -- loop name -> {id, volume}
local targets = {}      -- loop name -> target volume
local timer = 0
local habitat_cache = {}

local function habitat_at(x, z)
    local cx, cz = math.floor(x / 16), math.floor(z / 16)
    local key = cx .. ":" .. cz
    local h = habitat_cache[key]
    if h == nil then
        h = spawning.habitat(cx, cz) or false
        if block.get(cx * 16 + 8, 64, cz * 16 + 8) ~= -1 then
            habitat_cache[key] = h
        end
    end
    return h or DEFAULT
end

-- 0 by day, 1 at night, smooth around 6:00 and 19:00
function this.night_factor(t)
    local function ramp(a, b, v)
        local k = math.max(0, math.min(1, (v - a) / (b - a)))
        return k * k * (3 - 2 * k)
    end
    if t < 0.5 then
        return 1 - ramp(0.2, 0.28, t)
    end
    return ramp(0.76, 0.84, t)
end

-- a roof of solid blocks above the head
local function covered(x, y, z)
    for dy = 1, 24 do
        if block.is_solid_at(math.floor(x), math.floor(y) + dy, math.floor(z)) then
            return true
        end
    end
    return false
end

-- share of the water cells around (0..1)
local function water_near(x, y, z)
    local r = this.WATER_RADIUS
    local found = 0
    for dx = -r, r, 2 do
        for dz = -r, r, 2 do
            for dy = -3, 1, 2 do
                if flow.is_water(block.get(math.floor(x) + dx, math.floor(y) + dy, math.floor(z) + dz)) then
                    found = found + 1
                end
            end
        end
    end
    return math.min(1, found / 12)
end

-- what should be heard at the player's position: loop name -> volume
function this.mix(x, y, z, day_time)
    local mix = {}
    local loops = LOOPS[habitat_at(x, z)] or LOOPS[DEFAULT]
    local night = this.night_factor(day_time)
    local cave = 0
    if y < this.CAVE_DEPTH and covered(x, y, z) then
        cave = math.min(1, (this.CAVE_DEPTH - y) / 6)
    end
    local surface = 1 - cave
    local function add(name, v)
        if v > 0.001 then
            mix[name] = (mix[name] or 0) + v
        end
    end
    add(loops[1], this.BIOME_VOLUME * (1 - night) * surface)
    add(loops[2], this.BIOME_VOLUME * night * loops[3] * surface)
    add("amb_water", this.WATER_VOLUME * water_near(x, y, z))
    add("amb_cave", this.CAVE_VOLUME * cave)
    return mix
end

function this.update(dt, x, y, z)
    timer = timer - dt
    if timer <= 0 then
        timer = this.CHECK_INTERVAL
        targets = this.mix(x, y, z, world.get_day_time())
    end
    for name in pairs(targets) do
        if not speakers[name] then
            speakers[name] = {
                id = audio.play_sound_2d("medieval_core/" .. name, 0, 1, "ambient", true),
                volume = 0,
            }
        end
    end
    for name, s in pairs(speakers) do
        local goal = targets[name] or 0
        local step = this.FADE * dt
        s.volume = s.volume + math.max(-step, math.min(step, goal - s.volume))
        if s.volume <= 0 and goal <= 0 then
            audio.stop(s.id)
            speakers[name] = nil
        else
            audio.set_volume(s.id, s.volume)
        end
    end
end

function this.reset()
    for _, s in pairs(speakers) do
        audio.stop(s.id)
    end
    speakers = {}
    targets = {}
    habitat_cache = {}
    timer = 0
end

return this
