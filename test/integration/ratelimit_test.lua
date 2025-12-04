local t = require('luatest')
local helpers = require('test.helpers.integration')
local cbuilder = require('luatest.cbuilder')
local fiber = require('fiber')

---@type luatest.group
local g = t.group()

local function make_config(rps)
    return helpers.build_router_healthcheck_config({
        ratelim_rps = rps,
    })
end

g.before_each(function(cg)
    local base = cbuilder:new()
        :use_group('routers')
        :use_replicaset('router')
        :add_instance('router', {})
        :config()
    cg.cluster = helpers.create_test_cluster(base)
    cg.cluster:start()
end)

local function install_counter(cg)
    cg.cluster['router']:exec(function()
        local healthcheck = require('healthcheck')
        if rawget(_G, '_ratelimit_orig') == nil then
            rawset(_G, '_ratelimit_orig', healthcheck.check_health)
        end
        rawset(_G, '_ratelimit_calls', 0)
        healthcheck.check_health = function()
            rawset(_G, '_ratelimit_calls', rawget(_G, '_ratelimit_calls') + 1)
            return true, {}
        end
    end)
end

local function uninstall_counter(cg)
    cg.cluster['router']:exec(function()
        local orig = rawget(_G, '_ratelimit_orig')
        if orig ~= nil then
            require('healthcheck').check_health = orig
            rawset(_G, '_ratelimit_orig', nil)
        end
        rawset(_G, '_ratelimit_calls', nil)
    end)
end

g.after_each(function(cg)
    uninstall_counter(cg)
    cg.cluster:stop()
end)

local function get_call_count(cg)
    return cg.cluster['router']:exec(function()
        return rawget(_G, '_ratelimit_calls') or 0
    end)
end

--- ratelimit confines number of healthcheck calls and returns 429 for overflow
---@param cg basic_test_context
g.test_rps_limit_enforced = function(cg)
    ---@param rps number
    local function check_rps(rps)
        cg.cluster:reload(make_config(rps))
        install_counter(cg)

        local total = 100
        local ch = fiber.channel(total)

        local function spam()
            local resp = helpers.http_get(8081, '/healthcheck')
            ch:put(resp.status)
        end

        for _ = 1, total do
            fiber.create(spam)
        end

        local stats = {}
        for _ = 1, total do
            local status = ch:get()
            stats[status] = (stats[status] or 0) + 1
        end

        local calls = get_call_count(cg)
        local allowed_cap = rps + 1 -- event loop scheduling sometimes allows one extra token
        t.assert_le(calls, allowed_cap, 'healthcheck called more than ratelimit allows')

        local allowed = stats[200] or 0
        local limited = stats[429] or 0
        t.assert_equals(allowed + limited, total, 'unexpected response status')
        t.assert_le(allowed, allowed_cap)
        t.assert_ge(limited, total - allowed_cap)
    end

    check_rps(5)
    check_rps(6)
    check_rps(1)
end
