local t = require('luatest')
local g = t.group()

local healthcheck_role = require('roles.healthcheck')

-- ensure a typical configuration passes schema validation
function g.test_valid_config()
    local cfg = {
        http = {
            {
                server = 'default',
                endpoints = {
                    { path = '/healthz' },
                    { path = 'ready' },
                },
            },
            {
                endpoints = {
                    { path = '/health/secondary' },
                },
            },
        },
    }

    healthcheck_role.validate(cfg)
end

-- invalid endpoint path type should be rejected by schema
function g.test_invalid_path_type()
    local cfg = {
        http = {
            {
                endpoints = {
                    { path = 42 },
                },
            },
        },
    }

    t.assert_error_msg_contains(
        'http[1].endpoints[1].path',
        function()
            healthcheck_role.validate(cfg)
        end
    )
end
