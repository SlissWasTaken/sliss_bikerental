fx_version 'cerulean'
game 'gta5'

use_fxv2_oal 'yes'
lua54 'yes'

client_scripts { 'client/**/*.lua', 'shared/**/*.lua' }
server_scripts { 'server/**/*.lua', 'shared/**/*.lua'}
shared_scripts { '@es_extended/imports.lua', '@ox_lib/init.lua' }

dependencies {
    'es_extended',
    'ox_lib',
}