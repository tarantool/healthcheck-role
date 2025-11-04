local log = require("log")

---@alias LoggerLevel
---| '"fatal"'
---| '"error"'
---| '"warn"'
---| '"info"'
---| '"verbose"'
---| '"debug"'

--- Healthcheck-specific logger wrapper around Tarantool `log.new`.
---
---@class HealthcheckLogger
---@field level fun(level?: LoggerLevel): LoggerLevel Get or set log level.
---@field log_format fun(fmt?: string): string Get or set log message format.
---@field info fun(message: string, ...: any) Log info message.
---@field warn fun(message: string, ...: any) Log warning message.
---@field error fun(message: string, ...: any) Log error message.
---@field debug fun(message: string, ...: any) Log debug message.
---@field verbose fun(message: string, ...: any) Log verbose message.
---@field rotate fun(self: HealthcheckLogger): boolean Rotate log file if configured.
---@field pid fun(self: HealthcheckLogger): integer Return logger process id.

local module_name = 'healthcheck'

---@type HealthcheckLogger
local logger = log.new(module_name)

return logger
