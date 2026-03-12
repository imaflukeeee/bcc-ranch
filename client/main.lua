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
    
    -- แก้ไขการดึงชื่อ Model ให้ฉลาดขึ้น (เติม s ให้ตรงกับใน Config)
    local typeKey = animalData.animal_type .. "s"
    local aConfig = ConfigAnimals.animalSetup[typeKey] or ConfigAnimals.animalSetup[animalData.animal_type]
    local modelStr = (aConfig and aConfig.model) or "a_c_cow"
    
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
            sleep = 1
            ranchPromptGroup:ShowGroup("Buy")
            
            if openMenuPrompt:HasCompleted() then
                devPrint("Trigger UI for zone: " .. currentZone)
                
                -- ดึงค่าสัตว์ที่อนุญาตจาก Config
                local zoneConfig = ConfigRanch.Zones[currentZone]
                local allowedAnimals = zoneConfig and zoneConfig.allowedAnimals or {}
                
                -- โหลดข้อมูลสัตว์แบบ Real-time จาก Server ก่อนเปิด UI !! (สำคัญมาก)
                BccUtils.RPC:Call("bcc-ranch:server:getMyAnimals", {}, function(success, freshAnimalsData)
                    if success then
                        myAnimals = freshAnimalsData -- อัปเดตข้อมูลความหิว/เวลาเติบโตล่าสุด
                        
                        -- ส่ง Event ไปเปิด UI ด้วยข้อมูลที่อัปเดตแล้ว
                        SendNUIMessage({ 
                            action = "openRanchUI", 
                            zone = currentZone, 
                            myAnimals = myAnimals, 
                            allowedAnimals = allowedAnimals 
                        })
                        SetNuiFocus(true, true)
                    else
                        Notify("เกิดข้อผิดพลาดในการดึงข้อมูลสัตว์", "error", 3000)
                    end
                end)
                
                Wait(1500)
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
    local animalType = data.animalType
    local zoneId = data.zone

    if not animalType or not zoneId then 
        cb({ success = false, message = "Incomplete data provided" })
        return 
    end

    local ped = PlayerPedId()
    local pos = GetEntityCoords(ped)
    local coordsTable = { x = pos.x, y = pos.y, z = pos.z }

    BccUtils.RPC:Call("bcc-ranch:server:buyAnimal", {
        animalType = animalType,
        zoneId = zoneId,
        coords = coordsTable
    }, function(success, message, newAnimalData)
        if success then
            Notify(message, "success", 4000)
            local animalForSpawn = {
                id = newAnimalData.dbId,
                animal_type = animalType,
                coords = json.encode(newAnimalData.coords)
            }
            -- เสกสัตว์ขึ้นมาเดินเล่นทันที
            SpawnLocalAnimal(animalForSpawn)
            
            -- คืนค่า Success ไปให้ UI ทำการเรียก refreshAnimals อัตโนมัติ
            cb({ success = true, message = message })
        else
            Notify(message, "error", 4000)
            cb({ success = false, message = message })
        end
    end)
end)

-- 3. เมื่อผู้เล่นกดปุ่ม "ให้อาหาร" ใน UI
RegisterNUICallback('feedAnimal', function(data, cb)
    local dbId = data.dbId
    local animalType = data.animalType

    BccUtils.RPC:Call("bcc-ranch:server:feedAnimal", {
        animalDbId = dbId,
        animalType = animalType
    }, function(success, message)
        if success then
            Notify(message, "success", 4000)
            -- เล่นอนิเมชั่นให้อาหาร
            PlayAnim("amb_work@world_human_feed_pigs@working@throw_food_low@male_a@trans", "throw_trans_base", 3000)
            cb({ success = true, message = message })
        else
            Notify(message, "error", 4000)
            cb({ success = false, message = message })
        end
    end)
end)

-- 4. เมื่อผู้เล่นกดปุ่ม "เก็บเกี่ยวผลผลิต"
RegisterNUICallback('reciveItem', function(data, cb)
    local dbId = data.dbId
    local animalType = data.animalType

    BccUtils.RPC:Call("bcc-ranch:server:reciveItem", {
        animalDbId = dbId,
        animalType = animalType
    }, function(success, message)
        if success then
            Notify(message, "success", 4000)
            
            -- ลบโมเดลสัตว์ตัวนี้ออกจากหน้าจอ
            local ped = spawnedPeds[dbId]
            if ped and DoesEntityExist(ped) then
                DeletePed(ped)
                spawnedPeds[dbId] = nil
            end

            cb({ success = true })
        else
            Notify(message, "error", 4000)
            cb({ success = false })
        end
    end)
end)

-- 5. รีเฟรชข้อมูล (ถูกเรียกจาก UI เมื่อ ซื้อ/ให้อาหาร/เก็บเกี่ยว สำเร็จ)
RegisterNUICallback('refreshAnimals', function(data, cb)
    if not currentZone then cb('ok') return end
    
    BccUtils.RPC:Call("bcc-ranch:server:getMyAnimals", {}, function(success, freshAnimalsData)
        if success then
            myAnimals = freshAnimalsData
            local zoneConfig = ConfigRanch.Zones[currentZone]
            local allowedAnimals = zoneConfig and zoneConfig.allowedAnimals or {}
            
            SendNUIMessage({ 
                action = "openRanchUI", 
                zone = currentZone, 
                myAnimals = myAnimals,
                allowedAnimals = allowedAnimals
            })
        end
    end)
    cb('ok')
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