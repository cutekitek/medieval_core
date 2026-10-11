-- The panel above the player's inventory (see hud.lua): clothing slots
-- and the 2x2 crafting grid.
-- The result slot can't be taken from directly: a click crafts once into
-- the cursor stack, shift-click crafts as much as fits into the inventory.
local grid = require "medieval_core:crafting/grid"
local clothing = require "medieval_core:survival/clothing"
local temperature = require "medieval_core:survival/temperature"

local SIZE = 2
local CLOTHING = 5     -- first clothing slot: head, body, legs, feet
local last_craft = -1
local current = nil
local ticking = false

function on_grid(invid, slot)
    grid.refresh(invid, SIZE)
end

function on_result(invid, slot)
    -- a single right click reports the slot update twice in one frame
    local now = time.uptime()
    if now == last_craft then
        return
    end
    last_craft = now
    if input.is_pressed("key:left-shift") or input.is_pressed("key:right-shift") then
        grid.craft_all(invid, SIZE, player.get_inventory(hud.get_player()))
    else
        grid.craft_into(invid, SIZE, hud.get_exchange_inventory(), 0)
    end
end

function on_clothing(invid, slot)
    local pid = hud.get_player()
    clothing.check_slot(invid, slot, CLOTHING, hud.get_exchange_inventory())
    clothing.store_from(invid, CLOTHING, pid)
end

local function show_warmth()
    local pid = hud.get_player()
    local insulation, shade = clothing.totals(pid)
    document.insulation.text = gui.str("medieval_core.clothing.insulation") .. ": " .. insulation
    document.shade.text = shade > 0 and (gui.str("medieval_core.clothing.shade") .. ": " .. shade) or ""
    -- how the weather feels in these clothes: cold, hot or comfortable
    local cold_side, hot_side = temperature.felt(pid)
    local felt = gui.str("medieval_core.clothing.comfort")
    if cold_side < temperature.COMFORT_LOW then
        felt = string.format("%d°C", math.floor(cold_side + 0.5))
    elseif hot_side > temperature.COMFORT_HIGH then
        felt = string.format("%d°C", math.floor(hot_side + 0.5))
    end
    document.felt.text = felt
end

local function update()
    if current then
        grid.refresh(current, SIZE)
        show_warmth()
    end
end

function on_open(invid)
    current = invid
    clothing.load_into(invid, CLOTHING, hud.get_player())
    grid.refresh(invid, SIZE)
    show_warmth()
    -- shift-clicks and scripts can change the grid without slot events;
    -- intervals outlive the document being closed, so only one is added
    if not ticking then
        ticking = true
        document.root:setInterval(100, update)
    end
end

function on_close(invid)
    current = nil
    clothing.store_from(invid, CLOTHING, hud.get_player(), true)
    grid.give_back(invid, SIZE, hud.get_player())
end
