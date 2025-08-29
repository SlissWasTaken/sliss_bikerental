ESX = exports['es_extended']:getSharedObject()

local BikeRental = require 'shared/classes/BikeRental'
local Config = require 'shared/config'
local rentals = {}
for i, loc in ipairs(Config.Locations) do
    rentals[i] = BikeRental.new(i, loc)
    lib.print.info(('BikeRental: Location %d initialized.'):format(i))
end