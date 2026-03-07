-- ─────────────────────────────────────────────
-- qb-reservedgarage — client/main.lua v4
-- Multi-slot. Access is owner-level.
-- No vehicle spawning happens client-side.
-- ─────────────────────────────────────────────

local QBCore = exports['qb-core']:GetCoreObject()

if not Config then
    Config = {}
    Config.Debug                = false
    Config.TargetRadius         = 2.5
    Config.SlotInteractDistance = 5.0
end

-- ── State ─────────────────────────────────────

local ActiveZones   = {}   -- slotId → zone name
local EntityTargets = {}   -- slotId → entity handle

-- SlotCache: slotId → { owner_citizenid, vehicle_plate, hasAccess, accessPending }
local SlotCache = {}

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
    if cached.accessPending then
        DebugPrint('Access resolve already pending for slot ' .. slotId)
        return
    end

    cached.accessPending = true
    QBCore.Functions.TriggerCallback('qb-reservedgarage:server:hasAccess', function(result)
        if SlotCache[slotId] then
            SlotCache[slotId].hasAccess      = result
            SlotCache[slotId].accessPending  = false
        end
        if cb then cb(result) end
    end, slotId)
end

-- ── Zone Setup ────────────────────────────────

local function SetupSlotZone(slot)
    local slotId   = slot.slot_id
    local zoneName = 'vip_slot_' .. slotId

    if not SlotCache[slotId] then
        SlotCache[slotId] = {
            owner_citizenid = slot.owner_citizenid,
            vehicle_plate   = slot.vehicle_plate,
            hasAccess       = false,
            accessPending   = false,
        }
    else
        SlotCache[slotId].owner_citizenid = slot.owner_citizenid
        SlotCache[slotId].vehicle_plate   = slot.vehicle_plate
    end

    local citizenid = QBCore.Functions.GetPlayerData().citizenid

    if slot.owner_citizenid == nil then
        SlotCache[slotId].hasAccess = false
    elseif slot.owner_citizenid == citizenid then
        SlotCache[slotId].hasAccess = true
    elseif not SlotCache[slotId].hasAccess then
        ResolveAccess(slotId)
    end

    if ActiveZones[slotId] then
        exports['qb-target']:RemoveZone(ActiveZones[slotId])
        ActiveZones[slotId] = nil
    end

    local c = slot.coords

    exports['qb-target']:AddCircleZone(
        zoneName,
        vector3(c.x, c.y, c.z),
        Config.TargetRadius,
        { name = zoneName, debugPoly = Config.Debug },
        {
            options = {
                {
                    type  = 'client',
                    event = 'qb-reservedgarage:client:tryParkVehicle',
                    icon  = 'fas fa-parking',
                    label = 'Park Vehicle',
                    slotId = slotId,
                    canInteract = function()
                        local cached = SlotCache[slotId]
                        if not cached or not cached.hasAccess then return false end
                        if cached.vehicle_plate ~= nil then return false end
                        local ped = PlayerPedId()
                        local veh = GetVehiclePedIsIn(ped, false)
                        if veh == 0 then return false end
                        return GetPedInVehicleSeat(veh, -1) == ped
                    end,
                },
                {
                    type  = 'client',
                    event = 'qb-reservedgarage:client:tryRetrieveVehicle',
                    icon  = 'fas fa-car',
                    label = 'Retrieve Vehicle',
                    slotId = slotId,
                    canInteract = function()
                        local cached = SlotCache[slotId]
                        if not cached or not cached.hasAccess then return false end
                        if cached.vehicle_plate == nil then return false end
                        return GetVehiclePedIsIn(PlayerPedId(), false) == 0
                    end,
                },
            },
            distance = Config.SlotInteractDistance,
        }
    )

    ActiveZones[slotId] = zoneName
    DebugPrint('Zone set up: slot ' .. slotId)
end

-- ── Entity Target ─────────────────────────────

local function SetupEntityTarget(slotId, netId)
    if EntityTargets[slotId] then
        exports['qb-target']:RemoveTargetEntity(EntityTargets[slotId])
        EntityTargets[slotId] = nil
    end

    local entity = NetworkGetEntityFromNetworkId(netId)
    if not DoesEntityExist(entity) then
        DebugPrint('Entity target failed — not found for netId ' .. netId)
        return
    end

    exports['qb-target']:AddTargetEntity(entity, {
        options = {
            {
                type  = 'client',
                event = 'qb-reservedgarage:client:tryRetrieveVehicle',
                icon  = 'fas fa-car-side',
                label = 'Retrieve Vehicle',
                slotId = slotId,
                canInteract = function()
                    local cached = SlotCache[slotId]
                    if not cached or not cached.hasAccess then return false end
                    return GetVehiclePedIsIn(PlayerPedId(), false) == 0
                end,
            },
            {
                type  = 'client',
                event = 'qb-reservedgarage:client:tryParkVehicle',
                icon  = 'fas fa-parking',
                label = 'Park Vehicle',
                slotId = slotId,
                canInteract = function()
                    local cached = SlotCache[slotId]
                    if not cached or not cached.hasAccess then return false end
                    if cached.vehicle_plate ~= nil then return false end
                    local ped = PlayerPedId()
                    local veh = GetVehiclePedIsIn(ped, false)
                    if veh == 0 then return false end
                    return GetPedInVehicleSeat(veh, -1) == ped
                end,
            },
        },
        distance = Config.SlotInteractDistance,
    })

    EntityTargets[slotId] = entity
    DebugPrint('Entity target set: slot ' .. slotId)
end

-- ── Init ──────────────────────────────────────

local function PurgeAllZones()
    for _, zoneName in pairs(ActiveZones) do
        exports['qb-target']:RemoveZone(zoneName)
    end
    for _, entity in pairs(EntityTargets) do
        exports['qb-target']:RemoveTargetEntity(entity)
    end
    ActiveZones   = {}
    EntityTargets = {}
    DebugPrint('All zones purged (cache preserved)')
end

local function InitAllSlots(slots)
    PurgeAllZones()
    for _, slot in ipairs(slots) do
        SetupSlotZone(slot)
        if slot.entity then
            local sid, eid = slot.slot_id, slot.entity
            Citizen.SetTimeout(800, function()
                SetupEntityTarget(sid, eid)
            end)
        end
    end
end

AddEventHandler('QBCore:Client:OnPlayerLoaded', function()
    SlotCache = {}
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

    local propsJson = QBCore.Functions.GetVehicleProperties(veh)

    -- Capture exact position and heading BEFORE ejecting/deleting the vehicle
    local vehCoords  = GetEntityCoords(veh)
    local vehHeading = GetEntityHeading(veh)

    -- Tell server we are starting a park (disconnect guard)
    TriggerServerEvent('qb-reservedgarage:server:beginPark', plate)

    -- Eject player from vehicle first
    TaskLeaveVehicle(ped, veh, 16)
    Wait(1500)

    -- Take network control and delete the vehicle
    NetworkRequestControlOfEntity(veh)
    local ownerWait = 0
    while not NetworkHasControlOfEntity(veh) and ownerWait < 30 do
        Wait(100)
        ownerWait = ownerWait + 1
    end
    SetEntityAsMissionEntity(veh, true, true)
    DeleteVehicle(veh)

    -- Wait until confirmed gone
    local deleteWait = 0
    while DoesEntityExist(veh) and deleteWait < 40 do
        Wait(100)
        deleteWait = deleteWait + 1
    end

    -- Send exact parked position/heading to server alongside the normal park data
    TriggerServerEvent('qb-reservedgarage:server:parkVehicle', slotId, plate, modelName, json.encode(propsJson), {
        x = vehCoords.x,
        y = vehCoords.y,
        z = vehCoords.z,
        w = vehHeading,
    })
    Notify('Vehicle parked! Static copy will appear shortly.', 'success')
end)

-- ── Retrieve Vehicle ──────────────────────────

RegisterNetEvent('qb-reservedgarage:client:tryRetrieveVehicle', function(data)
    TriggerServerEvent('qb-reservedgarage:server:retrieveVehicle', data.slotId)
end)

-- ── Warp Into Retrieved Vehicle ───────────────
-- Waits for entity to exist, then waits for model to fully load before applying props
-- This ensures mods, colours, neons and extras are always restored correctly

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

            -- Wait for model to be fully streamed in
            local waited = 0
            while not HasModelLoaded(modelHash) and waited < 50 do
                Wait(100)
                waited = waited + 1
            end

            -- Apply props, wait, then apply again to guarantee mods/colours/neons stick
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
    SetupSlotZone(slot)
    DebugPrint('New slot registered: #' .. slot.slot_id)
end)

RegisterNetEvent('qb-reservedgarage:client:slotRemoved', function(slotId)
    if ActiveZones[slotId] then
        exports['qb-target']:RemoveZone(ActiveZones[slotId])
        ActiveZones[slotId] = nil
    end
    if EntityTargets[slotId] then
        exports['qb-target']:RemoveTargetEntity(EntityTargets[slotId])
        EntityTargets[slotId] = nil
    end
    SlotCache[slotId] = nil
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
            -- Apply props
            if propsJson then
                local props = type(propsJson) == 'string' and json.decode(propsJson) or propsJson
                if props then QBCore.Functions.SetVehicleProperties(entity, props) end
            end
            -- Make static vehicle truly unenterable and frozen client-side
            SetEntityInvincible(entity, true)
            FreezeEntityPosition(entity, true)
            SetVehicleDoorsLocked(entity, 10) -- 10 = cannot be entered by anyone
            SetVehicleCanBreak(entity, false)
        end
        SetupEntityTarget(slotId, netId)
    end)
end)

RegisterNetEvent('qb-reservedgarage:client:vehicleDespawned', function(slotId)
    if EntityTargets[slotId] then
        exports['qb-target']:RemoveTargetEntity(EntityTargets[slotId])
        EntityTargets[slotId] = nil
    end
end)

-- Force delete a frozen/static entity that server delete may not have cleaned up
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
    if EntityTargets[slotId] then
        exports['qb-target']:RemoveTargetEntity(EntityTargets[slotId])
        EntityTargets[slotId] = nil
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
