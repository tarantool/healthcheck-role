local M = {}

-- Replication statuses treated as healthy.
local good_states = {
    follow = true,
    sync = true,
}

local function default_get_replication_info()
    return box.info.replication or {}
end

local get_replication_info = default_get_replication_info

---Used in tests to stub replication info provider.
---@param fn fun(): table|nil
function M._set_replication_info_provider(fn)
    get_replication_info = fn or default_get_replication_info
end

local function peer_label(replica)
    return replica.name
end


---Reports peers that have no upstream.
---@return boolean, table<string,string>
function M.check_upstream_absent()
    if not box.info.ro then
        return true, {}
    end

    local details = {}
    local ok = true
    local self_name = box.info.name
    for _, replica in pairs(get_replication_info()) do
        local label = peer_label(replica)
        if label ~= nil and label ~= self_name and replica.upstream == nil then
            ok = false
            local key = string.format('replication.upstream_absent.%s', label)
            details[key] = string.format('Replication from %q to %q is not running', label, self_name)
        end
    end

    return ok, details
end

---Reports peers with bad replication state.
---@return boolean, table<string,string>
function M.check_state_bad()
    if not box.info.ro then
        return true, {}
    end

    local details = {}
    local ok = true
    local self_name = box.info.name

    for _, replica in pairs(get_replication_info()) do
        local label = peer_label(replica)
        if label ~= nil and label ~= self_name then
            local upstream = replica.upstream
            if upstream == nil then
                goto continue
            end
            local status = upstream.status or upstream.state
            if status ~= nil and not good_states[status] then
                ok = false
                local key = string.format('replication.state_bad.%s', label)
                local msg = upstream.message or ''
                details[key] = string.format('Replication from %q to %q state %q (%s)', label, self_name, status, tostring(msg))
            end
        end
        ::continue::
    end

    return ok, details
end

return M
