local BikeRental = {}
BikeRental.__index = BikeRental
local Config        = require 'shared/config'

function BikeRental.new(index, data)
    local self = setmetatable({}, BikeRental)
    self.index          = index
    self.data           = data
    self.activeVehicle  = nil
    self.expireTimer    = nil
    self.countThread    = nil
    self.rentalDuration = "5"

    self:registerBlip()
    self:createPoint()
    return self
end

function BikeRental:registerBlip()
    local blip = AddBlipForCoord(self.data.coords)
    SetBlipSprite(blip, self.data.blip.sprite)
    SetBlipScale(blip, self.data.blip.scale)
    SetBlipColour(blip, self.data.blip.colour)
    SetBlipAsShortRange(blip, true)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentString(self.data.blip.label)
    EndTextCommandSetBlipName(blip)
end

function BikeRental:createPoint()
    local rental = self
    self.point = lib.points.new({
        coords       = rental.data.coords,
        distance     = self.data.distance or 20.0,
        drawDistance = self.data.drawdistance or 2.5,
        nearby = function(ctx)
            local ped = PlayerPedId()
            local pedVeh = GetVehiclePedIsIn(ped, false)
            local isRentedVeh = pedVeh ~= 0 and VehToNet(pedVeh) == rental.activeVehicle
            local isInVeh = pedVeh ~= 0
        
            rental:drawMarker()
        
            if ctx.currentDistance > ctx.drawDistance or (isInVeh and not isRentedVeh) then
                lib.hideTextUI()
                return
            end
        
            local prompt = isRentedVeh and '[E] - Return your own bike' or '[E] - Rent a bike'
            lib.showTextUI(prompt)
        
            if IsControlJustReleased(0, 38) then
                if isRentedVeh then
                    rental:attemptReturn()
                else
                    rental:attemptRent()
                end
            end
        end,
    })
end

function BikeRental:drawMarker()
    DrawMarker(2, self.data.coords.x, self.data.coords.y, self.data.coords.z,
        0, 0, 0,
        0, 0, 0,
        0.4, 0.4, 0.4,
        10, 78, 161, 150,
        false, true, 2,
        false, false, false, false)
end

function BikeRental:isInVehicle()
    local veh = GetVehiclePedIsIn(PlayerPedId(), false)
    return veh ~= 0 and VehToNet(veh) == self.activeVehicle
end

function BikeRental:attemptRent()
    local result = lib.inputDialog('Rent a bike', {
        { type = 'number', label = 'Duration', default = tostring(self.rentalDuration),
        max = 60, min = 1, required = true }
    })
    if not result or not result[1] then return end

    local minutes = tonumber(result[1])
    if not minutes or minutes <= 0 then
        lib.notify({ type = 'error', description = 'invalid duration.' })
        return
    end
    self.rentalDuration = minutes

    local totalCost = self.data.cost * minutes
    local confirm = lib.inputDialog('Confirm rent', {
        { type = 'checkbox', label = ('Rent bike for %s minutes at $%s'):format(minutes, ESX.Math.GroupDigits(totalCost))}
    })
    if not confirm then
        lib.notify({ type = 'info', description = 'Rental cancelled.' })
        return
    end

    local allowed, reason = lib.callback.await('sliss_bikerental:server:attemptHire', 5000, self.index, minutes)
    if allowed then
        self:spawnBike()
    elseif reason then
        lib.notify({ type = 'error', description = reason })
    else
        lib.notify({ type = 'error', description = 'You cannot rent a bike at this time.' })
    end
end

function BikeRental:spawnBike()
    for _, sp in ipairs(self.data.spawnPoints) do
        if ESX.Game.IsSpawnPointClear(sp.coords, 5) then
            ESX.Game.SpawnVehicle(self.data.model, sp.coords, sp.heading, function(veh)
                self.activeVehicle = VehToNet(veh)
                LocalPlayer.state:set('rentalVehicle', self.activeVehicle, true)
                self:enterVehicle(veh)
                self:startExpireTimer()
            end)
            return
        end
    end
    lib.notify({ type = 'info' , description = 'The spawn location was not clear.' })
end

function BikeRental:enterVehicle(veh)
    for i=1,10 do if i~=3 then SetVehicleExtra(veh,i,false) end end
    TaskWarpPedIntoVehicle(PlayerPedId(), veh, -1)
    -- car keys export
end

function BikeRental:startExpireTimer()
    if self.expireTimer then
        return
    end

    local minutes    = self.rentalDuration or 15
    local durationMs = minutes * 60000
    if durationMs <= 0 then
        return
    end

    self.expireTimer = SetTimeout(durationMs, function()
        if self.activeVehicle then
            lib.callback.await('sliss_bikerental:server:deleteVehicle', false, self.activeVehicle)
        end
        self:clearRentalState()

        lib.notify({ type = 'error', description = 'Your rental time has expired.' })
    end)

    if self.countThread then
        TerminateThread(self.countThread)
    end
    self.countThread = CreateThread(function()
        local endTime = GetGameTimer() + durationMs
        lib.showTextUI(self:formatTime(durationMs), { icon = 'clock', position = 'top-center'})
        while self.activeVehicle and DoesEntityExist(NetToVeh(self.activeVehicle)) do
            Wait(1)
            local remaining = math.max(0, endTime - GetGameTimer())
            local text = self:formatTime(remaining)
            lib.showTextUI(text, { icon = 'clock', position = 'top-center' })
        end
    end)
end

function BikeRental:formatTime(ms)
    local totalSec = math.floor(ms / 1000)
    local m = math.floor(totalSec / 60)
    local s = totalSec % 60
    return string.format('%02d:%02d remaining', m, s)
end

function BikeRental:attemptReturn()
    local ok, reason = lib.callback.await('sliss_bikerental:server:attemptReturn', false, self.activeVehicle)
    if ok and self.activeVehicle then
        lib.callback.await('sliss_bikerental:server:deleteVehicle', false, self.activeVehicle)
        self:clearRentalState()
        lib.notify({ type = "success", description = 'Bike returned successfully.' })
    elseif reason then
        lib.notify({ type = 'error', description = reason })
    end
end

function BikeRental:clearRentalState()
    if self.expireTimer then ClearTimeout(self.expireTimer) end
    if self.countThread then TerminateThread(self.countThread) end
    lib.hideTextUI()
    self.expireTimer   = nil
    self.countThread   = nil
    LocalPlayer.state:set('rentalVehicle', nil, true)
    self.activeVehicle = nil
end

return BikeRental
