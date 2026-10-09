-- Procedural trees. Generated trunks use the *_trunk blocks: ":block"
-- placements can only rotate around Y, so a rotatable (pipe) log would lie
-- on its side. Every species is a function
--   species(put, x, y, z, rng)
-- where (x, y, z) is the lowest trunk block and put(id, x, y, z, priority)
-- places one block. The same code feeds world generation (":block"
-- placements) and can grow trees in the running game (block.set).
local this = {}

local LOG_PRIORITY = 3
local LEAF_PRIORITY = 2

local ids = nil
local function id(name)
    if not ids then
        ids = {}
    end
    local value = ids[name]
    if not value then
        value = block.index(name)
        ids[name] = value
    end
    return value
end

local function disk(put, leaf, cx, y, cz, r, rng, skip)
    local r2 = r * r + 0.6
    for dx = -r, r do
        for dz = -r, r do
            local d2 = dx * dx + dz * dz
            if d2 <= r2 and (d2 < r2 - 1.2 or rng:random() > (skip or 0.25)) then
                put(leaf, cx + dx, y, cz + dz, LEAF_PRIORITY)
            end
        end
    end
end

-- flattened ellipsoid of leaves
local function blob(put, leaf, cx, cy, cz, rx, ry, rng)
    for dy = -ry, ry do
        for dx = -rx, rx do
            for dz = -rx, rx do
                local d = (dx * dx + dz * dz) / (rx * rx + 0.5) + (dy * dy) / (ry * ry + 0.5)
                if d <= 1.0 and (d < 0.7 or rng:random() > 0.3) then
                    put(leaf, cx + dx, cy + dy, cz + dz, LEAF_PRIORITY)
                end
            end
        end
    end
end

local function trunk(put, log, x, y, z, height)
    for i = 0, height - 1 do
        put(log, x, y + i, z, LOG_PRIORITY)
    end
end

-- Conifer with layered skirts, narrowing to a pointed top
function this.spruce(put, x, y, z, rng)
    local log, leaf = id("millwright:spruce_trunk"), id("millwright:spruce_leaves")
    local height = rng:random(9, 15)
    local rmax = height >= 12 and 3 or 2
    local start = rng:random(2, 3)
    trunk(put, log, x, y, z, height)
    for i = start, height - 1 do
        local t = (height - i) / (height - start)
        local r = math.floor(rmax * t + 0.5)
        if (height - i) % 2 == 0 then
            r = math.max(1, r - 1)
        end
        disk(put, leaf, x, y + i, z, math.max(1, r), rng)
    end
    put(leaf, x, y + height, z, LEAF_PRIORITY)
    put(leaf, x, y + height + 1, z, LEAF_PRIORITY)
end

-- Stunted, sparse spruce of the tundra
function this.tundra_spruce(put, x, y, z, rng)
    local log, leaf = id("millwright:spruce_trunk"), id("millwright:spruce_leaves")
    local height = rng:random(3, 6)
    trunk(put, log, x, y, z, height)
    for i = math.max(1, height - 4), height - 1 do
        disk(put, leaf, x, y + i, z, 1, rng, 0.15)
    end
    put(leaf, x, y + height, z, LEAF_PRIORITY)
    put(leaf, x, y + height + 1, z, LEAF_PRIORITY)
end

local DIRS8 = {
    {1, 0}, {-1, 0}, {0, 1}, {0, -1}, {1, 1}, {1, -1}, {-1, 1}, {-1, -1},
}

-- Wraps put() to remember what the tree itself has placed (in order, so the
-- result stays deterministic for neighbouring chunks).
local function recorder(put)
    local cells = {}
    local order = {}
    local function rec(blockid, x, y, z, priority)
        local key = x .. "," .. y .. "," .. z
        if not cells[key] then
            table.insert(order, {x, y, z})
        end
        cells[key] = blockid
        put(blockid, x, y, z, priority)
    end
    return rec, cells, order
end

-- Hangs vines from the underside of the tree's own leaves; a vine stops
-- above any part of the tree.
local function vines(put, cells, order, leaf, rng, chance)
    local vine = id("millwright:vine")
    for _, p in ipairs(order) do
        local x, y, z = p[1], p[2], p[3]
        if cells[x .. "," .. y .. "," .. z] == leaf and
           not cells[x .. "," .. (y - 1) .. "," .. z] and rng:random() < chance then
            for i = 1, rng:random(2, 6) do
                if cells[x .. "," .. (y - i) .. "," .. z] then
                    break
                end
                put(vine, x, y - i, z, 1)
            end
        end
    end
end

-- Tall rainforest tree: buttress roots, side branches, wide flat crown, vines
function this.jungle(put, x, y, z, rng)
    local log, leaf = id("millwright:jungle_trunk"), id("millwright:jungle_leaves")
    local rec, cells, order = recorder(put)
    local height = rng:random(12, 19)
    trunk(rec, log, x, y, z, height)
    for _, d in ipairs({{1, 0}, {-1, 0}, {0, 1}, {0, -1}}) do
        if rng:random() < 0.6 then
            rec(log, x + d[1], y, z + d[2], LOG_PRIORITY)
        end
    end
    local branches = rng:random(2, 3)
    for b = 1, branches do
        local d = DIRS8[rng:random(1, #DIRS8)]
        local by = y + math.floor(height * (0.55 + 0.1 * b))
        local length = rng:random(2, 3)
        local bx, bz = x, z
        for i = 1, length do
            bx, bz = bx + d[1], bz + d[2]
            rec(log, bx, by + math.floor(i / 2), bz, LOG_PRIORITY)
        end
        blob(rec, leaf, bx, by + math.floor(length / 2) + 1, bz, 2, 1, rng)
    end
    local r = rng:random(3, 4)
    blob(rec, leaf, x, y + height, z, r, 1, rng)
    blob(rec, leaf, x, y + height + 1, z, r - 1, 1, rng)
    vines(put, cells, order, leaf, rng, 0.12)
end

-- Palm with a curved, leaning trunk and drooping fronds
function this.palm(put, x, y, z, rng)
    local log, leaf = id("millwright:palm_trunk"), id("millwright:palm_leaves")
    local height = rng:random(5, 8)
    local lean = DIRS8[rng:random(1, 4)]
    local tx, tz = x, z
    for i = 0, height - 1 do
        if i > height / 3 and i % 3 == 0 then
            tx, tz = tx + lean[1], tz + lean[2]
        end
        put(log, tx, y + i, tz, LOG_PRIORITY)
    end
    local ty = y + height
    put(leaf, tx, ty, tz, LEAF_PRIORITY)
    for _, d in ipairs(DIRS8) do
        local length = rng:random(3, 4)
        if d[1] ~= 0 and d[2] ~= 0 then
            length = length - 1
        end
        for i = 1, length do
            local droop = i >= 3 and -(i - 2) or 0
            put(leaf, tx + d[1] * i, ty + droop, tz + d[2] * i, LEAF_PRIORITY)
        end
    end
end

-- Columnar cactus, sometimes with an arm
function this.cactus(put, x, y, z, rng)
    local cactus = id("millwright:cactus")
    local height = rng:random(1, 4)
    trunk(put, cactus, x, y, z, height)
    if height >= 3 and rng:random() < 0.35 then
        local d = DIRS8[rng:random(1, 4)]
        local ay = y + rng:random(1, height - 2)
        put(cactus, x + d[1], ay, z + d[2], LOG_PRIORITY)
        for i = 1, rng:random(1, 2) do
            put(cactus, x + d[1], ay + i, z + d[2], LOG_PRIORITY)
        end
    end
end

-- put() for world generation placements (world coordinates)
function this.placer(placements)
    return function(blockid, x, y, z, priority)
        table.insert(placements, {":block", blockid, {x, y, z}, 0, priority})
    end
end

return this
