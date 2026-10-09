local _, dir = parse_path(__DIR__)
local ores = require "base:generation/ores"
local trees = require "millwright:generation/trees"
math.randomseed(SEED)
ores.load(dir)

local function get_rand(seed, x, y, z)
    local h = bit.bxor(bit.bor(x * 23729, y % 16786), y * x + seed)
    h = bit.bxor(h, z * 47917)
    h = bit.bxor(h, bit.bor(z % 12345, x + y))

    local n = (h % 10000) / 10000.0

    return n
end

local function gen_parameters(size, seed, x, y)
    local res = {}
    local rand = 0

    for i=1, size do
        rand = get_rand(seed, x, y, rand)
        table.insert(res, rand)
    end

    return res
end

local SEA_LEVEL = 64

local GRAVEL = block.index("millwright:gravel")
local CLAY = block.index("millwright:clay")
local SAND = block.index("base:sand")
local ROCK = block.index("millwright:loose_rock")
local FLINT = block.index("millwright:loose_flint")

-- deterministic 2D value noise in [0, 1)
local function hash2(ix, iz, salt)
    local h = bit.bxor(ix * 374761393 + iz * 668265263, SEED + salt * 1442695041)
    h = bit.bxor(h, bit.rshift(h, 13)) * 1274126177
    h = bit.bxor(h, bit.rshift(h, 16))
    return (h % 65536) / 65536
end

local function value_noise(x, z, scale, salt)
    local fx, fz = x / scale, z / scale
    local ix, iz = math.floor(fx), math.floor(fz)
    local tx, tz = fx - ix, fz - iz
    tx = tx * tx * (3 - 2 * tx)
    tz = tz * tz * (3 - 2 * tz)
    local a = hash2(ix, iz, salt)
    local b = hash2(ix + 1, iz, salt)
    local c = hash2(ix, iz + 1, salt)
    local d = hash2(ix + 1, iz + 1, salt)
    return (a + (b - a) * tx) * (1 - tz) + (c + (d - c) * tx) * tz
end

-- Riverbeds and shores: gravel, clay and sand instead of bare stone/dirt,
-- loose stones along the banks.
-- Note: the engine treats ":block" positions as world coordinates
-- (unlike structure placements, which are chunk-relative).
local function place_shores(placements, x, z, w, d, hmap, chunk_height)
    for lz = 0, d - 1 do
        for lx = 0, w - 1 do
            local h = math.floor(hmap:at(lx, lz) * chunk_height)
            local wx, wz = x + lx, z + lz
            local n = value_noise(wx, wz, 9, 1)
            if h < SEA_LEVEL then
                local id = n < 0.45 and GRAVEL or (n < 0.68 and CLAY or SAND)
                table.insert(placements, {":block", id, {wx, h, wz}, 0, 3})
                table.insert(placements, {":block", id, {wx, h - 1, wz}, 0, 3})
            elseif h <= SEA_LEVEL + 1 then
                local id = n < 0.3 and CLAY or (n < 0.55 and GRAVEL or SAND)
                table.insert(placements, {":block", id, {wx, h, wz}, 0, 3})
                local r = hash2(wx, wz, 2)
                if r < 0.04 then
                    table.insert(placements, {":block", ROCK, {wx, h + 1, wz}, 0, 3})
                elseif r < 0.05 then
                    table.insert(placements, {":block", FLINT, {wx, h + 1, wz}, 0, 3})
                end
            end
        end
    end
end

-- Biome selection ----------------------------------------------------------
-- place_structures() gets no biome info, so the engine's choice is repeated
-- here exactly: same parameter maps, same resize/crop, same score formula.
local BIOMES_BPD = 4
local biome_list = {}
for name, biome in pairs(file.read_combined_object(dir .. "/biomes.toml")) do
    table.insert(biome_list, {name = name, params = biome.parameters})
end

local function chunk_biomes(x, z, w, d)
    local bpd = BIOMES_BPD
    local maps = {generate_biome_parameters(
        math.floor(x / bpd), math.floor(z / bpd),
        math.floor(w / bpd) + 1, math.floor(d / bpd) + 1, bpd)}
    for _, map in ipairs(maps) do
        map:resize(w + bpd, d + bpd, "linear")
        map:crop(0, 0, w, d)
    end
    local result = {}
    for lz = 0, d - 1 do
        for lx = 0, w - 1 do
            local best, best_score = nil, math.huge
            for _, biome in ipairs(biome_list) do
                local score = 0
                for i, map in ipairs(maps) do
                    local p = biome.params[i]
                    score = score + math.abs((map:at(lx, lz) - p.value) / p.weight)
                end
                if score < best_score then
                    best, best_score = biome.name, score
                end
            end
            result[lz * w + lx] = best
        end
    end
    return result
end

-- Procedural trees -------------------------------------------------------------
-- per biome: chance per surface column, species weights, min spacing
local TREES = {
    taiga = {chance = 0.035, spacing = 3, species = {{"spruce", 1}}},
    tundra = {chance = 0.003, spacing = 4, species = {{"tundra_spruce", 1}}},
    tropics = {chance = 0.03, spacing = 5, species = {{"jungle", 1}}},
    desert = {chance = 0.004, spacing = 4, species = {{"cactus", 1}}},
}
-- palms grow on low shores of hot biomes
local PALM_BIOMES = {tropics = 0.04, desert = 0.012}

local function pick(species, r)
    local total = 0
    for _, s in ipairs(species) do total = total + s[2] end
    r = r * total
    for _, s in ipairs(species) do
        r = r - s[2]
        if r <= 0 then return s[1] end
    end
    return species[#species][1]
end

local function place_trees(placements, x, z, w, d, hmap, chunk_height)
    local biomes = chunk_biomes(x, z, w, d)
    local put = trees.placer(placements)
    local planted = {}
    local rng = random.Random()
    for lz = 0, d - 1 do
        for lx = 0, w - 1 do
            local name = biomes[lz * w + lx]
            local wx, wz = x + lx, z + lz
            local h = math.floor(hmap:at(lx, lz) * chunk_height)
            local species = nil
            local spacing = 3
            local r = hash2(wx, wz, 7)
            local palm = PALM_BIOMES[name]
            if palm and h >= SEA_LEVEL and h <= SEA_LEVEL + 2 and r < palm then
                species = "palm"
            elseif TREES[name] and h >= SEA_LEVEL and r < TREES[name].chance then
                species = pick(TREES[name].species, hash2(wx, wz, 8))
                spacing = TREES[name].spacing
            end
            if species then
                local free = true
                for _, t in ipairs(planted) do
                    if math.abs(t[1] - lx) < spacing and math.abs(t[2] - lz) < spacing then
                        free = false
                        break
                    end
                end
                if free then
                    table.insert(planted, {lx, lz})
                    rng:seed(math.abs(wx * 73856093 + wz * 19349663 + SEED) % 2147483647)
                    trees[species](put, wx, h + 1, wz, rng)
                end
            end
        end
    end
end

function place_structures(x, z, w, d, hmap, chunk_height)
    local placements = {}
    ores.place(placements, x, z, w, d, SEED, hmap, chunk_height)
    place_shores(placements, x, z, w, d, hmap, chunk_height)
    place_trees(placements, x, z, w, d, hmap, chunk_height)
    return placements
end

function place_structures_wide(x, z, w, d, chunk_height)
    local placements = {}
    local rands = gen_parameters(11, SEED, x, z)
    if rands[1] < 0.05 then -- generate caves

        local sx = x + rands[2] * 10 - 5
        local sy = rands[3] * (chunk_height / 4) + 10
        local sz = z + rands[4] * 10 - 5

        local dir = rands[5] * math.pi * 2
        local dir_inertia = (rands[6] - 0.5) * 2
        local elevation = -3
        local width = rands[7] * 3 + 2

        for i=1,18 do
            local dx = math.sin(dir) * 10
            local dz = -math.cos(dir) * 10

            local ex = sx + dx
            local ey = sy + elevation
            local ez = sz + dz

            table.insert(placements, 
                {":line", 0, {sx, sy, sz}, {ex, ey, ez}, width})

            sx = ex
            sy = ey
            sz = ez

            dir_inertia = dir_inertia * 0.8 + 
                (rands[8] - 0.5) * math.pow(rands[9], 2) * 8
            elevation = elevation * 0.9 + 
                (rands[10] - 0.4) * (1.0-math.pow(rands[11], 4)) * 8
            dir = dir + dir_inertia
        end
    end
    return placements
end

function generate_heightmap(x, y, w, h, s, inputs)
    local umap = Heightmap(w, h)
    local vmap = Heightmap(w, h)
    umap.noiseSeed = SEED
    vmap.noiseSeed = SEED
    vmap:noise({x+521, y+70}, 0.1*s, 3, 25.8)
    vmap:noise({x+95, y+246}, 0.15*s, 3, 25.8)

    local map = Heightmap(w, h)
    map.noiseSeed = SEED
    map:noise({x, y}, 0.8*s, 4, 0.02)
    map:cellnoise({x, y}, 0.1*s, 3, 0.3, umap, vmap)
    map:add(0.7)

    local rivermap = Heightmap(w, h)
    rivermap.noiseSeed = SEED
    rivermap:noise({ x + 21, y + 12 }, 0.1 * s, 4)
    rivermap:pow(4)
    rivermap:mul(3500)
    rivermap:add(1)
    rivermap:pow(-1)
    rivermap:mul(-1)
    rivermap:add(1)

    local rivermap_bottom = Heightmap(w, h)
    rivermap_bottom:add(0.23)
    rivermap_bottom:noise({ x, y }, 2 * s, 4, 0.005)

    map:sub(rivermap_bottom)

    local map_multiplied = Heightmap(w, h)
    map_multiplied:add(map)
    map_multiplied:mul(rivermap)

    map:min(map_multiplied)

    map:add(rivermap_bottom)

    -- dunes replace the relief only where it is hot and dry
    local desertmap = Heightmap(w, h)
    desertmap.noiseSeed = SEED
    desertmap:cellnoise({x+52, y+326}, 0.3*s, 2, 0.2)
    desertmap:add(0.5)
    local heat = Heightmap(w, h)
    heat:add(inputs[1])
    heat:sub(0.6)
    heat:mul(4)
    heat:max(0)
    heat:min(1)
    local dryness = Heightmap(w, h)
    dryness:add(0.5)
    dryness:sub(inputs[2])
    dryness:mul(4)
    dryness:max(0)
    dryness:min(1)
    heat:mul(dryness)
    map:mixin(desertmap, heat)
    return map
end

-- Temperature and humidity, both ~0.2..0.8 (noise is roughly +-0.85 at p10/p90)
function generate_biome_parameters(x, y, w, h, s)
    local tempmap = Heightmap(w, h)
    tempmap.noiseSeed = SEED + 5324
    tempmap:noise({x, y}, 0.05*s, 6)
    tempmap:mul(0.35)
    tempmap:add(0.5)
    local hummap = Heightmap(w, h)
    hummap.noiseSeed = SEED + 953
    hummap:noise({x, y}, 0.05*s, 6)
    hummap:mul(0.35)
    hummap:add(0.5)
    return tempmap, hummap
end
