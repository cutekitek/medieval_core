local network = require "millwright:kinetics/network"
local millstone = require "millwright:machines/millstone"
local status = require "millwright:kinetics/status"

share_func = require("core:inventory_utils").share_default_func

local BAR_WIDTH = 272
local pos = nil

local function refresh()
    if not pos then
        return
    end
    local x, y, z = pos[1], pos[2], pos[3]
    local progress = millstone.get_progress(x, y, z)
    document.bar.size = {math.floor(BAR_WIDTH * progress), 10}
    local node = network.get(x, y, z)
    document.status.text = node and status.describe(node) or ""
end

function on_open(invid, x, y, z)
    pos = {x, y, z}
    refresh()
    document.root:setInterval(100, refresh)
end

function on_close(invid)
    pos = nil
end
