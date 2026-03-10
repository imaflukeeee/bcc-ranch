Config = {
    defaultlang = "en_lang", -- set your language
    devMode = true,         -- Leave false on live server
    
    -- หากไม่ได้ใช้ระบบอาชีพในการจำกัดสิทธิ์ (เช่น ทุกคนเดินมาดูสัตว์ได้) สามารถลบปีกกานี้ออกได้เลย
    RanchAllowedJobs = {
        'rancher',
        'doctor'
    },

    Notify = "vorp-core", -- เปลี่ยนจาก feather-menu เป็น vorp-core (หรือถ้าคุณมี UI แจ้งเตือนของตัวเองค่อยไปแก้ใน client/helpers/functions.lua)
    
    EnableAnimalBlip = true,
    Webhook = "",
    WebhookTitle = 'BCC-Ranch',
    WebhookAvatar = '',
}