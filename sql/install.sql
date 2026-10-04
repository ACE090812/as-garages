-- These tables are also created automatically when the resource starts.
-- Your framework's own vehicle table (player_vehicles / owned_vehicles) is never altered.

CREATE TABLE IF NOT EXISTS `as_garage_vehicles` (
  `plate` VARCHAR(12) NOT NULL,
  `garage` VARCHAR(64) NOT NULL,
  `state` TINYINT NOT NULL DEFAULT 1,            -- 0 out, 1 stored, 2 impounded
  `fuel` TINYINT UNSIGNED NOT NULL DEFAULT 100,
  `engine` TINYINT UNSIGNED NOT NULL DEFAULT 100,
  `body` TINYINT UNSIGNED NOT NULL DEFAULT 100,
  `mileage` DOUBLE NOT NULL DEFAULT 0,
  `fav` TINYINT NOT NULL DEFAULT 0,
  `stored_at` BIGINT NOT NULL DEFAULT 0,
  `impound_reason` VARCHAR(255) NULL,
  `impound_by` VARCHAR(100) NULL,
  `impound_fee` INT NOT NULL DEFAULT 0,
  `impound_at` BIGINT NOT NULL DEFAULT 0,
  `impound_until` BIGINT NOT NULL DEFAULT 0,
  `owner_release` TINYINT NOT NULL DEFAULT 1,
  PRIMARY KEY (`plate`),
  KEY `garage_state` (`garage`, `state`)
);

CREATE TABLE IF NOT EXISTS `as_garage_locations` (
  `id` VARCHAR(64) NOT NULL,
  `data` LONGTEXT NOT NULL,
  PRIMARY KEY (`id`)
);
