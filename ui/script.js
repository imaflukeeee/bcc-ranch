let currentZone = "";
let myAnimals = [];
let allowedAnimals = {}; // เก็บ Config สัตว์จากโซนปัจจุบัน

// ==========================================
// 1. ส่วนรับคำสั่งจาก Lua (NUI Listener) - ส่วนนี้ที่หายไป!
// ==========================================
window.addEventListener('message', function(event) {
    let item = event.data;

    if (item.action === "openRanchUI") {
        currentZone = item.zone;
        myAnimals = item.myAnimals || [];
        allowedAnimals = item.allowedAnimals || {};
        
        document.getElementById('zone-title').innerText = "ทำฟาร์มที่: " + currentZone;
        
        renderShop();       // สร้างปุ่มร้านค้า
        renderMyAnimals();  // โชว์สัตว์ของเรา
        
        // แสดงหน้าต่าง UI
        document.getElementById('app').style.display = 'block';
    }

    if (item.action === "closeUI") { 
        closeUI(); 
    }
});

// ==========================================
// 2. ฟังก์ชันปิด UI และปุ่มกดต่างๆ
// ==========================================
function closeUI() {
    document.getElementById('app').style.display = 'none';
    fetch(`https://${GetParentResourceName()}/closeUI`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({})
    });
}

// กดปุ่ม ESC เพื่อปิดเมนู
document.onkeyup = function(data) {
    if (data.key == "Escape") {
        closeUI();
    }
};

// ฟังก์ชันสร้างปุ่มซื้อสัตว์จาก Config
function renderShop() {
    const shopContainer = document.querySelector('.buttons'); // ชี้ไปที่คลาส buttons ใน HTML
    shopContainer.innerHTML = "";

    // ดึงคีย์และข้อมูลสัตว์จาก Object (เช่น 'cow', 'pig')
    for (const [animalType, config] of Object.entries(allowedAnimals)) {
        let nameTH = "สัตว์";
        let icon = "🐾";
        if (animalType === "cow") { nameTH = "วัว"; icon = "🐮"; }
        if (animalType === "pig") { nameTH = "หมู"; icon = "🐷"; }
        if (animalType === "chicken") { nameTH = "ไก่"; icon = "🐔"; }

        // สร้างปุ่มโชว์ราคา และจำนวนลิมิต
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

// ฟังก์ชันกดซื้อสัตว์
function buyAnimal(animalType) {
    fetch(`https://${GetParentResourceName()}/buyAnimal`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ animalType: animalType, zone: currentZone })
    })
    .then(resp => resp.json())
    .then(data => {
        if (data.success) {
            myAnimals.push(data.newAnimal);
            renderMyAnimals();
        }
    });
}

// ฟังก์ชันวาด (Render) รายชื่อสัตว์
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

        // เช็คสถานะความหิว และ การเติบโต
        let statusText = animal.is_hungry ? "<span style='color:#ff4d4d;'>หิวอาหาร!</span>" : "<span style='color:#5cb85c;'>อิ่มแล้ว</span>";
        let growthText = `เติบโต: ${animal.growth}%`;

        // สลับปุ่มตามค่า Growth
        let actionBtn = "";
        if (animal.growth >= 100) {
            actionBtn = `<button class="buy-btn" style="background:#f0ad4e;" onclick="reciveItem(${animal.id}, '${animal.animal_type}')">📦 เก็บเกี่ยวผลผลิต</button>`;
        } else {
            actionBtn = `<button class="feed-btn" onclick="feedAnimal(${animal.id}, '${animal.animal_type}')">🌾 ให้อาหาร</button>`;
        }

        let animalHTML = `
            <div class="animal-card">
                <div>
                    <strong>${icon} ${nameTH} (ID: ${animal.id})</strong><br>
                    <small>สถานะ: ${statusText} | ${growthText}</small>
                </div>
                <div>
                    ${actionBtn}
                </div>
            </div>
        `;
        listContainer.innerHTML += animalHTML;
    });
}

// อัปเดตฟังก์ชันให้อาหาร
function feedAnimal(dbId, animalType) {
    fetch(`https://${GetParentResourceName()}/feedAnimal`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ dbId: dbId, animalType: animalType })
    }).then(resp => resp.json()).then(data => {
        if (data.success) {
            let anim = myAnimals.find(a => a.id === dbId);
            if (anim) {
                anim.is_hungry = 0;
                anim.growth = Math.min(anim.growth + 20, 100); 
            }
            renderMyAnimals();
        }
    });
}

// ฟังก์ชันเก็บเกี่ยวผลผลิต
function reciveItem(dbId, animalType) {
    fetch(`https://${GetParentResourceName()}/reciveItem`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ dbId: dbId, animalType: animalType })
    }).then(resp => resp.json()).then(data => {
        if (data.success) {
            myAnimals = myAnimals.filter(a => a.id !== dbId);
            renderMyAnimals();
        }
    });
}