local VORPcore = exports.vorp_core:GetCore()
local VORPInv = exports.vorp_inventory:vorp_inventoryApi()
local BccUtils = exports['bcc-utils'].initiate()

-- ==========================================
-- Helper Function: คำนวณสถานะเวลาและความหิวล่าสุด (แก้ไขใหม่ 100%)
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
    local feed_count = animalData.feed_count

    local isAnimalHungry = (is_hungry_val == 1 or is_hungry_val == true)
    local last_feed = animalData.last_feed_time

    local elapsed = 0
    if not isAnimalHungry then
        elapsed = os.time() - last_feed
    end

    if not isAnimalHungry and acc_growth < reqTime then
        local isFullyFed = (feed_count >= reqFeeds)
        local mealCapacity = timePerFeed
        -- ถ้าอาหารครบแล้ว อนุญาตให้เวลาไหลรวดเดียวจนถึง 100% (ไม่จำกัดแค่ทีละ 30 วิ)
        if isFullyFed then
            mealCapacity = reqTime - acc_growth
        end

        if elapsed >= mealCapacity then
            acc_growth = acc_growth + mealCapacity
            if acc_growth >= reqTime then
                acc_growth = reqTime
                isAnimalHungry = false
            else
                isAnimalHungry = true
            end
            elapsed = 0 -- รีเซ็ตเวลาสำหรับรอบถัดไป
            changed = true
        end
    end

    if changed then
        local db_hungry_val = isAnimalHungry and 1 or 0
        -- อัปเดตข้อมูลลงฐานข้อมูล พร้อมปรับ last_feed_time ป้องกันเวลาเพี้ยน
        exports.oxmysql:execute('UPDATE player_ranch_animals SET accumulated_growth = ?, is_hungry = ?, last_feed_time = ? WHERE id = ?', 
            {acc_growth, db_hungry_val, os.time(), animalData.id})
        animalData.accumulated_growth = acc_growth
        animalData.is_hungry = db_hungry_val
        animalData.last_feed_time = os.time()
    end

    local display_growth = acc_growth
    if not isAnimalHungry and acc_growth < reqTime then
        display_growth = acc_growth + elapsed
    end
    if display_growth > reqTime then display_growth = reqTime end
    
    animalData.current_growth = display_growth
    animalData.req_time = reqTime
    animalData.req_feeds = reqFeeds
    
    local meal_elap = elapsed
    if isAnimalHungry then
        meal_elap = timePerFeed
    end
    animalData.meal_elapsed = meal_elap

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
            cb(false, "")
            return
        end

        local currentMoney = character.money
        if currentMoney >= price then
            character.removeCurrency(0, price) 
            
            exports.oxmysql:insert('INSERT INTO player_ranch_animals (identifier, charid, zone_id, animal_type, coords, accumulated_growth, feed_count, last_feed_time, is_hungry) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)', 
            {character.identifier, character.charIdentifier, zoneId, animalType, json.encode(coords), 0, 0, os.time(), 1}, 
            function(insertId)
                data.dbId = insertId
                data.is_hungry = 1
                data.feed_count = 0
                cb(true, "", data)
            end)
        else
            cb(false, "เงินของคุณไม่พอ (ต้องการ: $" .. price .. ")")
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
                cb(false, "")
                return
            end

            if animalData.feed_count >= animalData.req_feeds then
                cb(false, "")
                return
            end

            local timePerFeed = math.floor(animalData.req_time / animalData.req_feeds)
            local halfTime = math.floor(timePerFeed * 0.5)

            if animalData.is_hungry == 0 and animalData.meal_elapsed < halfTime then
                cb(false, "")
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

                TriggerClientEvent("mtn_notify:sendItem", _source, {
                    title = "Removed",
                    description = "1x " .. requiredItem,
                    icon = "nui://vorp_inventory/html/img/items/" .. requiredItem .. ".png",
                    placement = "bottom-right",
                    titleColor = "#FF0000",
                    duration = 3000
                })

                local new_acc_growth = animalData.accumulated_growth
                if animalData.is_hungry == 0 then
                    new_acc_growth = new_acc_growth + animalData.meal_elapsed
                end

                exports.oxmysql:execute('UPDATE player_ranch_animals SET feed_count = feed_count + 1, last_feed_time = ?, is_hungry = 0, accumulated_growth = ? WHERE id = ?', {os.time(), new_acc_growth, animalDbId})

                cb(true, "")
            else
                cb(false, "คุณไม่มี " .. requiredItem .. " ในกระเป๋า")
            end
        else
            cb(false, "")
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
                cb(false, "ยังโตไม่เต็มที่เหลือเวลาอีก: " .. mins .. " นาที " .. secs .. " วินาที")
                return
            end

            local zoneConfig = ConfigRanch.Zones[animalData.zone_id]
            if not zoneConfig or not zoneConfig.allowedAnimals[animalType] then
                cb(false, "")
                return
            end

            local rewards = zoneConfig.allowedAnimals[animalType].rewards

            -- ==========================================
            -- [เพิ่มใหม่] ป้องกันบั๊กกระเป๋าเต็มแล้วสัตว์ค้าง
            -- ==========================================
            local canCarryAll = true
            if rewards then
                for _, reward in ipairs(rewards) do
                    -- เช็คว่าถือไอเทมนี้เพิ่มได้ไหม ถ้าไม่ได้ให้หยุดการทำงานทันที
                    if not exports.vorp_inventory:canCarryItem(_source, reward.item, reward.amount) then
                        canCarryAll = false
                        break
                    end
                end
            end

            if not canCarryAll then
                cb(false, "กระเป๋าของคุณเต็มไม่สามารถเก็บผลผลิตได้")
                return
            end
            -- ==========================================

            local rewardText = ""
            if rewards then
                for _, reward in ipairs(rewards) do
                    VORPInv.addItem(_source, reward.item, reward.amount)
                    rewardText = rewardText .. reward.amount .. "x " .. reward.item .. " "

                    TriggerClientEvent("mtn_notify:sendItem", _source, {
                        title = "Added",
                        description = reward.amount .. "x " .. reward.item,
                        icon = "nui://vorp_inventory/html/img/items/" .. reward.item .. ".png",
                        placement = "bottom-right",
                        titleColor = "#009900",
                        duration = 3500
                    })
                end
            end

            exports.oxmysql:execute('DELETE FROM player_ranch_animals WHERE id = ?', {animalDbId})
            cb(true, "")
        else
            cb(false, "")
        end
    end)
end)