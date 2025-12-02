--- tests for set_alerts option

local t = require('luatest')
local helpers = require('test.helpers.integration')
local cbuilder = require('luatest.cbuilder')

---@type luatest.group
local g = t.group()

local function build_config(set_alerts)
    return helpers.build_router_healthcheck_config({ set_alerts = set_alerts })
end

local function get_alerts(cluster)
    return cluster['router']:exec(function()
        return box.info.config.alerts or {}
    end)
end

g.before_each(function(cg)
    local config = cbuilder:new()
        :use_group('routers')
        :use_replicaset('router')
        :add_instance('router', {})
        :config()

    cg.cluster = helpers.create_test_cluster(config)
    cg.cluster:start()
    cg.mocked = false
end)

g.after_each(function(cg)
    if cg.mocked then
        helpers.unmock_healthcheck(cg.cluster)
    end
    cg.cluster:stop()
end)

local function mock_failure(cg, check_name, message)
    cg.mocked = true
    helpers.mock_healthcheck(cg.cluster, false, {
        [check_name] = message,
    })
end

local function mock_success(cg)
    cg.mocked = true
    helpers.mock_healthcheck(cg.cluster, true, {})
end

local function reload_with_alerts(cg, enabled)
    local config = build_config(enabled)
    cg.cluster:reload(config)
end

--- alerts appear when set_alerts enabled and checks fail
---@param cg basic_test_context
g.test_alert_created_on_failure = function(cg)
    reload_with_alerts(cg, true)

    mock_failure(cg, 'check_box_info_status', 'box failure')
    local resp = helpers.http_get(8081, '/healthcheck')
    t.assert_equals(resp.status, 500)

    local alerts = get_alerts(cg.cluster)
    t.assert_equals(#alerts, 1)
    t.assert_str_contains(alerts[1].message, 'box failure')
end

--- disabling set_alerts clears existing alerts and keeps them off until re-enabled
---@param cg basic_test_context
g.test_disable_and_reenable_alerts = function(cg)
    reload_with_alerts(cg, true)
    mock_failure(cg, 'check_wal_dir', 'wal error')
    helpers.http_get(8081, '/healthcheck')
    t.assert_equals(#get_alerts(cg.cluster), 1)

    reload_with_alerts(cg, false)
    t.assert_equals(get_alerts(cg.cluster), {})

    reload_with_alerts(cg, true)
    t.assert_equals(get_alerts(cg.cluster), {})
    helpers.http_get(8081, '/healthcheck')
    t.assert_equals(#get_alerts(cg.cluster), 1)
end

--- alerts are cleared when checks become successful again
---@param cg basic_test_context
g.test_alert_clears_on_success = function(cg)
    reload_with_alerts(cg, true)

    mock_failure(cg, 'check_snapshot_dir', 'snapshot error')
    helpers.http_get(8081, '/healthcheck')
    t.assert_equals(#get_alerts(cg.cluster), 1)

    mock_success(cg)
    local resp = helpers.http_get(8081, '/healthcheck')
    t.assert_equals(resp.status, 200)
    t.assert_equals(get_alerts(cg.cluster), {})
end
