fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'as-garages'
author 'AS'
version '0.3.0'
description 'Modern garages and impound for QBCore, Qbox and ESX'

shared_scripts {
    '@ox_lib/init.lua',
    'config.lua',
    'locales/*.lua',
    'shared.lua',
}

client_scripts {
    'client/bridge.lua',
    'client/preview.lua',
    'client/main.lua',
    'client/nui.lua',
    'client/interior.lua',
    'client/admin.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/bridge.lua',
    'server/main.lua',
    'server/impound.lua',
    'server/vehicles.lua',
    'server/private.lua',
    'server/interior.lua',
    'server/api.lua',
    'server/admin.lua',
}

ui_page 'web/index.html'

files {
    'web/index.html',
    'web/style.css',
    'web/app.js',
    'web/admin.js',
}

dependencies {
    'ox_lib',
    'oxmysql',
}
