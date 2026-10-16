-- Level of detail for animals. The engine draws every entity in view however
-- far it is (the models are put together on the CPU every frame) and runs
-- the physics of all of them: with a large load distance hundreds of
-- animals cost most of the frame. So far from every player an animal rests
-- (no physics, no AI, no animation), and its model is not drawn beyond the
-- species' draw distance from the camera.
local this = {}

this.SIM_DISTANCE = 96        -- m to the nearest player: further an animal rests
this.WAKE_MARGIN = 8          -- it wakes up again this much closer
this.DRAW_DISTANCE = 128      -- m from the camera (species.draw_distance)
this.CHECK_EVERY = 0.5        -- s between the checks of one animal

-- distance to the nearest player
function this.player_distance(pos)
    local best = math.huge
    for _, pid in ipairs(player.get_all()) do
        local x, y, z = player.get_pos(pid)
        local dx, dy, dz = x - pos[1], y - pos[2], z - pos[3]
        best = math.min(best, dx * dx + dy * dy + dz * dz)
    end
    return math.sqrt(best)
end

-- distance to the local camera (0 without a screen: always "visible")
function this.view_distance(pos)
    if not hud then
        return 0
    end
    local x, y, z = player.get_pos(hud.get_player())
    return vec3.distance(pos, {x, y, z})
end

return this
