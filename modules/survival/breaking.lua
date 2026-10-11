-- Timed block breaking for survival.
-- The engine fires on_block_breaking every ~0.16 s while the destroy button is
-- held; progress accumulates per player and resets when the target changes.
local drops = require "survival/drops"
local chest = require "storage/chest"

local this = {}

local HIT_INTERVAL = 0.16
local MAX_STEP = 0.3        -- longer gaps mean the player stopped breaking
local RESET_AFTER = 0.4     -- seconds without hits before cracks disappear
local CRACK_STAGES = 11     -- textures cracks/cracks_0 .. cracks_10
local DEFAULT_HARDNESS = 1.0
local UNBREAKABLE = 1e6

local HIT_SOUND_INTERVAL = 0.25
local HIT_SOUND_VOLUME = 0.55

local states = {}  -- pid -> {x, y, z, id, progress, last, wrap, next_sound}

-- Hit sounds while breaking (sounds/medieval_core/dig_<kind>_N): the kind comes
-- from the block name first (leaves, gravel, ice), then from its material.
local NAME_SOUND = {
    {"leaves", "leaves"}, {"bush", "leaves"}, {"vine", "leaves"},
    {"gravel", "gravel"}, {"loose_rock", "gravel"}, {"loose_flint", "gravel"},
    {"ice", "glass"},
}
local MATERIAL_SOUND = {
    ["base:wood"] = "wood",
    ["base:grass"] = "plant",
    ["base:ground"] = "dirt",
    ["base:grass_block"] = "dirt",
    ["base:sand"] = "sand",
    ["base:snow"] = "snow",
    ["base:glass"] = "glass",
}
local sound_kinds = {}

function this.sound_kind(blockid)
    local kind = sound_kinds[blockid]
    if kind == nil then
        local name = block.name(blockid):match(":(.+)$") or block.name(blockid)
        for _, rule in ipairs(NAME_SOUND) do
            if name:find(rule[1], 1, true) then
                kind = rule[2]
                break
            end
        end
        kind = kind or MATERIAL_SOUND[block.material(blockid)] or "stone"
        sound_kinds[blockid] = kind
    end
    return kind
end

local function play_hit(state)
    audio.play_sound("medieval_core/dig_" .. this.sound_kind(state.id),
        state.x + 0.5, state.y + 0.5, state.z + 0.5,
        HIT_SOUND_VOLUME, 0.9 + math.random() * 0.2, "regular")
end

-- Tools: item user property "medieval_core:tool" = {type=..., speed=...}.
-- A tool is faster on the blocks of its material and wears out on them
-- (item property "uses"). Bare hands = 1.
local MATERIAL_TOOL = {
    ["base:stone"] = "pick",
    ["base:metal"] = "pick",
    ["base:wood"] = "axe",
    ["base:ground"] = "shovel",
    ["base:sand"] = "shovel",
    ["base:snow"] = "shovel",
    ["base:grass_block"] = "shovel",
    ["base:grass"] = "knife",
}

-- the held tool's definition if it suits the block, else nil
function this.tool_for(pid, blockid)
    local invid, slot = player.get_inventory(pid)
    local itemid = inventory.get(invid, slot)
    if itemid == 0 then
        return nil
    end
    local props = item.properties and item.properties[itemid]
    local tool = props and props["medieval_core:tool"]
    if tool and MATERIAL_TOOL[block.material(blockid)] == tool.type then
        return tool
    end
    return nil
end

local function tool_speed(pid, blockid)
    local tool = this.tool_for(pid, blockid)
    return tool and tool.speed or 1.0
end

function this.hardness(blockid)
    local props = block.properties[blockid]
    local durability = props and props["base:durability"]
    if durability == nil then
        return DEFAULT_HARDNESS
    end
    return durability
end

local function clear_cracks(state)
    if state.wrap and gfx then
        gfx.blockwraps.unwrap(state.wrap)
    end
    state.wrap = nil
end

local function show_cracks(state)
    if not gfx then
        return
    end
    local stage = math.min(CRACK_STAGES - 1, math.floor(state.progress * CRACK_STAGES))
    local texture = "cracks/cracks_" .. stage
    if not state.wrap then
        state.wrap = gfx.blockwraps.wrap({state.x, state.y, state.z}, texture)
    elseif state.stage ~= stage then
        gfx.blockwraps.set_texture(state.wrap, texture)
    end
    state.stage = stage
end

function this.cancel(pid)
    local state = states[pid]
    if state then
        clear_cracks(state)
        states[pid] = nil
    end
end

local function finish(state, pid)
    this.cancel(pid)
    local id = state.id
    if block.get(state.x, state.y, state.z) ~= id then
        return
    end
    local tool = this.tool_for(pid, id)
    local variant = block.get_variant(state.x, state.y, state.z)
    -- the engine deletes a block's inventory with the block: empty it first
    chest.spill(state.x, state.y, state.z)
    block.destruct(state.x, state.y, state.z, pid)
    drops.spawn(id, state.x, state.y, state.z, tool and tool.type, variant)
    if tool and not player.is_infinite_items(pid) then
        local invid, slot = player.get_inventory(pid)
        inventory.use(invid, slot)
    end
end

-- Called on every breaking event; dt may be given explicitly (tests)
function this.hit(blockid, x, y, z, pid, dt)
    if player.is_instant_destruction(pid) then
        return
    end
    local hardness = this.hardness(blockid)
    if hardness >= UNBREAKABLE then
        return
    end
    local now = time.uptime()
    local state = states[pid]
    if not state or state.x ~= x or state.y ~= y or state.z ~= z or state.id ~= blockid then
        this.cancel(pid)
        state = {x = x, y = y, z = z, id = blockid, progress = 0, last = now}
        states[pid] = state
        dt = dt or HIT_INTERVAL
    else
        dt = dt or math.min(now - state.last, MAX_STEP)
    end
    state.last = now

    local time_needed = hardness / tool_speed(pid, blockid)
    if time_needed <= 0 then
        state.progress = 1
    else
        state.progress = state.progress + dt / time_needed
    end
    if state.progress >= 1 then
        finish(state, pid)
    else
        show_cracks(state)
        if not state.next_sound or now >= state.next_sound then
            state.next_sound = now + HIT_SOUND_INTERVAL
            play_hit(state)
            this.hits_played = (this.hits_played or 0) + 1
        end
    end
end

function this.get_progress(pid)
    local state = states[pid]
    return state and state.progress or 0
end

-- Drops stale progress when the player let go of the button
function this.update()
    local now = time.uptime()
    for pid, state in pairs(states) do
        if now - state.last > RESET_AFTER then
            this.cancel(pid)
        end
    end
end

function this.reset()
    for pid in pairs(states) do
        this.cancel(pid)
    end
    states = {}
end

return this
