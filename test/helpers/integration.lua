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

    local cluster = luatest_cluster:new(config, server_opts, {dir = fio.pathjoin(root, 'tmp')})
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

--- generate_healthcheck_http_sections builds randomized healthcheck sections.
---
--- Returned summary contains expected endpoints per server and allows callers to
--- accumulate all generated paths across iterations.
---
--- @class generate_http_section_options
--- @field seed? integer
--- @field sections? integer
--- @field min_endpoints? integer
--- @field max_endpoints? integer
--- @field servers? string[]
--- @field default_server? string
--- @field path_prefix? string
--- @field start_index? integer
--- @field allow_serverless? boolean
--- @field include_empty_section? boolean
--- @return table[] sections
--- @return table summary
function helpers.generate_healthcheck_http_sections(opts)
    opts = opts or {}
    local sections_count = opts.sections or 3
    local min_endpoints = opts.min_endpoints or 0
    local max_endpoints = opts.max_endpoints or 3
    local servers = opts.servers or {}
    local default_server = opts.default_server or 'default'
    local allow_serverless = opts.allow_serverless ~= false
    local next_index = opts.start_index or 1
    local path_prefix = opts.path_prefix or '/health-auto'

    assert(sections_count >= 1, 'opts.sections must be >= 1')
    assert(max_endpoints >= min_endpoints, 'opts.max_endpoints must be >= opts.min_endpoints')

    if opts.seed ~= nil then
        math.randomseed(opts.seed)
    end

    local sections = {}
    local per_server = {}

    for _, name in ipairs(servers) do
        per_server[name] = per_server[name] or {}
    end
    per_server[default_server] = per_server[default_server] or {}

    for _ = 1, sections_count do
        local section = {}
        local endpoints = {}

        local target_server = nil
        if #servers > 0 then
            local pool_size = #servers + (allow_serverless and 1 or 0)
            local choice = math.random(1, pool_size)
            if choice <= #servers then
                target_server = servers[choice]
                section.server = target_server
            end
        end

        local endpoints_count = 0
        if max_endpoints > 0 then
            endpoints_count = math.random(min_endpoints, max_endpoints)
        end

        for _ = 1, endpoints_count do
            local path = string.format('%s-%04d', path_prefix, next_index)
            next_index = next_index + 1
            table.insert(endpoints, { path = path })
            per_server[target_server or default_server] =
                per_server[target_server or default_server] or {}
            table.insert(per_server[target_server or default_server], path)
        end

        section.endpoints = endpoints
        table.insert(sections, section)
    end

    if opts.include_empty_section then
        table.insert(sections, { endpoints = {} })
    end

    local all_paths = {}
    for _, paths in pairs(per_server) do
        for _, path in ipairs(paths) do
            all_paths[path] = true
        end
    end

    return sections, {
        per_server = per_server,
        all_paths = all_paths,
        next_index = next_index,
    }
end

return helpers
