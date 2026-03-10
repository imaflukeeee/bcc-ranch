local VORPcore = exports.vorp_core:GetCore()
local VORPInv = exports.vorp_inventory:vorp_inventoryApi()
local BccUtils = exports['bcc-utils'].initiate()

-- ==========================================
-- Fetch Player's Animals
-- ==========================================
BccUtils.RPC:Register("bcc-ranch:server:getMyAnimals", function(data, cb, source)
    local _source = source
    local user = VORPcore.getUser(_source)
    if not user then cb(false) return end
    
    local character = user.getUsedCharacter
    local charid = character.charIdentifier

    exports.oxmysql:execute('SELECT * FROM player_ranch_animals WHERE charid = ?', {charid}, function(result)
        if result and #result > 0 then
            cb(true, result)
        else
            cb(true, {}) 
        end
    end)
end)

-- ==========================================
-- Buy Animal System
-- ==========================================
BccUtils.RPC:Register("bcc-ranch:server:buyAnimal", function(data, cb, source)
    local _source = source
    print("[Ranch Debug] 1. Starting buy animal command from Player ID: " .. tostring(_source))

    local user = VORPcore.getUser(_source)
    if not user then 
        print("[Ranch Debug] Error: User not found for ID " .. tostring(_source))
        cb(false, "Player data not found") return 
    end
    
    local character = user.getUsedCharacter
    if not character then 
        print("[Ranch Debug] Error: Character not found")
        cb(false, "Character data not found") return 
    end
    
    local animalType = data.animalType
    local zoneId = data.zoneId
    local coords = data.coords
    print("[Ranch Debug] 2. Received data: Animal = " .. tostring(animalType) .. " | Zone = " .. tostring(zoneId))

    local zoneConfig = ConfigRanch.Zones[zoneId]
    if not zoneConfig then
        print("[Ranch Debug] Error: ConfigRanch.Zones data not found for zone " .. tostring(zoneId))
        cb(false, "Error: Invalid zone")
        return
    end

    local animalConfig = zoneConfig.allowedAnimals[animalType]
    if not animalConfig then
        print("[Ranch Debug] Error: Animal data not found in AllowedAnimals")
        cb(false, "This zone does not allow purchasing this animal")
        return
    end

    local price = animalConfig.price
    local maxLimit = animalConfig.maxLimit
    print("[Ranch Debug] 3. Price: " .. tostring(price) .. " | Max Capacity: " .. tostring(maxLimit))

    print("[Ranch Debug] 4. Connecting to Database to check animal count...")
    exports.oxmysql:scalar('SELECT COUNT(*) FROM player_ranch_animals WHERE charid = ? AND zone_id = ? AND animal_type = ?', 
    {character.charIdentifier, zoneId, animalType}, function(currentCount)
        
        print("[Ranch Debug] 5. DB Response! Current count: " .. tostring(currentCount))
        local count = tonumber(currentCount) or 0
        
        if count >= maxLimit then
            cb(false, "You have reached the maximum capacity for " .. animalType .. " in this zone (" .. maxLimit .. ")")
            return
        end

        local currentMoney = character.money
        print("[Ranch Debug] 6. Player's cash: " .. tostring(currentMoney))

        if currentMoney >= price then
            character.removeCurrency(0, price) 
            print("[Ranch Debug] 7. Money deducted, saving to Database...")

            exports.oxmysql:insert('INSERT INTO player_ranch_animals (identifier, charid, zone_id, animal_type, coords, growth, is_hungry) VALUES (?, ?, ?, ?, ?, ?, ?)', 
            {character.identifier, character.charIdentifier, zoneId, animalType, json.encode(coords), 0, 1}, 
            function(insertId)
                print("[Ranch Debug] 8. DB Save successful! Animal ID is: " .. tostring(insertId))
                data.dbId = insertId
                cb(true, "Successfully bought a " .. animalType .. "!", data)
            end)
        else
            print("[Ranch Debug] 7. Error: Not enough money")
            cb(false, "Not enough money (Needed: $" .. price .. ")")
        end
    end)
end)

-- ==========================================
-- Feed Animal System
-- ==========================================
BccUtils.RPC:Register("bcc-ranch:server:feedAnimal", function(data, cb, source)
    local _source = source
    local animalDbId = data.animalDbId
    local animalType = data.animalType
    
    local feedItems = {
        ['cow'] = "hay",
        ['pig'] = "corn",
        ['chicken'] = "seed"
    }
    
    local requiredItem = feedItems[animalType]
    if not requiredItem then
        cb(false, "Feed item data not found for this animal")
        return
    end

    local itemCount = VORPInv.getItemCount(_source, requiredItem)

    if itemCount and itemCount > 0 then
        VORPInv.subItem(_source, requiredItem, 1)

        exports.oxmysql:execute('UPDATE player_ranch_animals SET is_hungry = 0, growth = LEAST(growth + 20, 100) WHERE id = ?', {animalDbId})

        cb(true, "Successfully fed the " .. animalType .. " (-1 " .. requiredItem .. ")")
    else
        cb(false, "You don't have " .. requiredItem .. " in your inventory")
    end
end)

-- ==========================================
-- Harvest Product System
-- ==========================================
BccUtils.RPC:Register("bcc-ranch:server:reciveItem", function(data, cb, source)
    local _source = source
    local user = VORPcore.getUser(_source)
    if not user then cb(false, "Player data not found") return end
    
    local character = user.getUsedCharacter
    
    local animalDbId = data.animalDbId
    local animalType = data.animalType

    exports.oxmysql:execute('SELECT zone_id, growth FROM player_ranch_animals WHERE id = ? AND charid = ?', 
    {animalDbId, character.charIdentifier}, function(result)
        
        if result and #result > 0 then
            local growth = result[1].growth
            local zoneId = result[1].zone_id

            if growth >= 100 then
                
                local zoneConfig = ConfigRanch.Zones[zoneId]
                if not zoneConfig or not zoneConfig.allowedAnimals[animalType] then
                    cb(false, "Error: Animal data not found for this zone")
                    return
                end

                local rewards = zoneConfig.allowedAnimals[animalType].rewards
                local rewardText = ""

                if rewards then
                    for _, reward in ipairs(rewards) do
                        VORPInv.addItem(_source, reward.item, reward.amount)
                        rewardText = rewardText .. reward.amount .. "x " .. reward.item .. " "
                    end
                end

                exports.oxmysql:execute('DELETE FROM player_ranch_animals WHERE id = ?', {animalDbId})

                cb(true, "Successfully harvested! Received: " .. rewardText)
            else
                cb(false, "Error: This animal is not fully grown yet!")
            end
        else
            cb(false, "Error: Animal data not found")
        end
    end)
end)