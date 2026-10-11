-- Short messages above the hotbar (like Minecraft's action bar): one or two
-- lines of translation keys per player, shown by layouts/notice.xml
local this = {}

this.DURATION = 3.5     -- seconds on screen

local notices = {}      -- pid -> {lines = {key, ...}, until_time}

-- shows the given translation keys (nil ones are skipped) as lines
function this.show(pid, ...)
    local lines = {}
    for i = 1, select("#", ...) do
        local key = select(i, ...)
        if key then
            table.insert(lines, key)
        end
    end
    if #lines == 0 then
        return
    end
    notices[pid] = {lines = lines, shown = time.uptime()}
end

-- the keys being shown to a player (nil if none) and the share of time left
function this.get(pid)
    local n = notices[pid]
    if not n then
        return nil
    end
    local left = 1 - (time.uptime() - n.shown) / this.DURATION
    if left <= 0 then
        notices[pid] = nil
        return nil
    end
    return n.lines, left
end

-- the keys last shown (tests: uptime does not run in headless ticks)
function this.last(pid)
    return notices[pid] and notices[pid].lines
end

function this.clear(pid)
    notices[pid] = nil
end

function this.reset()
    notices = {}
end

return this
