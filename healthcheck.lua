local config = require('config')
local fiber = require('fiber')
local fio = require('fio')
local log = require('logger')

local details_consts = require('details_consts')

local USER_CHECK_PREFIX = 'healthcheck.check_'

local M = {}

local function extend_details(dst, src)
    for _, value in ipairs(src) do
        table.insert(dst, value)
    end
end

--- check_health check health by:
--- - default checks
--- - user defined checks
--- - additional checks
---@return boolean, table<number, string>
function M.check_health()
    local overall_result = true
    local all_details = {}

    local handlers = {
        M.check_defaults,
        M.check_user_checks,
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
---@return boolean, table<number, string>
function M.check_defaults()
    local result = true
    local details = {}
    if not M._check_box_info_status() then
        table.insert(details, details_consts.BOX_INFO_STATUS_NOT_RUNNING)
    end

    if not M._check_snapshot_dir() then
        table.insert(details, details_consts.DISK_ERROR_SNAPSHOT_DIR)
    end

    if not M._check_wal_dir() then
        table.insert(details, details_consts.DISK_ERROR_WAL_DIR)
    end

    if #details > 0 then
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

function M.check_additional()
    
end

--- check_user_checks executes user-defined checks registered in _func space.
--- box functions must start with healthcheck.check_ prefix and return boolean[, string].
---@return boolean, table<number, string>
function M.check_user_checks()
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

        local func = box.func[func_name]
        if func == nil or func.call == nil then
            result = false
            table.insert(details, string.format('%s: function is not available', func_name))
            break
        end

        local ok, check_res, err_detail = pcall(func.call, func)
        if not ok then
            result = false
            table.insert(details, string.format('%s: %s', func_name, tostring(check_res)))
            break
        end

        if type(check_res) ~= 'boolean' then
            log.warn('healthcheck user check %s returned non-boolean result (%s), ignoring', func_name, type(check_res))
            break
        end

        if not check_res then
            result = false
            local reason = err_detail ~= nil and tostring(err_detail) or 'condition is not met'
            table.insert(details, string.format('%s: %s', func_name, reason))
        end

        processed = processed + 1
        if processed % 100 == 0 then
            fiber.yield()
        end
    end

    return result, details
end

return M
