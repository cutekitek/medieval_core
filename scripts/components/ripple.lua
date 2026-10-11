-- A ring spreading on the water: grows to `size` and fades, then is gone.
-- Not kept over a reload.
local tsf = entity.transform
local rig = entity.skeleton

local LIFE = 1.5
local size = ARGS and ARGS.size
local t = 0

local function update(dt)
    t = t + dt
    if not size or t >= LIFE then
        entity:despawn()
        return false
    end
    local k = t / LIFE
    local s = 0.15 + (size - 0.15) * (1 - (1 - k) * (1 - k))
    tsf:set_size({s, 1, s})
    return true
end

function on_physics_update(delta)
    update(delta)
end

function on_render(delta)
    if size then
        rig:set_color({1, 1, 1, math.max(0, 1 - t / LIFE)})
    end
end
