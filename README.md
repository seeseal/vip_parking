# vip_parking

A VIP Persistent Parking Slot system for FiveM servers running **QBCore**.

Admins assign dedicated parking spots to players. Vehicles park persistently in the world, survive server restarts, and stream in/out based on player proximity — no AdvancedParking dependency required.

---

## Features

- **Server-authoritative vehicle spawning** — no client exploits
- **Full vehicle props saved and restored** — mods, colours, livery, neons, extras, tyre smoke. Props are applied after model fully loads to guarantee accuracy.
- **Distance-based entity streaming** — vehicles only exist as entities when players are nearby. Spawn and despawn run on independent intervals.
- **Up to 10 slots per player**, assigned one at a time by admins
- **Owner-level access grants** — up to 4 grants per owner, covering all current and future slots
- **Startup reconciliation** — auto-heals any inconsistent DB state after a crash
- **Disconnect mid-park protection** — car sent to impound if player drops during park flow
- **Retrieve spawns vehicle at slot position** ready to drive — no garage trip needed
- **Fallback to impound on any spawn failure** — car is never lost

---

## Dependencies

| Resource | Notes |
|---|---|
| [qb-core](https://github.com/qbcore-framework/qb-core) | Latest stable |
| [oxmysql](https://github.com/overextended/oxmysql) | Required for all DB calls |
| [qb-target](https://github.com/qb-x64/qb-target) | Original qb-target — not ox_target |

---

## Installation

**1. Database**

Run `sql/vip_parking.sql` on your server database before starting the resource.

> If upgrading from an earlier version, use the **migration block** at the bottom of the SQL file instead of the `CREATE TABLE` statements.

**2. Resource**

Drop the `vip_parking` folder into your server's `resources` directory.

**3. server.cfg**

```
ensure vip_parking
```

Make sure this loads **after** `qb-core`, `oxmysql`, and `qb-target`.

---

## Configuration

All options are in `config.lua`.

```lua
Config.SpawnRadius            = 50.0   -- Distance at which parked vehicle entity spawns
Config.StreamInterval         = 5000   -- How often (ms) the server checks for vehicles to spawn
Config.DespawnInterval        = 5000   -- How often (ms) the server checks for vehicles to despawn
Config.TargetRadius           = 2.5    -- qb-target interaction zone radius
Config.SlotInteractDistance   = 5.0    -- Max distance to see Park / Retrieve prompt
Config.MaxSlotsPerOwner       = 10     -- Maximum slots one player can be assigned
Config.MaxAccessGrantsPerOwner = 4     -- Maximum access grants one owner can hand out
Config.AdminGroup             = 'admin' -- QBCore permission group for admin commands
Config.Debug                  = false  -- Server console debug output
```

---

## Commands

### Admin Commands

> Require the permission group set in `Config.AdminGroup`

| Command | Usage | Description |
|---|---|---|
| `/createslot` | `/createslot [citizenid]` | Creates a VIP parking slot at the admin's current position and heading, assigned to the given player. Respects `Config.MaxSlotsPerOwner`. |
| `/removeslot` | `/removeslot [slot_id]` | Permanently removes the slot. Any vehicle parked there is sent to impound. Access grants are only wiped if the owner has no slots remaining. |

### Player Commands

| Command | Usage | Description |
|---|---|---|
| `/addkeypersistent` | `/addkeypersistent [citizenid]` | Grants another player access to **all** of your VIP slots. Covers any slots you receive in the future too. Max 4 grants per owner. |
| `/removeaccess` | `/removeaccess [citizenid]` | Revokes a player's access across all of your slots. |

### Interactions (qb-target)

| Prompt | Condition | Description |
|---|---|---|
| `[E] Park Vehicle` | In driver seat, slot is empty, you have access | Parks the vehicle. Saves all props. Spawns static locked entity at slot. |
| `[E] Retrieve Vehicle` | On foot, slot is occupied, you have access | Despawns static entity, spawns driveable vehicle at slot, warps you into driver seat. |

Both prompts are visible to the slot owner and anyone granted access via `/addkeypersistent`. No one else sees them.

---

## How It Works

**Parking flow:**
1. Player drives into the slot zone
2. `[E] Park Vehicle` appears via qb-target
3. Player presses E — ejected from vehicle
4. Server verifies vehicle ownership against `player_vehicles`
5. Full vehicle props saved to DB
6. Static locked entity spawned at slot position
7. Vehicle marked as `out` in qb-garages

**Retrieve flow:**
1. Player walks up to slot or parked car
2. `[E] Retrieve Vehicle` appears
3. Player presses E
4. Server despawns static entity
5. Fresh driveable vehicle spawned at slot coords
6. Client waits for model to fully load, then restores all props
7. Player warped into driver seat, engine started

**After server restart:**
- All slots loaded from DB on boot
- Spawn thread checks proximity every `Config.StreamInterval` ms
- Despawn thread checks proximity every `Config.DespawnInterval` ms
- Entity spawned when any player is within `Config.SpawnRadius`
- Entity despawned when no players are within range

**Startup reconciliation** runs on every boot:
- Vehicle missing from DB → slot cleared
- Vehicle stuck as garaged → state reset to out
- Vehicle in impound → slot cleared

---

## Database Schema

### `vip_parking_slots`

| Column | Type | Description |
|---|---|---|
| `slot_id` | INT (PK) | Auto-increment slot identifier |
| `owner_citizenid` | VARCHAR(50) | citizenid of the assigned player |
| `coords` | LONGTEXT | JSON `{ x, y, z, w }` — position and heading |
| `vehicle_plate` | VARCHAR(8) | Plate of currently parked vehicle |
| `vehicle_model` | VARCHAR(50) | Spawn model name |
| `vehicle_props` | LONGTEXT | Full QBCore vehicle props JSON |

### `vip_vehicle_access`

| Column | Type | Description |
|---|---|---|
| `id` | INT (PK) | Auto-increment |
| `owner_citizenid` | VARCHAR(50) | Slot owner who granted access |
| `allowed_citizenid` | VARCHAR(50) | Player who was granted access |

Access is **owner-level** — one grant covers all slots the owner has, including future slots.

---

## Notes for Developers

- `qb-target` version: uses original `AddCircleZone` / `AddTargetEntity` API. If the server runs `ox_target`, the client-side zone calls will need updating.
- `player_vehicles` state values assumed: `0` = out, `1` = garaged, `2` = impound. Verify these match your garage script before deploying.
- All vehicle spawning is server-authoritative. Clients never call `CreateVehicle`.
- `SetVehicleProperties` is applied client-side after warp and after `HasModelLoaded` confirms the model is fully streamed in — this guarantees mods, neons, and extras are always restored correctly.

---

## Author

Made by **seeseal** — https://github.com/seeseal

---

## License

MIT — free to use and modify. Credit appreciated.
