local t = require('luatest')
local fiber = require('fiber')
local g = t.group()

local ratelim = require('healthcheck.ratelim')

g.test_basic = function()
    local check_limit = ratelim.get_ratelimitter(1,1)
    t.assert(check_limit())
    fiber.sleep(0.5)
    t.assert(not check_limit())
    fiber.sleep(0.5)
    t.assert(check_limit())
end

g.test_consumes_initial_burst = function()
    local burst = 3
    local check_limit = ratelim.get_ratelimitter(1, burst)

    for _ = 1, burst do
        t.assert(check_limit(), 'expected burst tokens to be available')
    end
    t.assert(not check_limit(), 'all burst tokens should be consumed')
end

g.test_tokens_refill_over_time = function()
    local check_limit = ratelim.get_ratelimitter(2, 2)

    t.assert(check_limit())
    t.assert(check_limit())
    t.assert(not check_limit(), 'burst exhausted, no tokens left')

    fiber.sleep(0.6)
    t.assert(check_limit(), 'tokens should replenish according to rps')
end

g.test_invalid_burst_value = function()
    t.assert_error_msg_contains(
        'burst must be greather than rps',
        function()
            ratelim.get_ratelimitter(10, 5)
        end
    )
end
