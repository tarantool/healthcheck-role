local t = require('luatest')
local helpers = require('test.helpers.integration')
local cbuilder = require('luatest.cbuilder')

local g = t.group()

local LEADER_NAME = 'storage-1'
local FOLLOWER_NAME = 'storage-2'

--- Build healthcheck role config with provided checks section.
---@param checks table|nil
---@return table
local function build_config(checks)
    return cbuilder:new()
        :use_group('storages')
        :set_group_option('replication.failover', 'manual')
        :set_group_option('roles', { 'roles.httpd', 'roles.healthcheck' })
        :set_group_option('roles_cfg', {
            ['roles.healthcheck'] = {
                checks = checks,
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
        :use_replicaset('storages')
        :set_replicaset_option('leader', LEADER_NAME)
        :add_instance(LEADER_NAME, {})
        :set_instance_option(LEADER_NAME, 'roles_cfg', {
            ['roles.httpd'] = {
                default = {
                    listen = 8081,
                },
            },
        })
        :add_instance(FOLLOWER_NAME, {})
        :set_instance_option(FOLLOWER_NAME, 'roles_cfg', {
            ['roles.httpd'] = {
                default = {
                    listen = 8082,
                },
            },
        })
        :config()
end

---@param cg basic_test_context
g.before_each(function(cg)
    cg.cluster = helpers.create_test_cluster(build_config())
    cg.cluster:start()
end)

g.after_each(function(cg)
    cg.cluster:stop()
end)

---@param cg basic_test_context
g.test_replication_checks_fail_when_leader_down = function(cg)
    local follower = cg.cluster[FOLLOWER_NAME]
    local leader = cg.cluster[LEADER_NAME]

    follower:wait_until_ready()

    -- replication healthy: follower should be alive
    local resp_ok = helpers.http_get(8082, '/healthcheck')
    t.assert_equals(resp_ok.status, 200)
    t.assert_equals(resp_ok:decode().status, 'alive')

    -- stop leader to break upstream on follower
    leader:stop()
    follower:wait_until_ready()

    local resp_bad = helpers.http_get(8082, '/healthcheck')
    t.assert_equals(resp_bad.status, 500)
    local body = resp_bad:decode()
    t.assert_equals(body.status, 'dead')
    local concat_details = table.concat(body.details or {}, ' ')
    t.assert_str_contains(concat_details, 'Replication from \"storage-1\" to \"storage-2\" state')
end

---@param cg basic_test_context
g.test_replication_checks_fail_when_upstream_removed = function(cg)
    local follower = cg.cluster[FOLLOWER_NAME]
    follower:wait_until_ready()

    local resp_ok = helpers.http_get(8082, '/healthcheck')
    t.assert_equals(resp_ok.status, 200)
    t.assert_equals(resp_ok:decode().status, 'alive')

    follower:exec(function()
        box.cfg({replication = {}}) -- drop upstream
    end)
    follower:wait_until_ready()

    local resp_bad = helpers.http_get(8082, '/healthcheck')
    t.assert_equals(resp_bad.status, 500)
    local body = resp_bad:decode()
    t.assert_equals(body.status, 'dead')
    local concat_details = table.concat(body.details or {}, ' ')
    t.assert_str_contains(concat_details, 'Replication from \"storage-1\" to \"storage-2\" is not running')

    local resp_master = helpers.http_get(8081, '/healthcheck')
    t.assert_equals(resp_master.status, 200)
    t.assert_equals(resp_master:decode().status, 'alive')
end

---@param cg basic_test_context
g.test_replication_checks_can_be_excluded = function(cg)
    local config = build_config({
        exclude = {'replication'},
    })
    cg.cluster:reload(config)

    local follower = cg.cluster[FOLLOWER_NAME]
    local leader = cg.cluster[LEADER_NAME]

    leader:stop()
    follower:wait_until_ready()

    local resp = helpers.http_get(8082, '/healthcheck')
    t.assert_equals(resp.status, 200)
    t.assert_equals(resp:decode().status, 'alive')
end

---@param cg basic_test_context
g.test_replication_group_include_respects_exclude_subcheck = function(cg)
    local config = build_config({
        include = {'replication'},
        exclude = {'replication.state_bad'},
    })
    cg.cluster:reload(config)

    local follower = cg.cluster[FOLLOWER_NAME]
    follower:wait_until_ready()

    follower:exec(function()
        box.cfg({replication = {}})
    end)
    follower:wait_until_ready()

    local resp = helpers.http_get(8082, '/healthcheck')
    t.assert_equals(resp.status, 500)
    local body = resp:decode()
    t.assert_equals(body.status, 'dead')
    local concat_details = table.concat(body.details or {}, ' ')
    t.assert_str_contains(concat_details, 'Replication from \"storage-1\" to \"storage-2\" is not running')
end

g.test_replication_checks_skip_on_leader = function(cg)
    local leader = cg.cluster[LEADER_NAME]
    leader:wait_until_ready()

    -- break replication on leader (no upstream anyway)
    leader:exec(function()
        box.cfg({replication = {}})
    end)
    leader:wait_until_ready()

    local resp = helpers.http_get(8081, '/healthcheck')
    t.assert_equals(resp.status, 200)
    t.assert_equals(resp:decode().status, 'alive')
end
