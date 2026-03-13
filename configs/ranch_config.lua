ConfigRanch = {
    -- กำหนดระยะห่าง (เมตร) ที่หากผู้เล่นเดินออกไปไกลกว่านี้ สัตว์จะหายถาวรและต้องซื้อใหม่
    AbandonDistance = 100.0, 

    ranchSetup = {
        animalFollowSettings = { offsetX = 1.0, offsetY = 1.0, offsetZ = 1.0 },
        animalsWalkOnly = false,
    },

    Zones = {
        ['ValentineRanch'] = {
            name = "Valentine Farm",
            showBlip = true,
            blipSprite = "blip_mp_roundup",
            coords = vector3(-3826.84, -3488.84, 58.91),
            zone = {
                coords = {
                    vector2(-3847.67, -3512.68),
                    vector2(-3841.52, -3460.61),
                    vector2(-3792.64, -3478.06),
                    vector2(-3805.17, -3518.63)
                },
                minZ = 54.0, maxZ = 66.0, debugPoly = false
            },
            allowedAnimals = {
                ['cow'] = { 
                    price = 50, 
                    maxLimit = 5,
                    growthTime = 60,
                    feedItem = "corn",
                    requiredFeedCount = 2,
                    -- กำหนดไอเทมผลผลิตที่ได้รับตอนโต 100% (ใส่กี่ชิ้น/กี่ชนิดก็ได้)
                    rewards = {
                        { item = "meat", amount = 1 },
                        { item = "milk", amount = 1 }
                    }
                },
                ['pig'] = { 
                    price = 30, 
                    maxLimit = 10, 
                    growthTime = 60,
                    feedItem = "corn",
                    requiredFeedCount = 2,
                    rewards = {
                        { item = "meat", amount = 1 }
                    }
                },
                ['chicken'] = { 
                    price = 10, 
                    maxLimit = 15, 
                    growthTime = 60,
                    feedItem = "corn",
                    requiredFeedCount = 2,
                    rewards = {
                        { item = "egg", amount = 1 }
                    }
                },
                ['goat'] = { 
                    price = 10, 
                    maxLimit = 15, 
                    growthTime = 60,
                    feedItem = "corn",
                    requiredFeedCount = 2,
                    rewards = {
                        { item = "egg", amount = 1 }
                    }
                },
                ['sheep'] = { 
                    price = 10, 
                    maxLimit = 15, 
                    growthTime = 60,
                    feedItem = "corn",
                    requiredFeedCount = 2,
                    rewards = {
                        { item = "egg", amount = 1 }
                    }
                }
            }
        }
    }
}