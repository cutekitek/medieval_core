require "kinetics/content"
local network = require "kinetics/network"
local stats = require "survival/stats"
local breaking = require "survival/breaking"
local mode = require "survival/mode"
local spawning = require "fauna/spawning"
local flight = require "player/flight"
local flow = require "water/flow"

local EYE_HEIGHT = 0.7

function on_world_open()
    mode.init()
    flight.init()
    stats.load()
    flow.load()
end

function on_world_save()
    stats.save()
    flow.save()
end

function on_world_tick()
    network.tick(1 / 20)
    breaking.update()
    flow.tick()
end

function on_player_tick(playerid, tps)
    flight.apply(playerid)
    if not mode.enabled() then
        return
    end
    mode.apply_player(playerid)
    local vx, _, vz = player.get_vel(playerid)
    stats.tick(playerid, 1 / tps, vec2.length({vx, vz}))
    local x, y, z = player.get_pos(playerid)
    stats.tick_air(playerid, 1 / tps,
        flow.in_water(x, y + EYE_HEIGHT, z) and not player.is_flight(playerid))
end

-- any block change by a player may let water flow
function on_block_broken(blockid, x, y, z, playerid)
    flow.notify(x, y, z)
end

function on_block_placed(blockid, x, y, z, playerid)
    flow.notify(x, y, z)
end

function on_block_breaking(blockid, x, y, z, playerid)
    if mode.enabled() then
        breaking.hit(blockid, x, y, z, playerid)
    end
end

function on_chunk_present(x, z, loaded)
    if not loaded then
        spawning.populate(x, z)
    end
end

function on_world_quit()
    network.reset()
    breaking.reset()
    stats.reset()
    flow.reset()
end
