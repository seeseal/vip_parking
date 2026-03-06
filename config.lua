Config = {}

-- Distance (in game units) at which a parked vehicle entity is spawned in the world
Config.SpawnRadius = 50.0

-- How often (ms) the server checks proximity to stream vehicle entities in
-- Keep this at 5000 or above to avoid unnecessary load
Config.StreamInterval = 5000

-- How often (ms) the server polls for players near spawned slots to despawn them
-- Keep this at 5000 or above to avoid unnecessary load
Config.DespawnInterval = 5000

-- The radius (in game units) around the slot coords that qb-target uses for the
-- interactive zone (park / retrieve prompt). This controls the clickable area.
Config.TargetRadius = 2.5

-- Maximum number of VIP slots one player can own
-- Admins can run /createslot multiple times for the same player up to this cap
Config.MaxSlotsPerOwner = 10

-- Maximum number of access grants one owner can hand out across all their slots
-- Prevents a single owner spamming grants; set to 0 to disable the cap
Config.MaxAccessGrantsPerOwner = 20

-- Admin permission level required to use /createslot and /removeslot
-- QBCore groups: 'god', 'admin', 'mod'
Config.AdminGroup = 'admin'

-- Notification style used for player-facing messages
-- Options: 'qb' (QBCore default), 'ox' (ox_lib)
Config.NotifyStyle = 'qb'

-- Debug prints in server console (set false in production)
Config.Debug = false
