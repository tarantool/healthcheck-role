local urilib = require("uri")
local http_server = require('http.server')
local httpd_role = require('roles.httpd')
local log = require('logger')
local metrics = require('metrics')
local healthcheck = require('healthcheck')
local json = require('json')

local M = {
    prev_conf = nil,
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

--- @class EndpointConfig
--- @field path string

--- @class RoleHttpConfig
--- @field server string|nil
--- @field endpoints table<number,EndpointConfig>

--- @class RoleConfig
--- @field http table<number,RoleHttpConfig>
--- @param conf RoleConfig
function M.validate(conf)
    
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

function M.apply(conf)
    local new_conf = (conf and conf.http) or {}
    -- set new routes
    for _, http_cfg in pairs(new_conf) do
        local server_name = http_cfg.server or httpd_role.DEFAULT_SERVER_NAME
        local server = httpd_role.get_server(server_name)

        for _, endpoint in pairs(http_cfg.endpoints) do
            local path = remove_side_slashes(endpoint.path)
            if server.iroutes[path] == nil then
                server:route({
                    method = "GET",
                    path = path,
                    name = path,
                }, wrap_handler(function()
                    local is_healthy, details = healthcheck.check_health()
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
                    else
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
                end))
                log.info("set route, server: %s, path: %s", server_name, path)
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

    M.prev_conf = table.deepcopy(new_conf)
end



function M.stop(conf)
-- deletes all routes

end

M.dependencies = {'roles.httpd'}

return M
