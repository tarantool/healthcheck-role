-- tests for basic usage scenarios

local t = require('luatest')
local helpers = require('test.helpers.integration')
local cbuilder = require('luatest.cbuilder')
local details = require('details_consts')
local http_client = require('http.client')

---@type luatest.group
local g = t.group()

--- Start a fresh cluster before each case.
---@param cg basic_test_context
g.before_each(function(cg)
    ---@type table
    local config = cbuilder:new()
        :use_group('routers')
        :use_replicaset('router')
        :add_instance('router', {})
        :config()

    cg.cluster = helpers.create_test_cluster(config)
    cg.cluster:start()
end)

--- Stop the cluster created for the test case.
---@param cg basic_test_context
g.after_each(function(cg)
    cg.cluster:stop()
end)


--- basic test with minimum config like in cartridge
---@param cg basic_test_context
g.test_basic = function(cg)
    local config = cbuilder:new()
        :use_group('routers')
        :set_group_option('roles', { 'roles.httpd', 'roles.healthcheck' })
        :set_group_option('roles_cfg', {
            ['roles.healthcheck'] = {
                http = {
                    {
                        endpoints = {
                            {
                                path = '/healthcheck',
                            },
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
        :config()
    cg.cluster:reload(config)

    local resp = helpers.http_get(8081,'/healthcheck')
    t.assert_equals(resp.status, 200)
    t.assert_equals(resp:decode(), {
        status = 'alive',
    })
end

--- basic test with minimum config like in cartridge
---@param cg basic_test_context
g.test_basic_not_ok = function (cg)
    local config = cbuilder:new()
        :use_group('routers')
        :set_group_option('roles', { 'roles.httpd', 'roles.healthcheck' })
        :set_group_option('roles_cfg', {
            ['roles.healthcheck'] = {
                http = {
                    {
                        endpoints = {
                            {
                                path = '/healthcheck',
                            },
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
        :config()
    cg.cluster:reload(config)
    helpers.mock_healthcheck(cg.cluster, false, {
        details.BOX_INFO_STATUS_NOT_RUNNING,
    })

    local resp = helpers.http_get(8081,'/healthcheck')
    t.assert_equals(resp.status, 500)
    t.assert_equals(resp:decode(), {
        status = 'dead',
        details = {details.BOX_INFO_STATUS_NOT_RUNNING},
    })
end