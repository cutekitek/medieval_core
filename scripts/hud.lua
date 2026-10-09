local visual = require "kinetics/visual"
local stats = require "survival/stats"
local mode = require "survival/mode"
local flight = require "player/flight"
local flow = require "water/flow"

local DRINK_DISTANCE = 4.0
local DRINK_AMOUNT = 4
local EYE_HEIGHT = 0.7

local function try_drink()
    if hud.is_paused() or hud.is_inventory_open() or not mode.enabled() then
        return
    end
    local pid = hud.get_player()
    local invid, slot = player.get_inventory(pid)
    if inventory.get(invid, slot) ~= 0 then
        return
    end
    local x, y, z = player.get_pos(pid)
    local hit = block.raycast({x, y + EYE_HEIGHT, z}, player.get_dir(pid),
        DRINK_DISTANCE, nil, {}, true)
    if hit and flow.is_water(hit.block) then
        if stats.get(pid).water < stats.MAX_WATER then
            stats.feed(pid, 0, DRINK_AMOUNT)
            audio.play_sound_2d("events/pickup", 0.5, 0.6)
        end
    end
end

function on_hud_open(playerid)
    hud.open_permanent("millwright:stats")
    input.add_callback("player.build", try_drink)
    console.add_command(
        "flight.speed value:num=-1",
        "Show or set the flight speed multiplier (rule millwright-flight-speed)",
        function(args)
            local value = args[1]
            if value > 0 then
                flight.set(value)
            end
            return "flight speed: " .. flight.get() .. " (default " .. flight.DEFAULT .. ")"
        end, true
    )
end

function on_hud_render()
    visual.render(time.delta())
end
