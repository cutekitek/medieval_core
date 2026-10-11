local stats = require "survival/stats"
local mode = require "survival/mode"
local flight = require "player/flight"
local flow = require "water/flow"
local campfire_visual = require "fire/campfire_visual"
local ranged = require "combat/ranged"
local ranged_pose = require "combat/ranged_pose"
local knapping = require "crafting/knapping"
local sleep = require "player/sleep"
local ambience = require "world/ambience"
local boat = require "boat/boat"
local fishing = require "fishing/fishing"

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
            audio.play_sound_2d("medieval_core/drink", 0.7, 0.95 + math.random() * 0.1)
        end
    end
end

-- shift + use with a stone in hand: knapping. The window opens before the
-- player controller handles the click, so the stone is not placed.
local function try_knap()
    if hud.is_paused() or hud.is_inventory_open() then
        return
    end
    if not (input.is_pressed("key:left-shift") or input.is_pressed("key:right-shift")) then
        return
    end
    if knapping.start(hud.get_player()) then
        hud.show_overlay("medieval_core:knapping", false)
    end
end

-- the use button with a boat on the shoulders puts it down
local function try_put_down_boat()
    if hud.is_paused() or hud.is_inventory_open() then
        return
    end
    boat.on_build(hud.get_player())
end

-- the first-person hand: spears, bows and fishing rods have their own
-- poses, the rest is default
local function hand_controller()
    local pid = hud.get_player()
    local m, model = fishing.first_person(pid)
    if not m then
        m, model = ranged_pose.first_person(pid)
    end
    if m then
        local bone = gfx.skeletons.index("hand", "item")
        gfx.skeletons.set_matrix("hand", bone, m)
        gfx.skeletons.set_model("hand", bone, model)
    elseif hud.default_hand_controller then
        hud.default_hand_controller()
    end
end

-- in bed: the dark overlay with the "leave bed" button, the view from the
-- pillow
local camera_back = nil

local function update_sleep(pid)
    local s = sleep.sleeper(pid)
    if not s then
        if hud.is_open("medieval_core:bed") then
            hud.close("medieval_core:bed")
        end
        if camera_back then
            player.set_camera(pid, camera_back)
            camera_back = nil
        end
        return
    end
    if not hud.is_open("medieval_core:bed") then
        hud.show_overlay("medieval_core:bed", false)
    end
    if sleep.free_camera then
        return
    end
    local cam = cameras.get("medieval_core:sleep")
    if player.get_camera(pid) ~= cam:get_index() then
        camera_back = player.get_camera(pid)
        cam:set_fov(cameras.get("core:first-person"):get_fov())
        player.set_camera(pid, cam:get_index())
    end
    -- the eyes above the pillow, looking up past the foot of the bed
    local eye = {
        s.foot[1] + 0.5 + s.dir[1] * 1.2,
        s.foot[2] + sleep.MATTRESS + 0.34,
        s.foot[3] + 0.5 + s.dir[3] * 1.2,
    }
    cam:set_pos(eye)
    cam:look_at({eye[1] - s.dir[1] * 3.0, eye[2] + 1.6, eye[3] - s.dir[3] * 3.0})
end

function on_hud_open(playerid)
    hud.open_permanent("medieval_core:stats")
    hud.open_permanent("medieval_core:notice")
    hud.hand_controller = hand_controller
    input.add_callback("player.build", try_drink)
    input.add_callback("player.build", try_knap)
    input.add_callback("player.build", try_put_down_boat)
    console.add_command(
        "flight.speed value:num=-1",
        "Show or set the flight speed multiplier (rule medieval_core-flight-speed)",
        function(args)
            local value = args[1]
            if value > 0 then
                flight.set(value)
            end
            return "flight speed: " .. flight.get() .. " (default " .. flight.DEFAULT .. ")"
        end, true
    )
end

-- The engine opens the bare player inventory on its key; reopen it together
-- with the crafting grid (one frame later). Block UIs keep their own layout.
local function attach_crafting()
    if hud.is_player_inventory_open() and hud.get_second_inventory() == 0
       and not hud.is_open("medieval_core:crafting") then
        hud.open("medieval_core:crafting")
    end
end

function on_hud_render()
    attach_crafting()
    local pid = hud.get_player()
    -- letting go of the use button throws a spear or shoots an arrow
    local use_held = input.is_active("player.build") and not hud.is_paused()
        and not hud.is_inventory_open()
    ranged.update_local(pid, use_held)
    fishing.update_local(pid, use_held)
    local x, y, z = player.get_pos(pid)
    campfire_visual.update_sounds(x, y + EYE_HEIGHT, z)
    ambience.update(time.delta(), x, y + EYE_HEIGHT, z)
    update_sleep(pid)
end

function on_hud_close()
    ambience.reset()
end
