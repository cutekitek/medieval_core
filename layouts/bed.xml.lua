-- Lying in bed (player/sleep): the screen darkens while falling asleep; the
-- button or Esc gets the player up
local sleep = require "medieval_core:player/sleep"

local MAX_DARK = 0.94
local registered = false

local function refresh()
    local s = sleep.sleeper(hud.get_player())
    local k = s and math.min(1, s.time / sleep.FALL_ASLEEP) or 0
    document.root.color = {0, 0, 0, math.floor(255 * MAX_DARK * k)}
end

function leave()
    hud.close("medieval_core:bed")
end

function on_open()
    document.leave.text = gui.str("medieval_core.bed.leave")
    refresh()
    if not registered then
        registered = true
        document.root:setInterval(50, refresh)
    end
end

function on_close()
    local pid = hud.get_player()
    if sleep.is_sleeping(pid) then
        sleep.wake(pid)
    end
end
