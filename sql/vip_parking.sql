-- ─────────────────────────────────────────────
--  VIP Parking — SQL Schema  v2
--  Run this once before starting the resource.
--
--  If upgrading from v1, run the migration block
--  at the bottom instead of the CREATE statements.
-- ─────────────────────────────────────────────

-- Slot definitions
CREATE TABLE IF NOT EXISTS `vip_parking_slots` (
    `slot_id`          INT           NOT NULL AUTO_INCREMENT,
    `owner_citizenid`  VARCHAR(50)   NOT NULL,
    `coords`           VARCHAR(100)  NOT NULL,   -- JSON { x, y, z, w (heading) }
    `vehicle_plate`    VARCHAR(8)    COLLATE utf8mb4_bin DEFAULT NULL, -- case-sensitive match
    `vehicle_model`    VARCHAR(50)   DEFAULT NULL,
    `vehicle_props`    LONGTEXT      DEFAULT NULL, -- JSON full QBCore vehicle props
    `created_at`       TIMESTAMP     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`slot_id`),
    INDEX `idx_owner`  (`owner_citizenid`),
    INDEX `idx_plate`  (`vehicle_plate`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;


-- Access grants — owner-level, not plate-level.
-- One row = allowed_citizenid can use ALL slots owned by owner_citizenid.
-- Grants survive individual slot removal as long as owner still has slots.
CREATE TABLE IF NOT EXISTS `vip_vehicle_access` (
    `id`                  INT          NOT NULL AUTO_INCREMENT,
    `owner_citizenid`     VARCHAR(50)  NOT NULL,  -- who owns the slot(s)
    `allowed_citizenid`   VARCHAR(50)  NOT NULL,  -- who was granted access
    `created_at`          TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    UNIQUE KEY `uq_owner_allowed` (`owner_citizenid`, `allowed_citizenid`),
    INDEX `idx_owner_access`   (`owner_citizenid`),
    INDEX `idx_allowed_access` (`allowed_citizenid`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;


-- ─────────────────────────────────────────────
--  MIGRATION (v1 → v2)
--  Only run this block if you already have v1
--  tables in your database. Skip if fresh install.
-- ─────────────────────────────────────────────
-- -- 1. Resize coords from LONGTEXT → VARCHAR(100) and add COLLATE + created_at to slots
-- ALTER TABLE `vip_parking_slots`
--     MODIFY COLUMN `coords`        VARCHAR(100) NOT NULL,
--     MODIFY COLUMN `vehicle_plate` VARCHAR(8)   COLLATE utf8mb4_bin DEFAULT NULL,
--     ADD    COLUMN `created_at`    TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP;
--
-- -- 2. Rebuild access table (v1 was plate-level; v2 is owner-level)
-- DROP TABLE IF EXISTS `vip_vehicle_access`;
-- CREATE TABLE `vip_vehicle_access` (
--     `id`                  INT          NOT NULL AUTO_INCREMENT,
--     `owner_citizenid`     VARCHAR(50)  NOT NULL,
--     `allowed_citizenid`   VARCHAR(50)  NOT NULL,
--     `created_at`          TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
--     PRIMARY KEY (`id`),
--     UNIQUE KEY `uq_owner_allowed` (`owner_citizenid`, `allowed_citizenid`),
--     INDEX `idx_owner_access`   (`owner_citizenid`),
--     INDEX `idx_allowed_access` (`allowed_citizenid`)
-- ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
