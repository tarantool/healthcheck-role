-- integration tests for custom format responses

local t = require('luatest')
local helpers = require('test.helpers.integration')
local cbuilder = require('luatest.cbuilder')

---@type luatest.group
local g = t.group()

local CUSTOM_FORMAT_NAME = 'healthcheck.custom_format'

--- Start a fresh cluster before each case.
---@param cg basic_test_context
g.before_each(function(cg)
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

--- Drop remote function if it exists.
---@param cluster LuatestCluster
---@param func_name string
local function drop_remote_func(cluster, func_name)
    cluster['router']:exec(function(name)
        if box.func[name] ~= nil then
            box.schema.func.drop(name)
        end
    end, {func_name})
end

--- Register remote function body under the given name.
---@param cluster LuatestCluster
---@param func_name string
---@param body string
local function register_remote_func(cluster, func_name, body)
    drop_remote_func(cluster, func_name)
    cluster['router']:exec(function(name, func_body)
        box.schema.func.create(name, {
            language = 'LUA',
            body = func_body,
        })
    end, {func_name, body})
end

local function register_custom_format(cluster)
    register_remote_func(cluster, CUSTOM_FORMAT_NAME, [[
        function(is_healthy, errs)
            local json = require('json')
            if is_healthy then
                return {
                    status = 209,
                    headers = { ['content-type'] = 'application/json' },
                    body = json.encode({ custom = 'ok' }),
                }
            end
            return {
                status = 560,
                headers = { ['content-type'] = 'application/json' },
                body = json.encode({ errors = errs }),
            }
        end
    ]])
end

local function drop_custom_format(cluster)
    drop_remote_func(cluster, CUSTOM_FORMAT_NAME)
end

local function reload_healthcheck_with_format(cluster)
    local config = helpers.build_router_healthcheck_config({ format = CUSTOM_FORMAT_NAME })
    cluster:reload(config)
end

--- ensure custom format overrides default success response
---@param cg basic_test_context
g.test_custom_format_success = function(cg)
    register_custom_format(cg.cluster)

    reload_healthcheck_with_format(cg.cluster)

    local resp = helpers.http_get(8081,'/healthcheck')
    t.assert_equals(resp.status, 209)
    t.assert_equals(resp:decode(), { custom = 'ok' })

    drop_custom_format(cg.cluster)
end

--- ensure failing custom format receives errors
---@param cg basic_test_context
g.test_custom_format_not_ok = function(cg)
    register_custom_format(cg.cluster)

    reload_healthcheck_with_format(cg.cluster)
    helpers.mock_healthcheck(cg.cluster, false, {
        check_box_info_status = 'custom failure',
    })

    local resp = helpers.http_get(8081,'/healthcheck')
    t.assert_equals(resp.status, 560)
    t.assert_equals(resp:decode(), { errors = {'check_box_info_status: custom failure'} })

    helpers.unmock_healthcheck(cg.cluster)
    drop_custom_format(cg.cluster)
end

--- configuration fails if custom format function is absent during apply
---@param cg basic_test_context
g.test_custom_format_missing_function = function(cg)
    drop_custom_format(cg.cluster)

    local config = helpers.build_router_healthcheck_config({ format = CUSTOM_FORMAT_NAME })
    t.assert_error_msg_contains(
        CUSTOM_FORMAT_NAME,
        function()
            cg.cluster:reload(config)
        end
    )
end

--- format removal after apply should flip endpoint to 500 with explanation
---@param cg basic_test_context
g.test_custom_format_removed_after_apply = function(cg)
    register_custom_format(cg.cluster)

    reload_healthcheck_with_format(cg.cluster)
    drop_custom_format(cg.cluster)

    local resp = helpers.http_get(8081,'/healthcheck')
    t.assert_equals(resp.status, 500)
    t.assert_equals(resp:decode(), {
        status = 'dead',
        details = {("healthcheck format function '%q' is not defined"):format(CUSTOM_FORMAT_NAME)},
    })
end
