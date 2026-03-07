# qb-reservedgarage

A reserved parking slot system for FiveM servers running **QBCore**.

Admins assign dedicated parking spots to players. Vehicles park persistently — saving their exact position and heading — survive server restarts, and stream in/out based on player proximity. No extra dependencies beyond QBCore and oxmysql.

---

## Features

- **No qb-target required** — native E key interaction with floating 3D markers
- **Floating in-world slot marker** — shows owner name, plate, and status above each slot. Visible only to the owner and granted players
- **Server-authoritative vehicle spawning** — clients never call `CreateVehicle`, preventing exploits
- **Exact position & heading saved on park** — vehicles reappear precisely where they were left
- **Full vehicle props preserved** — mods, colours, livery, neons, extras, tyre smoke, engine/body health
- **Distance-based entity streaming** — static vehicle entities only exist when players are nearby
- **Up to 10 slots per player**, assigned one at a time by admins
- **Owner-level access grants** — up to 20 grants per owner, covering all current and future slots
- **Startup reconciliation** — auto-heals inconsistent DB state after a crash or unclean shutdown
- **Disconnect mid-park protection** — vehicle sent to impound if player drops during park flow
- **Fallback to impound on spawn failure** — vehicle is never lost

---

## Dependencies

| Resource | Notes |
|---|---|
| [qb-core](https://github.com/qbcore-framework/qb-core) | Latest stable |
| [oxmysql](https://github.com/overextended/oxmysql) | Required for all DB calls |

---

## Installation

### 1. Database

Run `sql/qb-reservedgarage.sql` on your server database before starting the resource.

> **Upgrading from an earlier version?** See the [Upgrading](#upgrading) section below.

### 2. Resource

Drop the `qb-reservedgarage` folder into your server's `resources` directory.

### 3. server.cfg

```
ensure qb-reservedgarage
```

Ensure this loads **after** `qb-core` and `oxmysql`.

---

## Configuration

All options live in `config.lua`.

```lua
Config.SpawnRadius             = 50.0    -- Distance (m) at which the parked vehicle entity spawns
Config.StreamInterval          = 5000    -- How often (ms) the server checks for vehicles to spawn
Config.DespawnInterval         = 5000    -- How often (ms) the server checks for vehicles to despawn
Config.MarkerDrawDistance      = 10.0    -- Distance (m) at which the floating 3D marker is visible
Config.InteractDistance        = 1.5     -- Distance (m) at which pressing E triggers park/retrieve
Config.MaxSlotsPerOwner        = 10      -- Maximum slots one player can be assigned
Config.MaxAccessGrantsPerOwner = 20      -- Maximum access grants one owner can hand out
Config.AdminGroup              = 'admin' -- QBCore permission group for admin commands
Config.NotifyStyle             = 'qb'    -- Notification style: 'qb' or 'ox'
Config.Debug                   = false   -- Enable debug output in server console and F8
```

---

## Commands

### Admin Commands

> Require the permission group defined in `Config.AdminGroup`.

| Command | Usage | Description |
|---|---|---|
| `/createslot` | `/createslot [citizenid]` | Creates a reserved slot at the admin's current position and heading, assigned to the given player. |
| `/removeslot` | `/removeslot [slot_id]` | Permanently removes the slot. Any parked vehicle is sent to impound. |

### Player Commands

| Command | Usage | Description |
|---|---|---|
| `/addkeypersistent` | `/addkeypersistent [citizenid]` | Grants another player access to all of your reserved slots, including future ones. |
| `/removeaccess` | `/removeaccess [citizenid]` | Revokes a player's access across all of your slots. |

### In-World Interaction

No menus, no mouse clicking. Walk up to your slot or drive into it — press **E**.

| Action | Condition |
|---|---|
| **Park** | In driver seat · slot is empty · within `InteractDistance` |
| **Retrieve** | On foot · slot is occupied · within `InteractDistance` |

The floating marker above each slot shows the current state at a glance. Only the slot owner and granted players can see it.

---

## How It Works

### Parking Flow

1. Player drives up to their slot
2. Press **E** — player is ejected from the vehicle
3. Server captures exact coords and heading of the vehicle
4. Server verifies ownership against `player_vehicles`
5. Full vehicle props and parked position saved to DB
6. Vehicle deleted; static locked entity spawned at the exact parked position
7. Vehicle marked as `out` in the garage system

### Retrieve Flow

1. Player walks up to the slot
2. Press **E**
3. Server despawns the static entity
4. Driveable vehicle spawned at the exact saved position and heading
5. Client waits for model to fully stream in, then applies all props
6. Player warped into driver seat, engine started

### Floating Marker

A small 3D text notice floats above each slot, visible within `Config.MarkerDrawDistance`:

```
[ John Smith ]
ABC 1234
[PARKED]
```

```
[ John Smith ]
—  —  —
[AVAILABLE]
```

Orange for parked, green for available. Only visible to the owner and anyone with access.

### Streaming

- All slots and parked coords loaded from DB on boot
- Every `Config.StreamInterval` ms: entities spawned when a player is within `Config.SpawnRadius`
- Every `Config.DespawnInterval` ms: entities despawned when no players are in range

### Startup Reconciliation

Runs automatically on every server boot:

| Situation | Action |
|---|---|
| Vehicle missing from `player_vehicles` | Slot cleared |
| Vehicle stuck as garaged (`state = 1`) | State reset to out |
| Vehicle in impound (`state = 2`) | Slot cleared |

---

## Database Schema

### `vip_parking_slots`

| Column | Type | Description |
|---|---|---|
| `slot_id` | INT (PK, AUTO_INCREMENT) | Unique slot identifier |
| `owner_citizenid` | VARCHAR(50) | citizenid of the assigned player |
| `coords` | LONGTEXT | JSON `{x, y, z, w}` — fixed slot position set by admin |
| `vehicle_plate` | VARCHAR(8) | Plate of the currently parked vehicle |
| `vehicle_model` | VARCHAR(50) | Spawn model name |
| `vehicle_props` | LONGTEXT | Full QBCore vehicle props JSON |
| `parked_coords` | LONGTEXT | JSON `{x, y, z, w}` — exact position when vehicle was parked |

### `vip_vehicle_access`

| Column | Type | Description |
|---|---|---|
| `id` | INT (PK, AUTO_INCREMENT) | Auto-increment |
| `owner_citizenid` | VARCHAR(50) | Slot owner who granted access |
| `allowed_citizenid` | VARCHAR(50) | Player who received access |

Access is **owner-level** — one grant covers all of the owner's slots, including future ones.

---

## Upgrading

### Adding `parked_coords` (if not already present)

```sql
ALTER TABLE vip_parking_slots ADD COLUMN parked_coords LONGTEXT NULL;
```

Existing parked vehicles fall back to `slot.coords` until re-parked, at which point the exact position is saved automatically.

---

## Notes for Developers

- All vehicle spawning is server-authoritative — clients never call `CreateVehicle`
- Props are applied client-side after warp, once `HasModelLoaded` confirms the model is fully streamed in
- `parked_coords` is the vehicle's actual position at time of parking. `coords` is the admin-placed marker used for streaming proximity. If `parked_coords` is nil the system falls back to `coords`
- `player_vehicles` state values assumed: `0` = out, `1` = garaged, `2` = impound — verify these match your garage script

---

## Author

Made by **seeseal** — https://github.com/seeseal

---

## License

MIT — free to use and modify. Credit appreciated.
