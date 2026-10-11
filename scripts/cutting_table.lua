-- Carpentry and mason tables: open their window (layouts/<block>.xml)
function on_interact(x, y, z, playerid)
    if not hud then
        return false
    end
    hud.open_block(x, y, z)
    return true
end
