--- test for http configuration
--- - adding/deleting endpoints
--- - adding/deleting servers
--- - server port change

local t = require('luatest')
local helpers = require('test.helpers.integration')
local cbuilder = require('luatest.cbuilder')

local g = t.group()

--- Start a fresh cluster before each case.
---@param cg basic_test_context
g.before_each(function(cg)
    ---@type table
    local config = cbuilder:new()
        :use_group('routers')
        :use_replicaset('router')
        :add_instance('router', {})
        :config()

    cg.cluster = helpers.create_test_cluster(config)
    cg.cluster:start()
end)

--- Stop the cluster created for the test case.
---@param cg basic_test_context
g.after_each(function(cg)
    cg.cluster:stop()
end)

--- check_endpoint_existence check endpoint path existence
--- @param port number
--- @param path string
local function check_endpoint_existence(port, path)
    local resp = helpers.http_get(port, path)
    t.assert_equals(resp.status, 200, path)
end

--- check_endpoint_nonexistence check endpoint path nonexistence
--- @param port number
--- @param path string
local function check_endpoint_nonexistence(port, path)
    local resp = helpers.http_get(port, path)
    t.assert_equals(resp.status, 404, path)
end

--- test various endpoints configurations with default server
---@param cg basic_test_context
g.test_endpoints_add_remove = function(cg)
    -- first endpoint added
    local config = cbuilder:new()
        :use_group('routers')
        :set_group_option('roles', { 'roles.httpd', 'roles.healthcheck' })
        :set_group_option('roles_cfg', {
            ['roles.healthcheck'] = {
                http = {
                    {
                        endpoints = {
                            {
                                path = '/healthcheck1',
                            },
                        },
                    },
                },
            },
        })
        :use_replicaset('router')
        :add_instance('router', {})
        :set_instance_option('router', 'roles_cfg', {
            ['roles.httpd'] = {
                default = {
                    listen = 8081,
                },
            },
        })

    cg.cluster:reload(config:config())
    check_endpoint_existence(8081, '/healthcheck1')

    -- second endpoint added
    config:set_group_option('roles_cfg', {
        ['roles.healthcheck'] = {
            http = {
                {
                    endpoints = {
                        {
                            path = '/healthcheck1',
                        },
                        {
                            path = '/healthcheck2'
                        },
                    },
                },
            },
        },
    })
    cg.cluster:reload(config:config())
    check_endpoint_existence(8081, '/healthcheck1')
    check_endpoint_existence(8081, '/healthcheck2')

    -- check routes count if we add same path in config
    -- see remove_side_slashes
    config:set_group_option('roles_cfg', {
        ['roles.healthcheck'] = {
            http = {
                {
                    endpoints = {
                        {
                            path = '/healthcheck1',
                        },
                        {
                            path = '/healthcheck2'
                        },
                        {
                            path = '/healthcheck2/'
                        },
                    },
                },
            },
        },
    })
    cg.cluster:reload(config:config())
    check_endpoint_existence(8081, '/healthcheck1')
    check_endpoint_existence(8081, '/healthcheck2/')
    check_endpoint_existence(8081, '/healthcheck2')
    t.assert_equals(cg.cluster['router']:exec(function(...)
        local server = require('roles.httpd').get_server()
        local cnt = 0
        for _ in pairs(server.iroutes) do
            cnt = cnt + 1
        end
        return cnt
    end), 2)

    -- add healthcheck3 in another section
    config:set_group_option('roles_cfg', {
        ['roles.healthcheck'] = {
            http = {
                {
                    endpoints = {
                        {
                            path = '/healthcheck1',
                        },
                        {
                            path = '/healthcheck2'
                        },
                        {
                            path = '/healthcheck2/'
                        },
                    },
                },
                {
                    endpoints = {
                        {
                            path = '/healthcheck3'
                        }
                    }
                },
            },
        },
    })
    cg.cluster:reload(config:config())
    check_endpoint_existence(8081, '/healthcheck1')
    check_endpoint_existence(8081, '/healthcheck2/')
    check_endpoint_existence(8081, '/healthcheck2')
    check_endpoint_existence(8081, '/healthcheck3')

    -- remove healthcheck1
    config:set_group_option('roles_cfg', {
        ['roles.healthcheck'] = {
            http = {
                {
                    endpoints = {
                        {
                            path = '/healthcheck2'
                        },
                        {
                            path = '/healthcheck2/'
                        },
                    },
                },
                {
                    endpoints = {
                        {
                            path = '/healthcheck3'
                        }
                    }
                },
            },
        },
    })

    cg.cluster:reload(config:config())
    check_endpoint_nonexistence(8081, '/healthcheck1')
    check_endpoint_existence(8081, '/healthcheck2/')
    check_endpoint_existence(8081, '/healthcheck2')
    check_endpoint_existence(8081, '/healthcheck3')

    -- remove healthcheck2
    config:set_group_option('roles_cfg', {
        ['roles.healthcheck'] = {
            http = {
                {
                    endpoints = {},
                },
                {
                    endpoints = {
                        {
                            path = '/healthcheck3'
                        }
                    }
                },
            },
        },
    })

    cg.cluster:reload(config:config())
    check_endpoint_nonexistence(8081, '/healthcheck1')
    check_endpoint_nonexistence(8081, '/healthcheck2/')
    check_endpoint_nonexistence(8081, '/healthcheck2')
    check_endpoint_existence(8081, '/healthcheck3')

    -- remove and add healthcheck3
    config:set_group_option('roles_cfg', {
        ['roles.healthcheck'] = {
            http = {
                {
                    endpoints = {},
                },
                {
                    endpoints = {}
                },
                {
                    endpoints = {
                        {
                            path = '/healthcheck3'
                        }
                    }
                }
            },
        },
    })

    cg.cluster:reload(config:config())
    check_endpoint_nonexistence(8081, '/healthcheck1')
    check_endpoint_nonexistence(8081, '/healthcheck2/')
    check_endpoint_nonexistence(8081, '/healthcheck2')
    check_endpoint_existence(8081, '/healthcheck3')
end


g.test_server_add_remove = function(cg)
    local config = cbuilder:new()
        :use_group('routers')
        :set_group_option('roles', { 'roles.httpd', 'roles.healthcheck' })
        :set_group_option('roles_cfg', {
            ['roles.healthcheck'] = {
                http = {
                    {
                        endpoints = {
                            {
                                path = '/healthcheck1',
                            },
                        },
                    },
                },
            },
        })
        :use_replicaset('router')
        :add_instance('router', {})
        :set_instance_option('router', 'roles_cfg', {
            ['roles.httpd'] = {
                default = {
                    listen = 8081,
                },
                additional = {
                    listen = 8082,
                },
            },
        })

    cg.cluster:reload(config:config())
    check_endpoint_existence(8081, '/healthcheck1')
    check_endpoint_nonexistence(8082, '/healthcheck2')

    -- add server
    config:set_group_option('roles_cfg', {
        ['roles.healthcheck'] = {
            http = {
                {
                    endpoints = {
                        {
                            path = '/healthcheck1',
                        },
                    },
                },
                {
                    server = 'additional',
                    endpoints = {
                        {
                            path = '/healthcheck2',
                        },
                    },
                },
            },
        },
    })
    cg.cluster:reload(config:config())
    check_endpoint_existence(8081, '/healthcheck1')
    check_endpoint_existence(8082, '/healthcheck2')
    -- delete server
    config:set_group_option('roles_cfg', {
        ['roles.healthcheck'] = {
            http = {
                {
                    server = 'additional',
                    endpoints = {
                        {
                            path = '/healthcheck2',
                        },
                    },
                },
            },
        },
    })
    cg.cluster:reload(config:config())
    check_endpoint_nonexistence(8081, '/healthcheck1')
    check_endpoint_existence(8082, '/healthcheck2')
end


--- test random endpoints configurations with different servers
---@param cg basic_test_context
g.test_http_config_mutations = function(cg)
    local servers = {
        { name = 'default', port = 8081 },
        { name = 'srv_2', port = 8082 },
        { name = 'srv_3', port = 8083 },
    }

    local config = cbuilder:new()
        :use_group('routers')
        :set_group_option('roles', { 'roles.httpd', 'roles.healthcheck' })
        :set_group_option('roles_cfg', {
            ['roles.healthcheck'] = {
                http = {
                    {
                        endpoints = {},
                    },
                },
            },
        })
        :use_replicaset('router')
        :add_instance('router', {})
        :set_instance_option('router', 'roles_cfg', {
            ['roles.httpd'] = helpers.build_httpd_roles_cfg(servers),
        })

    cg.cluster:reload(config:config())

    local path_index = 1
    local iterations = 42
    local healthcheck_servers = {}

    for _, server in ipairs(servers) do
        if server.name ~= 'default' then
            table.insert(healthcheck_servers, server.name)
        end
    end

    for _ = 1, iterations do
        local sections, summary = helpers.generate_healthcheck_http_sections({
            sections = 30,
            endpoints_per_section = 3,
            servers = healthcheck_servers,
            start_index = path_index,
        })

        path_index = summary.next_index

        config:set_group_option('roles_cfg', {
            ['roles.healthcheck'] = {
                http = sections,
            },
        })

        cg.cluster:reload(config:config())

        for _, server in ipairs(servers) do
            local expected_paths = summary.per_server[server.name] or {}
            local actual_count = cg.cluster['router']:exec(function(server_name)
                local httpd_role = require('roles.httpd')
                local srv = httpd_role.get_server(server_name)
                local cnt = 0
                for _ in pairs(srv.iroutes) do
                    cnt = cnt + 1
                end
                return cnt
            end, {server.name})

            t.assert_equals(actual_count, #expected_paths, server.name)
            for _, path in pairs(expected_paths) do
                check_endpoint_existence(server.port, path)
            end
        end
    end
end

--- test when server's port changes, endpoints must be available on new port
---@param cg basic_test_context
g.test_change_server_port = function(cg)
    local config = cbuilder:new()
        :use_group('routers')
        :set_group_option('roles', { 'roles.httpd', 'roles.healthcheck' })
        :set_group_option('roles_cfg', {
            ['roles.healthcheck'] = {
                http = {
                    {
                        endpoints = {
                            {
                                path = '/healthcheck',
                            },
                        },
                    },
                },
            },
        })
        :use_replicaset('router')
        :add_instance('router', {})
        :set_instance_option('router', 'roles_cfg', {
            ['roles.httpd'] = {
                default = {
                    listen = 8081,
                },
            },
        })

    cg.cluster:reload(config:config())
    check_endpoint_existence(8081, '/healthcheck')

    config:set_instance_option('router', 'roles_cfg', {
            ['roles.httpd'] = {
                default = {
                    listen = 8082,
                },
            },
        })
    cg.cluster:reload(config:config())
    check_endpoint_existence(8082, '/healthcheck')
end


--- test when role deleted from configuration, endpoints should be deleted too
---@param cg basic_test_context
g.test_role_stop = function(cg)
    local config = cbuilder:new()
        :use_group('routers')
        :set_group_option('roles', { 'roles.httpd', 'roles.healthcheck' })
        :set_group_option('roles_cfg', {
            ['roles.healthcheck'] = {
                http = {
                    {
                        endpoints = {
                            {
                                path = '/healthcheck',
                            },
                        },
                    },
                    {
                        server = 'additional',
                        endpoints = {
                            {
                                path = '/healthcheck',
                            },
                        },
                    },
                },
            },
        })
        :use_replicaset('router')
        :add_instance('router', {})
        :set_instance_option('router', 'roles_cfg', {
            ['roles.httpd'] = {
                default = {
                    listen = 8081,
                },
                additional = {
                    listen = 8082,
                },
            },
        })

    cg.cluster:reload(config:config())
    check_endpoint_existence(8081, '/healthcheck')
    check_endpoint_existence(8082, '/healthcheck')

    config:set_group_option('roles', { 'roles.httpd' })
    cg.cluster:reload(config:config())

    check_endpoint_nonexistence(8081, '/healthcheck')
    check_endpoint_nonexistence(8082, '/healthcheck')
end
