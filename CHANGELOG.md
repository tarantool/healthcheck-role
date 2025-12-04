# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](http://keepachangelog.com/en/1.0.0/)
and this project adheres to [Semantic Versioning](http://semver.org/spec/v2.0.0.html).

## Unreleased

## 0.1.0

### Added

- Healthcheck module with default checks for `box.info.status`, snapshot and WAL directories.
- Additional replication checks (`replication.upstream_absent.*` and `replication.state_bad.*`).
- HTTP role integration with configurable endpoints, rate limiting and alerts.
- Support for user-defined checks via `healthcheck.check_*` functions.
- Test suite and CI workflows for linting and tests.
- README with `tt`-based quick start and configuration examples.
- Rockspec build configuration that packages all Lua modules.
