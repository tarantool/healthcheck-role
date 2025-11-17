local luatest_cluster = require('luatest.cluster')
local fio = require('fio')
local http_client = require('http.client')
local clock = require('clock')

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

    local cluster_dir = fio.pathjoin(root, 'tmp')
    fio.rmtree(cluster_dir)
    local cluster = luatest_cluster:new(config, server_opts, {dir = cluster_dir})
    ---@cast cluster LuatestCluster
    return cluster
end

--- Mock healthcheck restult for tests
--- 
--- @param cluster LuatestCluster
--- @param is_healthy boolean
--- @param details table<string,string>|nil
function helpers.mock_healthcheck(cluster, is_healthy, details)
    details = details or {}
    cluster:each(function(server)
        server:exec(function(is_healthy, details)
            local healthcheck = require('healthcheck')
            if rawget(_G, '_healthcheck_check_health_orig') == nil then
                rawset(_G, '_healthcheck_check_health_orig', healthcheck.check_health)
            end
            healthcheck.check_health = function ()
                return is_healthy, table.deepcopy(details)
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

--- build_httpd_roles_cfg produces roles.httpd configuration from a list of servers.
---
--- @param servers table<number, { name: string, port: number }>
--- @return table<string, { listen: number }>
function helpers.build_httpd_roles_cfg(servers)
    assert(type(servers) == 'table', 'servers must be a table')
    local cfg = {}
    for _, server in ipairs(servers) do
        assert(type(server) == 'table', 'server entry must be a table')
        assert(server.name ~= nil, 'server.name must be provided')
        assert(server.port ~= nil, 'server.port must be provided')
        cfg[server.name] = { listen = server.port }
    end
    return cfg
end

--- generate_healthcheck_http_sections builds a randomized set of sections.
---
--- For every section we pick a random server (or fall back to the default one)
--- and create a random number of endpoints in the range `[0, endpoints_per_section]`
--- with sequential names (`/endpointN`). The function keeps seeding randomness
--- so that repeated calls produce different shapes while still tracking the
--- generated endpoints per server for assertions.
---
--- @class generate_http_section_options
--- @field sections integer -- total number of sections to produce
--- @field endpoints_per_section integer -- endpoints per section
--- @field servers? string[] -- non-default server names
--- @field start_index? integer -- starting suffix for endpoint names
--- @return table[] sections
--- @return table summary
function helpers.generate_healthcheck_http_sections(opts)
    math.randomseed(clock.time())
    opts = opts or {}
    local sections_count = opts.sections or 1
    local endpoints_per_section = opts.endpoints_per_section or 1
    local servers = opts.servers or {}
    local next_index = opts.start_index or 1

    assert(sections_count >= 1, 'opts.sections must be >= 1')
    assert(endpoints_per_section >= 1, 'opts.endpoints_per_section must be >= 1')

    local sections = {}
    local per_server = {}

    for _ = 1, sections_count do
        local server_token = servers[math.random(1, #servers+1)]
        local server_name = server_token or 'default'
        per_server[server_name] = per_server[server_name] or {}

        local endpoints = {}
        for _ = 1, math.random(0, endpoints_per_section) do
            local path = string.format('/endpoint%d', next_index)
            next_index = next_index + 1
            table.insert(endpoints, { path = path })
            table.insert(per_server[server_name], path)
        end

        local section = { endpoints = endpoints }
        if server_token then
            section.server = server_token
        end

        table.insert(sections, section)
    end

    per_server['default'] = per_server['default'] or {}
    for _, name in ipairs(servers) do
        per_server[name] = per_server[name] or {}
    end

    return sections, {
        per_server = per_server,
        next_index = next_index,
    }
end

return helpers
