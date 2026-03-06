-- ─────────────────────────────────────────────
-- vip_parking — server/main.lua v3
-- Multi-slot support, owner-level access grants.
-- All vehicle spawning is server-authoritative.
-- ─────────────────────────────────────────────

local QBCore = exports['qb-core']:GetCoreObject()

-- ── State ─────────────────────────────────────
-- Slots: slot_id → { slotData..., entity = netId|nil }
-- OwnerIndex: citizenid → { slot_id = true, ... }
-- AccessCache: owner_citizenid → { allowed_citizenid = true, ... }
-- ParkingState: citizenid → plate (mid-park disconnect guard)

local Slots        = {}
local OwnerIndex   = {}
local AccessCache  = {}
local ParkingState = {}

-- ── Helpers ───────────────────────────────────

function DebugPrint(msg)
    if Config.Debug then
        print('^3[vip_parking]^7 ' .. tostring(msg))
    end
end

local function Notify(src, msg, ntype)
    TriggerClientEvent('QBCore:Notify', src, msg, ntype or 'primary')
end

-- ── Owner Index ───────────────────────────────

local function RebuildOwnerIndex()
    OwnerIndex = {}
    for slotId, slot in pairs(Slots) do
        local cid = slot.owner_citizenid
        if not OwnerIndex[cid] then OwnerIndex[cid] = {} end
        OwnerIndex[cid][slotId] = true
    end
end

local function GetSlotsByOwner(citizenid)
    local result = {}
    if not OwnerIndex[citizenid] then return result end
    for slotId in pairs(OwnerIndex[citizenid]) do
        if Slots[slotId] then result[#result + 1] = Slots[slotId] end
    end
    return result
end

local function SlotCountForOwner(citizenid)
    if not OwnerIndex[citizenid] then return 0 end
    local n = 0
    for _ in pairs(OwnerIndex[citizenid]) do n = n + 1 end
    return n
end

-- ── Access Cache ──────────────────────────────

local function RebuildAccessCache()
    AccessCache = {}
    local rows = MySQL.query.await('SELECT owner_citizenid, allowed_citizenid FROM vip_vehicle_access')
    for _, row in ipairs(rows) do
        local o = row.owner_citizenid
        if not AccessCache[o] then AccessCache[o] = {} end
        AccessCache[o][row.allowed_citizenid] = true
    end
    DebugPrint('Access cache rebuilt (' .. #rows .. ' grants)')
end

local function HasAccessToOwner(ownerCitizenid, allowedCitizenid)
    if ownerCitizenid == allowedCitizenid then return true end
    return AccessCache[ownerCitizenid] and AccessCache[ownerCitizenid][allowedCitizenid] == true
end

local function GrantCountForOwner(citizenid)
    if not AccessCache[citizenid] then return 0 end
    local n = 0
    for _ in pairs(AccessCache[citizenid]) do n = n + 1 end
    return n
end

-- ── DB Helpers ────────────────────────────────

local function SendToImpound(plate)
    MySQL.update.await("UPDATE player_vehicles SET state = 2 WHERE plate = ?", { plate })
end

local function ApplyServerProps(vehicle, props)
    if not props then return end
    if props.color1     then SetVehicleColours(vehicle, props.color1, props.color2 or props.color1) end
    if props.fuelLevel  then SetVehicleFuelLevel(vehicle, props.fuelLevel) end
    if props.engineHealth then SetVehicleEngineHealth(vehicle, props.engineHealth) end
    if props.bodyHealth   then SetVehicleBodyHealth(vehicle, props.bodyHealth) end
    if props.tankHealth   then SetVehiclePetrolTankHealth(vehicle, props.tankHealth) end
end

local function ClearSlot(slot, removeAccess)
    local plate = slot.vehicle_plate
    slot.vehicle_plate = nil
    slot.vehicle_model = nil
    slot.vehicle_props = nil

    MySQL.update.await(
        'UPDATE vip_parking_slots SET vehicle_plate=NULL, vehicle_model=NULL, vehicle_props=NULL WHERE slot_id=?',
        { slot.slot_id }
    )

    if removeAccess then
        MySQL.query.await(
            'DELETE FROM vip_vehicle_access WHERE owner_citizenid=?',
            { slot.owner_citizenid }
        )
        AccessCache[slot.owner_citizenid] = nil
    end

    TriggerClientEvent('vip_parking:client:slotCleared', -1, slot.slot_id)
    return plate
end

-- ── Load Slots ────────────────────────────────

local function LoadSlots()
    local rows = MySQL.query.await('SELECT * FROM vip_parking_slots')
    for _, row in ipairs(rows) do
        local coords = json.decode(row.coords)
        Slots[row.slot_id] = {
            slot_id          = row.slot_id,
            owner_citizenid  = row.owner_citizenid,
            coords           = coords,
            vehicle_plate    = row.vehicle_plate,
            vehicle_model    = row.vehicle_model,
            vehicle_props    = row.vehicle_props and json.decode(row.vehicle_props) or nil,
            entity           = nil,
        }
    end
    RebuildOwnerIndex()
    RebuildAccessCache()
    print(string.format('^2[vip_parking]^7 Loaded %d slot(s).', #rows))
end

-- ── Spawn / Despawn ───────────────────────────

local function SpawnSlotVehicle(slot)
    if slot.entity then return end
    if not slot.vehicle_model then return end

    local c = slot.coords
    local vehicle = CreateVehicle(joaat(slot.vehicle_model), c.x, c.y, c.z, c.w, true, false)
    local attempts = 0
    while not DoesEntityExist(vehicle) and attempts < 30 do
        Wait(100); attempts = attempts + 1
    end

    if not DoesEntityExist(vehicle) then
        print('^1[vip_parking]^7 Failed to spawn vehicle for slot ' .. slot.slot_id)
        return
    end

    SetEntityAsMissionEntity(vehicle, true, true)
    SetVehicleNumberPlateText(vehicle, slot.vehicle_plate)
    ApplyServerProps(vehicle, slot.vehicle_props)
    SetVehicleDoorsLocked(vehicle, 2)

    slot.entity = NetworkGetNetworkIdFromEntity(vehicle)

    local propsJson = slot.vehicle_props and json.encode(slot.vehicle_props) or nil
    TriggerClientEvent('vip_parking:client:vehicleSpawned', -1,
        slot.slot_id, slot.entity, slot.vehicle_plate, propsJson)

    DebugPrint('Spawned slot=' .. slot.slot_id .. ' netId=' .. slot.entity)
end

local function DespawnSlotVehicle(slot)
    if not slot.entity then return end
    local entity = NetworkGetEntityFromNetworkId(slot.entity)
    if DoesEntityExist(entity) then DeleteEntity(entity) end
    TriggerClientEvent('vip_parking:client:vehicleDespawned', -1, slot.slot_id)
    slot.entity = nil
    DebugPrint('Despawned slot=' .. slot.slot_id)
end

-- ── Streaming Thread ──────────────────────────
-- Spawn and despawn run on separate intervals so they can be tuned independently

CreateThread(function()
    Wait(3000)

    local spawnTimer   = 0
    local despawnTimer = 0

    while true do
        Wait(1000)
        spawnTimer   = spawnTimer   + 1000
        despawnTimer = despawnTimer + 1000

        local doSpawn   = spawnTimer   >= Config.StreamInterval
        local doDespawn = despawnTimer >= Config.DespawnInterval

        if not doSpawn and not doDespawn then goto continue end

        local players = GetPlayers()

        for _, slot in pairs(Slots) do
            if slot.vehicle_model then
                local sp = vector3(slot.coords.x, slot.coords.y, slot.coords.z)
                local nearby = false

                for _, pid in ipairs(players) do
                    local ped = GetPlayerPed(tonumber(pid))
                    if DoesEntityExist(ped) and #(GetEntityCoords(ped) - sp) <= Config.SpawnRadius then
                        nearby = true
                        break
                    end
                end

                if doSpawn and nearby and not slot.entity then
                    local s = slot
                    CreateThread(function() SpawnSlotVehicle(s) end)
                elseif doDespawn and not nearby and slot.entity then
                    DespawnSlotVehicle(slot)
                end
            end
        end

        if doSpawn   then spawnTimer   = 0 end
        if doDespawn then despawnTimer = 0 end

        ::continue::
    end
end)

-- ── Commands ──────────────────────────────────

QBCore.Commands.Add('createslot', 'Create a VIP parking slot at your position (Admin)', {
    { name = 'citizenid', help = 'Target player citizenid' }
}, true, function(src, args)
    local citizenid = args[1]
    if not citizenid then Notify(src, 'Provide a citizenid.', 'error'); return end

    local exists = MySQL.scalar.await('SELECT COUNT(*) FROM players WHERE citizenid=?', { citizenid })
    if not exists or exists == 0 then
        Notify(src, 'No player found with citizenid: ' .. citizenid, 'error'); return
    end

    local currentCount = SlotCountForOwner(citizenid)
    if currentCount >= Config.MaxSlotsPerOwner then
        Notify(src, string.format('%s already has the maximum of %d slot(s).', citizenid, Config.MaxSlotsPerOwner), 'error')
        return
    end

    local adminPed = GetPlayerPed(src)
    local c        = GetEntityCoords(adminPed)
    local coords   = {
        x = math.floor(c.x * 100) / 100,
        y = math.floor(c.y * 100) / 100,
        z = math.floor(c.z * 100) / 100,
        w = math.floor(GetEntityHeading(adminPed) * 100) / 100,
    }

    local slotId = MySQL.insert.await(
        'INSERT INTO vip_parking_slots (owner_citizenid, coords) VALUES (?,?)',
        { citizenid, json.encode(coords) }
    )

    Slots[slotId] = {
        slot_id         = slotId,
        owner_citizenid = citizenid,
        coords          = coords,
        vehicle_plate   = nil,
        vehicle_model   = nil,
        vehicle_props   = nil,
        entity          = nil,
    }

    if not OwnerIndex[citizenid] then OwnerIndex[citizenid] = {} end
    OwnerIndex[citizenid][slotId] = true

    TriggerClientEvent('vip_parking:client:slotCreated', -1, Slots[slotId])
    Notify(src, string.format('Slot #%d created for %s (%d/%d slots)',
        slotId, citizenid, currentCount + 1, Config.MaxSlotsPerOwner), 'success')
    DebugPrint('Admin ' .. src .. ' created slot ' .. slotId .. ' for ' .. citizenid)
end, Config.AdminGroup)

QBCore.Commands.Add('removeslot', 'Remove a VIP parking slot by ID (Admin)', {
    { name = 'slot_id', help = 'Slot ID to remove' }
}, true, function(src, args)
    local slotId = tonumber(args[1])
    if not slotId then Notify(src, 'Provide a valid slot ID.', 'error'); return end

    local slot = Slots[slotId]
    if not slot then Notify(src, 'Slot #' .. slotId .. ' does not exist.', 'error'); return end

    DespawnSlotVehicle(slot)

    if slot.vehicle_plate then
        SendToImpound(slot.vehicle_plate)
        print(string.format('^3[vip_parking]^7 Slot #%d removed — %s sent to impound', slotId, slot.vehicle_plate))
    end

    MySQL.query.await('DELETE FROM vip_parking_slots WHERE slot_id=?', { slotId })

    local cid = slot.owner_citizenid
    if OwnerIndex[cid] then
        OwnerIndex[cid][slotId] = nil
        if not next(OwnerIndex[cid]) then
            OwnerIndex[cid] = nil
            MySQL.query.await('DELETE FROM vip_vehicle_access WHERE owner_citizenid=?', { cid })
            AccessCache[cid] = nil
            DebugPrint('Owner ' .. cid .. ' has no slots left — access grants wiped')
        end
    end

    Slots[slotId] = nil
    TriggerClientEvent('vip_parking:client:slotRemoved', -1, slotId)
    Notify(src, 'Slot #' .. slotId .. ' removed.', 'success')
    DebugPrint('Admin ' .. src .. ' removed slot ' .. slotId)
end, Config.AdminGroup)

QBCore.Commands.Add('addkeypersistent', 'Grant a player access to all your VIP slots', {
    { name = 'citizenid', help = 'citizenid to grant access to' }
}, false, function(src, args)
    local targetCid = args[1]
    if not targetCid then Notify(src, 'Provide a citizenid.', 'error'); return end

    local player    = QBCore.Functions.GetPlayer(src)
    local citizenid = player.PlayerData.citizenid

    if SlotCountForOwner(citizenid) == 0 then
        Notify(src, 'You do not have any VIP parking slots.', 'error'); return
    end

    if targetCid == citizenid then
        Notify(src, 'You cannot grant access to yourself.', 'error'); return
    end

    local targetExists = MySQL.scalar.await('SELECT COUNT(*) FROM players WHERE citizenid=?', { targetCid })
    if not targetExists or targetExists == 0 then
        Notify(src, 'No player found with that citizenid.', 'error'); return
    end

    if HasAccessToOwner(citizenid, targetCid) then
        Notify(src, targetCid .. ' already has access to your slots.', 'error'); return
    end

    -- Enforce max access grants cap
    local currentGrants = GrantCountForOwner(citizenid)
    if currentGrants >= Config.MaxAccessGrantsPerOwner then
        Notify(src, string.format('You have reached the maximum of %d access grants.', Config.MaxAccessGrantsPerOwner), 'error')
        return
    end

    MySQL.insert.await(
        'INSERT INTO vip_vehicle_access (owner_citizenid, allowed_citizenid) VALUES (?,?)',
        { citizenid, targetCid }
    )

    if not AccessCache[citizenid] then AccessCache[citizenid] = {} end
    AccessCache[citizenid][targetCid] = true

    local slotCount = SlotCountForOwner(citizenid)
    Notify(src, string.format('Access granted to %s across all %d of your slot(s). (%d/%d grants used)',
        targetCid, slotCount, currentGrants + 1, Config.MaxAccessGrantsPerOwner), 'success')
    DebugPrint(citizenid .. ' granted access to ' .. targetCid)
end)

QBCore.Commands.Add('removeaccess', 'Revoke a player\'s access to all your VIP slots', {
    { name = 'citizenid', help = 'citizenid to revoke' }
}, false, function(src, args)
    local targetCid = args[1]
    if not targetCid then Notify(src, 'Provide a citizenid.', 'error'); return end

    local player    = QBCore.Functions.GetPlayer(src)
    local citizenid = player.PlayerData.citizenid

    if SlotCountForOwner(citizenid) == 0 then
        Notify(src, 'You do not have any VIP parking slots.', 'error'); return
    end

    if targetCid == citizenid then
        Notify(src, 'You cannot revoke your own access.', 'error'); return
    end

    if not HasAccessToOwner(citizenid, targetCid) then
        Notify(src, targetCid .. ' does not have access to your slots.', 'error'); return
    end

    MySQL.query.await(
        'DELETE FROM vip_vehicle_access WHERE owner_citizenid=? AND allowed_citizenid=?',
        { citizenid, targetCid }
    )

    if AccessCache[citizenid] then AccessCache[citizenid][targetCid] = nil end

    Notify(src, 'Access revoked for ' .. targetCid .. ' across all your slots.', 'success')
    DebugPrint(citizenid .. ' revoked access for ' .. targetCid)
end)

-- ── Callbacks ─────────────────────────────────

QBCore.Functions.CreateCallback('vip_parking:server:getSlots', function(src, cb)
    local result = {}
    for _, slot in pairs(Slots) do
        result[#result + 1] = {
            slot_id         = slot.slot_id,
            owner_citizenid = slot.owner_citizenid,
            coords          = slot.coords,
            vehicle_plate   = slot.vehicle_plate,
            entity          = slot.entity,
        }
    end
    cb(result)
end)

QBCore.Functions.CreateCallback('vip_parking:server:hasAccess', function(src, cb, slotId)
    local player    = QBCore.Functions.GetPlayer(src)
    local citizenid = player.PlayerData.citizenid
    local slot      = Slots[slotId]
    if not slot then cb(false); return end
    cb(HasAccessToOwner(slot.owner_citizenid, citizenid))
end)

-- ── Net Events ────────────────────────────────

RegisterNetEvent('vip_parking:server:beginPark', function(plate)
    local src    = source
    local player = QBCore.Functions.GetPlayer(src)
    if not player then return end
    ParkingState[player.PlayerData.citizenid] = plate
end)

RegisterNetEvent('vip_parking:server:parkVehicle', function(slotId, plate, model, propsJson)
    local src    = source
    local player = QBCore.Functions.GetPlayer(src)
    if not player then return end

    local citizenid = player.PlayerData.citizenid
    local slot      = Slots[slotId]
    if not slot then return end

    -- Validate model against QBCore shared vehicles
    if not model or not QBCore.Shared.Vehicles[model] then
        Notify(src, 'Invalid vehicle model.', 'error')
        ParkingState[citizenid] = nil
        return
    end

    if propsJson ~= nil and type(propsJson) ~= 'string' then
        Notify(src, 'Invalid vehicle data.', 'error')
        ParkingState[citizenid] = nil
        return
    end

    local propsOk, propsDecoded = pcall(json.decode, propsJson or '{}')
    if not propsOk or type(propsDecoded) ~= 'table' then
        Notify(src, 'Invalid vehicle props.', 'error')
        ParkingState[citizenid] = nil
        return
    end

    local vehicleOwner = MySQL.scalar.await(
        'SELECT citizenid FROM player_vehicles WHERE plate=? LIMIT 1', { plate }
    )
    if vehicleOwner ~= citizenid then
        Notify(src, 'You do not own this vehicle.', 'error')
        DebugPrint('Ownership mismatch: ' .. citizenid .. ' tried to park ' .. plate)
        ParkingState[citizenid] = nil
        return
    end

    if not HasAccessToOwner(slot.owner_citizenid, citizenid) then
        Notify(src, 'You do not have access to this VIP slot.', 'error')
        ParkingState[citizenid] = nil
        return
    end

    if slot.vehicle_plate and slot.vehicle_plate ~= plate then
        SendToImpound(slot.vehicle_plate)
        DespawnSlotVehicle(slot)
    end

    MySQL.update.await("UPDATE player_vehicles SET state=0 WHERE plate=?", { plate })

    slot.vehicle_plate = plate
    slot.vehicle_model = model
    slot.vehicle_props = propsDecoded

    MySQL.update.await(
        'UPDATE vip_parking_slots SET vehicle_plate=?, vehicle_model=?, vehicle_props=? WHERE slot_id=?',
        { plate, model, propsJson, slotId }
    )

    ParkingState[citizenid] = nil
    SpawnSlotVehicle(slot)
    TriggerClientEvent('vip_parking:client:slotOccupied', -1, slotId, plate)
    Notify(src, 'Vehicle parked in slot #' .. slotId .. '.', 'success')
    DebugPrint(citizenid .. ' parked ' .. plate .. ' in slot ' .. slotId)
end)

RegisterNetEvent('vip_parking:server:retrieveVehicle', function(slotId)
    local src    = source
    local player = QBCore.Functions.GetPlayer(src)
    if not player then return end

    local citizenid = player.PlayerData.citizenid
    local slot      = Slots[slotId]
    if not slot then return end

    if not HasAccessToOwner(slot.owner_citizenid, citizenid) then
        Notify(src, 'You do not have access to this vehicle.', 'error'); return
    end

    if not slot.vehicle_plate then
        Notify(src, 'No vehicle is parked here.', 'error'); return
    end

    local plate  = slot.vehicle_plate
    local model  = slot.vehicle_model
    local props  = slot.vehicle_props
    local coords = slot.coords

    DespawnSlotVehicle(slot)

    local vehicle  = CreateVehicle(joaat(model), coords.x, coords.y, coords.z, coords.w, true, false)
    local attempts = 0
    while not DoesEntityExist(vehicle) and attempts < 30 do
        Wait(100); attempts = attempts + 1
    end

    if not DoesEntityExist(vehicle) then
        print('^1[vip_parking]^7 Retrieve spawn failed slot=' .. slotId .. ' — impounding ' .. plate)
        SendToImpound(plate)
        Notify(src, 'Vehicle could not be spawned — sent to impound.', 'error')
        ClearSlot(slot, false)
        return
    end

    SetEntityAsMissionEntity(vehicle, true, true)
    SetVehicleNumberPlateText(vehicle, plate)
    ApplyServerProps(vehicle, props)
    SetVehicleDoorsLocked(vehicle, 1)

    local netId    = NetworkGetNetworkIdFromEntity(vehicle)
    local propsJson = props and json.encode(props) or nil

    TriggerClientEvent('vip_parking:client:warpIntoVehicle', src, netId, propsJson)

    MySQL.update.await("UPDATE player_vehicles SET state=0 WHERE plate=?", { plate })
    ClearSlot(slot, false)

    Notify(src, 'Vehicle ready. Drive safe!', 'success')
    DebugPrint(citizenid .. ' retrieved ' .. plate .. ' from slot ' .. slotId)
end)

-- ── Disconnect Guard ──────────────────────────

AddEventHandler('playerDropped', function()
    local src    = source
    local player = QBCore.Functions.GetPlayer(src)
    if not player then return end

    local citizenid = player.PlayerData.citizenid
    local plate     = ParkingState[citizenid]
    if plate then
        print(string.format('^3[vip_parking]^7 %s dropped mid-park (plate=%s) — impounding', citizenid, plate))
        SendToImpound(plate)
        ParkingState[citizenid] = nil
    end
end)

-- ── Startup Reconciliation ────────────────────

local function ReconcileSlots()
    local fixed = 0
    for slotId, slot in pairs(Slots) do
        if slot.vehicle_plate then
            local state = MySQL.scalar.await(
                'SELECT state FROM player_vehicles WHERE plate=?', { slot.vehicle_plate }
            )
            if state == nil then
                print(string.format('^3[vip_parking]^7 Slot #%d: %s missing from player_vehicles — clearing', slotId, slot.vehicle_plate))
                ClearSlot(slot, false); fixed = fixed + 1
            elseif state == 1 then
                print(string.format('^3[vip_parking]^7 Slot #%d: %s garaged (crash) — restoring state=0', slotId, slot.vehicle_plate))
                MySQL.update.await("UPDATE player_vehicles SET state=0 WHERE plate=?", { slot.vehicle_plate })
                fixed = fixed + 1
            elseif state == 2 then
                print(string.format('^3[vip_parking]^7 Slot #%d: %s in impound — clearing slot', slotId, slot.vehicle_plate))
                ClearSlot(slot, false); fixed = fixed + 1
            end
        end
    end
    print(fixed > 0
        and string.format('^2[vip_parking]^7 Reconciliation done — fixed %d slot(s)', fixed)
        or  '^2[vip_parking]^7 Reconciliation done — all slots consistent')
end

-- ── Bootstrap ─────────────────────────────────

AddEventHandler('onResourceStart', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    Wait(1000)
    LoadSlots()
    ReconcileSlots()
end)
