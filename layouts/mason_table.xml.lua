-- The mason table window (modules/building/cutting.lua)
local cutting = require "medieval_core:building/cutting"

local KIND = "stone"
local HINT = "medieval_core.cutting.hint_stone"
local last_click = -1
local current = nil
local ticking = false

local function refresh()
    if not current then
        return
    end
    local list = cutting.refresh(current, KIND)
    local empty = inventory.get(current, cutting.INPUT) == 0
    document.hint.text = (empty or #list == 0) and gui.str(HINT) or ""
end

function on_input(invid, slot)
    refresh()
end

function on_option(invid, slot)
    -- a single right click reports the slot update twice in one frame
    local now = time.uptime()
    if now == last_click then
        return
    end
    last_click = now
    local done
    if input.is_pressed("key:left-shift") or input.is_pressed("key:right-shift") then
        done = cutting.cut_all(invid, KIND, slot, player.get_inventory(hud.get_player())) > 0
    else
        done = cutting.cut_into(invid, KIND, slot, hud.get_exchange_inventory(), 0)
    end
    if done then
        audio.play_sound_2d("medieval_core/chisel", 0.7, 0.95 + math.random() * 0.1)
    end
    refresh()
end

function on_open(invid, x, y, z)
    current = invid
    refresh()
    -- intervals outlive the document being closed: add it once
    if not ticking then
        ticking = true
        document.root:setInterval(100, refresh)
    end
end

function on_close(invid)
    current = nil
    cutting.give_back(invid, hud.get_player())
end
