-- Human readable network state
local this = {}

local function tr(key)
    if hud then
        return gui.str("millwright." .. key)
    end
    return key
end

function this.describe(node)
    local net = node.net
    if not net then
        return tr("status.unconnected")
    end
    return string.format(
        "%s: %s | %.1f %s | %s %.0f / %.0f SU",
        tr("status.network"), tr("status." .. net.status),
        math.abs(node.rpm), tr("rpm"),
        tr("status.load"), net.load, net.capacity
    )
end

return this
