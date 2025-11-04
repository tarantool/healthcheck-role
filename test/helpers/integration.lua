local luatest_cluster = require('luatest.cluster')
local fio = require('fio')
local http_client = require('http.client')
local json = require('json')

--- Tarantool server helper exposed by luatest.
---
---@class LuatestServer
---@field alias string
---@field id integer
---@field workdir string
---@field http_port number
---@field http_client table
---@field net_box_uri? string|table
---@field net_box? table
---@field start fun(self: LuatestServer, opts?: table)
---@field restart fun(self: LuatestServer, params?: table, opts?: table)
---@field stop fun(self: LuatestServer)
---@field drop fun(self: LuatestServer)
---@field wait_until_ready fun(self: LuatestServer)
---@field exec fun(self: LuatestServer, fn: fun(...: any): any, args?: table, options?: table): any
---@field call fun(self: LuatestServer, fn: string, ...: any): any
---@field eval fun(self: LuatestServer, code: string, ...: any): any
---@field http_request fun(self: LuatestServer, method: string, path: string, options?: table): any
---@field grep_log fun(self: LuatestServer, pattern: string, bytes_num?: integer, opts?: table): string|nil
---@field update_box_cfg fun(self: LuatestServer, cfg: table)
---@field get_box_cfg fun(self: LuatestServer): table

--- Collection of Tarantool servers managed for a test case.
---
---@class LuatestCluster: { [string]: LuatestServer }
---@field start fun(self: LuatestCluster, opts?: table)
---@field start_instance fun(self: LuatestCluster, instance_name: string)
---@field stop fun(self: LuatestCluster)
---@field drop fun(self: LuatestCluster)
---@field size fun(self: LuatestCluster): integer
---@field each fun(self: LuatestCluster, f: fun(server: LuatestServer))
---@field sync fun(self: LuatestCluster, config: table, opts?: table)
---@field reload fun(self: LuatestCluster, config: table)
---@field _server_map table<string, LuatestServer>

--- Context shared between test cases.
---@class basic_test_context
---@field cluster LuatestCluster

--- Helper functions for integration tests in the healthcheck suite.
---
---@class integration_helpers
local helpers = {}

--- Create a cluster instance for integration tests.
---
---@param config table Configuration produced by `luatest.cbuilder`.
---@return LuatestCluster cluster Cluster object ready to be started.
function helpers.create_test_cluster(config)
    local root = fio.dirname(package.search('healthcheck'))
    local server_opts = {
        env = {
            LUA_PATH = root .. '/?.lua;' .. root .. '/?/?.lua;' ..
                root .. '/.rocks/share/tarantool/?.lua;' ..
                root .. '/.rocks/share/tarantool/?/init.lua;',
            LUA_CPATH = root .. '/.rocks/lib/tarantool/?.so;' ..
                root .. '/.rocks/lib/tarantool/?/?.so;',
        }
    }

    local cluster = luatest_cluster:new(config, server_opts, {dir = '.'})
    ---@cast cluster LuatestCluster
    return cluster
end

--- Mock healthcheck restult for tests
--- 
--- @param cluster LuatestCluster
--- @param is_healthy boolean
--- @param details table<number,string>|nil
function helpers.mock_healthcheck(cluster, is_healthy, details)
    cluster:each(function(server)
        server:exec(function(is_healthy, details)
            local healthcheck = require('healthcheck')
            if rawget(_G, '_healthcheck_check_health_orig') == nil then
                rawset(_G, '_healthcheck_check_health_orig', healthcheck.check_health)
            end
            healthcheck.check_health = function ()
                return is_healthy, details
            end
        end, {is_healthy, details})
    end)
end

--- Unmock healthcheck, returns original logic.
--- Must be called after helpers.mock_healthcheck, otherwise throws an error.
--- 
--- @param cluster LuatestCluster
function helpers.unmock_healthcheck(cluster)
    cluster:each(function(server)
        server:exec(function()
            local orig = rawget(_G, '_healthcheck_check_health_orig')
            if orig == nil then
                error('helpers.mock_healthcheck was not called')
            end
            local healthcheck = require('healthcheck')
            healthcheck.check_health = orig
            rawset(_G, '_healthcheck_check_health_orig', nil)
        end)
    end)
end

--- @class HTTPResponse
--- @field decode fun(self: HTTPResponse)
--- @field status string

--- http_get makes http get request to localhost.
--- Returns response object.
--- @param port number
--- @param path string
--- @return HTTPResponse
function helpers.http_get(port, path)
    return http_client.get('http://localhost:' .. port .. path)
end

return helpers
