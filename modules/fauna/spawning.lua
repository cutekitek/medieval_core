-- Populates freshly generated chunks with animals.
-- The world script gets no biome info, so a chunk's habitat is read from
-- its surface: the ground block of each biome is distinct, and forest is
-- told from plains by the trees standing on it.
local species_list = require "fauna/species"

local this = {}

local HERD_CHANCE = 0.12
-- weight of "nobody" in every habitat: habitats with few or rare species
-- stay emptier
local EMPTY_WEIGHT = 2
-- predators never appear this close to a player
local PREDATOR_SAFE_RADIUS = 32

-- ground block -> habitat
local GROUND = {
    ["medieval_core:snowy_dirt"] = "tundra",
    ["medieval_core:snow_block"] = "tundra",
    ["base:ice"] = "tundra",
    ["medieval_core:podzol"] = "taiga",
    ["medieval_core:tropical_grass_block"] = "tropics",
    ["base:sand"] = "desert",
    ["medieval_core:sandstone"] = "desert",
    ["base:grass_block"] = "grassland",
}
-- ground animals stand only on these (birds land anywhere dry)
local WALKABLE = {
    "base:grass_block", "medieval_core:podzol", "medieval_core:tropical_grass_block",
    "medieval_core:snowy_dirt", "medieval_core:snow_block", "base:ice", "base:sand",
    "base:dirt", "medieval_core:gravel",
}

local ids = nil
local function init_ids()
    if ids then
        return
    end
    ids = {ground = {}, walkable = {}, tree = {}, water = block.index("base:water")}
    for name, habitat in pairs(GROUND) do
        if block.index(name) then
            ids.ground[block.index(name)] = habitat
        end
    end
    for _, name in ipairs(WALKABLE) do
        ids.walkable[block.index(name)] = true
    end
    for i = 0, block.defs_count() - 1 do
        local name = block.name(i)
        if name:find("leaves") or name:find("_log") or name:find("_trunk") or
           name == "base:log" or name == "medieval_core:vine" then
            ids.tree[i] = true
        end
    end
end

-- surface of a column: ground y, ground id, true if a tree stands there,
-- y and id of the topmost solid block (the crown for trees)
local function column(x, z)
    local top_y, top_id = nil, nil
    local tree = false
    for y = 250, 1, -1 do
        local id = block.get(x, y, z)
        if id == -1 then
            return nil
        end
        if id == ids.water then
            return y, id, tree, top_y or y, top_id or id
        end
        if id > 0 and block.is_solid_at(x, y, z) then
            top_y, top_id = top_y or y, top_id or id
            if ids.tree[id] then
                tree = true
            else
                return y, id, tree, top_y, top_id
            end
        end
    end
    return nil
end

-- habitat of a chunk by majority of sampled ground blocks
function this.habitat(cx, cz)
    init_ids()
    local votes = {}
    local trees = 0
    for sx = 2, 14, 4 do
        for sz = 2, 14, 4 do
            local y, id, tree = column(cx * 16 + sx, cz * 16 + sz)
            if y then
                local h = ids.ground[id]
                if h then
                    votes[h] = (votes[h] or 0) + 1
                end
                if tree then
                    trees = trees + 1
                end
            end
        end
    end
    local best, best_votes = nil, 0
    for h, n in pairs(votes) do
        if n > best_votes then
            best, best_votes = h, n
        end
    end
    if best == "grassland" then
        best = trees >= 2 and "forest" or "plains"
    end
    return best, trees
end

local function pick_species(habitat, r)
    local total = EMPTY_WEIGHT
    local list = {}
    for name, s in pairs(species_list) do
        local w = s.habitats and s.habitats[habitat]
        if w then
            table.insert(list, {name, w})
            total = total + w
        end
    end
    -- pairs() order is not stable: sort for deterministic picks
    table.sort(list, function (a, b) return a[1] < b[1] end)
    r = r * total
    for _, entry in ipairs(list) do
        r = r - entry[2]
        if r <= 0 then
            return entry[1]
        end
    end
    return nil
end

local function near_player(x, z, radius)
    for _, pid in ipairs(player.get_all()) do
        local px, _, pz = player.get_pos(pid)
        if (px - x) ^ 2 + (pz - z) ^ 2 < radius * radius then
            return true
        end
    end
    return false
end

-- spawns one group of `kind` around (bx, bz); returns the spawned count
function this.spawn_group(kind, bx, bz, rng)
    init_ids()
    local species = species_list[kind]
    local hitbox = entities.def_hitbox(entities.def_index(species.entity))
    local count = rng:random(species.herd[1], species.herd[2])
    local args = {medieval_core__animal = {species = kind}}
    if species.variants and species.herd_variant then
        args.medieval_core__animal.variant = rng:random(1, #species.variants)
    end
    local spawned = 0
    for _ = 1, count do
        local x = bx + rng:random(-3, 3)
        local z = bz + rng:random(-3, 3)
        local y, id, tree, top_y, top_id = column(x, z)
        local pos = nil
        if not y or id == ids.water then
            pos = nil
        elseif species.flight then
            -- birds sit on the crown if there is one
            if top_id ~= ids.water then
                pos = {x + 0.5, top_y + 1 + hitbox[2] * 0.5 + 0.05, z + 0.5}
            end
        elseif ids.walkable[id] and block.get(x, y + 1, z) == 0 then
            pos = {x + 0.5, y + 1 + hitbox[2] * 0.5 + 0.05, z + 0.5}
        end
        if pos then
            if not (species.variants and species.herd_variant) and species.variants then
                args.medieval_core__animal.variant = rng:random(1, #species.variants)
            end
            entities.spawn(species.entity, pos, args)
            spawned = spawned + 1
        end
    end
    return spawned
end

-- Fish: a school in a chunk with deep enough still water. Returns the
-- spawned count.
local FISH_CHANCE = 0.2
local FISH_MIN_DEPTH = 2

-- depth of still water under the surface of a column, and the surface y
local function water_depth(x, z)
    for y = 250, 1, -1 do
        local id = block.get(x, y, z)
        if id == -1 then
            return 0
        elseif id == ids.water then
            local depth = 0
            while block.get(x, y - depth, z) == ids.water do
                depth = depth + 1
            end
            return depth, y
        elseif id > 0 and block.is_solid_at(x, y, z) then
            return 0
        end
    end
    return 0
end

function this.spawn_school(bx, bz, rng)
    init_ids()
    local fish = species_list.fish
    local count = rng:random(fish.school[1], fish.school[2])
    local args = {medieval_core__fish = {variant = rng:random(1, #fish.variants)}}
    local spawned = 0
    for _ = 1, count * 3 do
        local x = bx + rng:random(-2, 2)
        local z = bz + rng:random(-2, 2)
        local depth, top = water_depth(x, z)
        if depth >= FISH_MIN_DEPTH then
            -- not right under the surface nor on the bottom
            local y = top - rng:random(1, depth - 1)
            entities.spawn(fish.entity, {x + 0.5, y + 0.5, z + 0.5}, args)
            spawned = spawned + 1
            if spawned >= count then
                break
            end
        end
    end
    return spawned
end

function this.populate_water(cx, cz)
    init_ids()
    local rng = random.Random()
    rng:seed(math.abs(world.get_seed() * 3 + cx * 49979687 + cz * 15485863 + 7) % 2147483647)
    if rng:random() > FISH_CHANCE then
        return 0
    end
    -- the deepest of a few sampled columns
    local best, best_depth = nil, FISH_MIN_DEPTH - 1
    for sx = 2, 14, 4 do
        for sz = 2, 14, 4 do
            local x, z = cx * 16 + sx, cz * 16 + sz
            local depth = water_depth(x, z)
            if depth > best_depth then
                best, best_depth = {x, z}, depth
            end
        end
    end
    if not best then
        return 0
    end
    return this.spawn_school(best[1], best[2], rng)
end

function this.populate(cx, cz)
    local rng = random.Random()
    rng:seed(math.abs(world.get_seed() + cx * 73856093 + cz * 19349663) % 2147483647)
    if rng:random() > HERD_CHANCE then
        return 0
    end
    local habitat, trees = this.habitat(cx, cz)
    if not habitat then
        return 0
    end
    local kind = pick_species(habitat, rng:random())
    if not kind then
        return 0
    end
    local species = species_list[kind]
    if species.near_trees and trees == 0 then
        return 0
    end
    local bx = cx * 16 + rng:random(4, 11)
    local bz = cz * 16 + rng:random(4, 11)
    if species.predator and near_player(bx, bz, PREDATOR_SAFE_RADIUS) then
        return 0
    end
    return this.spawn_group(kind, bx, bz, rng)
end

return this
