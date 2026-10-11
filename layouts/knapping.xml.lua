-- The knapping window (modules/crafting/knapping.lua): the picture of the
-- stone (or clay) cut into 5x5 cells without gaps; a click knocks a cell out
-- and it disappears. Only cells that can go light up under the cursor: the
-- edge of a stone, any cell of clay.
local knapping = require "medieval_core:crafting/knapping"

local N = knapping.SIZE
local CELL = 52

local STONE = {255, 255, 255, 255}
local STONE_HOVER = {255, 236, 200, 255}

local pid = nil

local function cell_id(i)
    return "cell_" .. i
end

-- only the cells that can be knocked out react to the cursor
local function refresh(s)
    for i = 1, N * N do
        local el = document[cell_id(i)]
        if s.cells[i] then
            el.hoverColor = knapping.can_knock(s.cells, i, s.material) and STONE_HOVER or STONE
            el.pressedColor = el.hoverColor
        end
    end
end

local function build_grid(s)
    local grid = document.grid
    grid:clear()
    for i = 1, N * N do
        local x, y = (i - 1) % N, math.floor((i - 1) / N)
        grid:add(string.format(
            "<image id='%s' src='%s' pos='%d,%d' size='%d,%d' region='%f,%f,%f,%f' "..
            "interactive='true' onclick='knock(%d)'/>",
            cell_id(i), s.material.texture, x * CELL, y * CELL, CELL, CELL,
            -- (texture v runs bottom-up)
            x / N, 1 - (y + 1) / N, (x + 1) / N, 1 - y / N, i))
        document[cell_id(i)].color = STONE
    end
    refresh(s)
end

function knock(i)
    local s = knapping.session(pid)
    if not s or not s.cells[i] then
        return
    end
    local result = knapping.knock(pid, i)
    if result == "blocked" then
        return
    end
    if result == nil then
        hud.close("medieval_core:knapping")
        return
    end
    local el = document[cell_id(i)]
    el.visible = false
    el.interactive = false
    audio.play_sound_2d(s.material.sound, 0.7, s.material.pitch * (0.9 + math.random() * 0.2))
    if result == "done" then
        audio.play_sound_2d(s.material.done_sound, 0.8, s.material.pitch)
        hud.close("medieval_core:knapping")
    elseif result == "spoiled" then
        hud.close("medieval_core:knapping")
    else
        refresh(s)
    end
end

function on_open()
    pid = hud.get_player()
    local s = knapping.session(pid)
    if not s then
        hud.close("medieval_core:knapping")
        return
    end
    build_grid(s)
end

function on_close()
    knapping.close(pid)
end
