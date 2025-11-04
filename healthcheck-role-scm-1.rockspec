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
    "tarantool >= 3.0.2",
    "http == scm-1",
}

build = {
    type = "builtin",
    modules = {
        ["roles.healthcheck"] = "roles/healthcheck.lua"
    }
}
