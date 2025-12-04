local t = require('luatest')
local g = t.group()

local healthcheck = require('healthcheck')
local logger = require('healthcheck.logger')
local unit_helpers = require('test.helpers.unit')

local function create_func(cg, name, body)
    unit_helpers.create_func(name, body)
    table.insert(cg.created_funcs, name)
end

g.before_each(function(cg)
    cg.created_funcs = {}
end)

g.after_each(function(cg)
    for _, name in ipairs(cg.created_funcs or {}) do
        unit_helpers.drop_func(name)
    end
end)

--- user check returns true, so overall result is healthy
---@param cg table
g.test_user_check_success = function(cg)
    create_func(cg, 'healthcheck.check_success', [[
        function()
            return true
        end
    ]])

    local ok, details = healthcheck.check_user_checks(healthcheck._normalize_filter())
    t.assert_equals(ok, true)
    t.assert_equals(details, {})
end

--- user check returns false with error message
---@param cg table
g.test_user_check_failure = function(cg)
    create_func(cg, 'healthcheck.check_failure', [[
        function()
            return false, "condition not met"
        end
    ]])

    local ok, details = healthcheck.check_user_checks(healthcheck._normalize_filter())
    t.assert_equals(ok, false)
    t.assert_equals(details, {
        ['healthcheck.check_failure'] = 'condition not met',
    })
end

--- user check raises an error, the reason is propagated to details
---@param cg table
g.test_user_check_error = function(cg)
    create_func(cg, 'healthcheck.check_error', [[
        function()
            error('unexpected failure')
        end
    ]])

    local ok, details = healthcheck.check_user_checks(healthcheck._normalize_filter())
    t.assert_equals(ok, false)
    t.assert(details['healthcheck.check_error']:find('unexpected failure', 1, true) ~= nil)
end

--- user check returns invalid result (number), it is ignored and logged
---@param cg table
g.test_user_check_invalid_format = function(cg)
    create_func(cg, 'healthcheck.check_invalid', [[
        function()
            return 123
        end
    ]])

    local restore_warn, warnings = unit_helpers.stub_logger(logger, 'warn')
    local ok, details = healthcheck.check_user_checks(healthcheck._normalize_filter())
    restore_warn()

    t.assert_equals(ok, true)
    t.assert_equals(details, {})
    t.assert(#warnings > 0)
end

--- functions without the required prefix are ignored regardless of order
---@param cg table
g.test_user_check_prefix_filter = function(cg)
    create_func(cg, 'healthcheck.check0before', [[
        function()
            return false, "should not be called"
        end
    ]])
    create_func(cg, 'healthcheck.check_valid', [[
        function()
            return true
        end
    ]])
    create_func(cg, 'healthcheck.checkzafter', [[
        function()
            return false, "should not be called either"
        end
    ]])

    local ok, details = healthcheck.check_user_checks(healthcheck._normalize_filter())
    t.assert_equals(ok, true)
    t.assert_equals(details, {})
end

---ignore function if it appears in filter.exclude
---@param cg table
g.test_ignore_excluded_filter = function(cg)
    create_func(cg, 'healthcheck.check_check', [[
        function()
            return false, "error"
        end
    ]])

    local ok, details = healthcheck.check_user_checks(healthcheck._normalize_filter({exclude = {'healthcheck.check_check'}}))
    t.assert_equals(ok, true)
    t.assert_equals(details, {})

    ok, details = healthcheck.check_user_checks(healthcheck._normalize_filter())
    t.assert_equals(ok, false)
    t.assert_equals(details, {["healthcheck.check_check"] = "error"})
end
