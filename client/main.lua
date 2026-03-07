-- ─────────────────────────────────────────────
-- qb-reservedgarage — client/main.lua v5
-- Multi-slot. Access is owner-level.
-- No vehicle spawning happens client-side.
-- E key interaction. Floating 3D slot markers.
-- ─────────────────────────────────────────────

local QBCore = exports['qb-core']:GetCoreObject()

if not Config then Config = {} end
Config.Debug              = Config.Debug              ~= nil and Config.Debug              or false
Config.MarkerDrawDistance = Config.MarkerDrawDistance ~= nil and Config.MarkerDrawDistance or 10.0
Config.InteractDistance   = Config.InteractDistance   ~= nil and Config.InteractDistance   or 3

-- ── State ─────────────────────────────────────

-- SlotCache: slotId → { owner_citizenid, owner_name, coords, vehicle_plate, hasAccess, accessPending, slotIndex }
local SlotCache        = {}
local SlotIndexMap     = {}
local SlotIndexCounter = 0

-- ── Helpers ───────────────────────────────────

local function Notify(msg, ntype)
    QBCore.Functions.Notify(msg, ntype or 'primary')
end

local function DebugPrint(msg)
    if Config.Debug then print('^3[qb-reservedgarage:client]^7 ' .. tostring(msg)) end
end

-- ── Access Resolution ─────────────────────────

local function ResolveAccess(slotId, cb)
    local cached = SlotCache[slotId]
    if not cached then return end
    if cached.accessPending then return end

    cached.accessPending = true
    QBCore.Functions.TriggerCallback('qb-reservedgarage:server:hasAccess', function(result)
        if SlotCache[slotId] then
            SlotCache[slotId].hasAccess     = result
            SlotCache[slotId].accessPending = false
        end
        if cb then cb(result) end
    end, slotId)
end

-- ── Slot Registration ─────────────────────────

local function RegisterSlot(slot)
    local slotId    = slot.slot_id
    local citizenid = QBCore.Functions.GetPlayerData().citizenid

    if not SlotIndexMap[slotId] then
        SlotIndexCounter     = SlotIndexCounter + 1
        SlotIndexMap[slotId] = SlotIndexCounter
    end

    if not SlotCache[slotId] then
        SlotCache[slotId] = {
            owner_citizenid = slot.owner_citizenid,
            owner_name      = slot.owner_name or slot.owner_citizenid,
            coords          = slot.coords,
            vehicle_plate   = slot.vehicle_plate,
            hasAccess       = false,
            accessPending   = false,
            slotIndex       = SlotIndexMap[slotId],
        }
    else
        SlotCache[slotId].owner_citizenid = slot.owner_citizenid
        SlotCache[slotId].owner_name      = slot.owner_name or slot.owner_citizenid
        SlotCache[slotId].coords          = slot.coords
        SlotCache[slotId].vehicle_plate   = slot.vehicle_plate
        SlotCache[slotId].slotIndex       = SlotIndexMap[slotId]
    end

    if slot.owner_citizenid == nil then
        SlotCache[slotId].hasAccess = false
    elseif slot.owner_citizenid == citizenid then
        SlotCache[slotId].hasAccess = true
    elseif not SlotCache[slotId].hasAccess then
        ResolveAccess(slotId)
    end
end

local function UnregisterSlot(slotId)
    SlotCache[slotId] = nil
end

-- ── 3D Text Drawing ───────────────────────────

local function DrawText3D(x, y, z, text)
    local onScreen, sx, sy = World3dToScreen2d(x, y, z)
    if not onScreen then return end

    local scale = 0.22  -- fixed small size, no distance scaling

    SetTextScale(scale, scale)
    SetTextFont(4)
    SetTextProportional(true)
    SetTextColour(255, 255, 255, 255)
    SetTextOutline()
    SetTextEntry('STRING')
    SetTextCentre(true)
    AddTextComponentString(text)
    DrawText(sx, sy)
end

-- ── Main Draw / Interact Thread ───────────────

CreateThread(function()
    while true do
        local sleep     = 500
        local ped       = PlayerPedId()
        local pedCoords = GetEntityCoords(ped)
        local curVeh    = GetVehiclePedIsIn(ped, false)
        local inVehicle = curVeh ~= 0
        local isDriver  = inVehicle and GetPedInVehicleSeat(curVeh, -1) == ped

        for slotId, slot in pairs(SlotCache) do
            if not slot.hasAccess then goto continue end

            local c    = slot.coords
            local sp   = vector3(c.x, c.y, c.z)
            local dist = #(pedCoords - sp)

            if dist <= Config.MarkerDrawDistance then
                sleep = 0  -- full tick rate when near a slot

                local occupied     = slot.vehicle_plate ~= nil
                local ownerDisplay = slot.owner_name or ('Slot #' .. (slot.slotIndex or slotId))
                local floatZ       = c.z + 0.80

                -- Line 1: Owner name
                DrawText3D(c.x, c.y, floatZ + 0.30,
                    '~c~[ ~w~' .. ownerDisplay .. ' ~c~]')

                -- Line 2: Plate or dashes
                if occupied then
                    DrawText3D(c.x, c.y, floatZ + 0.08, '~y~' .. slot.vehicle_plate)
                else
                    DrawText3D(c.x, c.y, floatZ + 0.08, '~c~—  —  —')
                end

                -- Line 3: Status
                if occupied then
                    DrawText3D(c.x, c.y, floatZ - 0.14, '~o~[PARKED]')
                else
                    DrawText3D(c.x, c.y, floatZ - 0.14, '~g~[AVAILABLE]')
                end

                -- E key prompt + interaction
                if dist <= Config.InteractDistance then
                    if isDriver and not occupied then
                        if IsControlJustReleased(0, 38) then
                            TriggerEvent('qb-reservedgarage:client:tryParkVehicle', { slotId = slotId })
                        end
                    elseif not inVehicle and occupied then
                        if IsControlJustReleased(0, 38) then
                            TriggerEvent('qb-reservedgarage:client:tryRetrieveVehicle', { slotId = slotId })
                        end
                    end
                end
            end

            ::continue::
        end

        Wait(sleep)
    end
end)

-- ── Init ──────────────────────────────────────

local function InitAllSlots(slots)
    SlotCache        = {}
    SlotIndexMap     = {}
    SlotIndexCounter = 0
    for _, slot in ipairs(slots) do
        RegisterSlot(slot)
    end
    DebugPrint('InitAllSlots — received ' .. #slots .. ' slot(s)')
end

AddEventHandler('QBCore:Client:OnPlayerLoaded', function()
    QBCore.Functions.TriggerCallback('qb-reservedgarage:server:getSlots', function(slots)
        InitAllSlots(slots)
    end)
end)

AddEventHandler('onClientResourceStart', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    local pd = QBCore.Functions.GetPlayerData()
    if not pd or not pd.citizenid then return end
    QBCore.Functions.TriggerCallback('qb-reservedgarage:server:getSlots', function(slots)
        InitAllSlots(slots)
    end)
end)

-- ── Park Vehicle ──────────────────────────────

RegisterNetEvent('qb-reservedgarage:client:tryParkVehicle', function(data)
    local slotId = data.slotId
    local ped    = PlayerPedId()
    local veh    = GetVehiclePedIsIn(ped, false)

    if veh == 0 then Notify('You must be in a vehicle to park it.', 'error'); return end
    if GetPedInVehicleSeat(veh, -1) ~= ped then
        Notify('You must be in the driver seat to park.', 'error'); return
    end

    local plate     = string.gsub(GetVehicleNumberPlateText(veh), '%s+', '')
    local modelHash = GetEntityModel(veh)
    local modelName = ''
    for name, _ in pairs(QBCore.Shared.Vehicles) do
        if joaat(name) == modelHash then
            modelName = name
            break
        end
    end

    if modelName == '' then
        Notify('Could not identify this vehicle model.', 'error'); return
    end

    local propsJson  = QBCore.Functions.GetVehicleProperties(veh)
    local vehCoords  = GetEntityCoords(veh)
    local vehHeading = GetEntityHeading(veh)

    TriggerServerEvent('qb-reservedgarage:server:beginPark', plate)

    TaskLeaveVehicle(ped, veh, 16)
    Wait(1500)

    NetworkRequestControlOfEntity(veh)
    local ownerWait = 0
    while not NetworkHasControlOfEntity(veh) and ownerWait < 30 do
        Wait(100); ownerWait = ownerWait + 1
    end
    SetEntityAsMissionEntity(veh, true, true)
    DeleteVehicle(veh)

    local deleteWait = 0
    while DoesEntityExist(veh) and deleteWait < 40 do
        Wait(100); deleteWait = deleteWait + 1
    end

    TriggerServerEvent('qb-reservedgarage:server:parkVehicle', slotId, plate, modelName, json.encode(propsJson), {
        x = vehCoords.x,
        y = vehCoords.y,
        z = vehCoords.z,
        w = vehHeading,
    })
    Notify('Vehicle parked!', 'success')
end)

-- ── Retrieve Vehicle ──────────────────────────

RegisterNetEvent('qb-reservedgarage:client:tryRetrieveVehicle', function(data)
    TriggerServerEvent('qb-reservedgarage:server:retrieveVehicle', data.slotId)
end)

-- ── Warp Into Retrieved Vehicle ───────────────

RegisterNetEvent('qb-reservedgarage:client:warpIntoVehicle', function(netId, propsJson)
    local entity  = 0
    local timeout = 0
    while not DoesEntityExist(entity) and timeout < 50 do
        entity  = NetworkGetEntityFromNetworkId(netId)
        timeout = timeout + 1
        Wait(100)
    end

    if not DoesEntityExist(entity) then
        Notify('Vehicle could not be loaded. Try again.', 'error'); return
    end

    local ped = PlayerPedId()
    TaskWarpPedIntoVehicle(ped, entity, -1)
    SetVehicleEngineOn(entity, true, true, false)

    if propsJson then
        local props = type(propsJson) == 'string' and json.decode(propsJson) or propsJson
        if props then
            local modelHash = GetEntityModel(entity)
            local waited = 0
            while not HasModelLoaded(modelHash) and waited < 50 do
                Wait(100); waited = waited + 1
            end
            Wait(300)
            QBCore.Functions.SetVehicleProperties(entity, props)
            Wait(500)
            QBCore.Functions.SetVehicleProperties(entity, props)
        end
    end

    Notify('Vehicle ready to drive.', 'success')
    DebugPrint('Warped into netId=' .. netId)
end)

-- ── Server → Client Sync ──────────────────────

RegisterNetEvent('qb-reservedgarage:client:slotCreated', function(slot)
    RegisterSlot(slot)
    DebugPrint('New slot registered: #' .. slot.slot_id)
end)

RegisterNetEvent('qb-reservedgarage:client:slotRemoved', function(slotId)
    UnregisterSlot(slotId)
    DebugPrint('Slot removed: #' .. slotId)
end)

RegisterNetEvent('qb-reservedgarage:client:vehicleSpawned', function(slotId, netId, plate, propsJson)
    if SlotCache[slotId] then
        SlotCache[slotId].vehicle_plate = plate
        local citizenid = QBCore.Functions.GetPlayerData().citizenid
        if SlotCache[slotId].owner_citizenid ~= citizenid and not SlotCache[slotId].hasAccess then
            ResolveAccess(slotId)
        end
    end

    Citizen.SetTimeout(800, function()
        local entity = NetworkGetEntityFromNetworkId(netId)
        if DoesEntityExist(entity) then
            if propsJson then
                local props = type(propsJson) == 'string' and json.decode(propsJson) or propsJson
                if props then QBCore.Functions.SetVehicleProperties(entity, props) end
            end
            SetEntityInvincible(entity, true)
            FreezeEntityPosition(entity, true)
            SetVehicleDoorsLocked(entity, 10)
            SetVehicleCanBreak(entity, false)
        end
    end)
end)

RegisterNetEvent('qb-reservedgarage:client:vehicleDespawned', function(slotId)
    DebugPrint('Vehicle despawned for slot ' .. slotId)
end)

RegisterNetEvent('qb-reservedgarage:client:forceDeleteEntity', function(netId)
    local entity = NetworkGetEntityFromNetworkId(netId)
    if DoesEntityExist(entity) then
        SetEntityAsMissionEntity(entity, true, true)
        FreezeEntityPosition(entity, false)
        SetEntityInvincible(entity, false)
        DeleteEntity(entity)
        DebugPrint('Force deleted entity netId=' .. netId)
    end
end)

RegisterNetEvent('qb-reservedgarage:client:slotCleared', function(slotId)
    if SlotCache[slotId] then
        SlotCache[slotId].vehicle_plate = nil
    end
end)

RegisterNetEvent('qb-reservedgarage:client:slotOccupied', function(slotId, plate)
    if SlotCache[slotId] then
        SlotCache[slotId].vehicle_plate = plate
        local citizenid = QBCore.Functions.GetPlayerData().citizenid
        if SlotCache[slotId].owner_citizenid == citizenid then
            SlotCache[slotId].hasAccess = true
        elseif not SlotCache[slotId].hasAccess then
            ResolveAccess(slotId)
        end
    end
end)