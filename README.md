# bcc-ranch

> สคริปต์ระบบทำฟาร์ม (Ranching) นี้เป็นโปรเจกต์ขนาดใหญ่ที่ช่วยให้ผู้เล่นสามารถเป็นเจ้าของไร่หรือฟาร์มของตัวเองได้! พร้อมด้วยฟีเจอร์ต่างๆ เช่น การต้อนสัตว์, การเป็นเจ้าของสัตว์, งานจิปาถะในฟาร์ม (Chores), การขายสัตว์, การโรงฆ่าสัตว์ และอื่นๆ สคริปต์นี้จะทำให้คุณเพลิดเพลินไปกับการดูแลฟาร์มเสมือนจริงของคุณ!

# Requirements
- VORP Core
- VORP Utils
- VORP Inventory
- feather-menu
- bcc-utils
- VORP Character
- bcc-minigames

# Features
- คำสั่งล็อกเฉพาะ Admin เพื่อสร้างฟาร์ม!
- ระบบ Chores (งานในฟาร์ม) ที่ตั้งค่าได้ พร้อม Minigames เพื่อเพิ่ม Condition (สภาพ) ของฟาร์ม!
- เป็นเจ้าของสัตว์ได้ 4 ประเภท!
- ขายสัตว์ได้ โดยราคาขายจะเปลี่ยนไปตาม Condition ของสัตว์!
- ต้อนสัตว์ไปรอบๆ เพื่อเพิ่ม Condition ของสัตว์ โดยจำนวนที่เพิ่มจะขึ้นอยู่กับ Condition ของฟาร์ม!
- ตั้งชื่อฟาร์มแบบ Custom ได้!
- ตั้งค่า Blips ของฟาร์มได้!
- ตั้งค่าจุดขาย (Sale Locations) ได้!
- ระบบ Webhook แบบละเอียด!
- ระบบ Version checking เพื่อช่วยให้คุณอัปเดตเวอร์ชันใหม่ๆ อยู่เสมอ!
- ระบบโรงฆ่าสัตว์ (Butcher) เพื่อรับไอเทมจากสัตว์!
- Condition ของฟาร์มจะลดลงตามกาลเวลาเมื่อเจ้าของฟาร์มออนไลน์!
- ปรับแต่งได้สูงและตั้งค่าได้ง่าย!
- แปลภาษา (Translate) ได้ง่าย!
- มีระบบ Inventory ติดมากับตัวฟาร์ม!
- มี Export API สำหรับให้สคริปต์อื่นมาโต้ตอบกับสคริปต์นี้ได้!
- เมนู Ranch Management สำหรับ Admin เพื่อลบฟาร์ม, เปลี่ยนชื่อ และเปลี่ยนรัศมี (Radius) ของฟาร์ม!
- จ้างพนักงาน (Employees) มาทำงานในฟาร์มของคุณ!
- เก็บไข่จากไก่ และรีดนมจากวัว!
- สัตว์จะเริ่มแก่ (Age) ก็ต่อเมื่อ Condition สูงสุดถึงเกณฑ์แล้วเท่านั้น หากยังไม่ถึงเกณฑ์สัตว์จะไม่เริ่มแก่ลง

# How it works
- Admin สามารถสร้างฟาร์มได้โดยการกรอกคำสั่ง จากนั้นจะมีเมนูขึ้นมาให้ตั้งชื่อฟาร์ม, ใส่รัศมี (Radius) และระบุ Static ID ของเจ้าของ!
- เจ้าของฟาร์มสามารถเดินไปยังตำแหน่งที่ฟาร์มตั้งอยู่แล้วกด "G" เพื่อเปิดเมนูจัดการฟาร์ม!

# Side Notes
- จำกัด 1 ฟาร์มต่อ 1 ตัวละคร!
- หลังจากได้รับฟาร์มแล้ว ผู้เล่นจำเป็นต้อง Relog (ล็อกอินใหม่) เพื่อให้ฟาร์มแสดงผล!
- โปรเจกต์นี้มีขนาดใหญ่ อาจมีข้อผิดพลาดที่ตกหล่น หากพบ Bug หรือมีข้อเสนอแนะ โปรดรายงานทันที!
- ขณะนี้ ชื่อฟาร์ม (Ranch names) ห้ามมีช่องว่าง!
- สำหรับการลบฟาร์ม ปัจจุบันต้องลบผ่าน Database (ฐานข้อมูล) ด้วยตัวเองเท่านั้น!
- ตรวจสอบให้แน่ใจว่าได้ตั้งค่าตัวเองเป็น Admin ใน config.lua โดยเพิ่ม Steam ID ในจุดที่ระบุไว้!
- หลังจากตั้งค่าตำแหน่ง Chore และตำแหน่งสัตว์แล้ว ต้องทำการ Relog เพื่อให้การตั้งค่าทำงาน
- ปัญหาที่พบ: ปัญหา Collision (การชน) ใกล้กับ Pronghorn Ranch อาจทำให้สัตว์ติดขัด การติดตั้ง Spooni Pronghorn Ranch MLO หรือเลือกจุดอื่นจะช่วยแก้ปัญหานี้ได้
- หากต้องการความช่วยเหลือเพิ่มเติม สามารถเข้าร่วม bcc discord ได้ที่ https://discord.gg/VrZEEpBgZJ

## API

### ตรวจสอบว่าผู้เล่นเป็นเจ้าของฟาร์มหรือไม่
- ในการตรวจสอบว่าผู้เล่นมีฟาร์มหรือไม่ ให้ใช้คำสั่ง
```
local _source = source
local Character = VORPcore.getUser(_source).getUsedCharacter
local result = exports['bcc-ranch']:CheckIfRanchIsOwned(Character.charIdentifier)
```
- API นี้ใช้งานได้เฉพาะฝั่ง Server Side เท่านั้น โดย result จะเป็น true หากผู้เล่นเป็นเจ้าของ และเป็น false หากไม่ใช่
- คุณต้องส่งค่า Character ID ดังนั้นคุณจำเป็นต้องมี VORP Core

### เพิ่ม Condition ของฟาร์ม
- หากต้องการเพิ่ม Condition ของฟาร์ม ให้ใช้คำสั่ง
```
local _source = source
local Character = VORPcore.getUser(_source).getUsedCharacter
exports['bcc-ranch']:IncreaseRanchCondition(Character.charIdentifier, amounttoincrease)
```
- หมายเหตุ amounttoincrease ต้องเป็นค่าตัวเลข (Number)

### ลด Condition ของฟาร์ม
- หากต้องการลด Condition ของฟาร์ม ให้ใช้คำสั่ง
```
local _source = source
local Character = VORPcore.getUser(_source).getUsedCharacter
exports['bcc-ranch']:DecreaseRanchCondition(Character.charIdentifier, amounttodecrease)
```
- หมายเหตุ: amounttodecrease ต้องเป็นค่าตัวเลข (Number)

### ตรวจสอบว่าผู้เล่นทำงานที่ฟาร์มหรือไม่
```
local _source = source
local Character = VORPcore.getUser(_source).getUsedCharacter
local result = exports['bcc-ranch']:DoesPlayerWorkAtRanch(Character.charIdentifier)
```
- คืนค่ากลับมาเป็น true หากผู้เล่นทำงานที่นั่น และ false หากไม่ได้ทำ
