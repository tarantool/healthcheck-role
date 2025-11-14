local httpd_role = require('roles.httpd')
local log = require('logger')
local metrics = require('metrics')
local healthcheck = require('healthcheck')
local json = require('json')
local schema = require('experimental.config.utils.schema')
local config_module = require('config')

local ALERTS_NAMESPACE = 'healthcheck'

local M = {
    prev_conf = nil,
    alerts = nil,
    active_alerts = {},
    set_alerts_enabled = false,
}

local function wrap_handler(handler)
    if metrics ~= nil and metrics.enabled == true then
        local http_middleware = require('metrics.http_middleware')
        return http_middleware.v1(handler)
    end
    return handler
end

local function remove_side_slashes(path)
    if path:startswith('/') then
        path = string.lstrip(path, '/')
    end
    if path:endswith('/') then
        path = string.rstrip(path, '/')
    end
    return '/' .. path
end

local function ensure_alerts_namespace()
    if M.alerts == nil then
        M.alerts = config_module:new_alerts_namespace(ALERTS_NAMESPACE)
    end
end

local function clear_all_alerts()
    if M.alerts == nil then
        M.active_alerts = {}
        return
    end

    for name in pairs(M.active_alerts) do
        M.alerts:unset(name)
    end
    M.active_alerts = {}
end

local function update_alerts(details_map)
    ensure_alerts_namespace()
    local seen = {}

    for name, message in pairs(details_map or {}) do
        seen[name] = true
        M.alerts:set(name, {message = message})
        M.active_alerts[name] = true
    end

    for name in pairs(M.active_alerts) do
        if not seen[name] then
            M.alerts:unset(name)
            M.active_alerts[name] = nil
        end
    end
end

local function details_map_to_array(map)
    if map == nil then
        return {}
    end

    local keys = {}
    for name in pairs(map) do
        table.insert(keys, name)
    end
    table.sort(keys)

    local result = {}
    for _, name in ipairs(keys) do
        table.insert(result, map[name])
    end
    return result
end

local healthcheck_role_schema = schema.new('healthcheck_role', schema.record({
    set_alerts = schema.scalar({
        type = 'boolean',
        default = false,
    }),
    http = schema.array({
        items = schema.record({
            server = schema.scalar({
                type = 'string',
                default = httpd_role.DEFAULT_SERVER_NAME,
            }),
            endpoints = schema.array({
                items = schema.record({
                    path = schema.scalar({
                        type = 'string',
                    }),
                    format = schema.scalar({
                        type = 'string',
                    }),
                })
            })
        })
    })
}))

--- @class EndpointConfig
--- @field path string
--- @field format string|nil

--- @class RoleHttpConfig
--- @field server string|nil
--- @field endpoints table<number,EndpointConfig>

--- @class RoleConfig
--- @field http table<number,RoleHttpConfig>
--- @field set_alerts boolean|nil
--- @param conf RoleConfig
function M.validate(conf)
    healthcheck_role_schema:validate(conf)
end

--- Collects endpoints grouped by server for the provided config.
--- @param conf RoleConfig|nil
--- @alias server_name string
--- @alias endpoint_path string
--- @return table<server_name,table<endpoint_path,boolean>>
local function endpoints_by_server(conf)
    local index = {}
    if conf == nil then
        return index
    end

    local http_cfgs = conf.http or conf
    if http_cfgs == nil then
        return index
    end

    for _, cfg in pairs(http_cfgs) do
        if cfg ~= nil then
            local server_name = cfg.server or httpd_role.DEFAULT_SERVER_NAME
            local endpoints = cfg.endpoints or {}
            local server_entry = index[server_name]
            if server_entry == nil then
                server_entry = {}
                index[server_name] = server_entry
            end
            for _, endpoint in pairs(endpoints) do
                if endpoint ~= nil then
                    local path = endpoint.path
                    if type(path) == "string" and path ~= "" then
                        server_entry[remove_side_slashes(path)] = true
                    end
                end
            end
        end
    end

    return index
end

--- get_routes_to_delete compares previous and current conf and get routes to delete.
---@param prev_conf RoleConfig|nil
---@param curr_conf RoleConfig
---@return table<server_name,table<number,endpoint_path>>
local function get_routes_to_delete(prev_conf, curr_conf)
    local to_delete = {}
    local prev_index = endpoints_by_server(prev_conf)
    local curr_index = endpoints_by_server(curr_conf)

    for server_name, prev_paths in pairs(prev_index) do
        local curr_paths = curr_index[server_name]
        for path in pairs(prev_paths) do
            if curr_paths == nil or curr_paths[path] == nil then
                local list = to_delete[server_name]
                if list == nil then
                    list = {}
                    to_delete[server_name] = list
                end
                list[#list + 1] = path
            end
        end
    end

    return to_delete
end

local function default_response(is_healthy, details)
    if is_healthy then
        return {
            status = 200,
            body = json.encode({
                status = 'alive',
            }),
            headers = {
                ['content-type'] = 'application/json',
            }
        }
    end

    return {
        status = 500,
        body = json.encode({
            status = 'dead',
            details = details,
        }),
        headers = {
            ['content-type'] = 'application/json',
        },
    }
end

local function formatter_error_detail(format_name, reason)
    if reason == nil then
        return ("healthcheck format function '%s' is not defined"):format(format_name)
    end
    return ("healthcheck format function '%s' %s"):format(format_name, reason)
end

local function formatter_error_response(format_name, reason)
    return default_response(false, {formatter_error_detail(format_name, reason)})
end

local function ensure_formatter_exists(format_name)
    if format_name == nil then
        return
    end

    -- box.cfg might be not initialized yet, guard box.func access
    local fmt = box.func and box.func[format_name]
    if fmt == nil or fmt.call == nil then
        local msg = formatter_error_detail(format_name)
        log.error(msg)
        error(msg)
    end
end

local function build_response(is_healthy, details, format_name)
    if format_name ~= nil then
        -- box.cfg might be not initialized yet, guard box.func access
        local fmt = box.func and box.func[format_name]
        if fmt == nil or fmt.call == nil then
            log.error("healthcheck format function '%s' is not defined", format_name)
            return formatter_error_response(format_name)
        end

        -- tarantool box.func:call expects argument list packed in a table
        local ok, response = pcall(fmt.call, fmt, {is_healthy, details})
        if not ok then
            log.error("healthcheck format function '%s' failed: %s", format_name, tostring(response))
            return formatter_error_response(format_name, 'failed to execute')
        end

        if type(response) ~= 'table' then
            log.error("healthcheck format function '%s' returned non-table result", format_name)
            return formatter_error_response(format_name, 'returned invalid response')
        end

        return response
    end

    return default_response(is_healthy, details)
end

function M.apply(conf)
    local new_conf = healthcheck_role_schema:apply_default(conf)
    for _, http_cfg in pairs(new_conf.http) do
        local server = httpd_role.get_server(http_cfg.server)
        if server == nil then
            local msg = ("incorrect configuration, http server '%s' does not exist. check roles.https config"):format(http_cfg.server)
            log.error(msg)
            error(msg)
        end
    end
    M.set_alerts_enabled = new_conf.set_alerts
    if not M.set_alerts_enabled then
        clear_all_alerts()
    end

    -- set new routes
    for _, http_cfg in pairs(new_conf.http) do
        local server = httpd_role.get_server(http_cfg.server)
        for _, endpoint in pairs(http_cfg.endpoints) do
            local path = remove_side_slashes(endpoint.path)
            ensure_formatter_exists(endpoint.format)
            if server.iroutes[path] == nil then
                server:route({
                    method = "GET",
                    path = path,
                    name = path,
                }, wrap_handler(function()
                    local is_healthy, details_map = healthcheck.check_health()
                    if M.set_alerts_enabled then
                        update_alerts(details_map)
                    end
                    local details = details_map_to_array(details_map)
                    return build_response(is_healthy, details, endpoint.format)
                end))
                log.info("set route, server: %s, path: %s", http_cfg.server, path)
            end
        end
    end
    -- delete old routes
    local routes_to_delete = get_routes_to_delete(M.prev_conf, new_conf)
    for server_name, pathes in pairs(routes_to_delete) do
        local server = httpd_role.get_server(server_name)
        if server == nil then
            goto continue
        end
        for _, path in pairs(pathes) do
            server:delete(path)
            log.info("delete route, server: %s, path: %s", server_name, path)
        end
        ::continue::
    end

    ---@type RoleConfig
    M.prev_conf = table.deepcopy(new_conf)
end

function M.stop()
    -- deletes all routes
    if M.prev_conf == nil then
        clear_all_alerts()
        return
    end

    for _, http_cfg in pairs(M.prev_conf.http) do
        local server = httpd_role.get_server(http_cfg.server)
        if server == nil then
            goto continue
        end
        for _, endpoint in pairs(http_cfg.endpoints) do
            local path = remove_side_slashes(endpoint.path)
            if server.iroutes[path] ~= nil then
                server:delete(path)
                log.info("delete route, server: %s, path: %s", http_cfg.server, path)
            end
        end
        ::continue::
    end

    clear_all_alerts()
    M.alerts = nil
    M.set_alerts_enabled = false
end

M.dependencies = {
    'roles.httpd',
}

return M
