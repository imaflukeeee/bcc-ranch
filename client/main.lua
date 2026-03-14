-- ==========================================
-- ตัวแปรระบบ
-- ==========================================
local currentZone = nil
local activeBlips = {}
local myAnimals = {} -- เก็บข้อมูลสัตว์ของตัวเอง
local spawnedPeds = {} -- เก็บ Entity ID ของสัตว์ที่เสกออกมาเพื่อใช้ลบตอนออกเกม

-- [เพิ่มใหม่] ตัวแปรควบคุมการเปิด/ปิดข้อความแจ้งเตือน (ยกเว้น SendItem)
local isNotifyEnabled = true 
local isMenuOpen = false -- [เพิ่ม] ตัวแปรเช็คว่าเมนูเปิดอยู่หรือไม่
-- ==========================================
-- [เพิ่มใหม่] ฟังก์ชันกรองการแจ้งเตือน (เช็คสถานะปุ่ม Toggle ก่อนแสดงผล)
-- ==========================================
local function ShowNotify(data)
    if isNotifyEnabled then
        TriggerEvent("mtn_notify:send", data)
    end
end

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
                if not isMenuOpen then
                    exports.mtn_prompt:show("G", "เพื่อเลี้ยงสัตว์")
                end
            else
                if currentZone == zoneId then
                    currentZone = nil
                    SendNUIMessage({ action = "closeUI" })
                    SetNuiFocus(false, false)
                    isMenuOpen = false
                    exports.mtn_prompt:hide()
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
            
            -- ตรวจจับการกดปุ่ม G (รหัส 0x760A9C6F)
            if not isMenuOpen and IsControlJustPressed(0, 0x760A9C6F) then
                local zoneConfig = ConfigRanch.Zones[currentZone]
                local allowedAnimals = zoneConfig and zoneConfig.allowedAnimals or {}
                local zoneLimit = zoneConfig and zoneConfig.maxLimit or 10 
                
                -- ซ่อน Prompt เมื่อกดปุ่ม
                exports.mtn_prompt:hide()
                isMenuOpen = true
                
                BccUtils.RPC:Call("bcc-ranch:server:getMyAnimals", {}, function(success, freshAnimalsData)
                    if success then
                        myAnimals = freshAnimalsData
                        SendNUIMessage({ 
                            action = "openRanchUI", 
                            zone = currentZone, 
                            myAnimals = myAnimals, 
                            allowedAnimals = allowedAnimals,
                            zoneMaxLimit = zoneLimit
                        })
                        SetNuiFocus(true, true)
                    else
                        -- ถ้าเกิดข้อผิดพลาดในการโหลดข้อมูล ให้แสดง Prompt กลับมา
                        isMenuOpen = false
                        exports.mtn_prompt:show("G", "เพื่อเลี้ยงสัตว์")
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

                    if dist < 15.0 then 
                        sleep = 0 
                        
                        local onScreen, screenX, screenY = GetScreenCoordFromWorldCoord(aCoords.x, aCoords.y, aCoords.z + 1.2)
                        
                        if onScreen then
                            hasVisible = true
                            table.insert(floatingData, {
                                id = animal.id,
                                type = animal.animal_type,
                                x = screenX,
                                y = screenY,
                                dist = dist
                            })
                        end
                    end
                end
            end

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
        Wait(2000) 
        
        if myAnimals and #myAnimals > 0 then
            local ped = PlayerPedId()
            local pCoords = GetEntityCoords(ped)
            local abandonedAny = false
            local maxDist = ConfigRanch.AbandonDistance or 100.0

            for i = #myAnimals, 1, -1 do
                local animal = myAnimals[i]
                local aCoordsTable = json.decode(animal.coords)
                local aCoords = vector3(aCoordsTable.x, aCoordsTable.y, aCoordsTable.z)
                local dist = #(pCoords - aCoords)
                
                if dist > maxDist then
                    local animalPed = spawnedPeds[animal.id]
                    
                    if animalPed and DoesEntityExist(animalPed) then
                        ClearPedTasksImmediately(animalPed)
                        SetEntityAsMissionEntity(animalPed, true, true)
                        DeleteEntity(animalPed)
                        spawnedPeds[animal.id] = nil
                    end

                    TriggerServerEvent("bcc-ranch:server:abandonAnimal", animal.id)
                    SendNUIMessage({ action = "removeDeadAnimal", dbId = animal.id })
                    table.remove(myAnimals, i)
                    abandonedAny = true
                end
            end

            if abandonedAny then
                -- [แก้ไข] ใช้ฟังก์ชัน ShowNotify แทน
                ShowNotify({ 
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
-- NUI Callbacks
-- ==========================================

RegisterNUICallback('closeUI', function(data, cb)
    SetNuiFocus(false, false)
    isMenuOpen = false
    -- ถ้าปิด UI แล้วยังอยู่ในพื้นที่ฟาร์ม ให้แสดง Prompt คืน
    if currentZone then
        exports.mtn_prompt:show("G", "เพื่อเลี้ยงสัตว์")
    end
    cb('ok')
end)

-- [เพิ่มใหม่] รับค่าการกดปุ่มเปิดปิดแจ้งเตือนจากหน้า UI
RegisterNUICallback('toggleNotifyState', function(data, cb)
    if data and data.state ~= nil then
        isNotifyEnabled = data.state
    end
    cb('ok')
end)

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
            if message and message ~= "" then
                -- [แก้ไข] ใช้ฟังก์ชัน ShowNotify แทน
                ShowNotify({ 
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
            if message and message ~= "" then
                -- [แก้ไข] ใช้ฟังก์ชัน ShowNotify แทน
                ShowNotify({ 
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
            if message and message ~= "" then
                -- [แก้ไข] ใช้ฟังก์ชัน ShowNotify แทน
                ShowNotify({ 
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
            local zoneLimit = zoneConfig and zoneConfig.maxLimit or 10 
            
            SendNUIMessage({ 
                action = "openRanchUI", 
                zone = currentZone, 
                myAnimals = myAnimals,
                allowedAnimals = allowedAnimals,
                zoneMaxLimit = zoneLimit
            })
        end
    end)
    cb('ok')
end)

RegisterNUICallback('playSound', function(data, cb)
    if data and data.soundName then
        TriggerEvent('InteractSound_CL:PlayOnOne', data.soundName, data.volume)
    end
    cb('ok')
end)

RegisterNUICallback('sendNotify', function(data, cb)
    if data and data.description then
        -- [แก้ไข] ใช้ฟังก์ชัน ShowNotify แทน
        ShowNotify({ 
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

RegisterNetEvent("bcc-ranch:client:deleteDeadAnimal")
AddEventHandler("bcc-ranch:client:deleteDeadAnimal", function(dbId)
    if spawnedPeds[dbId] then
        local ped = spawnedPeds[dbId]
        if DoesEntityExist(ped) then
            DeletePed(ped)
        end
        spawnedPeds[dbId] = nil
    end
    
    if myAnimals then
        for i, a in ipairs(myAnimals) do
            if a.id == dbId then
                table.remove(myAnimals, i)
                -- [แก้ไข] ใช้ฟังก์ชัน ShowNotify แทน
                ShowNotify({ 
                    title = "", 
                    description = "สัตว์เลี้ยงของคุณตายเนื่องจากขาดอาหาร", 
                    placement = "middle-right", 
                    duration = 5000, 
                    progress = { enabled = true, type = 'bar', color = '#FFFFFF' }
                })
                
                SendNUIMessage({ 
                    action = "removeDeadAnimal", 
                    dbId = dbId 
                })
                break
            end
        end
    end
end)