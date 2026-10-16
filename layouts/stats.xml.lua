local stats = require "medieval_core:survival/stats"
local mode = require "medieval_core:survival/mode"
local temperature = require "medieval_core:survival/temperature"
local riding = require "medieval_core:riding/riding"

-- ten icons a row, two points each: full, half or empty
local ICONS = 10
local ICON = 18
local PITCH = 18
local SHAKE_HEALTH = 4        -- hearts shake at this health and below

-- name -> {row container, icon texture, filled from the right}
local ROWS = {
    health = {"health_row", "heart"},
    food = {"food_row", "food", true},
    water = {"water_row", "water", true},
    air = {"air_row", "air", true},
    stamina = {"stamina_row", "stamina"},
}

local WHITE = {255, 255, 255, 255}
local WINDED = {255, 140, 120, 255}

local function icon_id(name, i)
    return name .. "_" .. i
end

local function icon_x(right, i)
    local x = (i - 1) * PITCH
    return right and (ICONS - 1) * PITCH - x or x
end

local function build()
    for name, row in pairs(ROWS) do
        local container = document[row[1]]
        for i = 1, ICONS do
            container:add(string.format(
                "<image id='%s' src='gui/mw_hud_%s_empty' pos='%d,0' size='%d,%d'/>",
                icon_id(name, i), row[2], icon_x(row[3], i), ICON, ICON))
        end
    end
end

-- value of max as ten icons; hide_empty leaves out the empty ones (air);
-- shake jiggles them up and down; empty = the texture of an empty one
local function show(name, value, max, hide_empty, shake, color, empty)
    local row = ROWS[name]
    local points = math.floor(value / max * ICONS * 2 + 0.5)
    if value > 0 then
        points = math.max(points, 1)
    end
    for i = 1, ICONS do
        local img = document[icon_id(name, i)]
        local state = points >= i * 2 and "full" or (points == i * 2 - 1 and "half" or "empty")
        img.visible = not (hide_empty and state == "empty")
        img.src = "gui/mw_hud_" .. row[2] .. "_" .. (state == "empty" and empty or state)
        img.pos = {icon_x(row[3], i), shake and math.random(-1, 1) or 0}
        img.color = color or WHITE
    end
end

-- body temperature: the thermometer; it shivers in the cold and the heat
local function show_temperature(s)
    local state = temperature.state(s.body_temp or temperature.NORMAL)
    document.temp.src = "gui/mw_hud_temp_" .. state
    local shake = state == "cold" or state == "hot"
    document.temp.pos = {253 + (shake and math.random(-1, 1) or 0), 40}
end

-- the horse under the player: its stamina, also outside survival
local function show_stamina()
    local horse = riding.horse_of(hud.get_player())
    local value, max, winded
    if horse and horse.get_stamina then
        value, max, winded = horse.get_stamina()
    end
    document.stamina_row.visible = value ~= nil
    if value then
        show("stamina", value, max, false, false, winded and WINDED or nil, winded and "winded" or nil)
    end
end

local function refresh()
    show_stamina()
    local visible = mode.enabled()
    document.survival.visible = visible
    if not visible then
        return
    end
    local s = stats.get(hud.get_player())
    show("health", s.health, stats.MAX_HEALTH, false, s.health <= SHAKE_HEALTH)
    show("food", s.food, stats.MAX_FOOD)
    show("water", s.water, stats.MAX_WATER)
    local air = s.air or stats.MAX_AIR
    document.air_row.visible = air < stats.MAX_AIR
    show("air", air, stats.MAX_AIR, true)
    show_temperature(s)
end

function on_open()
    build()
    refresh()
    document.root:setInterval(100, refresh)
end
