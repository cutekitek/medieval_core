-- Scraping beam: a soaked hide or fur put on a stripped log is scraped
-- clean with a knife (hold the use button). The scraped piece goes to the
-- player. State per log is saved with the world.
local process = require "leather/process"
local wood = require "leather/wood"

local this = {}

local SAVE_FILE = "beams.json"
local GAP = 0.4    -- longer pauses in knife work start over

local sites = {}   -- "x,y,z" -> {x, y, z, item, progress, last}
local visuals = {} -- "x,y,z" -> entity uid

local function key(x, y, z)
    return x .. "," .. y .. "," .. z
end

function this.get(x, y, z)
    return sites[key(x, y, z)]
end

-- the hide lies across the log: turn the drape to the log's axis
local function drape_rotation(x, y, z)
    local ax, ay, az = block.get_Y(x, y, z)
    if math.abs(ax) > 0.5 then
        return mat4.idt()
    end
    return mat4.rotate({0, 1, 0}, 90)
end

local function clear_visual(x, y, z)
    local k = key(x, y, z)
    local uid = visuals[k]
    visuals[k] = nil
    local e = uid and entities and entities.get(uid)
    if e then
        e:despawn()
    end
end

local function sync(x, y, z)
    local s = this.get(x, y, z)
    local k = key(x, y, z)
    if not s then
        clear_visual(x, y, z)
        return
    end
    local e = visuals[k] and entities.get(visuals[k])
    if not e then
        -- the model's origin is on top of the log
        e = entities.spawn("medieval_core:beam_hide", {x + 0.5, y + 1, z + 0.5})
        if not e then
            return
        end
        e.transform:set_rot(drape_rotation(x, y, z))
        visuals[k] = e:get_uid()
    end
    e.skeleton:set_texture("$skin", process.SKIN[s.item] or "blocks:mw_skin_hide")
end

local function give(pid, x, y, z, name)
    local left = 1
    if pid then
        left = inventory.add(player.get_inventory(pid), item.index(name), 1)
    end
    if left > 0 then
        local base_util = require "base:util"
        base_util.drop({x + 0.5, y + 1.2, z + 0.5}, item.index(name), 1)
    end
end

-- right click on a stripped log: put a soaked hide on it or take it back
function this.interact(x, y, z, pid)
    if not wood.is_stripped(block.get(x, y, z)) then
        return false
    end
    local invid, slot = player.get_inventory(pid)
    local itemid = inventory.get(invid, slot)
    local name = itemid ~= 0 and item.name(itemid) or nil
    local s = this.get(x, y, z)
    if s then
        if itemid == 0 then
            sites[key(x, y, z)] = nil
            give(pid, x, y, z, s.item)
            sync(x, y, z)
            return true
        end
        return false
    end
    if name and process.SCRAPE[name] then
        sites[key(x, y, z)] = {x = x, y = y, z = z, item = name, progress = 0}
        if not player.is_infinite_items(pid) then
            inventory.decrement(invid, slot, 1)
        end
        sync(x, y, z)
        if gfx then
            audio.play_sound("medieval_core/splash", x + 0.5, y + 1, z + 0.5, 0.4, 1.3, "regular")
        end
        return true
    end
    return false
end

local function scrape_effects(x, y, z)
    if not gfx then
        return
    end
    gfx.particles.emit({x + 0.5, y + 1.05, z + 0.5}, 4, {
        texture = "blocks:mw_flesh_bits",
        lifetime = 0.7,
        spawn_interval = 0.01,
        explosion = {1.2, 1.5, 1.2},
        size = {0.05, 0.05, 0.05},
        spawn_shape = "box",
        spawn_spread = {0.25, 0.02, 0.25},
    })
    audio.play_sound("medieval_core/scrape", x + 0.5, y + 1, z + 0.5, 0.7,
        0.9 + math.random() * 0.2, "regular")
end

-- One knife stroke (the use button repeats while held); dt may be given
-- (tests). Returns "done", "scraping" or nil if there is nothing to scrape.
function this.scrape(pid, x, y, z, dt)
    local s = this.get(x, y, z)
    if not s or not process.SCRAPE[s.item] then
        return nil
    end
    local now = time.uptime()
    if not dt then
        dt = (s.last and now - s.last <= GAP) and (now - s.last) or 0.16
    end
    s.last = now
    s.progress = s.progress + dt
    scrape_effects(x, y, z)
    if s.progress < process.SCRAPE_TIME then
        return "scraping"
    end
    sites[key(x, y, z)] = nil
    sync(x, y, z)
    give(pid, x, y, z, process.SCRAPE[s.item])
    if pid and not player.is_infinite_items(pid) then
        local invid, slot = player.get_inventory(pid)
        inventory.use(invid, slot)
    end
    return "done"
end

function this.broken(x, y, z)
    local s = this.get(x, y, z)
    if s then
        sites[key(x, y, z)] = nil
        give(nil, x, y, z, s.item)
    end
    clear_visual(x, y, z)
end

function this.present(x, y, z)
    sync(x, y, z)
end

function this.unloaded(x, y, z)
    clear_visual(x, y, z)
end

function this.save()
    local list = {}
    for _, s in pairs(sites) do
        list[#list + 1] = {s.x, s.y, s.z, s.item, s.progress}
    end
    file.write(pack.data_file("medieval_core", SAVE_FILE), json.tostring(list))
end

function this.load()
    this.reset()
    local path = pack.data_file("medieval_core", SAVE_FILE)
    if file.exists(path) then
        for _, e in ipairs(json.parse(file.read(path))) do
            sites[key(e[1], e[2], e[3])] = {x = e[1], y = e[2], z = e[3], item = e[4], progress = e[5] or 0}
        end
    end
end

function this.reset()
    for k in pairs(visuals) do
        local uid = visuals[k]
        local e = entities and entities.get(uid)
        if e then
            e:despawn()
        end
    end
    visuals = {}
    sites = {}
end

return this
