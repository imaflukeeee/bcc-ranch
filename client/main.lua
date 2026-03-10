-- ==========================================
-- ตัวแปรระบบ
-- ==========================================
local currentZone = nil
local activeBlips = {}
local myAnimals = {} -- เก็บข้อมูลสัตว์ของตัวเอง
local spawnedPeds = {} -- เก็บ Entity ID ของสัตว์ที่เสกออกมาเพื่อใช้ลบตอนออกเกม

-- สร้าง Prompt กลุ่มคำสั่ง (ใช้ปุ่ม G)
local ranchPromptGroup = BccUtils.Prompts:SetupPromptGroup()
local openMenuPrompt = ranchPromptGroup:RegisterPrompt("Farm", BccUtils.Keys["G"], 1, 1, true, 'hold', { timedeventhash = "MEDIUM_TIMED_EVENT" })

-- ==========================================
-- ระบบโหลดและเสกสัตว์ (Local Ped)
-- ==========================================
RegisterNetEvent('vorp:SelectedCharacter')
AddEventHandler('vorp:SelectedCharacter', function()
    -- ดึงข้อมูลสัตว์ทั้งหมดของตัวละครนี้จาก Server
    BccUtils.RPC:Call("bcc-ranch:server:getMyAnimals", {}, function(success, animalsData)
        if success and animalsData then
            myAnimals = animalsData
            devPrint("[Ranch] Loaded " .. #myAnimals .. " animals for this player.")
            
            -- นำข้อมูลมาเสกสัตว์ทีละตัว
            for _, animal in ipairs(myAnimals) do
                SpawnLocalAnimal(animal)
            end
        end
    end)
end)

function SpawnLocalAnimal(animalData)
    local coords = json.decode(animalData.coords)
    
    -- ค้นหาโมเดลตามประเภทสัตว์ (สามารถไปดึงจาก Config ได้ถ้าแยกไฟล์ไว้)
    local modelStr = "a_c_cow"
    if animalData.animal_type == "pig" then modelStr = "a_c_pig_01" end
    if animalData.animal_type == "chicken" then modelStr = "a_c_chicken_01" end
    
    local modelHash = GetHashKey(modelStr)

    RequestModel(modelHash)
    while not HasModelLoaded(modelHash) do Wait(10) end

    -- สังเกตพารามิเตอร์: false, false (isNetwork = false) เพื่อให้เห็นคนเดียว!
    local ped = CreatePed(modelHash, coords.x, coords.y, coords.z, 0.0, false, false, false, false)
    
    Citizen.InvokeNative(0x283978A15512B2FE, ped, true) -- SetRandomOutfitVariation ให้สีไม่ซ้ำกัน
    SetEntityAsMissionEntity(ped, true, true)
    
    -- ให้สัตว์เดินเล่นบริเวณนั้น
    TaskWanderStandard(ped, 10.0, 10)

    -- เก็บ Entity ไว้ใช้อ้างอิงและลบทิ้งตอนออกเกม
    spawnedPeds[animalData.id] = ped
end

-- ==========================================
-- ระบบ PolyZone และปุ่มกด
-- ==========================================
CreateThread(function()
    for zoneId, zoneData in pairs(ConfigRanch.Zones) do
        -- 1. สร้าง Blip บนแผนที่
        if zoneData.showBlip then
            local blip = BccUtils.Blip:SetBlip(zoneData.name, zoneData.blipSprite, 0.2, zoneData.coords.x, zoneData.coords.y, zoneData.coords.z)
            local modifier = BccUtils.Blips:AddBlipModifier(blip, 'BLIP_MODIFIER_MP_COLOR_8')
            modifier:ApplyModifier()
            table.insert(activeBlips, blip)
        end

        -- 2. สร้าง PolyZone
        local ranchZone = PolyZone:Create(zoneData.zone.coords, {
            name = zoneId,
            minZ = zoneData.zone.minZ,
            maxZ = zoneData.zone.maxZ,
            debugPoly = zoneData.zone.debugPoly,
        })

        -- 3. ตรวจจับการเข้า-ออกโซน
        ranchZone:onPlayerInOut(function(isInside)
            if isInside then
                currentZone = zoneId
                devPrint("[PolyZone] Entered ranch area: " .. currentZone)
            else
                if currentZone == zoneId then
                    currentZone = nil
                    devPrint("[PolyZone] Exited ranch area.")
                    -- บังคับปิด UI หากผู้เล่นเดินออกนอกกรอบ
                    SendNUIMessage({ action = "closeUI" })
                    SetNuiFocus(false, false)
                end
            end
        end)
    end
end)

-- ลูปเช็คการกดปุ่ม G เมื่ออยู่ในโซน
CreateThread(function()
    while true do
        local sleep = 1000
        
        if currentZone then
            sleep = 1 -- ให้ลูปรันเร็วขึ้นเพื่อตรวจจับปุ่ม
            ranchPromptGroup:ShowGroup("Buy")
            
            if openMenuPrompt:HasCompleted() then
                devPrint("Trigger UI for zone: " .. currentZone)
                
                -- ดึงค่าสัตว์ที่อนุญาตจาก Config ของโซนปัจจุบัน
                local zoneConfig = ConfigRanch.Zones[currentZone]
                local allowedAnimals = zoneConfig and zoneConfig.allowedAnimals or {}
                
                -- ส่ง Event ไปเปิด UI ตัวใหม่
                SendNUIMessage({ 
                    action = "openRanchUI", 
                    zone = currentZone, 
                    myAnimals = myAnimals, -- ส่งข้อมูลสัตว์ของตัวเองไปโชว์ใน UI ด้วย
                    allowedAnimals = allowedAnimals -- ส่ง Config ไปให้ UI สร้างปุ่ม
                })
                SetNuiFocus(true, true)
                
                Wait(1500) -- ดีเลย์กันผู้เล่นกดรัวๆ
            end
        end
        Wait(sleep)
    end
end)

-- ==========================================
-- NUI Callbacks (รับค่าจากหน้าต่าง UI)
-- ==========================================

-- 1. ปิดหน้าต่าง UI
RegisterNUICallback('closeUI', function(data, cb)
    SetNuiFocus(false, false)
    cb('ok')
end)

-- 2. เมื่อผู้เล่นกดปุ่ม "ซื้อสัตว์" ใน UI
RegisterNUICallback('buyAnimal', function(data, cb)
    print("[Ranch Client] Player clicked buy button in UI!")
    local animalType = data.animalType
    local zoneId = data.zone

    if not animalType or not zoneId then 
        print("[Ranch Client] Error: Incomplete data from UI")
        cb({ success = false, message = "Incomplete data provided" })
        return 
    end

    local ped = PlayerPedId()
    local pos = GetEntityCoords(ped)
    local coordsTable = { x = pos.x, y = pos.y, z = pos.z }

    print("[Ranch Client] Sending buy request for " .. animalType .. " to Server...")
    
    BccUtils.RPC:Call("bcc-ranch:server:buyAnimal", {
        animalType = animalType,
        zoneId = zoneId,
        coords = coordsTable
    }, function(success, message, newAnimalData)
        
        print("[Ranch Client] Server replied: Success=" .. tostring(success))
        
        if success then
            Notify(message, "success", 4000)
            local animalForSpawn = {
                id = newAnimalData.dbId,
                animal_type = animalType,
                coords = json.encode(newAnimalData.coords),
                growth = 0,
                is_hungry = 1
            }
            SpawnLocalAnimal(animalForSpawn)
            table.insert(myAnimals, animalForSpawn)

            cb({ success = true, message = message, newAnimal = animalForSpawn })
        else
            Notify(message, "error", 4000)
            cb({ success = false, message = message })
        end
    end)
end)

-- 3. เมื่อผู้เล่นกดปุ่ม "ให้อาหาร" ใน UI
RegisterNUICallback('feedAnimal', function(data, cb)
    local dbId = data.dbId -- รับ ID สัตว์จากหน้า UI (เพื่อบอก Server ว่าให้อาหารตัวไหน)
    local animalType = data.animalType

    BccUtils.RPC:Call("bcc-ranch:server:feedAnimal", {
        animalDbId = dbId,
        animalType = animalType
    }, function(success, message)
        if success then
            Notify(message, "success", 4000)
            -- เล่นอนิเมชั่นให้อาหาร (เรียกใช้จาก helpers/functions.lua)
            PlayAnim("amb_work@world_human_feed_pigs@working@throw_food_low@male_a@trans", "throw_trans_base", 3000)
            
            -- อัปเดตข้อมูลฝั่ง Client ให้ตรงกัน
            for _, anim in ipairs(myAnimals) do
                if anim.id == dbId then
                    anim.is_hungry = 0
                    anim.growth = math.min((anim.growth or 0) + 20, 100)
                    break
                end
            end
            
            cb({ success = true, message = message })
        else
            Notify(message, "error", 4000)
            cb({ success = false, message = message })
        end
    end)
end)

-- 4. เมื่อผู้เล่นกดปุ่ม "เก็บเกี่ยวผลผลิต" (เปลี่ยนจาก sellAnimal เป็น reciveItem)
RegisterNUICallback('reciveItem', function(data, cb)
    local dbId = data.dbId
    local animalType = data.animalType

    BccUtils.RPC:Call("bcc-ranch:server:reciveItem", {
        animalDbId = dbId,
        animalType = animalType
    }, function(success, message)
        if success then
            Notify(message, "success", 4000)
            
            -- ลบโมเดลสัตว์ตัวนี้ออกจากหน้าจอ (Local Ped)
            local ped = spawnedPeds[dbId]
            if ped and DoesEntityExist(ped) then
                DeletePed(ped)
                spawnedPeds[dbId] = nil -- ลบออกจากตารางความจำ
            end
            
            -- ลบออกจาก myAnimals ฝั่ง Client
            for i, anim in ipairs(myAnimals) do
                if anim.id == dbId then
                    table.remove(myAnimals, i)
                    break
                end
            end

            cb({ success = true })
        else
            Notify(message, "error", 4000)
            cb({ success = false })
        end
    end)
end)

-- ==========================================
-- ทำความสะอาดเมื่อรีสตาร์ทสคริปต์
-- ==========================================
AddEventHandler('onResourceStop', function(resourceName)
    if GetCurrentResourceName() ~= resourceName then return end
    
    -- ลบสัตว์ทุกตัวที่เสกออกมา
    for _, ped in pairs(spawnedPeds) do
        if DoesEntityExist(ped) then
            DeletePed(ped)
        end
    end
    
    -- ลบ Blip
    for _, blip in ipairs(activeBlips) do
        if blip and blip.Remove then blip:Remove() end
    end
end)