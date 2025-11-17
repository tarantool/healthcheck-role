local config = require('config')
local fiber = require('fiber')
local fio = require('fio')
local log = require('logger')

local details_consts = require('details_consts')
local replication_checks = require('replication_checks')

local USER_CHECK_PREFIX = 'healthcheck.check_'

local M = {}
local additional_checks = {
    replication = {
        upstream_absent = replication_checks.check_upstream_absent,
        state_bad = replication_checks.check_state_bad,
    },
}

local all_includes = {
    replication = true,
}

local function is_additional_check_enabled(group_name, check_name, filter)
    local full_name = string.format('%s.%s', group_name, check_name)
    if filter.exclude[full_name] or filter.exclude[group_name] then
        return false
    end
    if filter.include_all then
        return true
    end
    return filter.include[full_name] ~= nil or filter.include[group_name] ~= nil
end

local function extend_details(dst, src)
    if src == nil then
        return
    end
    for name, message in pairs(src) do
        dst[name] = message
    end
end

--- check_health check health by:
--- - default checks
--- - user defined checks
--- - additional checks
---@class CheckFilter
---@field include string[]|nil
---@field exclude string[]|nil
---@field include_all boolean|nil
---@class CheckFilterNormalized
---@field include table<string, boolean>
---@field exclude table<string, boolean>
---@field include_all boolean
---@param filter CheckFilter|nil
---@return boolean, table<string, string>
function M.check_health(filter)
    local normalized_filter = M._normalize_filter(filter)
    local overall_result = true
    local all_details = {}

    local handlers = {
        M.check_defaults,
        function()
            return M.check_user_checks(normalized_filter)
        end,
        function()
            return M.check_additional(normalized_filter)
        end,
    }

    for _, checker in ipairs(handlers) do
        local ok, details = checker()
        if not ok then
            overall_result = false
            extend_details(all_details, details)
        end
    end

    return overall_result, all_details
end

--- check_defaults called always
--- checks:
--- - box.info.status == 'running'
--- - snapshot dir exists
--- - wal dir exists
---@return boolean, table<string, string>
function M.check_defaults()
    local result = true
    local details = {}

    local ok_box = M._check_box_info_status()
    if not ok_box then
        details['check_box_info_status'] = details_consts.BOX_INFO_STATUS_NOT_RUNNING
        result = false
    end

    local ok_snapshot = M._check_snapshot_dir()
    if not ok_snapshot then
        details['check_snapshot_dir'] = details_consts.DISK_ERROR_SNAPSHOT_DIR
        result = false
    end

    local ok_wal = M._check_wal_dir()
    if not ok_wal then
        details['check_wal_dir'] = details_consts.DISK_ERROR_WAL_DIR
        result = false
    end

    return result, details
end


---checks box.info.status == 'running'
---@return boolean
function M._check_box_info_status()
    return box.info.status == 'running'
end

---checks wal.dir exists
---@return boolean
function M._check_wal_dir()
    if type(box.cfg) ~= 'table' then
        return true
    end

    local path = config:get('wal.dir')
    local work_dir = config:get('process.work_dir')
    if work_dir ~= box.NULL then
        path = fio.pathjoin(work_dir, path)
    end

    return fio.lstat(path)
end

---checks snapshot.dir exists
---@return boolean
function M._check_snapshot_dir()
    if type(box.cfg) ~= 'table' then
        return true
    end

    local path = config:get('snapshot.dir')
    local work_dir = config:get('process.work_dir')
    if work_dir ~= box.NULL then
        path = fio.pathjoin(work_dir, path)
    end

    return fio.lstat(path)
end


--- check_additional executes optional built-in checks controlled by include/exclude filter.
--- By default include_all=true so all additional checks run; set include manually to opt in specific ones.
---@param filter CheckFilterNormalized
---@return boolean, table<string, string>
function M.check_additional(filter)
    local result = true
    local details = {}

    for group_name, group in pairs(additional_checks) do
        for name, fn in pairs(group) do
            if not is_additional_check_enabled(group_name, name, filter) then
                goto continue
            end

            local ok, check_ok, check_details = pcall(fn)
            if not ok then
                result = false
                local full_name = string.format('%s.%s', group_name, name)
                details[full_name] = string.format('%s: %s', full_name, tostring(check_ok))
                goto continue
            end

            if check_ok ~= true then
                result = false
                if type(check_details) == 'table' then
                    extend_details(details, check_details)
                else
                    local full_name = string.format('%s.%s', group_name, name)
                    details[full_name] = check_details or string.format('%s: condition is not met', full_name)
                end
            end
            ::continue::
        end
    end

    return result, details
end

--- check_user_checks executes user-defined checks registered in _func space.
--- box functions must start with healthcheck.check_ prefix and return boolean[, string].
--- user defined checks will not be executed only if they directly added `exlcude`
---@param filter CheckFilterNormalized
---@return boolean, table<string, string>
function M.check_user_checks(filter)
    local result = true
    local details = {}

    if type(box.cfg) ~= 'table' then
        return true, details
    end

    local processed = 0
    for _, func_tuple in box.space._func.index.name:pairs(USER_CHECK_PREFIX, 'GE') do
        local func_name = func_tuple.name
        if type(func_name) ~= 'string' or not func_name:startswith(USER_CHECK_PREFIX) then
            break
        end
        
        if filter.exclude[func_name] ~= nil then
            goto continue
        end

        local func = box.func[func_name]
        if func == nil or func.call == nil then
            result = false
            details[func_name] = string.format('%s: function is not available', func_name)
            break
        end

        local ok, check_res, err_detail = pcall(func.call, func)
        if not ok then
            result = false
            details[func_name] = tostring(check_res)
            break
        end

        if type(check_res) ~= 'boolean' then
            log.warn('healthcheck user check %s returned non-boolean result (%s), ignoring', func_name, type(check_res))
            break
        end

        if not check_res then
            result = false
            local reason = err_detail ~= nil and tostring(err_detail) or 'condition is not met'
            details[func_name] = reason
        end

        processed = processed + 1
        if processed % 100 == 0 then
            fiber.yield()
        end
        ::continue::
    end

    return result, details
end

---@param list table|nil
---@return table<string, boolean>
local function normalize_to_set(list)
    if list == nil then
        return {}
    end

    local result = {}
    for _, value in pairs(list) do
        if type(value) == 'string' then
            result[value] = true
        end
    end

    return result
end

--- normalize_filter adds default values to CheckFilter
--- @param filter CheckFilter|nil
--- @return CheckFilterNormalized
function M._normalize_filter(filter)
    ---@type CheckFilterNormalized
    filter = filter or {}
    local include = normalize_to_set(filter.include)
    local exclude = normalize_to_set(filter.exclude)
    local include_all = filter.include_all
    if include_all == nil then
        include_all = (filter.include == nil) or include['all'] == true
    end
    if include_all then
        include = table.deepcopy(all_includes)
    else
        include['all'] = nil
    end
    filter.exclude = exclude
    filter.include_all = include_all
    filter.include = include
    return filter
end

return M
