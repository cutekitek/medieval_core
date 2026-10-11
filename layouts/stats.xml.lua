local stats = require "medieval_core:survival/stats"
local mode = require "medieval_core:survival/mode"
local temperature = require "medieval_core:survival/temperature"

local WIDTH = 170
local HEIGHT = 14

local function bar(id, value, max, caption)
    document[id].size = {math.floor(WIDTH * value / max + 0.5), HEIGHT}
    document[id .. "_text"].text = caption .. ": " .. value .. " / " .. max
end

-- body temperature: the bar is centred on the normal 37 degrees
local TEMP_COLORS = {
    cold = {76, 140, 232, 255}, chilly = {136, 184, 232, 255}, normal = {88, 176, 80, 255},
    warm = {232, 160, 64, 255}, hot = {224, 64, 48, 255},
}
local function show_temperature(s)
    local body = s.body_temp or temperature.NORMAL
    local k = (body - 31) / 12   -- 31..43 fills the bar, 37 is the middle
    k = math.max(0.02, math.min(1, k))
    document.temp.size = {math.floor(WIDTH * k + 0.5), HEIGHT}
    local state = temperature.state(body)
    document.temp.color = TEMP_COLORS[state]
    -- the bar is narrow: the air temperature while all is well, the
    -- warning otherwise
    local text = string.format("%.1f°C", body)
    if state ~= "normal" then
        text = text .. "  " .. gui.str("medieval_core.temp." .. state)
    elseif s.air_temp then
        text = text .. string.format("  (%s %d°)", gui.str("medieval_core.temp.air"), math.floor(s.air_temp + 0.5))
    end
    document.temp_text.text = text
end

local function refresh()
    local visible = mode.enabled()
    document.bars.visible = visible
    if not visible then
        return
    end
    local s = stats.get(hud.get_player())
    bar("health", s.health, stats.MAX_HEALTH, gui.str("medieval_core.health"))
    bar("food", s.food, stats.MAX_FOOD, gui.str("medieval_core.hunger"))
    bar("water", s.water, stats.MAX_WATER, gui.str("medieval_core.thirst"))
    local air = s.air or stats.MAX_AIR
    document.air_bar.visible = air < stats.MAX_AIR
    bar("air", air, stats.MAX_AIR, gui.str("medieval_core.air"))
    show_temperature(s)
end

function on_open()
    refresh()
    document.root:setInterval(200, refresh)
end
