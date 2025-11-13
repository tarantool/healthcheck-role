-- tests for basic usage scenarios

local t = require('luatest')
local helpers = require('test.helpers.integration')
local cbuilder = require('luatest.cbuilder')
local details = require('details_consts')
local http_client = require('http.client')

---@type luatest.group
local g = t.group()

local CUSTOM_CHECK_NAME = 'healthcheck.check_integration'

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

--- Drop previously registered custom check function.
---@param cluster LuatestCluster
local function drop_custom_check(cluster)
    cluster['router']:exec(function(func_name)
        if box.func[func_name] ~= nil then
            box.schema.func.drop(func_name)
        end
    end, {CUSTOM_CHECK_NAME})
end

--- Register custom check function body under predefined name.
---@param cluster LuatestCluster
---@param body string
local function register_custom_check(cluster, body)
    drop_custom_check(cluster)
    cluster['router']:exec(function(func_name, func_body)
        box.schema.func.create(func_name, {
            language = 'LUA',
            body = func_body,
        })
    end, {CUSTOM_CHECK_NAME, body})
end


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

--- ensure custom user-defined check returning true keeps endpoint healthy
---@param cg basic_test_context
g.test_custom_check = function(cg)
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

    register_custom_check(cg.cluster, [[
        function()
            return true
        end
    ]])

    local resp = helpers.http_get(8081, '/healthcheck')
    t.assert_equals(resp.status, 200)
    t.assert_equals(resp:decode(), {
        status = 'alive',
    })

    drop_custom_check(cg.cluster)
end

--- ensure failing custom check propagates error to HTTP response
---@param cg basic_test_context
g.test_custom_check_not_ok = function(cg)
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

    register_custom_check(cg.cluster, [[
        function()
            return false, "custom failure"
        end
    ]])

    local resp = helpers.http_get(8081, '/healthcheck')
    t.assert_equals(resp.status, 500)
    t.assert_equals(resp:decode(), {
        status = 'dead',
        details = {string.format('%s: %s', CUSTOM_CHECK_NAME, 'custom failure')},
    })

    drop_custom_check(cg.cluster)
end

-- custom format tests moved to test/integration/custom_format_test.lua
