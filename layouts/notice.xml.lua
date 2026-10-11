-- Short messages above the bars (player/notice), fading out at the end
local notice = require "medieval_core:player/notice"

local registered = false

local function refresh()
    local lines, left = notice.get(hud.get_player())
    local alpha = lines and math.floor(255 * math.min(1, left * 4)) or 0
    for i = 1, 2 do
        local label = document["line" .. i]
        local key = lines and lines[i]
        label.text = key and gui.str(key) or ""
        label.color = {255, 255, 255, alpha}
    end
end

function on_open()
    refresh()
    if not registered then
        registered = true
        document.root:setInterval(100, refresh)
    end
end
