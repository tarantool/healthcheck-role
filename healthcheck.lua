local config = require('config')
local fio = require('fio')

local details_consts = require('details_consts')

local M = {}

--- check_health check health by:
--- - default checks
--- - user defined checks
--- - additional checks
---@return boolean, table<number, string>
function M.check_health()
    local res_defaults, details_defaults = M.check_defaults()
    return res_defaults, details_defaults
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

function M.check_user_checks()
    
end

return M
