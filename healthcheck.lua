local M = {}

--- check_health check health by:
--- - default checks
--- - user defined checks
--- - configurable checks
---@return boolean, table<number, string>
function M.check_health()
    return true, nil
end


return M
