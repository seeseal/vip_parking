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
    local modelName = QBCore.Functions.GetVehicleProperties(veh).model or ''

    -- Validate model name from QBCore vehicle props
    if modelName == '' then
        Notify('Could not identify this vehicle model.', 'error'); return
    end

    local propsJson = QBCore.Functions.GetVehicleProperties(veh)

    TriggerServerEvent('qb-reservedgarage:server:beginPark', plate)
    TaskLeaveVehicle(ped, veh, 16)
    Wait(900)
    TriggerServerEvent('qb-reservedgarage:server:parkVehicle', slotId, plate, modelName, json.encode(propsJson))
end)

-- ── Retrieve Vehicle ──────────────────────────

RegisterNetEvent('qb-reservedgarage:client:tryRetrieveVehicle', function(data)
    TriggerServerEvent('qb-reservedgarage:server:retrieveVehicle', data.slotId)
end)

-- ── Warp Into Retrieved Vehicle ───────────────
-- Waits for entity to exist, then waits for model to fully load before applying props
-- This ensures mods, colours, neons and extras are always restored correctly

RegisterNetEvent('qb-reservedgarage:client:warpIntoVehicle', function(netId, propsJson)
    -- Wait for entity to exist
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

    -- Wait for model to be fully streamed in before applying props
    -- This prevents mods/colours/neons being silently dropped
    if propsJson then
        local props = type(propsJson) == 'string' and json.decode(propsJson) or propsJson

        if props then
            local modelHash   = GetEntityModel(entity)
            local modelLoaded = false
            local waited      = 0

            while not modelLoaded and waited < 50 do
                modelLoaded = HasModelLoaded(modelHash)
                if not modelLoaded then
                    Wait(100)
                    waited = waited + 1
                end
            end

            -- Extra frame to let streaming settle
            Wait(200)

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
        if propsJson then
            local entity = NetworkGetEntityFromNetworkId(netId)
            if DoesEntityExist(entity) then
                local props = type(propsJson) == 'string' and json.decode(propsJson) or propsJson
                if props then QBCore.Functions.SetVehicleProperties(entity, props) end
            end
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
