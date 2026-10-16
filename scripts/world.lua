local stats = require "survival/stats"
local temperature = require "survival/temperature"
local breaking = require "survival/breaking"
local mode = require "survival/mode"
local spawning = require "fauna/spawning"
local flight = require "player/flight"
local flow = require "water/flow"
local campfire = require "fire/campfire"
local vat = require "leather/vat"
local beam = require "leather/beam"
local soaking = require "leather/soaking"
local ranged = require "combat/ranged"
local boat = require "boat/boat"
local dugout = require "boat/dugout"
local chest = require "storage/chest"
local pit_kiln = require "fire/pit_kiln"
local trough = require "husbandry/trough"
local fishing = require "fishing/fishing"
local farming = require "farming/farming"
local calendar = require "world/calendar"
local sleep = require "player/sleep"
local notice = require "player/notice"
local riding = require "riding/riding"
local leash = require "riding/leash"

local EYE_HEIGHT = 0.7
local FIELD_CHECK = 1.0    -- seconds between bringing the fields around a player up to date

local field_timers = {}

function on_world_open()
    mode.init()
    flight.init()
    calendar.load()
    stats.load()
    flow.load()
    campfire.load()
    pit_kiln.load()
    vat.load()
    beam.load()
end

function on_world_save()
    calendar.save()
    stats.save()
    flow.save()
    campfire.save()
    pit_kiln.save()
    vat.save()
    beam.save()
end

function on_world_tick()
    breaking.update()
    flow.tick()
    campfire.tick(1 / 20)
    pit_kiln.tick(1 / 20)
    vat.tick(1 / 20)
    soaking.tick(1 / 20)
    ranged.tick()
    sleep.tick(1 / 20)
end

-- crops and farmland near a player show the time passed
local function check_fields(playerid, dt)
    local t = (field_timers[playerid] or 0) + dt
    if t >= FIELD_CHECK then
        t = 0
        local x, y, z = player.get_pos(playerid)
        farming.refresh_around(x, y, z)
    end
    field_timers[playerid] = t
end

function on_player_tick(playerid, tps)
    flight.apply(playerid)
    riding.tick(playerid)
    boat.tick(playerid, riding.seated_in(playerid) ~= nil)
    check_fields(playerid, 1 / tps)
    if not mode.enabled() then
        mode.apply_creative(playerid)
        return
    end
    mode.apply_player(playerid)
    local vx, _, vz = player.get_vel(playerid)
    stats.tick(playerid, 1 / tps, vec2.length({vx, vz}))
    temperature.tick(playerid, 1 / tps)
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
        spawning.populate_water(x, z)
    end
end

function on_world_quit()
    breaking.reset()
    boat.reset()
    riding.reset()
    leash.reset()
    dugout.reset()
    chest.reset()
    trough.reset()
    fishing.reset()
    mode.reset()
    stats.reset()
    flow.reset()
    campfire.reset()
    pit_kiln.reset()
    temperature.reset()
    vat.reset()
    beam.reset()
    soaking.reset()
    ranged.reset()
    farming.reset()
    calendar.reset()
    sleep.reset()
    notice.reset()
    field_timers = {}
end
