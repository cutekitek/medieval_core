-- Workbench: opens the 3x3 crafting grid (layouts/workbench.xml)
function on_interact(x, y, z, playerid)
    if not hud then
        return false
    end
    local ox, oy, oz = block.seek_origin(x, y, z)
    hud.open_block(ox, oy, oz)
    return true
end
