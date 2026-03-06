fx_version 'adamant'
game 'gta5'

author      'vip_parking'
description 'VIP Persistent Parking Slot System — QBCore'
version     '2.0.0'

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
    'qb-target',
}
