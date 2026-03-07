fx_version 'adamant'
game 'gta5'

author      'qb-reservedgarage'
description 'VIP Persistent Parking Slot System — QBCore'
version     '3.0.0'

lua54 'yes'

shared_scripts {
    '@qb-core/shared/locale.lua',
    'config.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/main.lua',
}

client_scripts {
    'client/main.lua',
}

dependencies {
    'qb-core',
    'oxmysql',
}
