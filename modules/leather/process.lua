-- Leather making: hide -> soaked (water) -> scraped (knife on a stripped
-- log) -> leather (tanning liquor of bark in a vat). Fur goes the same way
-- and ends as dressed fur.
local this = {}

this.SOAK_TIME = 30          -- seconds in a vat of water
this.SOAK_TIME_WILD = 40     -- thrown into a river or a lake
this.TAN_TIME = 120          -- seconds in tanning liquor
this.SCRAPE_TIME = 3.0       -- seconds of knife work on the beam

this.SOAK = {
    ["medieval_core:hide"] = "medieval_core:soaked_hide",
    ["medieval_core:fur"] = "medieval_core:soaked_fur",
}
this.SCRAPE = {
    ["medieval_core:soaked_hide"] = "medieval_core:scraped_hide",
    ["medieval_core:soaked_fur"] = "medieval_core:scraped_fur",
}
this.TAN = {
    ["medieval_core:scraped_hide"] = "medieval_core:leather",
    ["medieval_core:scraped_fur"] = "medieval_core:dressed_fur",
}

-- the surface texture of every stage (vat lumps, the draped hide)
this.SKIN = {
    ["medieval_core:hide"] = "blocks:mw_skin_hide",
    ["medieval_core:soaked_hide"] = "blocks:mw_skin_soaked_hide",
    ["medieval_core:scraped_hide"] = "blocks:mw_skin_scraped_hide",
    ["medieval_core:leather"] = "blocks:mw_skin_leather",
    ["medieval_core:fur"] = "blocks:mw_skin_fur",
    ["medieval_core:soaked_fur"] = "blocks:mw_skin_soaked_fur",
    ["medieval_core:scraped_fur"] = "blocks:mw_skin_scraped_fur",
    ["medieval_core:dressed_fur"] = "blocks:mw_skin_dressed_fur",
}

function this.is_knife(itemid)
    if itemid == 0 then
        return false
    end
    local props = item.properties and item.properties[itemid]
    local tool = props and props["medieval_core:tool"]
    return tool ~= nil and tool.type == "knife"
end

-- what an item turns into in plain water / in tanning liquor (or nil)
function this.in_water(name)
    return this.SOAK[name]
end

function this.in_tannin(name)
    return this.TAN[name] or this.SOAK[name]
end

return this
