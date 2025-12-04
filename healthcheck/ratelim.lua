--- token bucket ratelimiter
local fiber = require('fiber')
local M = {}

--- get_ratelimiter simple ratelimiter for http requests.
--- @param rps number desired rps for ratelimit
--- @param burst number desired burst for ratelimit, must be greater than rps
--- @return fun(): boolean
--- ** usage **
---
--- local ratelim = require('healthcheck.ratelim')
---
--- local check_limit = ratelim.get_ratelimiter(10, 11)
---
--- check_limit()
function M.get_ratelimiter(rps, burst)
    assert(burst >= rps, 'burst must be not less than rps')
    local tokens = burst
    local last_time = fiber.time()

    return function()
        -- add new tokens
        local now = fiber.time()
        local elapsed = now - last_time
        if elapsed > 0 then
            tokens = math.min(burst, tokens + (elapsed * rps))
            last_time = now
        end

        -- Сheck limit.
        if tokens >= 1 then
            tokens = tokens - 1
            return true
        end
        return false
    end
end

return M
