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
    BccUtils.RPC:Call("bcc-ranch:server:getMyAnimals", {}, function(success, animalsData)
        if success and animalsData then
            myAnimals = animalsData
            for _, animal in ipairs(myAnimals) do
                SpawnLocalAnimal(animal)
            end
        end
    end)
end)

function SpawnLocalAnimal(animalData)
    local coords = json.decode(animalData.coords)
    local typeKey = animalData.animal_type .. "s"
    local aConfig = ConfigAnimals.animalSetup[typeKey] or ConfigAnimals.animalSetup[animalData.animal_type]
    local modelStr = (aConfig and aConfig.model) or "a_c_cow"
    local modelHash = GetHashKey(modelStr)

    RequestModel(modelHash)
    while not HasModelLoaded(modelHash) do Wait(10) end

    local ped = CreatePed(modelHash, coords.x, coords.y, coords.z, 0.0, false, false, false, false)
    Citizen.InvokeNative(0x283978A15512B2FE, ped, true) 
    SetEntityAsMissionEntity(ped, true, true)
    TaskWanderStandard(ped, 10.0, 10)
    spawnedPeds[animalData.id] = ped
end

-- ==========================================
-- ระบบ PolyZone และปุ่มกด
-- ==========================================
CreateThread(function()
    for zoneId, zoneData in pairs(ConfigRanch.Zones) do
        if zoneData.showBlip then
            local blip = BccUtils.Blip:SetBlip(zoneData.name, zoneData.blipSprite, 0.2, zoneData.coords.x, zoneData.coords.y, zoneData.coords.z)
            local modifier = BccUtils.Blips:AddBlipModifier(blip, 'BLIP_MODIFIER_MP_COLOR_8')
            modifier:ApplyModifier()
            table.insert(activeBlips, blip)
        end

        local ranchZone = PolyZone:Create(zoneData.zone.coords, {
            name = zoneId,
            minZ = zoneData.zone.minZ,
            maxZ = zoneData.zone.maxZ,
            debugPoly = zoneData.zone.debugPoly,
        })

        ranchZone:onPlayerInOut(function(isInside)
            if isInside then
                currentZone = zoneId
            else
                if currentZone == zoneId then
                    currentZone = nil
                    SendNUIMessage({ action = "closeUI" })
                    SetNuiFocus(false, false)
                end
            end
        end)
    end
end)

CreateThread(function()
    while true do
        local sleep = 1000
        
        if currentZone then
            sleep = 1
            ranchPromptGroup:ShowGroup("Buy")
            
            if openMenuPrompt:HasCompleted() then
                local zoneConfig = ConfigRanch.Zones[currentZone]
                local allowedAnimals = zoneConfig and zoneConfig.allowedAnimals or {}
                
                BccUtils.RPC:Call("bcc-ranch:server:getMyAnimals", {}, function(success, freshAnimalsData)
                    if success then
                        myAnimals = freshAnimalsData
                        SendNUIMessage({ 
                            action = "openRanchUI", 
                            zone = currentZone, 
                            myAnimals = myAnimals, 
                            allowedAnimals = allowedAnimals 
                        })
                        SetNuiFocus(true, true)
                    else
                        -- [แยกส่วนที่ 1] นำแจ้งเตือนโหลดข้อมูลฟาร์มล้มเหลวออกแล้ว
                    end
                end)
                Wait(1500)
            end
        end
        Wait(sleep)
    end
end)

-- ==========================================
-- ระบบ UI ลอยบนหัวสัตว์ (3D to 2D)
-- ==========================================
CreateThread(function()
    while true do
        local sleep = 500
        
        -- ทำงานเฉพาะตอนที่มีสัตว์เกิดแล้ว
        if myAnimals and #myAnimals > 0 then
            local ped = PlayerPedId()
            local pCoords = GetEntityCoords(ped)
            local floatingData = {}
            local hasVisible = false

            for _, animal in ipairs(myAnimals) do
                local animalPed = spawnedPeds[animal.id]
                
                if animalPed and DoesEntityExist(animalPed) then
                    local aCoords = GetEntityCoords(animalPed)
                    local dist = #(pCoords - aCoords)

                    -- [Distance Check] โชว์ UI เฉพาะระยะไม่เกิน 15 เมตร
                    if dist < 15.0 then 
                        sleep = 0 -- ถ้าอยู่ใกล้สัตว์ ปรับลูปให้เร็วขึ้นเพื่อให้ UI ลอยตามสมูทไม่กระตุก
                        
                        -- ดึงพิกัดจุดเหนือหัวสัตว์เล็กน้อย (z + 1.2)
                        local onScreen, screenX, screenY = GetScreenCoordFromWorldCoord(aCoords.x, aCoords.y, aCoords.z + 1.2)
                        
                        -- ถ้ากล้องมองเห็นสัตว์ตัวนั้นอยู่
                        if onScreen then
                            hasVisible = true
                            table.insert(floatingData, {
                                id = animal.id,
                                type = animal.animal_type, -- [แก้ไขแล้ว] เพิ่มประเภทสัตว์เพื่อนำไปใช้เรียกรูป PNG
                                x = screenX,
                                y = screenY,
                                dist = dist
                            })
                        end
                    end
                end
            end

            -- ส่งข้อมูลไปให้ HTML วาด ถ้ามีสัตว์ในจอ
            if hasVisible then
                SendNUIMessage({
                    action = "updateFloatingUI",
                    data = floatingData
                })
            else
                SendNUIMessage({ action = "hideFloatingUI" })
            end
        end
        Wait(sleep)
    end
end)

-- ==========================================
-- ระบบจัดการสัตว์หายถาวร (เมื่ออยู่ห่างเกินระยะ)
-- ==========================================
CreateThread(function()
    while true do
        Wait(2000) -- ตรวจสอบระยะทางทุกๆ 2 วินาที
        
        if myAnimals and #myAnimals > 0 then
            local ped = PlayerPedId()
            local pCoords = GetEntityCoords(ped)
            local abandonedAny = false
            local maxDist = ConfigRanch.AbandonDistance or 100.0 -- ดึงค่าจาก Config

            -- วนลูปถอยหลัง (เพื่อป้องกันบั๊กตอนลบข้อมูลออกจาก Table)
            for i = #myAnimals, 1, -1 do
                local animal = myAnimals[i]
                local aCoordsTable = json.decode(animal.coords)
                local aCoords = vector3(aCoordsTable.x, aCoordsTable.y, aCoordsTable.z)
                local dist = #(pCoords - aCoords)
                
                -- ถ้าระยะห่างเกินกว่าที่กำหนด -> สัตว์หายไปถาวร
                if dist > maxDist then
                    local animalPed = spawnedPeds[animal.id]
                    
                    -- 1. ลบโมเดลสัตว์ในเกมทิ้ง
                    if animalPed and DoesEntityExist(animalPed) then
                        ClearPedTasksImmediately(animalPed)
                        SetEntityAsMissionEntity(animalPed, true, true)
                        DeleteEntity(animalPed)
                        spawnedPeds[animal.id] = nil
                    end

                    -- 2. สั่งลบข้อมูลใน Database ถาวร
                    TriggerServerEvent("bcc-ranch:server:abandonAnimal", animal.id)

                    -- 3. สั่งซ่อน UI ลอยบนหัวของสัตว์ตัวนั้น
                    SendNUIMessage({ action = "removeDeadAnimal", dbId = animal.id })

                    -- 4. ลบออกจากข้อมูล Cache ในตัวเกม
                    table.remove(myAnimals, i)
                    abandonedAny = true
                end
            end

            -- แจ้งเตือน 1 ครั้งเมื่อมีสัตว์หายไปจากการทิ้งระยะห่าง
            if abandonedAny then
                TriggerEvent("mtn_notify:send", { 
                    title = "", 
                    description = "สัตว์ของคุณถูกขโมยหายไปแล้วเนื่องจากคุณอยู่ห่างจากพื้นที่ฟาร์มมากเกินไป", 
                    placement = "middle-right", 
                    duration = 5000, 
                    progress = { enabled = true, type = 'bar', color = '#FFFFFF' } 
                })
            end
        end
    end
end)

-- ==========================================
-- NUI Callbacks (แยกส่วนการแจ้งเตือนตามเหตุการณ์)
-- ==========================================

RegisterNUICallback('closeUI', function(data, cb)
    SetNuiFocus(false, false)
    cb('ok')
end)

-- [แยกส่วนที่ 2] เมื่อผู้เล่นกดปุ่ม "ซื้อสัตว์"
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
        animalType = animalType, zoneId = zoneId, coords = coordsTable
    }, function(success, message, newAnimalData)
        if success then
            local animalForSpawn = {
                id = newAnimalData.dbId, animal_type = animalType, coords = json.encode(newAnimalData.coords)
            }
            SpawnLocalAnimal(animalForSpawn)
            cb({ success = true, message = message })
        else
            -- ❌ ซื้อล้มเหลว: จะแจ้งเตือนก็ต่อเมื่อมีข้อความส่งมาเท่านั้น
            if message and message ~= "" then
                TriggerEvent("mtn_notify:send", { 
                    title = "", 
                    description = message, 
                    placement = "middle-right", 
                    duration = 4000, 
                    progress = { enabled = true, type = 'bar', color = '#FFFFFF' } 
                })
            end
            cb({ success = false, message = message })
        end
    end)
end)

-- [แยกส่วนที่ 3] เมื่อผู้เล่นกดปุ่ม "ให้อาหาร"
RegisterNUICallback('feedAnimal', function(data, cb)
    local dbId = data.dbId
    local animalType = data.animalType

    BccUtils.RPC:Call("bcc-ranch:server:feedAnimal", {
        animalDbId = dbId, animalType = animalType
    }, function(success, message)
        if success then
            PlayAnim("amb_work@world_human_feed_pigs@working@throw_food_low@male_a@trans", "throw_trans_base", 3000)
            cb({ success = true })
        else
            -- ❌ ให้อาหารล้มเหลว: จะแจ้งเตือนก็ต่อเมื่อมีข้อความส่งมาเท่านั้น
            if message and message ~= "" then
                TriggerEvent("mtn_notify:send", { 
                    title = "", 
                    description = message, 
                    placement = "middle-right", 
                    duration = 4000, 
                    progress = { enabled = true, type = 'bar', color = '#FFFFFF' } 
                })
            end
            cb({ success = false, message = message })
        end
    end)
end)

-- [แยกส่วนที่ 4] เมื่อผู้เล่นกดปุ่ม "เก็บเกี่ยวผลผลิต"
RegisterNUICallback('reciveItem', function(data, cb)
    local dbId = data.dbId
    local animalType = data.animalType

    BccUtils.RPC:Call("bcc-ranch:server:reciveItem", {
        animalDbId = dbId, animalType = animalType
    }, function(success, message)
        if success then
            local ped = spawnedPeds[dbId]
            if ped and DoesEntityExist(ped) then
                DeletePed(ped)
                spawnedPeds[dbId] = nil
            end
            cb({ success = true })
        else
            -- ❌ เก็บเกี่ยวล้มเหลว: จะแจ้งเตือนก็ต่อเมื่อมีข้อความส่งมาเท่านั้น
            if message and message ~= "" then
                TriggerEvent("mtn_notify:send", { 
                    title = "", 
                    description = message, 
                    placement = "middle-right", 
                    duration = 4000, 
                    progress = { enabled = true, type = 'bar', color = '#FFFFFF' } 
                })
            end
            cb({ success = false })
        end
    end)
end)

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

RegisterNUICallback('playSound', function(data, cb)
    if data and data.soundName then
        -- สั่งเล่นเสียงไปที่ interact-sound
        -- parameter: (ชื่อไฟล์ไม่รวมนามสกุล, ความดัง 0.1 - 1.0)
        TriggerEvent('InteractSound_CL:PlayOnOne', data.soundName, data.volume)
    end
    cb('ok')
end)

-- ==========================================
-- เพิ่มใหม่: รับคำสั่งแจ้งเตือน (mtn_notify) จาก UI
-- ==========================================
RegisterNUICallback('sendNotify', function(data, cb)
    if data and data.description then
        TriggerEvent("mtn_notify:send", { 
            title = "", 
            description = data.description, 
            placement = "middle-right", 
            duration = 6000, 
            progress = { enabled = true, type = 'bar', color = data.color or '#FFFFFF' }
        })
    end
    cb('ok')
end)

AddEventHandler('onResourceStop', function(resourceName)
    if GetCurrentResourceName() ~= resourceName then return end
    for _, ped in pairs(spawnedPeds) do
        if DoesEntityExist(ped) then DeletePed(ped) end
    end
    for _, blip in ipairs(activeBlips) do
        if blip and blip.Remove then blip:Remove() end
    end
end)

-- ==========================================
-- ระบบจัดการสัตว์ตาย (อัปเดตแก้บั๊ก UI)
-- ==========================================
RegisterNetEvent("bcc-ranch:client:deleteDeadAnimal")
AddEventHandler("bcc-ranch:client:deleteDeadAnimal", function(dbId)
    -- ลบโมเดลสัตว์ในเกม
    if spawnedPeds[dbId] then
        local ped = spawnedPeds[dbId]
        if DoesEntityExist(ped) then
            DeletePed(ped)
        end
        spawnedPeds[dbId] = nil
    end
    
    -- ลบออกจาก Cache และสั่งให้ UI อัปเดตแบบไม่รีเฟรชข้อมูลตัวอื่น
    if myAnimals then
        for i, a in ipairs(myAnimals) do
            if a.id == dbId then
                table.remove(myAnimals, i)
                TriggerEvent("mtn_notify:send", { 
                    title = "", 
                    description = "สัตว์เลี้ยงของคุณเสียชีวิตเนื่องจากขาดอาหาร", 
                    placement = "middle-right", 
                    duration = 5000, 
                    progress = { enabled = true, type = 'bar', color = '#FFFFFF' }
                })
                
                -- หากเปิด UI อยู่ ส่งคำสั่งไปลบแค่ตัวที่ตาย โดยไม่รบกวนเวลาตัวอื่น
                SendNUIMessage({ 
                    action = "removeDeadAnimal", 
                    dbId = dbId 
                })
                break
            end
        end
    end
end)