--- constants for failed healthcheck details

local details = {}

-- defaults
details.BOX_INFO_STATUS_NOT_RUNNING = 'box.info.status is not running'
details.DISK_ERROR_SNAPSHOT_DIR = 'failed to write to snapshot dir'
details.DISK_ERROR_WAL_DIR = 'failed to write to wal dir'
details.DISK_ERROR_VINYL_DIR = 'failed to write to vinyl dir'

return details