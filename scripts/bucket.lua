-- Wooden bucket and bucket of water (modules/water/bucket.lua)
local bucket = require "water/bucket"

function on_use(pid)
    bucket.use(pid)
end

function on_use_on_block(x, y, z, pid, normal)
    return bucket.use_on_block(x, y, z, pid, normal)
end
