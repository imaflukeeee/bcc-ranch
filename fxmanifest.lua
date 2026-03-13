game 'rdr3'
fx_version "adamant"
rdr3_warning 'I acknowledge that this is a prerelease build of RedM, and I am aware my resources *will* become incompatible once RedM ships.'

lua54 'yes'
author 'BCC Team @Jake2k4 / Modified'

ui_page 'ui/index.html'

shared_scripts {
    '/configs/*.lua',
    'locale.lua',
    'languages/*.lua'
}

files {
    'ui/index.html',
    'ui/style.css',
    'ui/script.js',
    'ui/sounds/*.mp3'
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    '/server/helpers/dbUpdater.lua',
    '/server/helpers/functions.lua',
    '/server/main.lua'
}

client_scripts {
    '@PolyZone/client.lua',
    '@PolyZone/BoxZone.lua',
    '@PolyZone/EntityZone.lua',
    '@PolyZone/CircleZone.lua',
    '@PolyZone/ComboZone.lua',
    '/client/helpers/functions.lua',
    '/client/main.lua',
    '/client/services/animalshelper/wandering.lua',
    '/client/services/animalshelper/herdanimals.lua'
}

dependency {
    'vorp_core',
    'vorp_character',
    'vorp_inventory',
    'bcc-utils'
}

version '2.7.2'