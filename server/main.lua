local ESX    = exports['es_extended']:getSharedObject()
local rented = {}
local Config = require 'shared/config'

local function log(title, msg)
    lib.print.info(title, msg)
end

local function waitForEntityFromNetId(netId, maxTries, delay)
    maxTries = maxTries or 50
    delay = delay or 100

    for i = 1, maxTries do
            local ent = NetworkGetEntityFromNetworkId(netId)
            if ent and ent ~= 0 and DoesEntityExist(ent) then
                return ent
            end
        Wait(delay)
    end
    return nil
end

local function deleteNetEntitySafely(netId, attempts, interval)
    attempts = attempts or 10
    interval = interval or 250
    if not netId then return true end

    for i = 1, attempts do
        local ent = NetworkGetEntityFromNetworkId(netId)
        if ent and DoesEntityExist(ent) then
            DeleteEntity(ent)
            
            Wait(0)
            if not DoesEntityExist(ent) then return true end
        else
            return true
        end
        Wait(interval)
    end
    return false
end

lib.callback.register('sliss_bikerental:server:attemptHire', function(source, locIndex, minutes)
    local xPlayer = ESX.GetPlayerFromId(source)
    local loc = Config.Locations[tonumber(locIndex) or locIndex]
    if not xPlayer or not loc then return false end

    local ped = GetPlayerPed(source)
    if not ped or ped == 0 then return false end

    local playerCoords = GetEntityCoords(ped)
    local distance = #(playerCoords - vector3(loc.coords.x, loc.coords.y, loc.coords.z))
    if distance > (loc.distance or 15.0) then return false end
    if rented[source] then return false, 'You already have a rented vehicle.' end

    minutes = tonumber(minutes) or 0
    if minutes <= 0 or minutes > 60 then return false, 'Invalid duration.' end

    local totalCost = loc.cost * minutes
    if (xPlayer.getMoney() or 0) < totalCost then
        return false, ('Not enough money for %d. ($%s)'):format(minutes, ESX.Math.GroupDigits(totalCost))
    end

    xPlayer.removeMoney(totalCost)

    rented[source] = {
        loc      = tonumber(locIndex) or locIndex,
        expires  = os.time() + (minutes * 60),
        costPaid = totalCost,
        netId    = 0,
    }
    log('Player rent a vehicle', ('Player: %s | ID: %s | Duration: %d min | Price: $%s'):format(
        GetPlayerName(source), source, minutes, ESX.Math.GroupDigits(totalCost)
    ))
    return true
end)

lib.callback.register('sliss_bikerental:server:attemptReturn', function(source, netId)
    local data = rented[source]
    if not data then return false end
    if data.expires < os.time() then return false end

    local loc = Config.Locations[data.loc]
    if not loc then return false end

    if not netId then return false end
    local veh = NetworkGetEntityFromNetworkId(netId)
    if not veh or not DoesEntityExist(veh) then return false end
    if data.netId and data.netId ~= netId then
        return false, 'This vehicle is not rented by you'
    end
    local est = Entity(veh).state
    if est and est.rentalOwner and est.rentalOwner ~= source then
        return false, 'This vehicle is not rented by you'
    end

    local refund = math.floor((data.costPaid or 0) * (Config.RefundPercentage or 0.5))
    local xPlayer = ESX.GetPlayerFromId(source)
    if xPlayer and refund > 0 then xPlayer.addMoney(refund) end

    log('Player return a vehicle', ('Player: %s | ID: %s | Refund: $%s'):format(
        GetPlayerName(source), source, ESX.Math.GroupDigits(refund)
    ))
    return true
end)

lib.callback.register('sliss_bikerental:server:deleteVehicle', function(source, netId)
    local data = rented[source]
    if not data then return false end

    netId = tonumber(netId) or 0
    if netId == 0 then return false end

    if data.netId and data.netId ~= 0 and data.netId ~= netId then
        return false
    end

    local ok = deleteNetEntitySafely(netId, 20, 150)

    rented[source] = nil

    return ok
end)

AddStateBagChangeHandler('rentalVehicle', '', function(bagName, key, value, _reserved, _replicated)
    local src = tonumber(bagName:match('player:(%d+)'))
    if not src then return end

    local data = rented[src]
    if not data then return end
    if value == nil then
        data.netId = nil
        return
    end

    local netId = tonumber(value)
    if not netId then return end

    CreateThread(function()
        local ent = waitForEntityFromNetId(netId, 50, 100)
        if not ent then return end
    
        data.netId = netId
        Entity(ent).state:set('rentalOwner', src, true)
    end)
end)

AddEventHandler('playerDropped', function(reason)
    local src  = source
    if not src or src == 0 then return end
    local data = rented[src]

    if not data then return end

    if not data.netId then return end

    CreateThread(function()
        local ok = deleteNetEntitySafely(data.netId, 20, 150)
        if ok then
            log('Player dropped', ('Player: %s | ID: %s | Reason: %s'):format(
                GetPlayerName(src), src, reason or 'No reason provided'
            ))
            rented[src] = nil
        end
    end)
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    local snapshot = {}
    if not next(rented) then
        return
    end

    for src, data in pairs(rented) do
        snapshot[#snapshot+1] = { src = src, netId = data and data.netId or nil }
    end

    for _, row in ipairs(snapshot) do
        if row.netId then
            deleteNetEntitySafely(row.netId, 15, 100)
        end
        rented[row.src] = nil
    end
end)