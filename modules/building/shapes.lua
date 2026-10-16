-- Building shapes (blocks from dev/gen_building_assets.py), Minecraft-like:
--   * stairs, slabs and roof slopes are placed by where the cursor hits a
--     block: the upper half of a side or a ceiling turns them upside down;
--     stairs and slopes rise in the direction the player looks;
--   * stairs take corner shapes from their neighbours (separate block ids
--     <mat>_stairs_inner / _outer, so the collision fits; a corner keeps the
--     facing it was placed with in its user bits);
--   * two slabs (or two vertical slabs) in one cell merge into the full
--     block of the material (planks / bricks);
--   * vertical slabs stand against the clicked side; on a floor or ceiling
--     on the half nearest to the cursor;
--   * columns go along the clicked face's axis like logs and grow a base and
--     a capital at their free ends (variants);
--   * fences connect to fences, gates across their line and solid blocks
--     (16 variants); gates open away from the player.
-- The facing of every shape model is local -Z.
local catalog = require "building/catalog"

local this = {}

local P = "medieval_core:"
this.EYE_HEIGHT = 0.7

-- the forms of a material besides the input items listed in the catalogue
local FORMS = {
    wood = {"planks", "hewn", "stairs", "slab", "vslab", "column", "roof", "fence", "gate", "ladder"},
    stone = {"hewn", "bricks", "stairs", "slab", "vslab", "column", "roof"},
}
this.FORMS = FORMS

-- longest suffixes first
local KINDS = {"stairs_inner", "stairs_outer", "gate_open", "stairs", "vslab", "slab",
               "column", "roof", "fence", "gate", "ladder", "planks", "hewn", "bricks"}

local materials = {}
for _, m in ipairs(catalog) do
    materials[m.name] = m
end
this.materials = materials

function this.block_name(mat, kind)
    return P .. mat .. "_" .. kind
end

function this.block_of(mat, kind)
    return block.index(this.block_name(mat, kind))
end

-- block id -> {mat = material name, kind = shape kind} or nil
local info_cache = {}
function this.info(id)
    local cached = info_cache[id]
    if cached ~= nil then
        return cached or nil
    end
    local result = false
    local name = block.name(id)
    if name:sub(1, #P) == P then
        local rest = name:sub(#P + 1)
        for _, kind in ipairs(KINDS) do
            local suffix = "_" .. kind
            if #rest > #suffix and rest:sub(-#suffix) == suffix then
                local mat = rest:sub(1, -#suffix - 1)
                if materials[mat] then
                    result = {mat = mat, kind = kind}
                    break
                end
            end
        end
    end
    info_cache[id] = result
    return result or nil
end

-- rotations -------------------------------------------------------------------

-- the "stairs" profile (0..3 = pane): axes X, Y, Z of every rotation
local STAIRS_AXES = {
    [0] = {{1, 0, 0}, {0, 1, 0}, {0, 0, 1}},
    {{0, 0, -1}, {0, 1, 0}, {1, 0, 0}},
    {{-1, 0, 0}, {0, 1, 0}, {0, 0, -1}},
    {{0, 0, 1}, {0, 1, 0}, {-1, 0, 0}},
    {{-1, 0, 0}, {0, -1, 0}, {0, 0, 1}},
    {{0, 0, 1}, {0, -1, 0}, {1, 0, 0}},
    {{1, 0, 0}, {0, -1, 0}, {0, 0, -1}},
    {{0, 0, -1}, {0, -1, 0}, {-1, 0, 0}},
}
-- the Y axis of the "pipe" rotations (column axis)
local PIPE_UP = {[0] = {0, 0, 1}, {-1, 0, 0}, {0, 0, -1}, {1, 0, 0}, {0, 1, 0}, {0, -1, 0}}

-- horizontal facings: the rotation index of a pane / stairs block looking there
local DIRS = {[0] = {0, 0, -1}, {-1, 0, 0}, {0, 0, 1}, {1, 0, 0}}     -- N, W, S, E
this.DIRS = DIRS

local function ccw(f) return (f + 1) % 4 end    -- to the left
local function cw(f) return (f + 3) % 4 end     -- to the right
local function opposite(f) return (f + 2) % 4 end

-- facing index of a horizontal direction (dominant axis)
function this.facing_of(dir)
    if math.abs(dir[1]) > math.abs(dir[3]) then
        return dir[1] > 0 and 3 or 1
    end
    return dir[3] > 0 and 2 or 0
end

-- octants of a cell: bit ix + 2*iy + 4*iz (each 0 = lower half of the axis)
local function octant_bit(ix, iy, iz)
    return 2 ^ (ix + 2 * iy + 4 * iz)
end

local function has_bit(mask, bit)
    return math.floor(mask / bit) % 2 == 1
end

local MODEL_OCTANTS = {
    stairs = {{0, 0, 0}, {1, 0, 0}, {0, 0, 1}, {1, 0, 1}, {0, 1, 0}, {1, 1, 0}},
    stairs_inner = {{0, 0, 0}, {1, 0, 0}, {0, 0, 1}, {1, 0, 1}, {0, 1, 0}, {1, 1, 0}, {0, 1, 1}},
    stairs_outer = {{0, 0, 0}, {1, 0, 0}, {0, 0, 1}, {1, 0, 1}, {0, 1, 0}},
}

-- kind -> rotation -> mask of the occupied world octants
local stair_masks = {}
for kind, octants in pairs(MODEL_OCTANTS) do
    stair_masks[kind] = {}
    for r = 0, 7 do
        local ax = STAIRS_AXES[r]
        local mask = 0
        for _, o in ipairs(octants) do
            local s = {o[1] * 2 - 1, o[2] * 2 - 1, o[3] * 2 - 1}
            local w = {}
            for i = 1, 3 do
                w[i] = s[1] * ax[1][i] + s[2] * ax[2][i] + s[3] * ax[3][i]
            end
            mask = mask + octant_bit(w[1] > 0 and 1 or 0, w[2] > 0 and 1 or 0, w[3] > 0 and 1 or 0)
        end
        stair_masks[kind][r] = mask
    end
end

-- stairs ----------------------------------------------------------------------

local function is_stairs_kind(kind)
    return kind == "stairs" or kind == "stairs_inner" or kind == "stairs_outer"
end

-- facing and upper-half flag of the stairs at x, y, z, or nil
function this.stairs_state(x, y, z)
    local inf = this.info(block.get(x, y, z))
    if not inf or not is_stairs_kind(inf.kind) then
        return nil
    end
    local rot = block.get_rotation(x, y, z)
    local facing = rot % 4
    if inf.kind ~= "stairs" then
        facing = block.get_user_bits(x, y, z, 0, 2)
    end
    return facing, rot >= 4
end

local function rel(x, y, z, f)
    local d = DIRS[f]
    return x + d[1], y, z + d[3]
end

-- the neighbour in direction d is not stairs facing like these ones
local function can_take_shape(x, y, z, f, top, d)
    local nf, ntop = this.stairs_state(rel(x, y, z, d))
    return not (nf ~= nil and nf == f and ntop == top)
end

-- Minecraft's StairBlock.getStairsShape
function this.stairs_shape(x, y, z, f, top)
    local bf, btop = this.stairs_state(rel(x, y, z, f))
    if bf ~= nil and btop == top and bf % 2 ~= f % 2 and
       can_take_shape(x, y, z, f, top, opposite(bf)) then
        return bf == ccw(f) and "outer_left" or "outer_right"
    end
    local ff, ftop = this.stairs_state(rel(x, y, z, opposite(f)))
    if ff ~= nil and ftop == top and ff % 2 ~= f % 2 and
       can_take_shape(x, y, z, f, top, ff) then
        return ff == ccw(f) and "inner_left" or "inner_right"
    end
    return "straight"
end

-- octants of a stairs shape in the world
local function shape_mask(f, top, shape)
    local full, part = top and 1 or 0, top and 0 or 1
    local sides
    if shape == "straight" then
        sides = function(dx, dz) return dx * DIRS[f][1] + dz * DIRS[f][3] > 0 end
    else
        local side = (shape == "outer_left" or shape == "inner_left") and ccw(f) or cw(f)
        local inner = shape:sub(1, 5) == "inner"
        sides = function(dx, dz)
            local a = dx * DIRS[f][1] + dz * DIRS[f][3] > 0
            local b = dx * DIRS[side][1] + dz * DIRS[side][3] > 0
            if inner then
                return a or b
            end
            return a and b
        end
    end
    local mask = 0
    for ix = 0, 1 do
        for iz = 0, 1 do
            mask = mask + octant_bit(ix, full, iz)
            if sides(ix * 2 - 1, iz * 2 - 1) then
                mask = mask + octant_bit(ix, part, iz)
            end
        end
    end
    return mask
end

-- block kind and rotation drawing a stairs shape
function this.stairs_block(f, top, shape)
    local mask = shape_mask(f, top, shape)
    local first = top and 4 or 0
    for _, kind in ipairs({"stairs", "stairs_inner", "stairs_outer"}) do
        for r = first, first + 3 do
            if stair_masks[kind][r] == mask and (kind ~= "stairs" or r % 4 == f) then
                return kind, r
            end
        end
    end
    return "stairs", f + first
end

-- recomputes the shape of the stairs at x, y, z from their neighbours
function this.update_stairs(x, y, z)
    local id = block.get(x, y, z)
    local inf = this.info(id)
    if not inf or not is_stairs_kind(inf.kind) then
        return
    end
    local f, top = this.stairs_state(x, y, z)
    local kind, rot = this.stairs_block(f, top, this.stairs_shape(x, y, z, f, top))
    local want = this.block_of(inf.mat, kind)
    local bits = kind == "stairs" and 0 or f
    if want ~= id or rot ~= block.get_rotation(x, y, z) or
       (kind ~= "stairs" and block.get_user_bits(x, y, z, 0, 2) ~= f) then
        block.set(x, y, z, want, rot + bits * 256)
    end
end

-- columns ---------------------------------------------------------------------

local function column_axis(x, y, z)
    local inf = this.info(block.get(x, y, z))
    if not inf or inf.kind ~= "column" then
        return nil
    end
    return PIPE_UP[block.get_rotation(x, y, z)] or PIPE_UP[4]
end

local function parallel(a, b)
    return a and b and math.abs(a[1] * b[1] + a[2] * b[2] + a[3] * b[3]) > 0.5
end

-- variant: bit 1 = a base at the lower end, bit 2 = a capital at the upper
function this.update_column(x, y, z)
    local up = column_axis(x, y, z)
    if not up then
        return
    end
    local above = column_axis(x + up[1], y + up[2], z + up[3])
    local below = column_axis(x - up[1], y - up[2], z - up[3])
    local variant = (parallel(up, below) and 0 or 1) + (parallel(up, above) and 0 or 2)
    if block.get_variant(x, y, z) ~= variant then
        block.set_variant(x, y, z, variant)
    end
end

-- fences and gates ------------------------------------------------------------

local FENCE_BITS = {{0, 0, -1, 1}, {1, 0, 0, 2}, {0, 0, 1, 4}, {-1, 0, 0, 8}}
local FENCE_TAG = P .. "fence"
local GATE_TAG = P .. "gate"

-- the panel of a gate with this rotation runs along X
local function gate_along_x(rot)
    return rot % 2 == 0
end

local function fence_connects(x, y, z, dx, dz)
    local id = block.get(x, y, z)
    if id <= 0 then
        return false
    end
    if block.has_tag(id, FENCE_TAG) then
        return true
    end
    if block.has_tag(id, GATE_TAG) then
        return gate_along_x(block.get_rotation(x, y, z)) == (dx ~= 0)
    end
    return block.is_solid_at(x, y, z)
end

function this.fence_mask(x, y, z)
    local mask = 0
    for _, b in ipairs(FENCE_BITS) do
        if fence_connects(x + b[1], y, z + b[3], b[1], b[3]) then
            mask = mask + b[4]
        end
    end
    return mask
end

function this.update_fence(x, y, z)
    if not block.has_tag(block.get(x, y, z), FENCE_TAG) then
        return
    end
    local mask = this.fence_mask(x, y, z)
    if block.get_variant(x, y, z) ~= mask then
        block.set_variant(x, y, z, mask)
    end
end

function this.is_gate_open(x, y, z)
    local inf = this.info(block.get(x, y, z))
    return inf and inf.kind == "gate_open"
end

-- opens a closed gate away from the player (pid may be nil) or closes it
function this.toggle_gate(x, y, z, pid)
    local inf = this.info(block.get(x, y, z))
    if not inf or (inf.kind ~= "gate" and inf.kind ~= "gate_open") then
        return false
    end
    local rot = block.get_rotation(x, y, z)
    if inf.kind == "gate_open" then
        block.set(x, y, z, this.block_of(inf.mat, "gate"), rot)
        audio.play_sound("medieval_core/gate_close", x + 0.5, y + 0.5, z + 0.5, 0.9,
            0.95 + math.random() * 0.1, "regular")
        return true
    end
    -- the open leaves swing to local -Z: keep the player on the +Z side
    local zaxis = STAIRS_AXES[rot][3]
    if pid then
        local px, _, pz = player.get_pos(pid)
        if (px - x - 0.5) * zaxis[1] + (pz - z - 0.5) * zaxis[3] < 0 then
            rot = (rot + 2) % 4
        end
    end
    block.set(x, y, z, this.block_of(inf.mat, "gate_open"), rot)
    audio.play_sound("medieval_core/gate_open", x + 0.5, y + 0.5, z + 0.5, 0.9,
        0.95 + math.random() * 0.1, "regular")
    return true
end

local LADDER_TAG = P .. "ladder"
function this.is_ladder_at(x, y, z)
    local id = block.get(math.floor(x), math.floor(y), math.floor(z))
    return id > 0 and block.has_tag(id, LADDER_TAG)
end

-- placing ---------------------------------------------------------------------

-- where the player looks and what the ray hits (tests replace it: headless
-- player.get_dir ignores the rotation)
function this.aim(pid)
    local x, y, z = player.get_pos(pid)
    local dir = player.get_dir(pid)
    -- the engine selected the block within the player's reach (from the
    -- camera, a little off this eye point)
    local hit = block.raycast({x, y + this.EYE_HEIGHT, z}, dir, player.get_interaction_distance(pid) + 0.5)
    return dir, hit and hit.endpoint
end

-- blocks with their own use action: the item leaves them to the engine
local INTERACTIVE = {
    [P .. "workbench"] = true, [P .. "carpentry_table"] = true, [P .. "mason_table"] = true,
    [P .. "bed"] = true, [P .. "tanning_vat"] = true, [P .. "tanning_vat_water"] = true,
    [P .. "tanning_vat_tannin"] = true, [P .. "campfire"] = true, [P .. "campfire_lit"] = true,
}

local function interactive(id)
    return INTERACTIVE[block.name(id)] or block.has_tag(id, GATE_TAG)
end

-- something with a body (a player, an animal) in the world box
local function occupied(box)
    local c = {(box[1] + box[4]) / 2, (box[2] + box[5]) / 2, (box[3] + box[6]) / 2}
    for _, uid in ipairs(entities.get_all_in_radius(c, 3)) do
        local e = entities.get(uid)
        if e and e:get_component("core:mob") then
            local p = e.transform:get_pos()
            local s = e.rigidbody:get_size()
            if p[1] + s[1] / 2 > box[1] + 0.01 and p[1] - s[1] / 2 < box[4] - 0.01 and
               p[2] + s[2] / 2 > box[2] + 0.01 and p[2] - s[2] / 2 < box[5] - 0.01 and
               p[3] + s[3] / 2 > box[3] + 0.01 and p[3] - s[3] / 2 < box[6] - 0.01 then
                return true
            end
        end
    end
    return false
end

local function cell_box(x, y, z, x0, y0, z0, x1, y1, z1)
    return {x + x0, y + y0, z + z0, x + x1, y + y1, z + z1}
end

-- the world box of a half cell on side f (0..3) or the lower/upper half
local function half_box(x, y, z, f, top)
    if f == nil then
        return top and cell_box(x, y, z, 0, 0.5, 0, 1, 1, 1) or cell_box(x, y, z, 0, 0, 0, 1, 0.5, 1)
    end
    local d = DIRS[f]
    local x0, x1, z0, z1 = 0, 1, 0, 1
    if d[1] < 0 then x1 = 0.5 elseif d[1] > 0 then x0 = 0.5 end
    if d[3] < 0 then z1 = 0.5 elseif d[3] > 0 then z0 = 0.5 end
    return cell_box(x, y, z, x0, 0, z0, x1, 1, z1)
end

local function take_item(pid)
    if pid and not player.is_infinite_items(pid) then
        local invid, slot = player.get_inventory(pid)
        inventory.decrement(invid, slot, 1)
    end
end

local function place(x, y, z, id, state, pid, box)
    if not block.is_replaceable_at(x, y, z) then
        return false
    end
    if occupied(box or cell_box(x, y, z, 0, 0, 0, 1, 1, 1)) then
        return false
    end
    block.place(x, y, z, id, state, pid)
    if block.get(x, y, z) ~= id then
        return false
    end
    take_item(pid)
    return true
end

local function merge(x, y, z, inf, pid)
    local full = block.index(materials[inf.mat].full)
    block.set(x, y, z, full, 0)
    take_item(pid)
    return {x, y, z}
end

-- upper half by the cursor: a ceiling, or high on a side
local function upper(normal, hit, y)
    if normal[2] < 0 then
        return true
    elseif normal[2] > 0 then
        return false
    end
    return hit ~= nil and hit[2] - y > 0.5
end

local function place_slab(pid, id, inf, x, y, z, normal, hit)
    -- onto the open face of a slab: both halves
    if block.get(x, y, z) == id then
        local top = block.get_rotation(x, y, z) >= 4
        if (not top and normal[2] > 0) or (top and normal[2] < 0) then
            return merge(x, y, z, inf, pid)
        end
    end
    local tx, ty, tz = x + normal[1], y + normal[2], z + normal[3]
    local top = upper(normal, hit, y)
    if block.is_replaceable_at(x, y, z) and block.get(x, y, z) ~= id then
        tx, ty, tz = x, y, z
    end
    if block.get(tx, ty, tz) == id then
        if (block.get_rotation(tx, ty, tz) >= 4) ~= top then
            return merge(tx, ty, tz, inf, pid)
        end
        return nil
    end
    if place(tx, ty, tz, id, top and 4 or 0, pid, half_box(tx, ty, tz, nil, top)) then
        return {tx, ty, tz}
    end
end

local function place_vslab(pid, id, inf, x, y, z, normal, hit)
    if block.get(x, y, z) == id and normal[2] == 0 then
        local f = block.get_rotation(x, y, z) % 4
        local d = DIRS[f]
        if d[1] == -normal[1] and d[3] == -normal[3] then
            return merge(x, y, z, inf, pid)
        end
    end
    local tx, ty, tz = x + normal[1], y + normal[2], z + normal[3]
    if block.is_replaceable_at(x, y, z) and block.get(x, y, z) ~= id then
        tx, ty, tz = x, y, z
    end
    local f
    if normal[2] == 0 then
        f = this.facing_of({-normal[1], 0, -normal[3]})
    elseif hit then
        f = this.facing_of({hit[1] - x - 0.5, 0, hit[3] - z - 0.5})
    else
        f = 0
    end
    if block.get(tx, ty, tz) == id then
        if block.get_rotation(tx, ty, tz) % 4 == opposite(f) then
            return merge(tx, ty, tz, inf, pid)
        end
        return nil
    end
    if place(tx, ty, tz, id, f, pid, half_box(tx, ty, tz, f)) then
        return {tx, ty, tz}
    end
end

local function target_cell(x, y, z, normal)
    if block.is_replaceable_at(x, y, z) then
        return x, y, z, true
    end
    return x + normal[1], y + normal[2], z + normal[3], false
end

local function place_facing(pid, id, x, y, z, normal, hit, look)
    local tx, ty, tz = target_cell(x, y, z, normal)
    local f = this.facing_of(look)
    local top = upper(normal, hit, y)
    if place(tx, ty, tz, id, f + (top and 4 or 0), pid) then
        return {tx, ty, tz}
    end
end

local function place_column(pid, id, x, y, z, normal)
    local tx, ty, tz, replaced = target_cell(x, y, z, normal)
    local rot = 4
    if not replaced then
        if normal[1] > 0 then rot = 3 elseif normal[1] < 0 then rot = 1
        elseif normal[3] > 0 then rot = 0 elseif normal[3] < 0 then rot = 2 end
    end
    if place(tx, ty, tz, id, rot, pid, cell_box(tx, ty, tz, 0.125, 0, 0.125, 0.875, 1, 0.875)) then
        return {tx, ty, tz}
    end
end

-- Places the shape block id clicked at x, y, z (face normal) by player pid.
-- hit: the point the cursor hits, look: the view direction. Returns the
-- cell that changed or nil.
function this.place(pid, id, x, y, z, normal, hit, look)
    local inf = this.info(id)
    if not inf then
        return nil
    end
    local kind = inf.kind
    if kind == "slab" then
        return place_slab(pid, id, inf, x, y, z, normal, hit)
    elseif kind == "vslab" then
        return place_vslab(pid, id, inf, x, y, z, normal, hit)
    elseif kind == "column" then
        return place_column(pid, id, x, y, z, normal)
    elseif kind == "stairs" or kind == "roof" then
        return place_facing(pid, id, x, y, z, normal, hit, look)
    end
    return nil
end

-- item on_use_on_block: true = handled (the engine must not place it)
function this.use_item(pid, x, y, z, normal)
    if interactive(block.get(x, y, z)) then
        return false
    end
    local invid, slot = player.get_inventory(pid)
    local itemid = inventory.get(invid, slot)
    local id = item.placing_block(itemid)
    if not id or id <= 0 then
        return false
    end
    local look, hit = this.aim(pid)
    this.place(pid, id, x, y, z, normal, hit, look)
    return true
end

return this
