local t = require('luatest')
local fio = require('fio')

--- Helpers for unit tests (box initialization, helper utilities).
---
---@class unit_test_helpers
local helpers = {}

t.before_suite(function()
    local root = fio.dirname(package.search('healthcheck'))
    local data_path = fio.pathjoin(root, 'tmp', 'unit')
    fio.mktree(data_path)

    local ok, err = pcall(box.cfg, {
        wal_dir = data_path,
        memtx_dir = data_path,
        vinyl_dir = data_path,
    })

    if not ok then
        local message = tostring(err)
        if not message:match('already been called') then
            error(err)
        end
    end
end)

--- Create (or replace) a box.func with provided body.
---@param name string
---@param body string
function helpers.create_func(name, body)
    helpers.drop_func(name)
    box.schema.func.create(name, {
        language = 'LUA',
        body = body,
    })
end

--- Drop function if it exists.
---@param name string
function helpers.drop_func(name)
    if box.func[name] ~= nil then
        box.schema.func.drop(name)
    end
end

--- Stub logger method and capture calls until restore is invoked.
---@param logger table
---@param method string
---@return fun()
---@return table
function helpers.stub_logger(logger, method)
    local original = logger[method]
    local entries = {}
    logger[method] = function(...)
        table.insert(entries, {...})
    end
    return function()
        logger[method] = original
    end, entries
end

return helpers
