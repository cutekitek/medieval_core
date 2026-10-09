-- Kinetic network: a graph of rotating parts.
--
-- The graph is rebuilt only when parts are added or removed. Every tick each
-- network only sums its sources and checks precomputed limits.
local vec = require "kinetics/vec"
local parts = require "kinetics/parts"

local this = {}

local EPS = 1e-6

local nodes = {}      -- key -> node
local networks = {}   -- id -> network
local dirty = {}      -- key -> true: nodes to rebuild networks from
local next_net_id = 1
local ticks = 0

-- listeners: on_node_added(node), on_node_removed(node)
this.listeners = {}

local function key(x, y, z)
    return x .. "," .. y .. "," .. z
end
this.key = key

local function notify(event, ...)
    for _, listener in ipairs(this.listeners) do
        if listener[event] then
            listener[event](...)
        end
    end
end

local function mark_network_dirty(net)
    if not net then
        return
    end
    for _, node in ipairs(net.nodes) do
        dirty[node.key] = true
    end
    net.dead = true
end

local function remove_node(k)
    local node = nodes[k]
    if not node then
        return
    end
    nodes[k] = nil
    dirty[k] = nil
    mark_network_dirty(node.net)
    if node.net then
        networks[node.net.id] = nil
    end
    node.net = nil
    notify("on_node_removed", node)
end

-- Registers the kinetic block at x, y, z (or refreshes it if it changed)
function this.add(x, y, z)
    local id = block.get(x, y, z)
    if id <= 0 then
        return nil
    end
    local name = block.name(id)
    local part = parts.get(name)
    if not part then
        return nil
    end
    local facing = {block.get_Y(x, y, z)}
    local k = key(x, y, z)
    local old = nodes[k]
    if old and old.name == name and vec.eq(old.facing, facing) then
        return old
    end
    remove_node(k)

    local axis = vec.axis_index(facing)
    local avec = vec.axis_vec(axis)
    local node = {
        x = x, y = y, z = z,
        key = k,
        name = name,
        part = part,
        facing = facing,
        axis = axis,
        avec = avec,
        fsign = vec.dot(facing, avec),
        ratio = 0,
        rpm = 0,
    }
    nodes[k] = node
    dirty[k] = true
    notify("on_node_added", node)
    return node
end

function this.remove(x, y, z)
    remove_node(key(x, y, z))
end

function this.get(x, y, z)
    return nodes[key(x, y, z)]
end

function this.get_networks()
    return networks
end

function this.get_ticks()
    return ticks
end

local function new_network()
    local net = {
        id = next_net_id,
        nodes = {},
        sources = {},
        consumers = {},
        speed = 0,        -- rpm of a reference node with ratio 1
        status = "idle",
        capacity = 0,
        load = 0,
        stress_per_rpm = 0,  -- sum of stress * |ratio|
        max_speed = math.huge,
        conflict = false,
        theta = 0,        -- visual angle of the reference, degrees
        visual_speed = 0,
    }
    next_net_id = next_net_id + 1
    networks[net.id] = net
    return net
end

local function build_from(start)
    local net = new_network()
    start.ratio = 1
    local queue = {start}
    local visited = {[start.key] = true}
    local head = 1
    while queue[head] do
        local node = queue[head]
        head = head + 1

        if node.net and node.net ~= net and not node.net.dead then
            node.net.dead = true
            networks[node.net.id] = nil
        end
        node.net = net
        dirty[node.key] = nil
        table.insert(net.nodes, node)

        local part = node.part
        local r = math.abs(node.ratio)
        net.stress_per_rpm = net.stress_per_rpm + part.stress * r
        if part.max_rpm then
            net.max_speed = math.min(net.max_speed, part.max_rpm / r)
        end
        if part.source then
            table.insert(net.sources, node)
        end
        if part.on_tick then
            table.insert(net.consumers, node)
        end

        for _, d in ipairs(vec.NEIGHBOURS) do
            local other = nodes[key(node.x + d[1], node.y + d[2], node.z + d[3])]
            if other then
                local link = parts.link(node, other, d)
                if link then
                    local ratio = node.ratio * link
                    if visited[other.key] then
                        if math.abs(other.ratio - ratio) > EPS * math.abs(ratio) then
                            net.conflict = true
                        end
                    else
                        visited[other.key] = true
                        other.ratio = ratio
                        table.insert(queue, other)
                    end
                end
            end
        end
    end
    return net
end

function this.rebuild()
    local seeds = {}
    for k in pairs(dirty) do
        table.insert(seeds, k)
    end
    for _, k in ipairs(seeds) do
        local node = nodes[k]
        if node and dirty[k] then
            build_from(node)
        end
        dirty[k] = nil
    end
end

local function evaluate(net)
    net.capacity = 0
    if net.conflict then
        net.status = "conflict"
        net.speed = 0
        return
    end
    local speed = 0
    local best = 0
    local opposite = false
    for _, node in ipairs(net.sources) do
        local rpm, capacity = node.part.source(node, ticks)
        if rpm ~= 0 and capacity > 0 then
            -- convert to the reference node: rpm about the canonical axis
            local ref = rpm * node.fsign / node.ratio
            if speed ~= 0 and (ref > 0) ~= (speed > 0) then
                opposite = true
            end
            net.capacity = net.capacity + capacity
            if capacity > best then
                best = capacity
                speed = ref
            end
        end
    end
    net.load = net.stress_per_rpm * math.abs(speed)
    if speed == 0 then
        net.status = "idle"
    elseif opposite then
        net.status = "conflict"
        speed = 0
    elseif math.abs(speed) > net.max_speed + EPS then
        net.status = "overspeed"
        speed = 0
    elseif net.load > net.capacity + EPS then
        net.status = "overload"
        speed = 0
    else
        net.status = "ok"
    end
    net.speed = speed
end

function this.tick(dt)
    ticks = ticks + 1
    if next(dirty) then
        this.rebuild()
    end
    for _, net in pairs(networks) do
        evaluate(net)
        for _, node in ipairs(net.nodes) do
            node.rpm = net.speed * node.ratio
        end
        for _, node in ipairs(net.consumers) do
            node.part.on_tick(node, node.rpm, dt)
        end
    end
end

-- Drops all state (world close)
function this.reset()
    nodes = {}
    networks = {}
    dirty = {}
    ticks = 0
end

return this
