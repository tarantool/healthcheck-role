color = true
std = "luajit"
read_globals = {
    'require', 'debug', 'pcall', 'xpcall', 'tostring',
    'tonumber', 'type', 'assert', 'ipairs', 'math', 'error', 'string',
    'table', 'pairs', 'os', 'io', 'select', 'unpack', 'dofile', 'next',
    'loadstring', 'setfenv', 'utf8', 'tonumber64', 'print', 'load',
    'rawget', 'rawset', 'getmetatable', 'setmetatable', '_G'
}
globals = {'_G', 'package', 'box'}
include_files = {
    '**/*.lua',
    'test/**/*.lua',
    '*.luacheckrc',
    '*.rockspec'
}
exclude_files = {
    '.git/',
    '.rocks/',
    'doc/',
    'tmp/',
}

max_line_length = 160
