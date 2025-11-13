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

-- format field is optional but must be a string when present
function g.test_valid_format_config()
    local cfg = {
        http = {
            {
                endpoints = {
                    { path = '/healthz', format = 'custom_healthcheck_format' },
                },
            },
        },
    }

    healthcheck_role.validate(cfg)
end

function g.test_invalid_format_type()
    local cfg = {
        http = {
            {
                endpoints = {
                    { path = '/healthz', format = 123 },
                },
            },
        },
    }

    t.assert_error_msg_contains(
        'http[1].endpoints[1].format',
        function()
            healthcheck_role.validate(cfg)
        end
    )
end
