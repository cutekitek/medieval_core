-- The workbench's 3x3 crafting grid; works like the 2x2 grid of the
-- inventory panel (layouts/crafting.xml.lua). The grid is emptied back to
-- the player when the window closes.
local grid = require "medieval_core:crafting/grid"

local SIZE = 3
local last_craft = -1
local current = nil
local ticking = false

function on_grid(invid, slot)
    grid.refresh(invid, SIZE)
end

function on_result(invid, slot)
    -- a single right click reports the slot update twice in one frame
    local now = time.uptime()
    if now == last_craft then
        return
    end
    last_craft = now
    if input.is_pressed("key:left-shift") or input.is_pressed("key:right-shift") then
        grid.craft_all(invid, SIZE, player.get_inventory(hud.get_player()))
    else
        grid.craft_into(invid, SIZE, hud.get_exchange_inventory(), 0)
    end
end

function on_open(invid, x, y, z)
    current = invid
    grid.refresh(invid, SIZE)
    -- intervals outlive the document being closed: add it once
    if not ticking then
        ticking = true
        document.root:setInterval(100, function ()
            if current then
                grid.refresh(current, SIZE)
            end
        end)
    end
end

function on_close(invid)
    current = nil
    grid.give_back(invid, SIZE, hud.get_player())
end
