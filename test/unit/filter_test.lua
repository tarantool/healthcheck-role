local t = require('luatest')
local g = t.group('filter')

local healthcheck = require('healthcheck')

g.test_default_filter_values = function()
    local filter = healthcheck._normalize_filter()

    t.assert_equals(filter.include_all, true)
    t.assert_equals(filter.exclude, {})
    t.assert_equals(filter.include, {replication = true})
end

g.test_filter_arrays_are_normalized = function()
    local filter = healthcheck._normalize_filter({
        include = {'custom-check'},
        exclude = {'healthcheck.check_skip'},
    })

    t.assert_equals(filter.include_all, false)
    t.assert_equals(filter.include, {['custom-check'] = true})
    t.assert_equals(filter.exclude, {['healthcheck.check_skip'] = true})
end
