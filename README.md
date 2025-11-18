# Tarantool 3 Healthcheck Role

A Tarantool role that exposes configurable HTTP health endpoints (e.g. `/healthcheck`), runs built-in checks (cluster and replication), executes your own checks, and can emit alerts.

## Contents

- [Quick start (working config)](#quick-start-working-config)
- [Why use it](#why-use-it)
- [Configuration (from simple to advanced)](#configuration-from-simple-to-advanced)
  - [Minimal endpoint](#minimal-endpoint)
  - [Custom endpoint / server](#custom-endpoint--server)
  - [Rate limiting](#rate-limiting)
  - [Alerts](#alerts)
  - [Additional checks include/exclude](#additional-checks-includeexclude)
  - [Custom response format](#custom-response-format)
- [Default checks](#default-checks)
- [Additional checks](#additional-checks)
- [Custom checks (user-defined)](#custom-checks-user-defined)
- [Response format (default)](#response-format-default)

## Quick start (working config)

Create `config.yml`:
```yaml
roles_cfg:
  roles.healthcheck:
    http:
      - endpoints:
          - path: /healthcheck
groups:
  group-001:
    replicasets:
      router:
        instances:
          router:
            roles: [roles.httpd, roles.healthcheck]
            roles_cfg:
              roles.httpd:
                default:
                  listen: '127.0.0.1:8081'
```

Create `instances.yml`:
```yaml
router:
```

Then initialize and start the instance with `tt`:

```bash
tt init
tt start
curl http://127.0.0.1:8081/healthcheck
{"status":"alive"}
```

After start, `http://127.0.0.1:8081/healthcheck` returns `200` when all checks pass, and `500` with details when some checks fail.

## Why use it

- HTTP endpoint(s) for liveness with meaningful failure reasons.
- Built-in defaults: Tarantool status (`box.info.status`) and ability to write snapshot/WAL files.
- Optional additional checks (e.g. replication).
- Custom criteria: add your own `healthcheck.check_*` functions.
- Optional alerts, rate limiting, and custom response formats.

## Configuration (from simple to advanced)

### Minimal endpoint
The snippet above enables one endpoint at `/healthcheck` on the default HTTP server; you can add more paths/endpoints if needed.

For details on HTTP server configuration, see the [tarantool/http](https://github.com/tarantool/http) README.

### Custom endpoint / server
```yaml
roles_cfg:
  roles.httpd:
    default:
      listen: '127.0.0.1:8081'
    additional:
      listen: '127.0.0.1:8082'
  roles.healthcheck:
    http:
      - server: additional
        endpoints:
          - path: /hc
```

### Rate limiting
```yaml
roles_cfg:
  roles.healthcheck:
    ratelim_rps: 5  # requests per second; null (default) disables
    http:
      - endpoints:
          - path: /healthcheck
```
Excess requests return `429`.

### Alerts
```yaml
roles_cfg:
  roles.healthcheck:
    set_alerts: true
    http:
      - endpoints:
          - path: /healthcheck
```
Failed checks are mirrored into alerts.

Alerts are visible via `box.info.config.alerts` (see the
[config.info() reference](https://www.tarantool.io/ru/doc/latest/reference/reference_lua/config/#lua-function.config.info))
and in the [TCM](https://www.tarantool.io/en/doc/latest/tooling/tcm/) web interface.

### Additional checks include/exclude
```yaml
roles_cfg:
  roles.healthcheck:
    checks:
      include: [all]        # default
      exclude: ['replication.upstream_absent', 'replication.state_bad'] # default {}
    http:
      - endpoints:
          - path: /healthcheck
```
`include` / `exclude` applies to built-in additional checks. `exclude` wins. **User checks run unless explicitly excluded.**

### Custom response format
Provide a formatter function in `box.func` returning `{status=<number>, headers=?, body=?}`.
For details on the HTTP request/response format, see
[Fields and methods of the request object](https://github.com/tarantool/http?tab=readme-ov-file#fields-and-methods-of-the-request-object).
```lua
box.schema.func.create('custom_healthcheck_format', {
  language = 'LUA',
  body = [[
    function(is_healthy, details)
      local json = require('json')
      if is_healthy then
        return { status = 200, body = json.encode({ok=true}) }
      end
      return {
        status = 560,
        headers = {['content-type'] = 'application/json'},
        body = json.encode({errors = details}),
      }
    end
  ]]
})
```
Use it in the endpoint:
```yaml
roles_cfg:
  roles.healthcheck:
    http:
      - endpoints:
          - path: /healthcheck
            format: custom_healthcheck_format
```

## Default checks

| Check key               | What it does                                | Fails when                                      |
|-------------------------|---------------------------------------------|-------------------------------------------------|
| `check_box_info_status` | `box.info.status == 'running'`              | Tarantool status is not `running`               |
| `check_snapshot_dir`    | `snapshot.dir` exists (respecting work_dir) | Snapshot dir missing or inaccessible            |
| `check_wal_dir`         | `wal.dir` exists (respecting work_dir)      | WAL dir missing or inaccessible                 |

## Additional checks

| Key prefix / detail                        | Runs when               | Fails when / detail example                                          |
|--------------------------------------------|-------------------------|-----------------------------------------------------------------------|
| `replication.upstream_absent.<peer>`       | Replica nodes           | No upstream for a peer; `Replication from <peer> to <self> is not running` |
| `replication.state_bad.<peer>`             | Replica nodes           | Upstream state not `follow`/`sync`; includes upstream state/message   |

Additional checks are included by default; refine with `checks.include` / `checks.exclude`.

## Custom checks (user-defined)

Any `box.func` named `healthcheck.check_*` is executed unless excluded.

```lua
-- migration or role code
box.schema.func.create('healthcheck.check_space_size', {
  if_not_exists = true,
  language = 'LUA',
  body = [[
    function()
      local limit = 10 * 1024 * 1024
      local used = box.space.my_space:bsize()
      if used > limit then
        return false, 'my_space is larger than 10MB'
      end
      return true
    end
  ]]
})
```

Exclude if needed:
```yaml
roles_cfg:
  roles.healthcheck:
    checks:
      exclude:
        - healthcheck.check_space_size
    http:
      - endpoints:
          - path: /healthcheck
```

## Response format (default)

- `200 OK` with body `{"status":"alive"}`
- `500 Internal Server Error` with body `{"status":"dead","details":["<key>: <reason>", ...]}` (details sorted)
- Rate-limited requests return `429` with `{"status":"rate limit exceeded"}`
