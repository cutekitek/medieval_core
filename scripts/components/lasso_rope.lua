-- The rope of a lasso from an animal to the hand that leads it or round a
-- fence post (with a knot there). Sags when slack. Lives as long as the
-- animal is held (not saved: the animal spawns it again). Logic:
-- modules/riding/leash.lua, components/animal.lua
local leash = require "riding/leash"

local tsf = entity.transform
local rig = entity.skeleton

local SEGMENTS = 10
local BOX = 0.03              -- thickness of a segment in the model
local THICKNESS = 0.035

local animal_uid = ARGS and ARGS.animal
local bones = nil
local knot = rig:index("knot")

local function animal()
    local e = animal_uid and entities.get(animal_uid)
    return e and e:get_component("medieval_core:animal")
end

local function segment_matrix(a, b, origin)
    local d = vec3.sub(b, a)
    local len = vec3.length(d)
    if len < 1e-4 then
        return mat4.scale({0, 0, 0})
    end
    local yaw = math.deg(math.atan2(d[1], d[3]))
    local pitch = -math.deg(math.atan2(d[2], math.sqrt(d[1] * d[1] + d[3] * d[3])))
    local k = THICKNESS / BOX
    local m = mat4.translate(vec3.sub(a, origin))
    m = mat4.mul(m, mat4.rotate({0, 1, 0}, yaw))
    m = mat4.mul(m, mat4.rotate({1, 0, 0}, pitch))
    return mat4.mul(m, mat4.scale({k, k, len}))
end

local function alive()
    local ai = animal()
    if not ai or not ai.get_leash() then
        entity:despawn()
        return nil
    end
    return ai
end

function on_physics_update()
    alive()
end

function on_render()
    local ai = alive()
    if not ai then
        return
    end
    local holder = ai.get_leash()
    local a = leash.anchor(holder)
    if not a then
        rig:set_visible(false)
        return
    end
    rig:set_visible(true)
    if not bones then
        bones = {}
        for i = 0, SEGMENTS - 1 do
            bones[i + 1] = rig:index("seg" .. i)
        end
    end
    local b = ai.rope_point()
    tsf:set_pos(a)
    if knot then
        rig:set_visible(knot, holder.post ~= nil)
    end
    -- a slack rope hangs (parabola of the same length), a taut one is straight
    local dist = vec3.distance(a, b)
    local slack = math.max(0, leash.LENGTH - dist)
    local sag = math.min(0.9, math.sqrt(3 * math.max(dist, 0.3) * slack / 8))
    local prev = a
    for i = 1, SEGMENTS do
        local t = i / SEGMENTS
        local p = {
            a[1] + (b[1] - a[1]) * t,
            a[2] + (b[2] - a[2]) * t - sag * 4 * t * (1 - t),
            a[3] + (b[3] - a[3]) * t,
        }
        rig:set_matrix(bones[i], segment_matrix(prev, p, a))
        prev = p
    end
end
