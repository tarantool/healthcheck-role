--- Alerts helper for the healthcheck role.
-- Encapsulates creation and cleanup of config alerts so the role logic stays lean.
local config = require('config')

---@class alerts_module
local M = {
    namespace_name = 'healthcheck',
    alerts_namespace = nil,
    active = {},
}

local function ensure_namespace()
    if M.alerts_namespace == nil then
        M.alerts_namespace = config:new_alerts_namespace(M.namespace_name)
    end
end

--- Clears every alert previously set via this module.
function M.clear_all()
    if M.alerts_namespace == nil then
        M.active = {}
        return
    end

    for name in pairs(M.active) do
        M.alerts_namespace:unset(name)
    end
    M.active = {}
end

--- Updates alerts using the provided map of failed checks.
-- @param details table<string,string>|nil Map of check names to error messages.
function M.update(details)
    ensure_namespace()
    details = details or {}

    local seen = {}
    for name, message in pairs(details) do
        seen[name] = true
        M.alerts_namespace:set(name, {message = message})
        M.active[name] = true
    end

    for name in pairs(M.active) do
        if not seen[name] then
            M.alerts_namespace:unset(name)
            M.active[name] = nil
        end
    end
end

return M

