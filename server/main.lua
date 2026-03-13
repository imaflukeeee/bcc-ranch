local VORPcore = exports.vorp_core:GetCore()
local VORPInv = exports.vorp_inventory:vorp_inventoryApi()
local BccUtils = exports['bcc-utils'].initiate()

-- ==========================================
-- Helper Function: คำนวณสถานะเวลา, ความหิว, HP และระบบหยุดเวลา
-- ==========================================
local function GetCalculatedAnimalState(animalData, src)
    local now = os.time()
    
    -- 1. ระบบหยุดเวลาเมื่อออฟไลน์ (Offline Time Pause System)
    local last_active = animalData.last_active_time or now
    if last_active == 0 then last_active = now end
    local offline_duration = now - last_active
    
    -- หากไม่ได้อัปเดตเกิน 2 นาที (120 วิ) แปลว่าผู้เล่นออฟไลน์หรือเซิร์ฟเวอร์ดับ
    if offline_duration > 120 then 
        animalData.last_feed_time = (animalData.last_feed_time or now) + offline_duration
        if animalData.hunger_start_time and animalData.hunger_start_time > 0 then
            animalData.hunger_start_time = animalData.hunger_start_time + offline_duration
        end
    end
    animalData.last_active_time = now

    -- 2. ดึง Config สัตว์
    local aConfig = ConfigAnimals.animalSetup[animalData.animal_type .. "s"] or ConfigAnimals.animalSetup[animalData.animal_type]
    local zoneConfig = ConfigRanch.Zones[animalData.zone_id]
    local ranchAnimalConfig = zoneConfig and zoneConfig.allowedAnimals[animalData.animal_type] or {}

    local reqTime = ranchAnimalConfig.growthTime or (aConfig and aConfig.growTimeSeconds) or 900
    local reqFeeds = ranchAnimalConfig.requiredFeedCount or (aConfig and aConfig.requiredFeedCount) or 2
    local timePerFeed = math.floor(reqTime / reqFeeds)

    local acc_growth = animalData.accumulated_growth or 0
    local is_hungry_val = animalData.is_hungry
    local feed_count = animalData.feed_count or 0

    local isAnimalHungry = (is_hungry_val == 1 or is_hungry_val == true)
    local last_feed = animalData.last_feed_time or now

    local elapsed = 0
    if not isAnimalHungry then
        elapsed = now - last_feed
    end

    if not isAnimalHungry and acc_growth < reqTime then
        local isFullyFed = (feed_count >= reqFeeds)
        local mealCapacity = timePerFeed
        if isFullyFed then mealCapacity = reqTime - acc_growth end

        if elapsed >= mealCapacity then
            acc_growth = acc_growth + mealCapacity
            if acc_growth >= reqTime then
                acc_growth = reqTime
                isAnimalHungry = false
            else
                isAnimalHungry = true
            end
            elapsed = 0
        end
    end

-- 3. ระบบความหิว, HP และการตาย
    local current_hp = animalData.hp or 100
    local hunger_start = animalData.hunger_start_time or 0

    if isAnimalHungry then
        if hunger_start == 0 then
            hunger_start = now -- เพิ่งเริ่มหิว ให้บันทึกเวลาไว้
        else
            local elapsed_hungry = now - hunger_start
            
            -- [จุดที่ 1] ตั้งเป็น 60 วินาที (1 นาที) ก่อนที่เลือดจะเริ่มลด
            if elapsed_hungry > 60 then 
                local depleting_time = elapsed_hungry - 60
                
                -- [จุดที่ 2] ลด 100 HP ใน 60 วินาที (60 / 100 = 0.6 วินาที ต่อ 1 HP)
                local hp_lost = math.floor(depleting_time / 0.6)
                current_hp = 100 - hp_lost
                if current_hp < 0 then current_hp = 0 end
            end
        end
    else
        hunger_start = 0 -- ไม่หิวแล้ว รีเซ็ตเวลาหิว
    end

    -- อัปเดตข้อมูลเพื่อเตรียมบันทึก
    animalData.accumulated_growth = acc_growth
    animalData.is_hungry = isAnimalHungry and 1 or 0
    animalData.last_feed_time = last_feed
    animalData.hp = current_hp
    animalData.hunger_start_time = hunger_start

    -- บันทึกกลับลงฐานข้อมูล
    exports.oxmysql:execute('UPDATE player_ranch_animals SET accumulated_growth = ?, is_hungry = ?, last_feed_time = ?, hp = ?, hunger_start_time = ?, last_active_time = ? WHERE id = ?', 
        {acc_growth, animalData.is_hungry, last_feed, current_hp, hunger_start, animalData.last_active_time, animalData.id})

    -- 4. ตรวจสอบหากสัตว์ตาย
    if current_hp <= 0 then
        exports.oxmysql:execute('DELETE FROM player_ranch_animals WHERE id = ?', {animalData.id})
        if src then
            TriggerClientEvent("bcc-ranch:client:deleteDeadAnimal", src, animalData.id)
        end
        return nil -- ส่งกลับ nil เพื่อไม่ให้แสดงใน UI
    end

    -- 5. คำนวณเวลาหลอกเพื่อแสดงใน UI
    local display_growth = acc_growth
    if not isAnimalHungry and acc_growth < reqTime then
        display_growth = acc_growth + elapsed
    end
    if display_growth > reqTime then display_growth = reqTime end
    
    animalData.current_growth = display_growth
    animalData.req_time = reqTime
    animalData.req_feeds = reqFeeds
    
    local meal_elap = elapsed
    if isAnimalHungry then meal_elap = timePerFeed end
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
                local st = GetCalculatedAnimalState(animal, _source)
                -- เช็คว่าสัตว์ยังไม่ตายถึงจะโหลดแสดงในเมนู
                if st then 
                    table.insert(processedAnimals, st)
                end
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
            
            exports.oxmysql:insert('INSERT INTO player_ranch_animals (identifier, charid, zone_id, animal_type, coords, accumulated_growth, feed_count, last_feed_time, is_hungry, hp, hunger_start_time, last_active_time) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)', 
            {character.identifier, character.charIdentifier, zoneId, animalType, json.encode(coords), 0, 0, os.time(), 1, 100, os.time(), os.time()}, 
            function(insertId)
                data.dbId = insertId
                data.is_hungry = 1
                data.feed_count = 0
                data.hp = 100
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
            local animalData = GetCalculatedAnimalState(result[1], _source)

            -- ดักไว้กรณีที่กดให้อาหารจังหวะที่สัตว์ตายพอดี
            if not animalData then
                cb(false, "สัตว์เลี้ยงเสียชีวิตแล้ว")
                return
            end

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

                exports.oxmysql:execute('UPDATE player_ranch_animals SET feed_count = feed_count + 1, last_feed_time = ?, is_hungry = 0, accumulated_growth = ?, hp = 100, hunger_start_time = 0 WHERE id = ?', {os.time(), new_acc_growth, animalDbId})

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
            local animalData = GetCalculatedAnimalState(result[1], _source)

            -- ดักไว้กรณีที่กดเก็บผลผลิตจังหวะที่สัตว์ตายพอดี
            if not animalData then
                cb(false, "สัตว์เลี้ยงเสียชีวิตแล้ว")
                return
            end

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

-- ==========================================
-- Loop ตรวจสอบสถานะสัตว์ และอัปเดตเวลาออนไลน์
-- ==========================================
CreateThread(function()
    while true do
        Wait(5000) -- ทำงานทุกๆ 1 นาที
        local players = GetPlayers()
        for _, src in ipairs(players) do
            local user = VORPcore.getUser(src)
            if user then
                local character = user.getUsedCharacter
                if character then
                    exports.oxmysql:execute('SELECT * FROM player_ranch_animals WHERE charid = ?', {character.charIdentifier}, function(animals)
                        if animals and #animals > 0 then
                            for _, animal in ipairs(animals) do
                                GetCalculatedAnimalState(animal, src)
                            end
                        end
                    end)
                end
            end
        end
    end
end)