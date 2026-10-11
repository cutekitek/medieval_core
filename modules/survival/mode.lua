-- Survival mode switch (world rule) and death handling
local stats = require "survival/stats"
local base_util = require "base:util"
local sleep = require "player/sleep"

local this = {}

this.RULE = "medieval_core-survival"

local function apply_rules(enabled)
    rules.set("allow-content-access", not enabled)
    rules.set("allow-flight", not enabled)
    rules.set("allow-noclip", not enabled)
end

function this.enabled()
    return rules.get(this.RULE) == true
end

function this.init()
    rules.create(this.RULE, true, apply_rules)
    apply_rules(this.enabled())
end

-- players whose creative breaking was given back (survival off)
local creative = {}

-- Keeps creative abilities off for survival players
function this.apply_player(pid)
    creative[pid] = nil
    if player.is_infinite_items(pid) then
        player.set_infinite_items(pid, false)
    end
    if player.is_instant_destruction(pid) then
        player.set_instant_destruction(pid, false)
    end
    if player.is_flight(pid) then
        player.set_flight(pid, false)
    end
    if player.is_noclip(pid) then
        player.set_noclip(pid, false)
    end
end

-- With survival off the timed breaking (survival/breaking) does not run and
-- the engine only breaks blocks with instant destruction, which survival
-- took away: give it back once (later toggles by the player stay theirs).
function this.apply_creative(pid)
    if creative[pid] then
        return
    end
    creative[pid] = true
    if not player.is_instant_destruction(pid) then
        player.set_instant_destruction(pid, true)
    end
end

function this.reset()
    creative = {}
end

local function drop_inventory(pid)
    local invid = player.get_inventory(pid)
    local pos = {player.get_pos(pid)}
    for slot = 0, inventory.size(invid) - 1 do
        local itemid, count = inventory.get(invid, slot)
        if itemid ~= 0 then
            local drop = base_util.drop(pos, itemid, count, inventory.get_all_data(invid, slot))
            if drop then
                drop.rigidbody:set_vel(vec3.spherical_rand(4.0))
            end
            inventory.set(invid, slot, 0, 0)
        end
    end
end

table.insert(stats.listeners, {
    on_death = function(pid)
        drop_inventory(pid)
        player.set_vel(pid, 0, 0, 0)
        -- by the bed if there is one, otherwise at the world spawn
        local bx, by, bz = sleep.respawn_point(pid)
        if bx then
            player.set_pos(pid, bx, by + 0.91, bz)
            if hud then
                console.chat(gui.str("medieval_core.died"))
            end
            return
        end
        local x, y, z = player.get_spawnpoint(pid)
        -- the spawnpoint stays NaN until the engine has chosen one
        if x == x and y == y and z == z then
            player.set_pos(pid, x, y, z)
        end
        if hud then
            console.chat(gui.str("medieval_core.died"))
        end
    end,
})

return this
