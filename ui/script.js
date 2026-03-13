let currentZone = "";
let myAnimals = [];
let allowedAnimals = {}; 
let uiTimer = null; 

// ==========================================
// 1. ส่วนรับคำสั่งจาก Lua (NUI Listener)
// ==========================================
window.addEventListener('message', function(event) {
    let item = event.data;

    if (item.action === "openRanchUI") {
        currentZone = item.zone;
        myAnimals = item.myAnimals || [];
        allowedAnimals = item.allowedAnimals || {};
        
        document.getElementById('zone-title').innerText = "ทำฟาร์มที่: " + currentZone;
        
        myAnimals.forEach(a => {
            a.current_growth = a.current_growth || 0;
            a.req_time = a.req_time || 900; 
            a.feed_count = a.feed_count || 0;
            a.req_feeds = a.req_feeds || 2;
            a.is_hungry = a.is_hungry !== undefined ? a.is_hungry : 1;
            a.meal_elapsed = a.meal_elapsed || 0; 
            a.hp = a.hp !== undefined ? a.hp : 100;

            // เตรียมตัวแปรสำหรับจำลองเวลาหิวบน UI
            // ถ้าเปิดเมนูมาแล้วเลือดน้อยกว่า 100 แปลว่าพ้นระยะทนหิวไปแล้ว
            a.ui_hungry_ticks = (a.hp < 100) ? 9999 : 0; 
        });

        renderShop();       
        renderMyAnimals();  
        document.getElementById('app').style.display = 'block';

        // ==================================================
        // ระบบเวลานับถอยหลัง & จำลองเลือดลด Real-time บน UI
        // ==================================================
        if(uiTimer) clearInterval(uiTimer);
        uiTimer = setInterval(() => {
            let needsRender = false;

            // [ตั้งค่าให้ตรงกับ Server] 
            let gracePeriod = 60; // ระยะทนหิว 60 วินาที 
            let drainRate = 0.6;  // ลด 1 HP ทุกๆ 0.6 วินาที

            myAnimals.forEach(a => {
                // 1. จำลองการเติบโตและการย่อยอาหาร
                if ((a.is_hungry == 0 || a.is_hungry === false) && a.current_growth < a.req_time) {
                    a.current_growth++;
                    a.meal_elapsed++; 
                    
                    let timePerFeed = Math.floor(a.req_time / a.req_feeds);

                    if (a.meal_elapsed >= timePerFeed && a.feed_count < a.req_feeds) {
                        a.meal_elapsed = timePerFeed;
                        a.is_hungry = 1; // สั่งให้หิว!
                        a.ui_hungry_ticks = 0; // รีเซ็ตเวลาหิว

                        // 🔔 ร้องครั้งที่ 1: ตอนที่กระเพาะอาหารตกมาเหลือ 0% พอดี
                        playHungrySound(a.animal_type); 
                    }
                    needsRender = true;
                } 
                // 2. จำลองการลด HP บนหน้าจอ
                else if (a.is_hungry == 1 || a.is_hungry === true) {
                    a.ui_hungry_ticks++;

                    // ถ้าเวลาหิวใน UI เกินช่วงทนหิวไปแล้ว ให้เลือดลด
                    if (a.ui_hungry_ticks > gracePeriod || a.hp < 100) {
                        if (a.hp > 0) {
                            let previousHp = a.hp; // จดจำค่าเลือด 'ก่อนลด'
                            
                            a.hp -= (1 / drainRate); // หักเลือดทีละนิด
                            if (a.hp < 0) a.hp = 0;
                            
                            // 🔔 ร้องครั้งที่ 2: ดักจับตอนที่เลือดเพิ่งจะตกลงมาถึงจุด 50% (หรือต่ำกว่า 50% ในวินาทีนั้นพอดี)
                            if (previousHp > 50 && a.hp <= 50) {
                                playHungrySound(a.animal_type);
                            }

                            needsRender = true;
                        }
                    }
                }
            });

            if(needsRender) renderMyAnimals();
        }, 1000); // UI ทำงานทุกๆ 1 วินาที
    }
    
    // ==========================================
    // จัดการลบสัตว์ตัวที่ตายออกจากหน้าจอ (แก้ไขบั๊ก UI เด้งเต็ม)
    // ==========================================
    if (item.action === "removeDeadAnimal") {
        let index = myAnimals.findIndex(a => a.id == item.dbId);
        if (index > -1) {
            myAnimals.splice(index, 1);
            renderMyAnimals(); // วาด UI ใหม่โดยใช้ข้อมูล Real-time ที่มีอยู่แล้ว
        }
    }

    // ==========================================
    // รับพิกัดจาก Client มาวาด UI ลอยบนหัวสัตว์
    // ==========================================
    if (item.action === "updateFloatingUI") {
        let activeIds = []; // เก็บ ID สัตว์ที่อยู่ในระยะมองเห็น

        if (item.data && item.data.length > 0) {
            item.data.forEach(pos => {
                // ค้นหาข้อมูลสัตว์จาก ID ที่ Client ส่งมา (ถ้าไม่มีใน UI ให้ข้ามไป)
                let anim = myAnimals.find(a => a.id == pos.id);
                if (!anim) return;

                activeIds.push(anim.id);

                // สร้างกล่อง UI ลอยหากยังไม่มี
                let tag = document.getElementById("float-" + anim.id);
                if (!tag) {
                    tag = document.createElement('div');
                    tag.id = "float-" + anim.id;
                    tag.className = "floating-tag";
                    document.body.appendChild(tag);
                }

                // การปรับขนาดตามระยะห่าง (Distance Scaling)
                let scale = 1.0 - (pos.dist / 15); 
                if (scale < 0.6) scale = 0.6; // เล็กสุดแค่นี้พอเดี๋ยวอ่านไม่ออก

                // ขยับ UI ตามพิกัดหน้าจอที่ Client คำนวณมาให้
                tag.style.left = (pos.x * 100) + "vw";
                tag.style.top = (pos.y * 100) + "vh";
                tag.style.transform = `translate(-50%, -100%) scale(${scale})`;
                tag.style.display = "block";

                // ไอคอนสัตว์
                let imgFile = "default.png";
                if (anim.animal_type === "cow") imgFile = "cow.png";
                if (anim.animal_type === "pig") imgFile = "pig.png";
                if (anim.animal_type === "chicken") imgFile = "chicken.png";
                if (anim.animal_type === "sheep") imgFile = "sheep.png";
                if (anim.animal_type === "goat") imgFile = "goat.png";

                let icon = `<img src="img/${imgFile}" style="width: 60px; height: 60px; opacity: 0.8; vertical-align: middle;">`;

                // ข้อมูลสำหรับวาดหลอดเลือด
                let hp = Math.floor(anim.hp !== undefined ? anim.hp : 100);
                let hpColor = (hp > 50) ? "#5cb85c" : (hp > 20) ? "#f0ad4e" : "#d9534f";
                let isHungry = (anim.is_hungry == 1 || anim.is_hungry === true);
                
                let statusIcon = isHungry ? "<span style='color:#ff4d4d;'>⚠️ หิว!</span>" : "<span style='color:#5cb85c;'>✅ ปกติ</span>";
                
                // ระบบระยะการมองเห็น: โชว์รายละเอียดแตกต่างกันตามระยะทาง
                if (pos.dist < 5.0) {
                    // ระยะใกล้ (ไม่เกิน 5 เมตร): โชว์ละเอียด เลือด + ความหิว
                    tag.innerHTML = `
                        <strong>${icon} ฟาร์มของคุณ</strong>
                        <div style="font-size: 11px; margin-top:2px;">❤️ HP: ${hp}% | ${statusIcon}</div>
                        <div class="float-hp-bar">
                            <div class="float-hp-fill" style="width:${hp}%; background:${hpColor};"></div>
                        </div>
                    `;
                    tag.style.background = "rgba(30, 20, 15, 0.85)";
                    tag.style.border = "2px solid #8B5A2B";
                    tag.style.boxShadow = "0 4px 10px rgba(0,0,0,0.5)";
                } else {
                    // ระยะไกล (5 ถึง 15 เมตร): โชว์แค่ไอคอนสัตว์ลอยๆ
                    tag.innerHTML = `<span style="font-size:24px;">${icon}</span>`;
                    tag.style.background = "transparent";
                    tag.style.border = "none";
                    tag.style.boxShadow = "none";
                }
            });
        }

        // ซ่อน UI ของสัตว์ตัวที่เดินออกนอกระยะ (หรือไม่มีอยู่แล้ว)
        document.querySelectorAll('.floating-tag').forEach(el => {
            let id = parseInt(el.id.replace('float-', ''));
            if (!activeIds.includes(id)) {
                el.style.display = "none";
            }
        });
    } else if (item.action === "hideFloatingUI") {
        // ซ่อน UI ลอยบนหัวทั้งหมด (ตอนออกจากโซนฟาร์ม)
        document.querySelectorAll('.floating-tag').forEach(el => el.style.display = "none");
    }

    if (item.action === "closeUI") { closeUI(); }
});

// ==========================================
// 2. ฟังก์ชันปิด UI และปุ่มกดต่างๆ
// ==========================================
function closeUI() {
    document.getElementById('app').style.display = 'none';
    if(uiTimer) clearInterval(uiTimer); 
    fetch(`https://${GetParentResourceName()}/closeUI`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({})
    });
}

document.onkeyup = function(data) {
    if (data.key == "Escape") { closeUI(); }
};

function renderShop() {
    const shopContainer = document.querySelector('.buttons');
    shopContainer.innerHTML = "";

    for (const [animalType, config] of Object.entries(allowedAnimals)) {
        let nameTH = "สัตว์"; let icon = "🐾";
        if (animalType === "cow") { nameTH = "วัว"; icon = "🐮"; }
        if (animalType === "pig") { nameTH = "หมู"; icon = "🐷"; }
        if (animalType === "chicken") { nameTH = "ไก่"; icon = "🐔"; }
        if (animalType === "sheep") { nameTH = "แกะ"; icon = "🐑"; }
        if (animalType === "goat") { nameTH = "แพะ"; icon = "🐐"; }

        shopContainer.innerHTML += `
            <button class="buy-btn" onclick="buyAnimal('${animalType}')">
                ${icon} ซื้อ${nameTH} ($${config.price}) <br> <span style="font-size:12px;">(ความจุ: ${config.maxLimit} ตัว)</span>
            </button>
        `;
    }
    if (shopContainer.innerHTML === "") {
        shopContainer.innerHTML = "<p style='color: white;'>โซนนี้ไม่เปิดขายสัตว์</p>";
    }
}

// ==========================================
// วาดหน้าจอ Progress Bars และข้อมูลสัตว์
// ==========================================
function renderMyAnimals() {
    const listContainer = document.getElementById('animal-list');
    listContainer.innerHTML = ""; 

    if (myAnimals.length === 0) {
        listContainer.innerHTML = "<p>คุณยังไม่มีสัตว์เลี้ยงเลย กดซื้อด้านบนได้เลย!</p>";
        return;
    }

    myAnimals.forEach(animal => {
        let nameTH = "สัตว์"; let icon = "🐾";
        if (animal.animal_type === "cow") { nameTH = "วัว"; icon = "🐮"; }
        if (animal.animal_type === "pig") { nameTH = "หมู"; icon = "🐷"; }
        if (animal.animal_type === "chicken") { nameTH = "ไก่"; icon = "🐔"; }
        if (animal.animal_type === "sheep") { nameTH = "แกะ"; icon = "🐑"; }
        if (animal.animal_type === "goat") { nameTH = "แพะ"; icon = "🐐"; }

        // 1. คำนวณหลอด Growth (0 - 100%)
        let percent = Math.min((animal.current_growth / animal.req_time) * 100, 100);
        let timeLeft = animal.req_time - animal.current_growth;
        let m = Math.floor(timeLeft / 60);
        let s = Math.floor(timeLeft % 60);

        let isHungry = (animal.is_hungry == 1 || animal.is_hungry === true);
        let isFullyFed = (animal.feed_count >= animal.req_feeds); // เช็คว่าได้รับอาหารครบโควต้าหรือยัง
        
        let hungerPercent = 0;
        let hungerText = "";
        let barColor = "";
        let statusText = "";
        let actionBtn = "";

        // ==================================================
        // 2. จัดการสถานะ UI (แยกตามเงื่อนไขให้ชัดเจน)
        // ==================================================
        if (percent >= 100) {
            // กรณีที่ 1: โตเต็มที่ 100% พร้อมเก็บเกี่ยว
            hungerPercent = 100; 
            hungerText = "<span style='color:#5cb85c;'>พร้อมเก็บเกี่ยว</span>";
            barColor = "linear-gradient(90deg, #5cb85c, #4cae4c)"; 
            statusText = "<span style='color:#5cb85c;'>✅ เติบโตเต็มที่แล้ว!</span>";
            actionBtn = `<button class="buy-btn" style="background:#f0ad4e; font-weight:bold; width: 100%; padding: 12px 10px;" onclick="reciveItem(${animal.id}, '${animal.animal_type}')">📦 เก็บเกี่ยว</button>`;
            
        } else if (isFullyFed) {
            // กรณีที่ 2: อาหารครบโควต้าแล้ว แต่ยังโตไม่เต็ม 100% (สถานะสมบูรณ์แบบ)
            hungerPercent = 100; 
            hungerText = "<span style='color:#FFD700;'>🌟 อาหารครบถ้วน (รอโตอย่างเดียว)</span>";
            barColor = "linear-gradient(90deg, #FFD700, #ff8c00)"; // เปลี่ยนหลอดเป็นสีทอง!
            statusText = `<span style='color:#FFD700;'>💤 รอเวลา (โตอีก: ${m}น. ${s}วิ.)</span>`;
            actionBtn = `<button class="feed-btn" style="background:#555; cursor:not-allowed; width: 100%; padding: 12px 10px;" disabled>⏳ รอเก็บเกี่ยวผลผลิต</button>`;

        } else if (isHungry) {
            // กรณีที่ 3: หิวโซ รอการป้อนอาหาร
            hungerPercent = 0; 
            hungerText = "<span style='color:#ff4d4d;'>หิวโซ! (ต้องการอาหารด่วน)</span>";
            barColor = "linear-gradient(90deg, #d9534f, #c9302c)"; 
            statusText = `<span style='color:#ff4d4d;'>⚠️ หิวอาหาร!</span>`;
            actionBtn = `<button class="feed-btn" style="width: 100%; padding: 12px 10px;" onclick="feedAnimal(${animal.id}, '${animal.animal_type}')">🌾 ให้อาหาร</button>`;

        } else {
            // กรณีที่ 4: วงจรการย่อยอาหารปกติ (กำลังเติบโต)
            let timePerFeed = animal.req_time / animal.req_feeds;
            let remainingInMeal = timePerFeed - animal.meal_elapsed;
            let actualPercent = Math.max((remainingInMeal / timePerFeed) * 100, 0);

            if (actualPercent > 50) {
                hungerPercent = 100; 
                hungerText = "<span style='color:#5bc0de;'>อิ่มอยู่ท้อง (รอย่อย)</span>";
                barColor = "linear-gradient(90deg, #5bc0de, #31b0d5)"; 
                statusText = `<span style='color:#5cb85c;'>💤 โตอีก: ${m}น. ${s}วิ.</span>`;
                actionBtn = `<button class="feed-btn" style="background:#555; cursor:not-allowed; width: 100%; padding: 12px 10px;" disabled>⏳ รอย่อย</button>`;
            } else {
                hungerPercent = (actualPercent / 50) * 100;
                
                if (hungerPercent > 50) {
                    hungerText = "<span style='color:#f0ad4e;'>กำลังย่อยอาหาร (รอสักพัก)</span>";
                    barColor = "linear-gradient(90deg, #f0ad4e, #ec971f)"; 
                    statusText = `<span style='color:#5cb85c;'>💤 โตอีก: ${m}น. ${s}วิ.</span>`;
                    actionBtn = `<button class="feed-btn" style="background:#555; cursor:not-allowed; width: 100%; padding: 12px 10px;" disabled>⏳ รอย่อย</button>`;
                } else {
                    hungerText = "<span style='color:#d9534f;'>ท้องเริ่มว่าง (เติมอาหารได้)</span>";
                    barColor = "linear-gradient(90deg, #d9534f, #c9302c)"; 
                    statusText = `<span style='color:#ff4d4d;'>⚠️ ให้อาหารเพิ่มได้</span>`;
                    actionBtn = `<button class="feed-btn" style="width: 100%; padding: 12px 10px;" onclick="feedAnimal(${animal.id}, '${animal.animal_type}')">🌾 ให้อาหาร</button>`;
                }
            }
        }

        // 3. สร้างหลอด Feed Blocks (x/x)
        let feedBlocksHTML = '';
        for(let i = 1; i <= animal.req_feeds; i++) {
            let filled = (i <= animal.feed_count) ? 'filled' : '';
            feedBlocksHTML += `<div class="feed-block ${filled}"></div>`;
        }

        // คำนวณสีของ HP
        let animalHp = Math.floor(animal.hp !== undefined ? animal.hp : 100);
        let hpColor = (animalHp > 50) ? "#5cb85c" : (animalHp > 20) ? "#f0ad4e" : "#d9534f";

        let animalHTML = `
            <div class="animal-card">
                <div style="flex: 1; padding-right: 15px;">
                    <div style="display:flex; justify-content: space-between; margin-bottom: 5px;">
                        <strong style="font-size:16px;">${icon} ${nameTH} <span style="color:#aaa; font-size:12px;">(ID: ${animal.id})</span></strong>
                        <small>${statusText}</small>
                    </div>

                    <div class="status-label">
                        <span>❤️ พลังชีวิต (HP)</span>
                        <span>${animalHp}%</span>
                    </div>
                    <div class="bar-container" style="margin-bottom: 8px;">
                        <div class="bar-fill-hp" style="width: ${animalHp}%; background: ${hpColor}; border-radius: 4px;"></div>
                        <div class="bar-dashes"></div>
                    </div>

                    <div class="status-label">
                        <span>🌱 ความก้าวหน้าการเติบโต</span>
                        <span>${Math.floor(percent)}%</span>
                    </div>
                    <div class="bar-container">
                        <div class="bar-fill-growth" style="width: ${percent}%;"></div>
                        <div class="bar-dashes"></div>
                    </div>

                    <div class="status-label">
                        <span>🍖 สถานะกระเพาะ: ${hungerText}</span>
                    </div>
                    <div class="bar-container">
                        <div class="bar-fill-hunger" style="width: ${hungerPercent}%; background: ${barColor};"></div>
                        <div class="bar-dashes"></div>
                    </div>

                    <div class="status-label">
                        <span>🌾 จำนวนมื้อที่กินไปแล้ว (${animal.feed_count}/${animal.req_feeds})</span>
                    </div>
                    <div class="feed-blocks">
                        ${feedBlocksHTML}
                    </div>
                </div>
                <div style="display:flex; align-items:center; justify-content:center; min-width: 120px;">
                    ${actionBtn}
                </div>
            </div>
        `;
        listContainer.innerHTML += animalHTML;
    });
}

// ==========================================
// 3. ฟังก์ชันตัวช่วย: ส่งคำสั่งให้ Server ดึงข้อมูลใหม่
// ==========================================
function refreshData() {
    fetch(`https://${GetParentResourceName()}/refreshAnimals`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({})
    });
}

// ==========================================
// 4. ปุ่ม Action
// ==========================================
function buyAnimal(animalType) {
    fetch(`https://${GetParentResourceName()}/buyAnimal`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ animalType: animalType, zone: currentZone })
    }).then(resp => resp.json()).then(data => {
        if (data.success) { setTimeout(() => refreshData(), 400); }
    });
}

function feedAnimal(dbId, animalType) {
    let anim = myAnimals.find(a => a.id == dbId); 
    if (anim) {
        anim.is_hungry = 0;   
        anim.feed_count += 1; 
        anim.meal_elapsed = 0; 
        anim.hp = 100; // เมื่อให้อาหาร HP จะกลับมาเต็มทันทีในหน้า UI
        renderMyAnimals();    
    }

    fetch(`https://${GetParentResourceName()}/feedAnimal`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ dbId: dbId, animalType: animalType })
    }).then(resp => resp.json()).then(data => {
        if (!data.success) { refreshData(); }
    }).catch(err => {
        refreshData();
    });
}

function reciveItem(dbId, animalType) {
    let index = myAnimals.findIndex(a => a.id == dbId);
    let backupAnim = null;
    
    if(index > -1) {
         backupAnim = myAnimals[index];     
         myAnimals.splice(index, 1);        
         renderMyAnimals();                 
    }

    fetch(`https://${GetParentResourceName()}/reciveItem`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ dbId: dbId, animalType: animalType })
    }).then(resp => resp.json()).then(data => {
        if (!data.success && backupAnim) {
            myAnimals.push(backupAnim);
            renderMyAnimals();
        }
    });
}

function playHungrySound(animalType) {
    let soundFile = "";
    if (animalType === "cow") soundFile = "cow.mp3";
    else if (animalType === "pig") soundFile = "pig.mp3";
    else if (animalType === "chicken") soundFile = "chicken.mp3";
    else if (animalType === "sheep") soundFile = "sheep.mp3";
    else if (animalType === "goat") soundFile = "goat.mp3";

    if (soundFile !== "") {
        let audio = new Audio("sounds/" + soundFile);
        audio.volume = 0.5; // ปรับความดังตรงนี้ (0.1 - 1.0)
        audio.play().catch(err => { console.log("เล่นเสียงไม่ได้:", err); });
    }
}