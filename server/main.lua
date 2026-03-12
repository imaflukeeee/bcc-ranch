local VORPcore = exports.vorp_core:GetCore()
local VORPInv = exports.vorp_inventory:vorp_inventoryApi()
local BccUtils = exports['bcc-utils'].initiate()

-- ==========================================
-- Helper Function: คำนวณสถานะเวลาและความหิวล่าสุด
-- ==========================================
local function GetCalculatedAnimalState(animalData)
    local aConfig = ConfigAnimals.animalSetup[animalData.animal_type .. "s"] or ConfigAnimals.animalSetup[animalData.animal_type]
    local zoneConfig = ConfigRanch.Zones[animalData.zone_id]
    local ranchAnimalConfig = zoneConfig and zoneConfig.allowedAnimals[animalData.animal_type] or {}

    local reqTime = ranchAnimalConfig.growthTime or (aConfig and aConfig.growTimeSeconds) or 900
    local reqFeeds = ranchAnimalConfig.requiredFeedCount or (aConfig and aConfig.requiredFeedCount) or 2
    local timePerFeed = math.floor(reqTime / reqFeeds)

    local changed = false
    local acc_growth = animalData.accumulated_growth
    local is_hungry_val = animalData.is_hungry
    
    local isAnimalHungry = (is_hungry_val == 1 or is_hungry_val == true)
    local last_feed = animalData.last_feed_time

    local elapsed = 0
    if not isAnimalHungry then
        elapsed = os.time() - last_feed
    end

    if not isAnimalHungry and acc_growth < reqTime then
        if elapsed >= timePerFeed then
            acc_growth = acc_growth + timePerFeed
            if acc_growth >= reqTime then
                acc_growth = reqTime
                isAnimalHungry = false 
                elapsed = 0
            else
                isAnimalHungry = true 
                elapsed = timePerFeed
            end
            changed = true
        end
    end

    if changed then
        local db_hungry_val = isAnimalHungry and 1 or 0
        exports.oxmysql:execute('UPDATE player_ranch_animals SET accumulated_growth = ?, is_hungry = ? WHERE id = ?', {acc_growth, db_hungry_val, animalData.id})
        animalData.accumulated_growth = acc_growth
        animalData.is_hungry = db_hungry_val
    end

    local display_growth = acc_growth
    if not isAnimalHungry and acc_growth < reqTime then
        display_growth = acc_growth + elapsed
    end
    if display_growth > reqTime then display_growth = reqTime end
    
    animalData.current_growth = display_growth
    animalData.req_time = reqTime
    animalData.req_feeds = reqFeeds
    
    -- คำนวณเวลาในกระเพาะที่ย่อยไปแล้วส่งไปให้ UI
    animalData.meal_elapsed = isAnimalHungry and timePerFeed or elapsed

    return animalData
end

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
            local processedAnimals = {}
            for _, animal in ipairs(result) do
                table.insert(processedAnimals, GetCalculatedAnimalState(animal))
            end
            cb(true, processedAnimals, os.time())
        else
            cb(true, {}, os.time()) 
        end
    end)
end)

-- ==========================================
-- Buy Animal System
-- ==========================================
BccUtils.RPC:Register("bcc-ranch:server:buyAnimal", function(data, cb, source)
    local _source = source
    local user = VORPcore.getUser(_source)
    if not user then cb(false, "Player data not found") return end
    local character = user.getUsedCharacter
    
    local animalType = data.animalType
    local zoneId = data.zoneId
    local coords = data.coords

    local zoneConfig = ConfigRanch.Zones[zoneId]
    if not zoneConfig then cb(false, "Error: Invalid zone") return end

    local animalZoneConfig = zoneConfig.allowedAnimals[animalType]
    if not animalZoneConfig then cb(false, "This zone does not allow purchasing this animal") return end

    local price = animalZoneConfig.price
    local maxLimit = animalZoneConfig.maxLimit

    exports.oxmysql:scalar('SELECT COUNT(*) FROM player_ranch_animals WHERE charid = ? AND zone_id = ? AND animal_type = ?', 
    {character.charIdentifier, zoneId, animalType}, function(currentCount)
        
        local count = tonumber(currentCount) or 0
        if count >= maxLimit then
            cb(false, "You have reached the maximum capacity for " .. animalType .. " in this zone (" .. maxLimit .. ")")
            return
        end

        local currentMoney = character.money
        if currentMoney >= price then
            character.removeCurrency(0, price) 
            
            exports.oxmysql:insert('INSERT INTO player_ranch_animals (identifier, charid, zone_id, animal_type, coords, accumulated_growth, feed_count, last_feed_time, is_hungry) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)', 
            {character.identifier, character.charIdentifier, zoneId, animalType, json.encode(coords), 0, 0, 0, 1}, 
            function(insertId)
                data.dbId = insertId
                data.is_hungry = 1
                data.feed_count = 0
                cb(true, "Successfully bought a " .. animalType .. "!", data)
            end)
        else
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

    exports.oxmysql:execute('SELECT * FROM player_ranch_animals WHERE id = ?', {animalDbId}, function(result)
        if result and #result > 0 then
            local animalData = GetCalculatedAnimalState(result[1])

            if animalData.current_growth >= animalData.req_time then
                cb(false, "This animal is fully grown! It's ready for harvest.")
                return
            end

            -- เช็คว่าให้อาหารครบโควต้าหรือยัง
            if animalData.feed_count >= animalData.req_feeds then
                cb(false, "This animal has eaten enough for its lifetime!")
                return
            end

            local timePerFeed = math.floor(animalData.req_time / animalData.req_feeds)
            local halfTime = math.floor(timePerFeed * 0.5)

            -- ถ้ายอมให้กินก่อนหิวได้ แต่ต้องย่อยไปแล้วอย่างน้อย 50%
            if animalData.is_hungry == 0 and animalData.meal_elapsed < halfTime then
                cb(false, "สัตว์ยังอิ่มอยู่มาก! รอให้ย่อยอีกสักนิด (อีกประมาณ " .. (halfTime - animalData.meal_elapsed) .. " วินาที)")
                return
            end

            local zoneId = animalData.zone_id
            local requiredItem = "hay" 
            if ConfigRanch.Zones[zoneId] and ConfigRanch.Zones[zoneId].allowedAnimals[animalType] then
                requiredItem = ConfigRanch.Zones[zoneId].allowedAnimals[animalType].feedItem or "hay"
            end

            local itemCount = VORPInv.getItemCount(_source, requiredItem)
            if itemCount and itemCount > 0 then
                VORPInv.subItem(_source, requiredItem, 1)

                -- เก็บเวลาที่อุตส่าห์เติบโตมาได้ก่อนจะรีเซ็ตกระเพาะ (Top-up system)
                local new_acc_growth = animalData.accumulated_growth
                if animalData.is_hungry == 0 then
                    new_acc_growth = new_acc_growth + animalData.meal_elapsed
                end

                exports.oxmysql:execute('UPDATE player_ranch_animals SET feed_count = feed_count + 1, last_feed_time = ?, is_hungry = 0, accumulated_growth = ? WHERE id = ?', {os.time(), new_acc_growth, animalDbId})

                cb(true, "Successfully fed the " .. animalType .. " (" .. (animalData.feed_count + 1) .. "/" .. animalData.req_feeds .. ")")
            else
                cb(false, "You don't have " .. requiredItem .. " in your inventory")
            end
        else
            cb(false, "Error: Animal data not found in Database")
        end
    end)
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

    exports.oxmysql:execute('SELECT * FROM player_ranch_animals WHERE id = ? AND charid = ?', 
    {animalDbId, character.charIdentifier}, function(result)
        
        if result and #result > 0 then
            local animalData = GetCalculatedAnimalState(result[1])

            if animalData.current_growth < animalData.req_time then
                local timeLeft = animalData.req_time - animalData.current_growth
                local mins = math.floor(timeLeft / 60)
                local secs = timeLeft % 60
                cb(false, "Not fully grown! Time remaining: " .. mins .. "m " .. secs .. "s.")
                return
            end

            local zoneConfig = ConfigRanch.Zones[animalData.zone_id]
            if not zoneConfig or not zoneConfig.allowedAnimals[animalType] then
                cb(false, "Error: Zone Rewards data not found")
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
            cb(false, "Error: Animal data not found")
        end
    end)
end)