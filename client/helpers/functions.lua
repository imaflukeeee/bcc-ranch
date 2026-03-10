VORPcore = exports.vorp_core:GetCore()
BccUtils = exports['bcc-utils'].initiate()

if Config.devMode then
    -- Helper function for debugging
    function devPrint(message)
        print("^1[DEV MODE]^3 " .. message .. "^0")
    end
else
    -- Define devPrint as a no-op function if DevMode is not enabled
    function devPrint(message)
    end
end

function PlayAnim(animDict, animName, time) --function to play an animation
    RequestAnimDict(animDict)
    while not HasAnimDictLoaded(animDict) do
        Wait(100)
    end

    local flag = 16
    -- if time is -1 then play the animation in an infinite loop which is not possible with flag 16 but with 1
    -- if time is -1 the caller has to deal with ending the animation by themselve
    if time == -1 then
        flag = 1
    end
    TaskPlayAnim(PlayerPedId(), animDict, animName, 1.0, 1.0, time, flag, 0, true, 0, false, 0, false)
end

-- Set the relationship between ped and player
function relationshipsetup(ped, relInt)
    if not ped or not DoesEntityExist(ped) then
        return
    end

    relInt = tonumber(relInt) or 1 -- fallback to friendly if bad input

    local pedGroup = GetPedRelationshipGroupHash(ped)
    local playerGroup = joaat('PLAYER')

    -- Both directions
    SetRelationshipBetweenGroups(relInt, playerGroup, pedGroup)
    SetRelationshipBetweenGroups(relInt, pedGroup, playerGroup)
end

-- Make the animals follow the player
function SetRelAndFollowPlayer(pedObjs)
    local playerPed = PlayerPedId()

    for _, pedObj in ipairs(pedObjs) do
        if pedObj and pedObj.GetPed then
            local ped = pedObj:GetPed()
            if ped and DoesEntityExist(ped) then
                relationshipsetup(ped, 1)

                -- Apply follow behavior
                TaskFollowToOffsetOfEntity(
                    ped,
                    playerPed,
                    ConfigRanch.ranchSetup.animalFollowSettings.offsetX,
                    ConfigRanch.ranchSetup.animalFollowSettings.offsetY,
                    ConfigRanch.ranchSetup.animalFollowSettings.offsetZ,
                    1.0,                                  -- movement speed (you can make dynamic if wanted)
                    -1,                                   -- timeout (never timeout)
                    5.0,                                  -- stop within 5 meters
                    true, true,
                    ConfigRanch.ranchSetup.animalsWalkOnly, -- walk only or run
                    true, true, true
                )
            end
        end
    end
end

function Notify(message, typeOrDuration, maybeDuration)
    local notifyDuration = 6000

    -- Detect duration input
    if type(typeOrDuration) == "number" then
        notifyDuration = typeOrDuration
    elseif type(maybeDuration) == "number" then
        notifyDuration = maybeDuration
    end

    -- Force using vorp-core since we removed feather-menu
    VORPcore.NotifyRightTip(message, notifyDuration)
end

BccUtils.RPC:Register("bcc-ranch:NotifyClient", function(data)
    Notify(data.message, data.type, data.duration)
end)

function ClearAllRanchBlips()
    for _, blip in ipairs(activeBlips) do
        if blip and blip.Remove then
            blip:Remove()
        end
    end
    activeBlips = {}
end

function ClearAllRanchEntities()
    -- 1. Wandering animals
    if wanderingPeds then
        for _, ped in ipairs(wanderingPeds) do
            if DoesEntityExist(ped) then
                SetEntityAsMissionEntity(ped, true, true)
                DeletePed(ped)
            end
        end
        wanderingPeds = {}
        devPrint("[Cleanup] Cleared wanderingPeds")
    end
    
    -- ลบการจัดการ ped ส่วนที่ถูกยกเลิก (butcheringPed, feedPeds, harvestPed) ออกแล้ว
end