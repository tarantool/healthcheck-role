-- integration tests for snapshot/wal path resolution

local t = require('luatest')
local helpers = require('test.helpers.integration')
local cbuilder = require('luatest.cbuilder')
local fio = require('fio')

---@type luatest.group
local g = t.group()

local function root_path()
    return fio.dirname(package.search('healthcheck'))
end

local function assert_health_ok()
    local resp = helpers.http_get(8081, '/healthcheck')
    t.assert_equals(resp.status, 200)
    t.assert_equals(resp:decode().status, 'alive')
end

---@param cg basic_test_context
g.before_each(function(cg)
    cg.base = fio.pathjoin(root_path(), 'tmp', 'dir_resolution')
    fio.rmtree(cg.base)
    fio.mktree(cg.base)
end)

---@param cg basic_test_context
g.after_each(function(cg)
    if cg.cluster ~= nil then
        cg.cluster:stop()
    end
end)

---Start cluster with provided dir options and ensure target dirs exist inside instance.
---@param cg basic_test_context
---@param opts table
local function start_cluster(cg, opts)
    local builder = cbuilder:new()
        :use_group('routers')
        :set_group_option('roles', { 'roles.httpd', 'roles.healthcheck' })
        :set_group_option('roles_cfg', {
            ['roles.healthcheck'] = {
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

    if opts.wal_dir then
        builder:set_global_option('wal.dir', opts.wal_dir)
    end
    if opts.snap_dir then
        builder:set_global_option('snapshot.dir', opts.snap_dir)
    end
    if opts.work_dir then
        builder:set_global_option('process.work_dir', opts.work_dir)
    end

    local cluster = helpers.create_test_cluster(builder:config())
    cluster:start()

    cg.cluster = cluster
end

---@param cg basic_test_context
g.test_absolute_dirs_with_absolute_work_dir = function(cg)
    local base = fio.pathjoin(cg.base, 'abs')
    fio.mktree(base)
    local wal_dir = fio.pathjoin(base, 'wal')
    local snap_dir = fio.pathjoin(base, 'snap')
    local work_dir = fio.pathjoin(base, 'work')
    fio.mktree(wal_dir)
    fio.mktree(snap_dir)
    fio.mktree(work_dir)

    start_cluster(cg, {
        wal_dir = wal_dir,
        snap_dir = snap_dir,
        work_dir = work_dir,
    })

    assert_health_ok()
end

---@param cg basic_test_context
g.test_relative_dirs_with_absolute_work_dir = function(cg)
    local base = fio.pathjoin(cg.base, 'rel_with_abs_work')
    fio.mktree(base)
    local work_dir = fio.pathjoin(base, 'work')
    local wal_rel = 'wal_rel'
    local snap_rel = 'snap_rel'
    fio.mktree(work_dir)

    start_cluster(cg, {
        wal_dir = wal_rel,
        snap_dir = snap_rel,
        work_dir = work_dir,
    })

    assert_health_ok()
end

---@param cg basic_test_context
g.test_absolute_dirs_with_relative_work_dir = function(cg)
    local base = fio.pathjoin(cg.base, 'abs_with_rel_work')
    fio.mktree(base)
    local wal_dir = fio.pathjoin(base, 'wal_abs')
    local snap_dir = fio.pathjoin(base, 'snap_abs')
    fio.mktree(wal_dir)
    fio.mktree(snap_dir)

    start_cluster(cg, {
        wal_dir = wal_dir,
        snap_dir = snap_dir,
        work_dir = 'work',
    })

    assert_health_ok()
end

---@param cg basic_test_context
g.test_relative_dirs_with_relative_work_dir = function(cg)
    local base = fio.pathjoin(cg.base, 'all_rel')
    fio.mktree(base)

    start_cluster(cg, {
        wal_dir = 'wal_rel',
        snap_dir = 'snap_rel',
        work_dir = 'work',
    })

    assert_health_ok()
end

---@param cg basic_test_context
g.test_no_workdir_relative_dirs = function(cg)
    local base = fio.pathjoin(cg.base, 'no_work_dir')
    fio.mktree(base)

    start_cluster(cg, {
        wal_dir = 'wal_rel',
        snap_dir = 'snap_rel',
    })

    assert_health_ok()
end

---@param cg basic_test_context
g.test_relative_workdir_no_dirs = function(cg)
    local base = fio.pathjoin(cg.base, 'no_dir_rel_workdir')
    fio.mktree(base)

    start_cluster(cg, {
        work_dir = 'work',
    })

    assert_health_ok()
end
