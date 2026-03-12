CreateThread(function()
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `player_ranch_animals` (
            `id` INT(11) NOT NULL AUTO_INCREMENT,
            `identifier` VARCHAR(50) NOT NULL,
            `charid` INT(11) NOT NULL,
            `zone_id` VARCHAR(50) NOT NULL,
            `animal_type` VARCHAR(50) NOT NULL,
            `coords` LONGTEXT NOT NULL,
            `accumulated_growth` INT(11) NOT NULL DEFAULT 0,
            `feed_count` INT(11) NOT NULL DEFAULT 0,
            `last_feed_time` INT(11) NOT NULL DEFAULT 0,
            `is_hungry` TINYINT(1) NOT NULL DEFAULT 1,
            PRIMARY KEY (`id`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]])

    print("^5[Database]^0 Table for ^3player_ranch_animals^0 ^2created or verified successfully^0.")
end)