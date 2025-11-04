local t = require('luatest')
local g = t.group('defaults')

local healthcheck = require('healthcheck')
local details_consts = require('details_consts')

local function stub_checker(cg, field, fn)
    cg.originals[field] = cg.originals[field] or healthcheck[field]
    healthcheck[field] = fn
end

g.before_each(function(cg)
    cg.originals = {}
end)

g.after_each(function(cg)
    for field, original in pairs(cg.originals or {}) do
        healthcheck[field] = original
    end
end)

--- defaults succeed when every checker returns true
---@param cg table
g.test_defaults_ok = function(cg)
    stub_checker(cg, '_check_box_info_status', function() return true end)
    stub_checker(cg, '_check_snapshot_dir', function() return true end)
    stub_checker(cg, '_check_wal_dir', function() return true end)

    local ok, details = healthcheck.check_defaults()
    t.assert_equals(ok, true)
    t.assert_equals(details, {})
end

--- snapshot dir failure produces dedicated detail
---@param cg table
g.test_snapshot_dir_failure = function(cg)
    stub_checker(cg, '_check_box_info_status', function() return true end)
    stub_checker(cg, '_check_snapshot_dir', function() return false end)
    stub_checker(cg, '_check_wal_dir', function() return true end)

    local ok, details = healthcheck.check_defaults()
    t.assert_equals(ok, false)
    t.assert_equals(details, {
        details_consts.DISK_ERROR_SNAPSHOT_DIR,
    })
end

--- wal dir failure produces dedicated detail
---@param cg table
g.test_wal_dir_failure = function(cg)
    stub_checker(cg, '_check_box_info_status', function() return true end)
    stub_checker(cg, '_check_snapshot_dir', function() return true end)
    stub_checker(cg, '_check_wal_dir', function() return false end)

    local ok, details = healthcheck.check_defaults()
    t.assert_equals(ok, false)
    t.assert_equals(details, {
        details_consts.DISK_ERROR_WAL_DIR,
    })
end

--- multiple failures include all detail entries in order
---@param cg table
g.test_multiple_failures = function(cg)
    stub_checker(cg, '_check_box_info_status', function() return false end)
    stub_checker(cg, '_check_snapshot_dir', function() return false end)
    stub_checker(cg, '_check_wal_dir', function() return false end)

    local ok, details = healthcheck.check_defaults()
    t.assert_equals(ok, false)
    t.assert_equals(details, {
        details_consts.BOX_INFO_STATUS_NOT_RUNNING,
        details_consts.DISK_ERROR_SNAPSHOT_DIR,
        details_consts.DISK_ERROR_WAL_DIR,
    })
end

