-- Stripping logs: the use button with an axe on a log peels the bark off
-- (bark is the tanning agent) and leaves a stripped log, which serves as
-- the beam for scraping hides.
local this = {}

-- log (and generated trunk) -> its stripped version
local STRIPPED = {
    ["base:wood"] = "medieval_core:stripped_oak_log",
    ["medieval_core:spruce_log"] = "medieval_core:stripped_spruce_log",
    ["medieval_core:spruce_trunk"] = "medieval_core:stripped_spruce_log",
    ["medieval_core:jungle_log"] = "medieval_core:stripped_jungle_log",
    ["medieval_core:jungle_trunk"] = "medieval_core:stripped_jungle_log",
    ["medieval_core:palm_log"] = "medieval_core:stripped_palm_log",
    ["medieval_core:palm_trunk"] = "medieval_core:stripped_palm_log",
}

-- generated tree trunks have no rotation: their stripped logs stand upright
local TRUNKS = {
    ["medieval_core:spruce_trunk"] = true,
    ["medieval_core:jungle_trunk"] = true,
    ["medieval_core:palm_trunk"] = true,
}
local UPRIGHT = 4   -- BLOCK_DIR_UP of the pipe rotation

local ids = nil
local stripped_ids = nil
local function init()
    if ids then
        return
    end
    ids, stripped_ids = {}, {}
    for log, stripped in pairs(STRIPPED) do
        local ok, a = pcall(block.index, log)
        local ok2, b = pcall(block.index, stripped)
        if ok and ok2 and a and b then
            ids[a] = b
            stripped_ids[b] = true
        end
    end
end

function this.stripped_of(blockid)
    init()
    return ids[blockid]
end

function this.is_stripped(blockid)
    init()
    return stripped_ids[blockid] == true
end

-- the held item is an axe
function this.is_axe(itemid)
    if itemid == 0 then
        return false
    end
    local props = item.properties and item.properties[itemid]
    local tool = props and props["medieval_core:tool"]
    return tool ~= nil and tool.type == "axe"
end

-- Strips the log at x, y, z; bark goes to the player (or drops).
-- Returns the number of bark pieces or nil if it is not a log.
function this.strip(x, y, z, pid)
    local stripped = this.stripped_of(block.get(x, y, z))
    if not stripped then
        return nil
    end
    local states = block.get_states(x, y, z)
    if TRUNKS[block.name(block.get(x, y, z))] then
        states = UPRIGHT
    end
    block.set(x, y, z, stripped, states)
    local count = math.random(1, 2)
    local bark = item.index("medieval_core:bark")
    local left = count
    if pid then
        left = inventory.add(player.get_inventory(pid), bark, count)
    end
    if left > 0 then
        local base_util = require "base:util"
        base_util.drop({x + 0.5, y + 1.1, z + 0.5}, bark, left)
    end
    if gfx then
        gfx.particles.emit({x + 0.5, y + 0.5, z + 0.5}, 10, {
            texture = "blocks:mw_bark_chip",
            lifetime = 0.8,
            spawn_interval = 0.0001,
            explosion = {2.5, 2.5, 2.5},
            size = {0.08, 0.08, 0.08},
            spawn_shape = "box",
            spawn_spread = {0.4, 0.4, 0.4},
        })
        audio.play_sound("medieval_core/bark_strip", x + 0.5, y + 0.5, z + 0.5, 0.8,
            0.9 + math.random() * 0.2, "regular")
    end
    return count
end

return this
