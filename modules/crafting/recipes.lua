-- Crafting recipes, Minecraft style.
--   shaped:    a pattern of rows with one character per cell (space = empty)
--              and a key mapping characters to ingredients. The pattern may
--              stand anywhere in the grid; mirrored placement also counts
--              unless "mirror" is false.
--   shapeless: a list of ingredients in any cells.
-- An ingredient is an item name or a list of alternative names.
-- "tools": item names among the ingredients that are not used up but
-- lose "tool_wear" uses (default 1) per craft, e.g. a knife cutting leather.
-- Recipes are read from <pack>:recipes/*.json of every installed pack
-- (each file holds an array of recipes) and can be added from scripts.
local this = {}

local recipes = {}
local loaded = false

local function ingredient(value)
    local set = {}
    if type(value) == "string" then
        set[value] = true
    else
        for _, name in ipairs(value) do
            set[name] = true
        end
    end
    return set
end

-- Bounding box of the non-empty cells of a w x h array (1-based, row-major).
-- Returns the trimmed width, height and cells, or 0 when it is empty.
local function trim(cells, w, h)
    local x1, y1, x2, y2 = w + 1, h + 1, 0, 0
    for y = 1, h do
        for x = 1, w do
            if cells[(y - 1) * w + x] ~= nil then
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
            out[(y - 1) * tw + x] = cells[(y1 + y - 2) * w + x1 + x - 1]
        end
    end
    return tw, th, out
end

local function check_result(def)
    if type(def.result) ~= "string" then
        error("recipe without a result")
    end
end

local function tools_of(def)
    local set = {}
    for _, name in ipairs(def.tools or {}) do
        set[name] = true
    end
    return set
end

function this.add_shaped(def)
    check_result(def)
    local h = #def.pattern
    local w = 0
    for _, row in ipairs(def.pattern) do
        w = math.max(w, #row)
    end
    local cells = {}
    for y, row in ipairs(def.pattern) do
        for x = 1, #row do
            local ch = row:sub(x, x)
            if ch ~= " " then
                local value = def.key[ch]
                if value == nil then
                    error("recipe for " .. def.result .. ": '" .. ch .. "' is not in the key")
                end
                cells[(y - 1) * w + x] = ingredient(value)
            end
        end
    end
    local tw, th, trimmed = trim(cells, w, h)
    local recipe = {
        type = "shaped", w = tw, h = th, cells = trimmed,
        mirror = def.mirror ~= false,
        result = def.result, count = def.count or 1,
        tools = tools_of(def), wear = def.tool_wear or 1,
    }
    table.insert(recipes, recipe)
    return recipe
end

function this.add_shapeless(def)
    check_result(def)
    local list = {}
    for _, value in ipairs(def.ingredients) do
        table.insert(list, ingredient(value))
    end
    local recipe = {
        type = "shapeless", ingredients = list,
        result = def.result, count = def.count or 1,
        tools = tools_of(def), wear = def.tool_wear or 1,
    }
    table.insert(recipes, recipe)
    return recipe
end

function this.add(def)
    if def.type == "shapeless" then
        return this.add_shapeless(def)
    end
    return this.add_shaped(def)
end

-- recipes whose items are missing (another pack not installed) are skipped
local function items_exist(def)
    local names = {def.result}
    local values = def.ingredients or {}
    for _, value in pairs(def.key or {}) do
        table.insert(values, value)
    end
    for _, value in ipairs(values) do
        if type(value) == "string" then
            table.insert(names, value)
        else
            for _, name in ipairs(value) do
                table.insert(names, name)
            end
        end
    end
    for _, name in ipairs(names) do
        if not pcall(item.index, name) then
            return false, name
        end
    end
    return true
end

function this.load_file(path)
    local list = json.parse(file.read(path))
    local count = 0
    for i, def in ipairs(list) do
        local ok, missing = items_exist(def)
        if ok then
            this.add(def)
            count = count + 1
        else
            debug.warning(string.format("%s #%d: unknown item %s", path, i, missing))
        end
    end
    return count
end

function this.load()
    if loaded then
        return
    end
    loaded = true
    for _, packid in ipairs(pack.get_installed()) do
        local folder = packid .. ":recipes"
        if file.isdir(folder) then
            for _, path in ipairs(file.list(folder)) do
                if path:sub(-5) == ".json" then
                    this.load_file(path)
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

local function match_shaped(r, w, h, cells)
    if w ~= r.w or h ~= r.h then
        return false
    end
    local function fits(mirrored)
        for y = 1, h do
            for x = 1, w do
                local sx = mirrored and (w - x + 1) or x
                local want = r.cells[(y - 1) * w + sx]
                local have = cells[(y - 1) * w + x]
                if want == nil then
                    if have ~= nil then return false end
                elseif have == nil or not want[have] then
                    return false
                end
            end
        end
        return true
    end
    return fits(false) or (r.mirror and fits(true))
end

-- every item must take a different ingredient: tiny bipartite matching
local function match_shapeless(r, items)
    if #items ~= #r.ingredients then
        return false
    end
    local used = {}
    local function place(i)
        if i > #items then
            return true
        end
        for j, set in ipairs(r.ingredients) do
            if not used[j] and set[items[i]] then
                used[j] = true
                if place(i + 1) then
                    return true
                end
                used[j] = false
            end
        end
        return false
    end
    return place(1)
end

-- grid: item names (nil = empty) of a w x h grid, row-major from the top.
-- Returns the recipe or nil.
function this.match(grid, w, h)
    this.load()
    local cells = {}
    local items = {}
    for i = 1, w * h do
        local name = grid[i]
        if name ~= nil and name ~= "" then
            cells[i] = name
            table.insert(items, name)
        end
    end
    if #items == 0 then
        return nil
    end
    local tw, th, trimmed = trim(cells, w, h)
    for _, r in ipairs(recipes) do
        if r.type == "shaped" then
            if match_shaped(r, tw, th, trimmed) then
                return r
            end
        elseif match_shapeless(r, items) then
            return r
        end
    end
    return nil
end

return this
