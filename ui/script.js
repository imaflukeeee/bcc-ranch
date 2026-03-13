let currentZone = "";
let myAnimals = [];
let allowedAnimals = {}; 
let uiTimer = null; 

let isSoundEnabled = true;
let isNotifyEnabled = true;

window.addEventListener('message', function(event) {
    let item = event.data;

    if (item.action === "openRanchUI") {
        currentZone = item.zone;
        myAnimals = item.myAnimals || [];
        allowedAnimals = item.allowedAnimals || {};
        
        document.getElementById('farm-name').innerText = currentZone;
        
        myAnimals.forEach(a => {
            a.current_growth = a.current_growth || 0;
            a.req_time = a.req_time || 900; 
            a.feed_count = a.feed_count || 0;
            a.req_feeds = a.req_feeds || 2;
            a.is_hungry = a.is_hungry !== undefined ? a.is_hungry : 1;
            a.meal_elapsed = a.meal_elapsed || 0; 
            a.hp = a.hp !== undefined ? a.hp : 100;
            a.ui_hungry_ticks = (a.hp < 100) ? 9999 : 0; 
        });

        updateLimitDisplay();
        renderShop();       
        renderItemsAndRewards();
        renderMyAnimals();  
        document.getElementById('app').style.display = 'flex';
    
        if(uiTimer) clearInterval(uiTimer);
        uiTimer = setInterval(processSimulation, 1000);
    }
    
    if (item.action === "closeUI") { closeUI(); }
});

function processSimulation() {
    let needsRender = false;
    let gracePeriod = 60; 
    let drainRate = 0.6;  

    myAnimals.forEach(a => {
        if ((a.is_hungry == 0 || a.is_hungry === false) && a.current_growth < a.req_time) {
            a.current_growth++;
            a.meal_elapsed++; 
            let timePerFeed = Math.floor(a.req_time / a.req_feeds);

            if (a.meal_elapsed >= timePerFeed && a.feed_count < a.req_feeds) {
                a.meal_elapsed = timePerFeed;
                a.is_hungry = 1; 
                a.ui_hungry_ticks = 0; 
                
                playAlertSound(); 
                sendNotify(`สัตว์ของคุณหิว (ID: ${a.id})`, '#FFFFFF');
            }
            needsRender = true;
        } 
        else if (a.is_hungry == 1 || a.is_hungry === true) {
            a.ui_hungry_ticks++;
            if (a.ui_hungry_ticks > gracePeriod || a.hp < 100) {
                if (a.hp > 0) {
                    let previousHp = a.hp; 
                    a.hp -= (1 / drainRate); 
                    if (a.hp < 0) a.hp = 0;
                    
                    if (previousHp > 50 && a.hp <= 50) {
                        playAlertSound();
                        sendNotify(`สัตว์ของคุณกำลังจะอดตายโปรดให้อาหาร (ID: ${a.id})`, '#FFFFFF');
                    }
                    needsRender = true;
                }
            }
        }
    });

    if(needsRender) renderMyAnimals();
}

function updateLimitDisplay() {
    let totalMaxLimit = 0;
    for (const key in allowedAnimals) { totalMaxLimit += allowedAnimals[key].maxLimit; }
    let displayLimit = totalMaxLimit > 0 ? totalMaxLimit : 5;
    document.getElementById('animal-limit').innerText = `${myAnimals.length}/${displayLimit} Limit`;
}

function renderShop() {
    const shopContainer = document.getElementById('shop-list');
    shopContainer.innerHTML = "";

    for (const [animalType, config] of Object.entries(allowedAnimals)) {
        let nameTH = getAnimalNameTH(animalType);
        let imgFile = `img/${animalType}_icon.png`; 

        shopContainer.innerHTML += `
            <div class="shop-card" onclick="buyAnimal('${animalType}')">
                <img src="${imgFile}" onerror="this.src='img/default.png'">
                <div class="shop-info">
                    <h3>${nameTH}</h3>
                    <p>$${config.price}</p>
                </div>
            </div>
        `;
    }
}

function renderItemsAndRewards() {
    const reqContainer = document.getElementById('req-items-list');
    const rewContainer = document.getElementById('reward-items-list');
    reqContainer.innerHTML = ""; 
    rewContainer.innerHTML = "";

    // เปลี่ยนมาใช้ class แบบ List แนวนอน
    reqContainer.className = "item-list-container";
    rewContainer.className = "item-list-container";

    let reqItemsMap = {};
    let rewItemsMap = {};

    // จัดกลุ่มข้อมูลไอเทมและเชื่อมโยงกับสัตว์ที่ใช้
    for (const key in allowedAnimals) {
        let animalName = getAnimalNameTH(key);

        // 1. จัดกลุ่มอาหารที่ใช้ (Feed Items)
        if(allowedAnimals[key].feedItem) {
            let item = allowedAnimals[key].feedItem;
            if(!reqItemsMap[item]) reqItemsMap[item] = [];
            reqItemsMap[item].push(animalName);
        }

        // 2. จัดกลุ่มผลผลิตที่ได้รับ (Reward Items)
        if(allowedAnimals[key].rewards) {
            allowedAnimals[key].rewards.forEach(r => {
                let mapKey = r.item + "_" + r.amount; // แยกกลุ่มไอเทมและจำนวน
                if(!rewItemsMap[mapKey]) {
                    rewItemsMap[mapKey] = { item: r.item, amount: r.amount, animals: [] };
                }
                if(!rewItemsMap[mapKey].animals.includes(animalName)) {
                    rewItemsMap[mapKey].animals.push(animalName);
                }
            });
        }
    }

    // วาด UI รายการอาหาร (Feed)
    for (const [item, animals] of Object.entries(reqItemsMap)) {
        let animalsText = animals.join(" , ");
        reqContainer.innerHTML += `
            <div class="item-list-card">
                <img src="nui://vorp_inventory/html/img/items/${item}.png" onerror="this.src='img/default.png'">
                <div class="item-list-info">
                    <h4>${item.toUpperCase()} x1</h4>
                    <p>ใช้สำหรับเลี้ยง : ${animalsText}</p>
                </div>
            </div>
        `;
    }

    // วาด UI รายการผลผลิต (Rewards)
    for (const key in rewItemsMap) {
        let data = rewItemsMap[key];
        let animalsText = data.animals.join(" , ");
        rewContainer.innerHTML += `
            <div class="item-list-card">
                <img src="nui://vorp_inventory/html/img/items/${data.item}.png" onerror="this.src='img/default.png'">
                <div class="item-list-info">
                    <h4>${data.item.toUpperCase()} x${data.amount}</h4>
                    <p>ได้รับผลผลิตจาก : ${animalsText}</p>
                </div>
            </div>
        `;
    }

    // กรณีไม่มีข้อมูลให้แสดงข้อความว่างเปล่า
    if (reqContainer.innerHTML === "") {
        reqContainer.innerHTML = `<div class="empty-slot" style="height: 60px; border:none;">ไม่มีข้อมูลอาหาร</div>`;
    }
    if (rewContainer.innerHTML === "") {
        rewContainer.innerHTML = `<div class="empty-slot" style="height: 60px; border:none;">ไม่มีข้อมูลผลผลิต</div>`;
    }
}

function renderMyAnimals() {
    const listContainer = document.getElementById('my-animals-list');
    listContainer.innerHTML = ""; 

    let maxSlots = 5; 
    let totalCards = Math.max(maxSlots, myAnimals.length);

    for(let i = 0; i < totalCards; i++) {
        if(i < myAnimals.length) {
            let animal = myAnimals[i];
            let nameTH = getAnimalNameTH(animal.animal_type);
            let imgFile = `img/${animal.animal_type}_icon.png`;
            
            let percent = Math.min((animal.current_growth / animal.req_time) * 100, 100);
            let timeLeft = animal.req_time - animal.current_growth;
            let m = Math.floor(timeLeft / 60); let s = Math.floor(timeLeft % 60);
            let timeStr = percent >= 100 ? "พร้อมเก็บเกี่ยว" : `${m} นาที ${s} วินาที`;

            let isHungry = (animal.is_hungry == 1 || animal.is_hungry === true);
            let isFullyFed = (animal.feed_count >= animal.req_feeds);
            let animalHp = Math.floor(animal.hp !== undefined ? animal.hp : 100);
            
            let hungerPercent = 0; let actionBtn = "";
            let feedPercent = (animal.feed_count / animal.req_feeds) * 100;

            if (percent >= 100) {
                hungerPercent = 100; 
                actionBtn = `<button class="btn-harvest" onclick="reciveItem(${animal.id}, '${animal.animal_type}')">เก็บเกี่ยว</button>`;
            } else if (isFullyFed) {
                hungerPercent = 100; 
                actionBtn = `<button class="btn-wait" disabled>รอย่อย</button>`;
            } else if (isHungry) {
                hungerPercent = 0; 
                actionBtn = `<button class="btn-feed" onclick="feedAnimal(${animal.id}, '${animal.animal_type}')">ให้อาหาร</button>`;
            } else {
                let timePerFeed = animal.req_time / animal.req_feeds;
                let actualPercent = Math.max(((timePerFeed - animal.meal_elapsed) / timePerFeed) * 100, 0);
                hungerPercent = (actualPercent > 50) ? 100 : (actualPercent / 50) * 100;
                actionBtn = (hungerPercent <= 50) ? `<button class="btn-feed" onclick="feedAnimal(${animal.id}, '${animal.animal_type}')">ให้อาหาร</button>` : `<button class="btn-wait" disabled>รอย่อย</button>`;
            }

            // โครงสร้างแบบแนวนอน (Horizontal Layout)
            listContainer.innerHTML += `
                <div class="animal-card">
                    <div class="animal-icon"><img src="${imgFile}" onerror="this.src='img/default.png'"></div>
                    
                    <div class="animal-details">
                        <div class="animal-header">
                            <h3>${nameTH} <small style="color:#aaa; font-size:12px;"></small></h3>
                        </div>
                        <div class="progress-grid">
                            <div class="progress-item">
                                <div class="prog-label"><span>สุขภาพ</span><span>${animalHp}%</span></div>
                                <div class="progress-bg"><div class="progress-fill" style="width: ${animalHp}%; background: var(--color-hp);"></div></div>
                            </div>
                            <div class="progress-item">
                                <div class="prog-label"><span>ความหิว</span><span>${Math.floor(hungerPercent)}%</span></div>
                                <div class="progress-bg"><div class="progress-fill" style="width: ${hungerPercent}%; background: var(--color-hunger);"></div></div>
                            </div>
                            <div class="progress-item">
                                <div class="prog-label"><span>การเจริญเติบโต</span><span>${Math.floor(percent)}%</span></div>
                                <div class="progress-bg"><div class="progress-fill" style="width: ${percent}%; background: var(--color-growth);"></div></div>
                            </div>
                            <div class="progress-item">
                                <div class="prog-label"><span>อาหาร</span><span>${animal.feed_count}/${animal.req_feeds}</span></div>
                                <div class="progress-bg"><div class="progress-fill" style="width: ${feedPercent}%; background: var(--color-feed);"></div></div>
                            </div>
                        </div>
                    </div>
                    
                    <div class="action-area">
                        <span class="time-out">ระยะเวลาเติบโต ${timeStr}</span>
                        ${actionBtn}
                    </div>
                </div>
            `;
        } else {
            listContainer.innerHTML += `<div class="empty-slot">คุณยังไม่ได้ซื้อสัตว์เลี้ยง</div>`;
        }
    }
}

function toggleSound() {
    isSoundEnabled = !isSoundEnabled;
    document.getElementById('btn-sound').className = isSoundEnabled ? "toggle-btn active" : "toggle-btn inactive";
}

function toggleNotify() {
    isNotifyEnabled = !isNotifyEnabled;
    document.getElementById('btn-notify').className = isNotifyEnabled ? "toggle-btn active" : "toggle-btn inactive";
}

function playAlertSound() {
    if(!isSoundEnabled) return;
    fetch(`https://${GetParentResourceName()}/playSound`, {
        method: 'POST', headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ soundName: "alert", volume: 0.5 })
    }).catch(err => console.log(err));
}

function sendNotify(msg, colorCode) {
    if(!isNotifyEnabled) return;
    fetch(`https://${GetParentResourceName()}/sendNotify`, {
        method: 'POST', headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ description: msg, color: colorCode, duration: 5000 })
    }).catch(err => console.log(err));
}

function getAnimalNameTH(type) {
    if (type === "cow") return "วัว";
    if (type === "pig") return "หมู";
    if (type === "chicken") return "ไก่";
    if (type === "sheep") return "แกะ";
    if (type === "goat") return "แพะ";
    return type.toUpperCase();
}

function closeUI() {
    document.getElementById('app').style.display = 'none';
    if(uiTimer) clearInterval(uiTimer); 
    fetch(`https://${GetParentResourceName()}/closeUI`, {
        method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({})
    });
}
document.onkeyup = function(data) { if (data.key == "Escape") closeUI(); };

function refreshData() {
    fetch(`https://${GetParentResourceName()}/refreshAnimals`, {
        method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({})
    });
}

function buyAnimal(animalType) {
    fetch(`https://${GetParentResourceName()}/buyAnimal`, {
        method: 'POST', headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ animalType: animalType, zone: currentZone })
    }).then(resp => resp.json()).then(data => { if (data.success) setTimeout(() => refreshData(), 400); });
}

function feedAnimal(dbId, animalType) {
    let anim = myAnimals.find(a => a.id == dbId); 
    if (anim) { anim.is_hungry = 0; anim.feed_count += 1; anim.meal_elapsed = 0; anim.hp = 100; renderMyAnimals(); }
    fetch(`https://${GetParentResourceName()}/feedAnimal`, {
        method: 'POST', headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ dbId: dbId, animalType: animalType })
    }).then(resp => resp.json()).then(data => { if (!data.success) refreshData(); }).catch(err => refreshData());
}

function reciveItem(dbId, animalType) {
    let index = myAnimals.findIndex(a => a.id == dbId);
    let backupAnim = null;
    if(index > -1) { backupAnim = myAnimals[index]; myAnimals.splice(index, 1); renderMyAnimals(); }
    fetch(`https://${GetParentResourceName()}/reciveItem`, {
        method: 'POST', headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ dbId: dbId, animalType: animalType })
    }).then(resp => resp.json()).then(data => { if (!data.success && backupAnim) { myAnimals.push(backupAnim); renderMyAnimals(); } });
}