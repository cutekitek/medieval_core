-- The lasso (riding/leash): thrown at an animal it catches it or lets go
-- of one already led; used on a fence it ties the led animals to it (or
-- takes the ones tied there).
local leash = require "riding/leash"

function on_use(pid)
    leash.use_lasso(pid)
end

function on_use_on_block(x, y, z, pid, normal)
    if leash.use_post(pid, x, y, z) then
        return true
    end
    return leash.use_lasso(pid)
end
