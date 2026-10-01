fx_version 'cerulean'
game 'gta5'

author 'レトロ'
description 'Contextual parkour and traversal system (standalone, ox_lib)'
lua54 'yes'
version '1.6.0'

dependency 'ox_lib'

shared_scripts {
    '@ox_lib/init.lua',
    'shared/config.lua',
    'shared/presets.lua',
    'shared/animations.lua',
    'shared/constants.lua',
}

client_scripts {
    'client/main.lua',
}

server_scripts {
    'server/main.lua',
}

files {
    'client/core/*.lua',
    'client/detection/*.lua',
    'client/abilities/*.lua',
    'client/systems/*.lua',
    'client/debug/*.lua',
}
