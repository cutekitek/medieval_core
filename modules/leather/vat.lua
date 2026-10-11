-- Tanning vat. Filled with water (bucket) it soaks raw hides and furs;
-- bark turns the water into tanning liquor, which tans scraped hides into
-- leather (one piece of bark per hide). Up to four pieces float inside.
-- Right click with an empty hand takes out what is ready (or everything
-- when nothing is). State per vat is saved with the world.
local process = require "leather/process"

local this = {}

local SAVE_FILE = "vats.json"
this.SLOTS = 4
this.MAX_CHARGES = 8

local EMPTY, WATER, TANNIN = "medieval_core:tanning_vat", "medieval_core:tanning_vat_water",
    "medieval_core:tanning_vat_tannin"

local sites = {}    -- "x,y,z" -> {x, y, z, charges, items = {[slot] = {item, t}}}
local visuals = {}  -- "x,y,z" -> {[slot] = {uid, item}}

local ids = nil
local function init()
    if not ids then
        ids = {[EMPTY] = block.index(EMPTY), [WATER] = block.index(WATER), [TANNIN] = block.index(TANNIN)}
    end
end

local function key(x, y, z)
    return x .. "," .. y .. "," .. z
end

-- "empty", "water", "tannin" or nil if it is not a vat
function this.liquid(blockid)
    init()
    if blockid == ids[EMPTY] then return "empty" end
    if blockid == ids[WATER] then return "water" end
    if blockid == ids[TANNIN] then return "tannin" end
    return nil
end

function this.get(x, y, z)
    return sites[key(x, y, z)]
end

local function site(x, y, z)
    local k = key(x, y, z)
    local s = sites[k]
    if not s then
        s = {x = x, y = y, z = z, charges = 0, items = {}}
        sites[k] = s
    end
    return s
end

-- what an item becomes in this liquid
local function target(liquid, name)
    if liquid == "water" then
        return process.in_water(name)
    elseif liquid == "tannin" then
        return process.in_tannin(name)
    end
    return nil
end

-- visuals: a floating lump per piece ------------------------------------------
local OFFSETS = {{-0.17, -0.15}, {0.16, 0.17}, {0.15, -0.16}, {-0.16, 0.16}}
local SURFACE = 0.66

local function sync(x, y, z)
    local k = key(x, y, z)
    local s = sites[k]
    local v = visuals[k] or {}
    visuals[k] = v
    local liquid = this.liquid(block.get(x, y, z))
    for slot = 1, this.SLOTS do
        local it = s and liquid and liquid ~= "empty" and s.items[slot]
        local cur = v[slot]
        if it then
            local e = cur and entities.get(cur.uid)
            if not e then
                local o = OFFSETS[slot]
                e = entities.spawn("medieval_core:vat_hide", {x + 0.5 + o[1], y + SURFACE, z + 0.5 + o[2]})
                if e then
                    e.transform:set_rot(mat4.rotate({0, 1, 0}, slot * 67))
                    v[slot] = {uid = e:get_uid()}
                end
            end
            if e and v[slot].item ~= it.item then
                e.skeleton:set_texture("$skin", process.SKIN[it.item] or "blocks:mw_skin_hide")
                v[slot].item = it.item
            end
        elseif cur then
            local e = entities and entities.get(cur.uid)
            if e then
                e:despawn()
            end
            v[slot] = nil
        end
    end
    if next(v) == nil then
        visuals[k] = nil
    end
end

function this.clear_visual(x, y, z)
    local v = visuals[key(x, y, z)]
    if v then
        for _, cur in pairs(v) do
            local e = entities and entities.get(cur.uid)
            if e then
                e:despawn()
            end
        end
    end
    visuals[key(x, y, z)] = nil
end

local function splash(x, y, z, volume)
    if gfx then
        audio.play_sound("medieval_core/splash", x + 0.5, y + 0.7, z + 0.5, volume or 0.6,
            0.9 + math.random() * 0.2, "regular")
    end
end

local function set_liquid(x, y, z, name)
    init()
    block.set(x, y, z, ids[name], block.get_states(x, y, z))
    sync(x, y, z)
end

-- interactions -------------------------------------------------------------------

-- a full bucket poured in; returns true if the vat took it
function this.fill(x, y, z)
    if this.liquid(block.get(x, y, z)) ~= "empty" then
        return false
    end
    site(x, y, z).charges = 0
    set_liquid(x, y, z, WATER)
    splash(x, y, z, 0.8)
    return true
end

-- an empty bucket scoops the water back (only clean water without hides)
function this.scoop(x, y, z)
    local s = this.get(x, y, z)
    if this.liquid(block.get(x, y, z)) ~= "water" or (s and next(s.items)) then
        return false
    end
    sites[key(x, y, z)] = nil
    set_liquid(x, y, z, EMPTY)
    splash(x, y, z, 0.5)
    return true
end

local function has_items(s)
    return s and next(s.items) ~= nil
end

-- takes ready pieces (or all when nothing is ready); true if any
local function take(x, y, z, pid, everything)
    local s = this.get(x, y, z)
    if not has_items(s) then
        return false
    end
    local liquid = this.liquid(block.get(x, y, z))
    local ready = false
    for _, it in pairs(s.items) do
        if not target(liquid, it.item) then
            ready = true
        end
    end
    local base_util = require "base:util"
    for slot = 1, this.SLOTS do
        local it = s.items[slot]
        if it and (everything or not ready or not target(liquid, it.item)) then
            local left = 1
            if pid then
                left = inventory.add(player.get_inventory(pid), item.index(it.item), 1)
            end
            if left > 0 then
                base_util.drop({x + 0.5, y + 1.1, z + 0.5}, item.index(it.item), 1)
            end
            s.items[slot] = nil
        end
    end
    sync(x, y, z)
    splash(x, y, z, 0.4)
    return true
end

function this.interact(x, y, z, pid)
    local liquid = this.liquid(block.get(x, y, z))
    if not liquid then
        return false
    end
    local invid, slot = player.get_inventory(pid)
    local itemid = inventory.get(invid, slot)
    local name = itemid ~= 0 and item.name(itemid) or nil
    local function use_one()
        if not player.is_infinite_items(pid) then
            inventory.decrement(invid, slot, 1)
        end
    end
    if name == nil then
        return take(x, y, z, pid)
    end
    if liquid == "empty" then
        return false
    end
    if name == "medieval_core:bark" then
        local s = site(x, y, z)
        if s.charges < this.MAX_CHARGES then
            s.charges = s.charges + 1
            use_one()
            if liquid ~= "tannin" then
                set_liquid(x, y, z, TANNIN)
            end
            splash(x, y, z, 0.4)
        end
        return true
    end
    -- anything that soaks or tans here goes in
    if process.SOAK[name] or (process.TAN[name] and liquid == "tannin") then
        local s = site(x, y, z)
        for i = 1, this.SLOTS do
            if not s.items[i] then
                s.items[i] = {item = name, t = 0}
                use_one()
                sync(x, y, z)
                splash(x, y, z, 0.6)
                return true
            end
        end
        return true
    end
    return false
end

-- simulation --------------------------------------------------------------------
function this.tick(dt)
    init()
    for k, s in pairs(sites) do
        local blockid = block.get(s.x, s.y, s.z)
        local liquid = this.liquid(blockid)
        if blockid == -1 then
            -- unloaded: frozen
        elseif not liquid then
            sites[k] = nil
            this.clear_visual(s.x, s.y, s.z)
        else
            local changed = false
            for slot = 1, this.SLOTS do
                local it = s.items[slot]
                local result = it and target(liquid, it.item)
                if result then
                    local tanning = process.TAN[it.item] ~= nil
                    local need = tanning and process.TAN_TIME or process.SOAK_TIME
                    it.t = math.min(need, it.t + dt)
                    if it.t >= need and (not tanning or s.charges > 0) then
                        it.item, it.t = result, 0
                        changed = true
                        if tanning then
                            s.charges = s.charges - 1
                        end
                    end
                end
            end
            if liquid == "tannin" and s.charges <= 0 then
                -- the liquor is spent: plain water again
                s.charges = 0
                set_liquid(s.x, s.y, s.z, WATER)
            elseif changed then
                sync(s.x, s.y, s.z)
            end
        end
    end
end

function this.broken(x, y, z)
    local s = this.get(x, y, z)
    if s then
        local base_util = require "base:util"
        for _, it in pairs(s.items) do
            base_util.drop({x + 0.5, y + 0.6, z + 0.5}, item.index(it.item), 1)
        end
    end
    sites[key(x, y, z)] = nil
    this.clear_visual(x, y, z)
end

function this.present(x, y, z)
    sync(x, y, z)
end

function this.unloaded(x, y, z)
    this.clear_visual(x, y, z)
end

function this.save()
    local list = {}
    for _, s in pairs(sites) do
        local items = {}
        for slot = 1, this.SLOTS do
            local it = s.items[slot]
            items[slot] = it and {it.item, it.t} or false
        end
        list[#list + 1] = {s.x, s.y, s.z, s.charges, items}
    end
    file.write(pack.data_file("medieval_core", SAVE_FILE), json.tostring(list))
end

function this.load()
    this.reset()
    local path = pack.data_file("medieval_core", SAVE_FILE)
    if not file.exists(path) then
        return
    end
    for _, e in ipairs(json.parse(file.read(path))) do
        local s = site(e[1], e[2], e[3])
        s.charges = e[4] or 0
        for slot, it in ipairs(e[5] or {}) do
            if it then
                s.items[slot] = {item = it[1], t = it[2]}
            end
        end
    end
end

function this.reset()
    for k, v in pairs(visuals) do
        for _, cur in pairs(v) do
            local e = entities and entities.get(cur.uid)
            if e then
                e:despawn()
            end
        end
    end
    visuals = {}
    sites = {}
end

return this
