-- Knapping: shaping a stone by knocking flakes off it. Shift + use with a
-- knappable stone in hand opens the stone cut into 5x5 cells (layouts/knapping.xml);
-- every click knocks a cell out. Flakes come off the edge only: a cell can be
-- knocked out when it lies on the border of the stone or next to a cell
-- knocked out already. As soon as the cells left form a recipe
-- pattern the stone turns into that tool part, which goes to the inventory.
-- The first knock uses the stone up: closing the window halfway loses it.
-- Recipes are read from <pack>:knapping/*.json of every installed pack: arrays
-- of {pattern = rows of "X" (stone left) and " " (knocked out), result,
-- count}. A pattern may stand anywhere in the grid; mirrored placement also
-- counts unless "mirror" is false.
-- Clay is shaped in the same window: its recipes have "material": "clay"
-- (stone ones are "stone" by default), and a pinch of clay comes off
-- anywhere, not only at the edge.
local base_util = require "base:util"

local this = {}

this.SIZE = 5

-- what can be knapped and how the grid shows and sounds it; kind picks the
-- recipes, any_cell lets a cell go from the middle too
this.MATERIALS = {
    ["medieval_core:rock"] = {kind = "stone", texture = "gui/mw_knap_rock", pitch = 1.0,
        sound = "medieval_core/knap", done_sound = "medieval_core/knap_done"},
    ["medieval_core:flint"] = {kind = "stone", texture = "gui/mw_knap_flint", pitch = 1.25,
        sound = "medieval_core/knap", done_sound = "medieval_core/knap_done"},
    ["medieval_core:clay.item"] = {kind = "clay", texture = "gui/mw_knap_clay", pitch = 1.0,
        sound = "medieval_core/clay_pinch", done_sound = "medieval_core/clay_done", any_cell = true},
}

local recipes = {}
local loaded = false
local sessions = {}  -- pid -> {material, slot, cells, started}

-- the trimmed shape of the stone cells: width, height, set of "x,y"
local function shape(cells, w, h)
    local x1, y1, x2, y2 = w + 1, h + 1, 0, 0
    for y = 1, h do
        for x = 1, w do
            if cells[(y - 1) * w + x] then
                x1, y1 = math.min(x1, x), math.min(y1, y)
                x2, y2 = math.max(x2, x), math.max(y2, y)
            end
        end
    end
    if x2 == 0 then
        return 0, 0, {}
    end
    local tw, th = x2 - x1 + 1, y2 - y1 + 1
    local out = {}
    for y = 1, th do
        for x = 1, tw do
            out[(y - 1) * tw + x] = cells[(y1 + y - 2) * w + x1 + x - 1] or false
        end
    end
    return tw, th, out
end

function this.add(def)
    if type(def.result) ~= "string" or type(def.pattern) ~= "table" then
        error("knapping recipe needs a pattern and a result")
    end
    local h = #def.pattern
    local w = 0
    for _, row in ipairs(def.pattern) do
        w = math.max(w, #row)
    end
    if w > this.SIZE or h > this.SIZE then
        error("knapping pattern is larger than " .. this.SIZE .. "x" .. this.SIZE)
    end
    local cells = {}
    for y, row in ipairs(def.pattern) do
        for x = 1, w do
            local c = row:sub(x, x)
            cells[(y - 1) * w + x] = c ~= "" and c ~= " "
        end
    end
    local tw, th, trimmed = shape(cells, w, h)
    local r = {
        result = def.result,
        count = def.count or 1,
        material = def.material or "stone",
        mirror = def.mirror ~= false,
        pattern = def.pattern,
        w = tw, h = th, cells = trimmed,
    }
    table.insert(recipes, r)
    return r
end

function this.load()
    if loaded then
        return
    end
    loaded = true
    for _, packid in ipairs(pack.get_installed()) do
        local folder = packid .. ":knapping"
        if file.isdir(folder) then
            for _, path in ipairs(file.list(folder)) do
                if path:sub(-5) == ".json" then
                    for i, def in ipairs(json.parse(file.read(path))) do
                        if item.index(def.result) then
                            this.add(def)
                        else
                            debug.warning(string.format("%s #%d: unknown item %s", path, i, def.result))
                        end
                    end
                end
            end
        end
    end
end

function this.all()
    this.load()
    return recipes
end

-- clears everything (tests); the next lookup reloads the JSON files
function this.reset()
    recipes = {}
    loaded = false
end

-- The recipe of the material kind ("stone" by default) whose pattern the
-- cells (SIZE*SIZE booleans, row-major, true = material left) form, or nil.
function this.match(cells, kind)
    kind = kind or "stone"
    local w, h, have = shape(cells, this.SIZE, this.SIZE)
    if w == 0 then
        return nil
    end
    for _, r in ipairs(this.all()) do
        if r.material == kind and r.w == w and r.h == h then
            for _, mirrored in ipairs(r.mirror and {false, true} or {false}) do
                local fits = true
                for y = 1, h do
                    for x = 1, w do
                        local sx = mirrored and (w - x + 1) or x
                        if r.cells[(y - 1) * w + sx] ~= have[(y - 1) * w + x] then
                            fits = false
                            break
                        end
                    end
                    if not fits then break end
                end
                if fits then
                    return r
                end
            end
        end
    end
    return nil
end

function this.material_of(itemid)
    return itemid and itemid ~= 0 and this.MATERIALS[item.name(itemid)] or nil
end

-- Starts knapping the stone the player holds; returns the session or nil.
function this.start(pid)
    local invid, slot = player.get_inventory(pid)
    local itemid = inventory.get(invid, slot)
    local material = this.material_of(itemid)
    if not material then
        return nil
    end
    local cells = {}
    for i = 1, this.SIZE * this.SIZE do
        cells[i] = true
    end
    local s = {material = material, item = itemid, slot = slot, cells = cells, started = false}
    sessions[pid] = s
    return s
end

function this.session(pid)
    return sessions[pid]
end

-- The window was closed: a started stone is lost (it was used up already).
function this.close(pid)
    sessions[pid] = nil
end

local function give(pid, name, count)
    local invid = player.get_inventory(pid)
    local left = inventory.add(invid, item.index(name), count)
    if left > 0 then
        local x, y, z = player.get_pos(pid)
        base_util.drop({x, y + 0.5, z}, item.index(name), left)
    end
end

-- Whether cell i can be knocked out: it is still there and lies on the
-- border of the grid or next to (not diagonally) a knocked out cell.
-- Any cell of a material with any_cell (clay) can go.
function this.can_knock(cells, i, material)
    if not cells[i] then
        return false
    end
    if material and material.any_cell then
        return true
    end
    local n = this.SIZE
    local x, y = (i - 1) % n, math.floor((i - 1) / n)
    if x == 0 or y == 0 or x == n - 1 or y == n - 1 then
        return true
    end
    return not cells[i - 1] or not cells[i + 1] or not cells[i - n] or not cells[i + n]
end

-- Knocks cell i (1..SIZE*SIZE) out. Returns:
--   "knocked"        the stone is shaped further,
--   "blocked"        the cell is surrounded by stone: no flake comes off,
--   "done", recipe   the cells form a recipe: the part is in the inventory,
--   "spoiled"        nothing is left of the stone,
--   nil              no session, the cell is gone already or no stone in hand.
function this.knock(pid, i)
    local s = sessions[pid]
    if not s or not s.cells[i] then
        return nil
    end
    if not this.can_knock(s.cells, i, s.material) then
        return "blocked"
    end
    if not s.started then
        -- the stone leaves the hand with the first blow
        local invid = player.get_inventory(pid)
        if inventory.get(invid, s.slot) ~= s.item then
            sessions[pid] = nil
            return nil
        end
        if not player.is_infinite_items(pid) then
            inventory.decrement(invid, s.slot, 1)
        end
        s.started = true
    end
    s.cells[i] = false
    local r = this.match(s.cells, s.material.kind)
    if r then
        sessions[pid] = nil
        give(pid, r.result, r.count)
        return "done", r
    end
    for _, c in ipairs(s.cells) do
        if c then
            return "knocked"
        end
    end
    sessions[pid] = nil
    return "spoiled"
end

return this
