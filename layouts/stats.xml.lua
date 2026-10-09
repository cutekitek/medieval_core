local stats = require "millwright:survival/stats"
local mode = require "millwright:survival/mode"

local WIDTH = 170
local HEIGHT = 14

local function bar(id, value, max, caption)
    document[id].size = {math.floor(WIDTH * value / max + 0.5), HEIGHT}
    document[id .. "_text"].text = caption .. ": " .. value .. " / " .. max
end

local function refresh()
    local visible = mode.enabled()
    document.bars.visible = visible
    if not visible then
        return
    end
    local s = stats.get(hud.get_player())
    bar("health", s.health, stats.MAX_HEALTH, gui.str("millwright.health"))
    bar("food", s.food, stats.MAX_FOOD, gui.str("millwright.hunger"))
    bar("water", s.water, stats.MAX_WATER, gui.str("millwright.thirst"))
    local air = s.air or stats.MAX_AIR
    document.air_bar.visible = air < stats.MAX_AIR
    bar("air", air, stats.MAX_AIR, gui.str("millwright.air"))
end

function on_open()
    refresh()
    document.root:setInterval(200, refresh)
end
