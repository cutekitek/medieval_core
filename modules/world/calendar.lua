-- The world's calendar in game days: the world time plus the nights skipped
-- by sleeping (and days skipped in tests). Crops and farmland count their
-- time by it, so a night slept through passes for them as well.
local this = {}

this.DAY = 1440             -- seconds of world time in a game day

local SAVE_FILE = "calendar.json"

local skipped = 0           -- days added on top of the world time

function this.now()
    return world.get_total_time() / this.DAY + skipped
end

-- moves the calendar on by some days
function this.skip(days)
    skipped = skipped + days
end

function this.skipped()
    return skipped
end

function this.load()
    skipped = 0
    local path = pack.data_file("medieval_core", SAVE_FILE)
    if file.exists(path) then
        skipped = json.parse(file.read(path)).skipped or 0
    end
end

function this.save()
    file.write(pack.data_file("medieval_core", SAVE_FILE), json.tostring({skipped = skipped}))
end

function this.reset()
    skipped = 0
end

return this
