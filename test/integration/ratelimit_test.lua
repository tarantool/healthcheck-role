local t = require('luatest')
local helpers = require('test.helpers.integration')
local cbuilder = require('luatest.cbuilder')
local fiber = require('fiber')
local http_client = require('http.client')

---@type luatest.group
local g = t.group('ratelimit')

local function make_config(rps)
    return cbuilder:new()
        :use_group('routers')
        :set_group_option('roles', { 'roles.httpd', 'roles.healthcheck' })
        :set_group_option('roles_cfg', {
            ['roles.healthcheck'] = {
                ratelim_rps = rps,
                http = {
                    {
                        endpoints = {
                            { path = '/healthcheck' },
                        },
                    },
                },
            },
        })
        :use_replicaset('router')
        :add_instance('router', {})
        :set_instance_option('router', 'roles_cfg', {
            ['roles.httpd'] = {
                default = {
                    listen = 8081,
                },
            },
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
        healthcheck.check_health = function(...)
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
    cg.cluster:reload(make_config(5):config())
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
    t.assert_le(calls, 5, 'healthcheck called more than ratelimit allows')
    t.assert_equals(stats[200], 5)
    t.assert_equals(stats[429], 95)
end

