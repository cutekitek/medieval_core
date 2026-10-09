-- Shared script of all kinetic blocks
require "kinetics/content"
local network = require "kinetics/network"
local status = require "kinetics/status"

function on_block_present(x, y, z)
    network.add(x, y, z)
end

function on_placed(x, y, z, playerid)
    network.add(x, y, z)
end

function on_block_removed(x, y, z)
    network.remove(x, y, z)
end

function on_broken(x, y, z, playerid)
    network.remove(x, y, z)
end

function on_interact(x, y, z, playerid)
    local node = network.get(x, y, z) or network.add(x, y, z)
    if not node then
        return false
    end
    if node.part.interact and node.part.interact(node, playerid) then
        return true
    end
    if node.part.on_tick then
        -- machines with inventory open their UI
        return false
    end
    local invid, slot = player.get_inventory(playerid)
    if inventory.get(invid, slot) ~= 0 then
        -- let the player place blocks against the part
        return false
    end
    console.chat(status.describe(node))
    return true
end
