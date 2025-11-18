package = "healthcheck-role"
version = "scm-1"

source = {
    branch = "master",
    url = "git+https://github.com/tarantool/healthcheck-role",
}

description = {
    summary = "The Tarantool 3 role for healthchecks",
    homepage = "https://github.com/tarantool/healthcheck-role",
}

dependencies = {
    "lua >= 5.1",
    "tarantool >= 3.3.0",
    "http == 1.9.0",
}

build = {
    type = "builtin",
    modules = {
        ["roles.healthcheck"] = "roles/healthcheck.lua",
        ["healthcheck"] = "healthcheck.lua",
        ["healthcheck/alerts"] = "healthcheck/alerts.lua",
        ["healthcheck/logger"] = "healthcheck/logger.lua",
        ["healthcheck/ratelim"] = "healthcheck/ratelim.lua",
        ["healthcheck/replication_checks"] = "healthcheck/replication_checks.lua",
        ["healthcheck/version"] = "healthcheck/version.lua",
    }
}
