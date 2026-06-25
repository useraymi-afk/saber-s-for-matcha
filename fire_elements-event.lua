--====================================================================--
--   FIRE FARM V5.9 — FIXED NIL CONCATENATION ERROR                  --
--   by useraymi — защита от nil в названиях зон                     --
--====================================================================--

loadstring(game:HttpGet("https://scripts.wabisabi.mom/wabi-sabi-ui-lib.lua"))()
local Library = WabiSabi

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local VirtualUser = game:GetService("VirtualUser")

local LocalPlayer = Players.LocalPlayer
while not LocalPlayer do task.wait(0.1) LocalPlayer = Players.LocalPlayer end

-- ===== НАСТРОЙКИ =====
local BOSS_HOLDER_PATH = "ReplicatedStorage.HiddenRegions.SummerEvent26.Boss.BossHolder"
local SUMMER_TP_PAD = Vector3.new(609.14, 208.54, 74.28)
local BOSS_TP_PAD = Vector3.new(1030.07, 89.31, 1530.62)
local POST_BOSS_TELEPORT = Vector3.new(829.05, 100.03, 1222.91)
local HB_MULT = 15.0

local MOB_ZONES = {
    {
        name = "ElementZones",
        searchPaths = {"Workspace.Gameplay.Map.ElementZones.Fire"},
        directPaths = {
            "Workspace.Gameplay.Map.ElementZones.Fire.Fire.Fire Golem",
            "Workspace.Gameplay.Map.ElementZones.Fire.Fire.Fire Boss",
        },
        farmPos = Vector3.new(547.62, 189.75, 463.46),
        exitPad = Vector3.new(500.59, 205.12, 474.27),
        backwardPad = nil,
    },
    {
        name = "AdvancedFireArea",
        searchPaths = {
            "Workspace.Gameplay.RegionsLoaded.AdvancedFireArea.Important.Fire",
            "Workspace.Gameplay.Map.ElementZones.Fire",
        },
        directPaths = {
            "Workspace.Gameplay.RegionsLoaded.AdvancedFireArea.Important.Fire.Fire Golem",
            "Workspace.Gameplay.RegionsLoaded.AdvancedFireArea.Important.Fire.Fire Boss",
        },
        farmPos = Vector3.new(-110.74, 35.95, 681.57),
        exitPad = Vector3.new(-117.51, 40.17, 762.62),
        backwardPad = Vector3.new(106.21, 30.13, 679.55),
    },
    {
        name = "MasterFireArea",
        searchPaths = {
            "Workspace.Gameplay.RegionsLoaded.MasterFireArea.Important.Fire",
        },
        directPaths = {
            "Workspace.Gameplay.RegionsLoaded.MasterFireArea.Important.Fire.Fire Golem",
            "Workspace.Gameplay.RegionsLoaded.MasterFireArea.Important.Fire.Master Fire Boss",
        },
        farmPos = Vector3.new(-757.39, 90.88, 708.44),
        exitPad = nil,
        backwardPad = Vector3.new(-639.72, 97.43, 709.74),
    },
}

local MOB_PRIORITY = {"Fire Boss", "Fire Golem"}
local MOB_TELEPORT_OFFSET = 4.0
local MOB_HP_CHECK_INTERVAL = 0.3
local MOB_MAX_WAIT_TIME = 120   
local MOB_CHASE_DISTANCE = 8
local ZONE_SWITCH_DELAY = 1.0
local MOB_CACHE_TIME = 1.5
local BOSS_WAIT_AFTER_TP = 1.0
local BOSS_FARM_OFFSET = 5.0
local BOSS_MAX_WAIT_TIME = 90

-- ===== СОСТОЯНИЕ =====
local IS_RUNNING = false
local FARM_MODE = "mobs"
local currentZoneIndex = 1
local mobsKilled = 0
local bossesKilled = 0
local mobCache = nil
local mobCacheTime = 0
local mobCacheZone = nil
local currentProfile = "Дневной"

local summerOrigSizes = {}
local summerExpParts = {}
local summerExpMobs = {}
local summerHighlights = {}
local normOrigSizes = {}
local normExpParts = {}
local normExpMobs = {}
local normHighlights = {}

local blacklistedMobs = {}
local pathCache = {}

local bossAlive = false

local statusParagraph = nil
local mobKillsParagraph = nil
local bossKillsParagraph = nil
local bossStatusParagraph = nil
local zoneDropdown = nil

local sliders = {}

local function findObject(path)
    if pathCache[path] and pathCache[path].Parent then return pathCache[path] end
    pathCache[path] = nil
    local current = game
    local startIdx = 1
    if path:sub(1, 9) == "Workspace" then
        current = Workspace
        startIdx = 11
    elseif path:sub(1, 17) == "ReplicatedStorage" then
        current = ReplicatedStorage
        startIdx = 19
    end
    for part in string.gmatch(path:sub(startIdx), "[^%.]+") do
        if current then current = current:FindFirstChild(part) else return nil end
    end
    if current then pathCache[path] = current end
    return current
end

local function getPlayerRoot()
    local char = LocalPlayer.Character
    if not char then return nil end
    return char:FindFirstChild("HumanoidRootPart")
end

local function getPlayerPos()
    local root = getPlayerRoot()
    return root and root.Position or nil
end

local function isMobAlive(model)
    if not model or not model.Parent or blacklistedMobs[model] then return false end
    local hum = model:FindFirstChildOfClass("Humanoid")
    if hum and hum.Health <= 0 then return false end
    local root = model:FindFirstChild("HumanoidRootPart")
    if not root or not root.Parent then return false end
    return true
end

local function findSummerBoss()
    local holder = findObject(BOSS_HOLDER_PATH)
    if not holder then holder = findObject("Workspace.Gameplay.RegionsLoaded.SummerEvent26.Boss.BossHolder") end
    if not holder then return nil end
    for _, obj in ipairs(holder:GetChildren()) do
        if obj:IsA("Model") then
            local root = obj:FindFirstChild("HumanoidRootPart")
            if root and isMobAlive(obj) then return obj end
        end
    end
    return nil
end

local function safeTeleport(pos, offset, forceAllow)
    if FARM_MODE ~= "mobs_only" and not forceAllow and findSummerBoss() then return false end
    offset = offset or 0
    local root = getPlayerRoot()
    if not root then return false end
    local targetPos = pos + Vector3.new(0, offset, 0)
    pcall(function()
        if root.AssemblyLinearVelocity.Magnitude > 1 then
            root.AssemblyLinearVelocity = Vector3.new(0,0,0)
        end
        root.CFrame = CFrame.new(targetPos.X, targetPos.Y, targetPos.Z)
    end)
    return true
end

local function waitForCharacter(timeout)
    timeout = timeout or 15
    local start = tick()
    while tick() - start < timeout do
        if getPlayerRoot() then return true end
        task.wait(0.5)
    end
    return false
end

-- ===== ХИТБОКСЫ =====
local function saveOriginal(part, tbl)
    if not tbl[part] then
        tbl[part] = {size = part.Size, transparency = part.Transparency}
    end
end

local function restorePart(part, tbl)
    local orig = tbl[part]
    if orig then
        pcall(function()
            if part.Parent then
                part.Size = orig.size
                part.Transparency = orig.transparency
            end
        end)
        tbl[part] = nil
    end
end

local function addHighlight(part, tbl, color)
    if not part or not part.Parent or tbl[part] then return end
    pcall(function()
        local hl = Instance.new("Highlight")
        hl.Name = "HBHighlight"
        hl.FillColor = color
        hl.FillTransparency = 0.5
        hl.OutlineColor = Color3.fromRGB(255, 255, 255)
        hl.OutlineTransparency = 0
        hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
        hl.Parent = part
        tbl[part] = hl
    end)
end

local function removeHighlight(part, tbl)
    if tbl[part] then
        pcall(function() tbl[part]:Destroy() end)
        tbl[part] = nil
    end
end

local function expandHRP(part, mult, origTbl, expTbl, hlTbl, color)
    if not part or not part.Parent or not part:IsA("BasePart") or expTbl[part] then return end
    saveOriginal(part, origTbl)
    pcall(function()
        local orig = origTbl[part]
        part.Size = Vector3.new(orig.size.X * mult, orig.size.Y * mult, orig.size.Z * mult)
        part.Transparency = 1
    end)
    if color then addHighlight(part, hlTbl, color) end
    expTbl[part] = true
end

local function restoreAllHitboxes(origTbl, expTbl, hlTbl)
    for part, _ in pairs(expTbl) do
        restorePart(part, origTbl)
        removeHighlight(part, hlTbl)
    end
    table.clear(expTbl)
    table.clear(origTbl)
    table.clear(hlTbl)
end

local function hitboxLoopSummer()
    while true do
        task.wait(MOB_HP_CHECK_INTERVAL * 3)
        pcall(function()
            for mob, _ in pairs(summerExpMobs) do
                if not mob or not mob.Parent then summerExpMobs[mob] = nil end
            end
            for part, _ in pairs(summerExpParts) do
                if not part or not part.Parent then
                    restorePart(part, summerOrigSizes)
                    removeHighlight(part, summerHighlights)
                    summerExpParts[part] = nil
                end
            end
            local boss = findSummerBoss()
            if boss then
                local currentBossMob = nil
                for mob, _ in pairs(summerExpMobs) do currentBossMob = mob; break end
                if currentBossMob ~= boss then
                    restoreAllHitboxes(summerOrigSizes, summerExpParts, summerHighlights)
                    local hrp = boss:FindFirstChild("HumanoidRootPart")
                    if hrp then
                        expandHRP(hrp, HB_MULT, summerOrigSizes, summerExpParts, summerHighlights, Color3.fromRGB(255, 50, 50))
                        summerExpMobs[boss] = true
                    end
                end
            end
        end)
    end
end

local function hitboxLoopNormal()
    while true do
        task.wait(MOB_HP_CHECK_INTERVAL * 3)
        pcall(function()
            for mob, _ in pairs(normExpMobs) do
                if not mob or not mob.Parent then normExpMobs[mob] = nil end
            end
            for part, _ in pairs(normExpParts) do
                if not part or not part.Parent then
                    restorePart(part, normOrigSizes)
                    removeHighlight(part, normHighlights)
                    normExpParts[part] = nil
                end
            end
            local holder = findObject("Workspace.Gameplay.Boss.BossHolder")
            if holder then
                for _, obj in ipairs(holder:GetChildren()) do
                    if obj:IsA("Model") and isMobAlive(obj) then
                        local currentBossMob = nil
                        for mob, _ in pairs(normExpMobs) do currentBossMob = mob; break end
                        if currentBossMob ~= obj then
                            restoreAllHitboxes(normOrigSizes, normExpParts, normHighlights)
                            local hrp = obj:FindFirstChild("HumanoidRootPart")
                            if hrp then
                                expandHRP(hrp, HB_MULT, normOrigSizes, normExpParts, normHighlights, nil)
                                normExpMobs[obj] = true
                            end
                        end
                        break
                    end
                end
            end
        end)
    end
end

task.spawn(hitboxLoopSummer)
task.spawn(hitboxLoopNormal)

-- ===== ПОИСК МОБОВ =====
local function extractMobData(model, zoneName)
    if not model or not model:IsA("Model") or not model.Parent or blacklistedMobs[model] then return nil end
    local root = model:FindFirstChild("HumanoidRootPart")
    if not root or not root.Parent then return nil end
    local pPos = getPlayerPos()
    local dist = pPos and (root.Position - pPos).Magnitude or 0
    local priority = 99
    for i = 1, #MOB_PRIORITY do
        if model.Name:find(MOB_PRIORITY[i]) then priority = i; break end
    end
    return {model = model, root = root, pos = root.Position, dist = dist, name = model.Name, priority = priority}
end

local function findMobsInZone(zone)
    local now = os.clock()
    local useCache = mobCacheZone == zone and mobCache and (now - mobCacheTime) < MOB_CACHE_TIME

    if useCache then
        local validMobs = {}
        for _, data in ipairs(mobCache) do
            if isMobAlive(data.model) then
                table.insert(validMobs, data)
            end
        end
        if #validMobs > 0 then
            return validMobs
        else
            useCache = false
        end
    end

    local results = {}
    local seen = {}
    for d = 1, #zone.directPaths do
        local obj = findObject(zone.directPaths[d])
        if obj and not seen[obj] then
            local data = extractMobData(obj, zone.name)
            if data then seen[obj] = true; table.insert(results, data) end
        end
    end
    for s = 1, #zone.searchPaths do
        local container = findObject(zone.searchPaths[s])
        if container then
            for _, obj in ipairs(container:GetDescendants()) do
                if obj:IsA("Model") and not seen[obj] then
                    for p = 1, #MOB_PRIORITY do
                        if obj.Name:find(MOB_PRIORITY[p]) then
                            local data = extractMobData(obj, zone.name)
                            if data then seen[obj] = true; table.insert(results, data) end
                            break
                        end
                    end
                end
            end
        end
    end
    table.sort(results, function(a, b)
        if a.priority ~= b.priority then return a.priority < b.priority end
        return a.dist < b.dist
    end)
    mobCache = results
    mobCacheTime = now
    mobCacheZone = zone
    return results
end

local function farmSingleMob(mobData, offset, maxWait)
    local mob = mobData.model
    if not isMobAlive(mob) then return false end 
    
    local startTime = tick()
    local lastFollowTp = 0
    local tpOffset = offset or MOB_TELEPORT_OFFSET
    local waitTime = maxWait or MOB_MAX_WAIT_TIME

    if not getPlayerRoot() then waitForCharacter() end
    safeTeleport(mobData.pos, tpOffset, true)

    while IS_RUNNING and isMobAlive(mob) do
        if FARM_MODE ~= "mobs_only" and findSummerBoss() then break end
        if tick() - startTime > waitTime then
            blacklistedMobs[mob] = true
            break
        end

        if mobData.root and mobData.root.Parent then
            local mobPos = mobData.root.Position
            mobData.pos = mobPos
            local root = getPlayerRoot()
            if root then
                local distToMob = (mobPos - root.Position).Magnitude
                local chaseDist = (mobData.name:find("Boss") and 12) or MOB_CHASE_DISTANCE
                if distToMob > chaseDist then
                    local now = tick()
                    if now - lastFollowTp > 0.5 then
                        safeTeleport(mobPos, tpOffset, true)
                        lastFollowTp = now
                    end
                end
            else
                waitForCharacter()
            end
        end
        task.wait(MOB_HP_CHECK_INTERVAL)
    end
    
    if not isMobAlive(mob) then
        if mobData.name:find("Boss") then
            bossesKilled = bossesKilled + 1
            if bossKillsParagraph then bossKillsParagraph:SetContent(tostring(bossesKilled)) end
        else
            mobsKilled = mobsKilled + 1
            if mobKillsParagraph then mobKillsParagraph:SetContent(tostring(mobsKilled)) end
        end
        return true
    end
    return false
end

-- ===== ФАРМ БОССА (с защитой от nil) =====
local function farmSummerBoss()
    local boss = findSummerBoss()
    if not boss then return false end
    if not getPlayerRoot() then waitForCharacter() end
    safeTeleport(SUMMER_TP_PAD, 3, true)
    task.wait(BOSS_WAIT_AFTER_TP)
    safeTeleport(BOSS_TP_PAD, 3, true)
    task.wait(1.5)
    boss = findSummerBoss()
    if not boss then return false end
    local bossRoot = boss:FindFirstChild("HumanoidRootPart")
    if not bossRoot then return false end
    safeTeleport(bossRoot.Position, BOSS_FARM_OFFSET, true)
    task.wait(0.5)
    local startTime = tick()
    while IS_RUNNING and isMobAlive(boss) do
        if tick() - startTime > BOSS_MAX_WAIT_TIME then break end
        local myPos = getPlayerPos()
        if myPos and (bossRoot.Position - myPos).Magnitude > 15 then
            safeTeleport(bossRoot.Position, BOSS_FARM_OFFSET, true)
        end
        task.wait(0.8)
    end
    if not isMobAlive(boss) then
        print("[Boss] Босс убит! Телепорт на промежуточные координаты...")
        safeTeleport(POST_BOSS_TELEPORT, 0, true)
        task.wait(0.5)
        local firstZone = MOB_ZONES[1]
        if firstZone then
            safeTeleport(firstZone.farmPos, 3, true)
            task.wait(1.5)
        end
        currentZoneIndex = 1
        if zoneDropdown then
            pcall(function() zoneDropdown:SetValue(1) end)
        end
        mobCache = nil
        mobCacheTime = 0
        mobCacheZone = nil
        print("[Boss] Телепорт завершён, кэш сброшен, начинаем фарм мобов.")
        return true
    end
    return false
end

-- ===== АНТИ-AFK =====
task.spawn(function()
    while true do
        task.wait(30)
        pcall(function()
            VirtualUser:CaptureController()
            VirtualUser:ClickButton2(Vector2.new())
        end)
    end
end)

-- ===== ПЕРЕКЛЮЧЕНИЕ ЗОН =====
local function transitionToNextZone(fromZone)
    local nextIdx = currentZoneIndex + 1
    if nextIdx > #MOB_ZONES then
        local zone3 = MOB_ZONES[3]
        if zone3 and zone3.backwardPad then
            safeTeleport(zone3.backwardPad, 3, true)
            task.wait(ZONE_SWITCH_DELAY)
        end
        local zone2 = MOB_ZONES[2]
        if zone2 and zone2.backwardPad then
            safeTeleport(zone2.backwardPad, 3, true)
            task.wait(ZONE_SWITCH_DELAY)
        end
        local zone1 = MOB_ZONES[1]
        if zone1 then
            safeTeleport(zone1.farmPos, 3, true)
            task.wait(ZONE_SWITCH_DELAY)
        end
        currentZoneIndex = 1
        if zoneDropdown then
            pcall(function() zoneDropdown:SetValue(1) end)
        end
        return
    end

    local nextZone = MOB_ZONES[nextIdx]
    if fromZone.exitPad then
        safeTeleport(fromZone.exitPad, 3, true)
        task.wait(ZONE_SWITCH_DELAY)
    end
    if not getPlayerRoot() then waitForCharacter() end
    safeTeleport(nextZone.farmPos, 3, true)
    task.wait(ZONE_SWITCH_DELAY)
    currentZoneIndex = nextIdx
    if zoneDropdown then
        pcall(function() zoneDropdown:SetValue(currentZoneIndex) end)
    end
end

-- ===== ОСНОВНОЙ ЦИКЛ ФАРМА =====
task.spawn(function()
    while true do
        if IS_RUNNING and (FARM_MODE == "mobs" or FARM_MODE == "mobs_only") then
            pcall(function()
                if not getPlayerRoot() then waitForCharacter() end
                if FARM_MODE ~= "mobs_only" and findSummerBoss() then
                    farmSummerBoss()
                else
                    local zone = MOB_ZONES[currentZoneIndex]
                    local mobs = findMobsInZone(zone)
                    
                    if #mobs > 0 then
                        farmSingleMob(mobs[1], MOB_TELEPORT_OFFSET, MOB_MAX_WAIT_TIME)
                    else
                        task.wait(2.0)
                        mobs = findMobsInZone(zone)
                        
                        if #mobs > 0 then
                            farmSingleMob(mobs[1], MOB_TELEPORT_OFFSET, MOB_MAX_WAIT_TIME)
                        else
                            if FARM_MODE ~= "mobs_only" and findSummerBoss() then
                                farmSummerBoss()
                            else
                                transitionToNextZone(zone)
                            end
                        end
                    end
                end
            end)
        end
        task.wait(0.1)
    end
end)

-- ===== ОБНОВЛЕНИЕ СТАТУСА БОССА =====
task.spawn(function()
    while true do
        task.wait(2.0)
        local boss = findSummerBoss()
        if boss then
            bossAlive = true
            if bossStatusParagraph then bossStatusParagraph:SetContent("✅ Жив") end
        else
            bossAlive = false
            if bossStatusParagraph then bossStatusParagraph:SetContent("❌ Мёртв") end
        end
    end
end)

-- ===== GUI =====
local Window = Library:CreateWindow({
    Title = "Fire Farm ⚔️",
    SubTitle = "V5.9 • No Nil Errors",
    Size = Vector2.new(650, 620),
    Resize = true,
})

local MainTab = Window:AddTab({ Title = "Главная", Icon = "house" })

MainTab:AddParagraph({
    Title = "Управление фармом",
    Content = "Настройте режим и зону, затем нажмите Старт."
})

statusParagraph = MainTab:AddParagraph({ Title = "Статус", Content = "Остановлен" })
bossStatusParagraph = MainTab:AddParagraph({ Title = "Босс", Content = "Загрузка..." })

mobKillsParagraph = MainTab:AddParagraph({ Title = "Убито мобов", Content = "0" })
bossKillsParagraph = MainTab:AddParagraph({ Title = "Убито боссов", Content = "0" })

MainTab:AddButton({
    Title = "▶️ Старт / Стоп",
    Callback = function()
        if IS_RUNNING then
            IS_RUNNING = false
            restoreAllHitboxes(summerOrigSizes, summerExpParts, summerHighlights)
            restoreAllHitboxes(normOrigSizes, normExpParts, normHighlights)
            if statusParagraph then statusParagraph:SetContent("Остановлен") end
        else
            IS_RUNNING = true
            if statusParagraph then statusParagraph:SetContent("Фарминг") end
        end
    end
})

MainTab:AddParagraph({ Title = "Режим фарма", Content = "" })
MainTab:AddButton({
    Title = "🗡️ Мобы + Босс",
    Callback = function()
        FARM_MODE = "mobs"
        if statusParagraph then statusParagraph:SetContent("Режим: Мобы+Босс") end
    end
})
MainTab:AddButton({
    Title = "🗡️ Только мобы",
    Callback = function()
        FARM_MODE = "mobs_only"
        if statusParagraph then statusParagraph:SetContent("Режим: Только мобы") end
    end
})

local zoneNames = {}
for i, z in ipairs(MOB_ZONES) do zoneNames[i] = z.name end

MainTab:AddDropdown({
    Id = "zone_select",
    Title = "Зона фарма",
    Description = "Выберите зону",
    Options = zoneNames,
    Default = 1,
    Callback = function(value)
        currentZoneIndex = value
        local zoneName = zoneNames[value] or "Неизвестно"
        if statusParagraph then statusParagraph:SetContent("Зона: " .. zoneName) end
    end
})
zoneDropdown = Library.Options.zone_select

MainTab:AddButton({
    Title = "🔄 Сброс чёрного списка",
    Callback = function()
        table.clear(blacklistedMobs)
        Library:Notify({ Title = "Чёрный список", Content = "Очищен.", Duration = 2 })
    end
})

local TeleportsTab = Window:AddTab({ Title = "Телепорты", Icon = "map" })
TeleportsTab:AddParagraph({ Title = "Огненные зоны", Content = "" })
for i, zone in ipairs(MOB_ZONES) do
    TeleportsTab:AddButton({
        Title = zone.name,
        Callback = function()
            safeTeleport(zone.farmPos, 3, true)
        end
    })
end
TeleportsTab:AddParagraph({ Title = "Переходы между зонами (прямые)", Content = "" })
TeleportsTab:AddButton({
    Title = "Element -> Advanced (exitPad)",
    Callback = function() safeTeleport(MOB_ZONES[1].exitPad, 3, true) end
})
TeleportsTab:AddButton({
    Title = "Advanced -> Master (exitPad)",
    Callback = function() safeTeleport(MOB_ZONES[2].exitPad, 3, true) end
})
TeleportsTab:AddParagraph({ Title = "Переходы между зонами (обратные)", Content = "" })
TeleportsTab:AddButton({
    Title = "Advanced -> Element (backwardPad)",
    Callback = function() safeTeleport(MOB_ZONES[2].backwardPad, 3, true) end
})
TeleportsTab:AddButton({
    Title = "Master -> Advanced (backwardPad)",
    Callback = function() safeTeleport(MOB_ZONES[3].backwardPad, 3, true) end
})
TeleportsTab:AddParagraph({ Title = "Summer Event", Content = "" })
TeleportsTab:AddButton({
    Title = "Summer Event Pin",
    Callback = function() safeTeleport(SUMMER_TP_PAD, 3, true) end
})
TeleportsTab:AddButton({
    Title = "Summer Boss Pad",
    Callback = function() safeTeleport(BOSS_TP_PAD, 3, true) end
})

local SettingsTab = Window:AddTab({ Title = "Настройки", Icon = "sliders-horizontal" })

local profileSection = SettingsTab:AddSection("Быстрые профили")
profileSection:AddParagraph({
    Title = "Выберите профиль для быстрой настройки:",
    Content = "🔥 Быстрый — оптимизирован для големов; ☀️ Дневной — баланс; 🌙 Ночной — стабильность."
})

profileSection:AddButton({
    Title = "🔥 Быстрый",
    Callback = function()
        currentProfile = "Быстрый"
        sliders.hp_check_interval:SetValue(0.25)
        sliders.zone_switch_delay:SetValue(0.8)
        sliders.mob_cache_time:SetValue(1.5)
        sliders.boss_max_wait:SetValue(120)
        sliders.boss_wait_after_tp:SetValue(1.0)
        sliders.mob_timeout:SetValue(120)
        if statusParagraph then statusParagraph:SetContent("Профиль: Быстрый") end
        Library:Notify({ Title = "Профиль", Content = "Установлен Быстрый режим.", Duration = 2 })
    end
})

profileSection:AddButton({
    Title = "☀️ Дневной",
    Callback = function()
        currentProfile = "Дневной"
        sliders.hp_check_interval:SetValue(0.3)
        sliders.zone_switch_delay:SetValue(1.0)
        sliders.mob_cache_time:SetValue(1.5)
        sliders.boss_max_wait:SetValue(90)
        sliders.boss_wait_after_tp:SetValue(1.0)
        sliders.mob_timeout:SetValue(120)
        if statusParagraph then statusParagraph:SetContent("Профиль: Дневной") end
        Library:Notify({ Title = "Профиль", Content = "Установлен Дневной режим.", Duration = 2 })
    end
})

profileSection:AddButton({
    Title = "🌙 Ночной",
    Callback = function()
        currentProfile = "Ночной"
        sliders.hp_check_interval:SetValue(1.2)
        sliders.zone_switch_delay:SetValue(3.0)
        sliders.mob_cache_time:SetValue(4.0)
        sliders.boss_max_wait:SetValue(240)
        sliders.boss_wait_after_tp:SetValue(2.5)
        sliders.mob_timeout:SetValue(180)
        if statusParagraph then statusParagraph:SetContent("Профиль: Ночной") end
        Library:Notify({ Title = "Профиль", Content = "Установлен Ночной режим.", Duration = 2 })
    end
})

local section = SettingsTab:AddSection("Задержки (сек)")

local function createSlider(id, title, min, max, default, rounding)
    local slider = section:AddSlider({
        Id = id,
        Title = title,
        Min = min,
        Max = max,
        Default = default,
        Rounding = rounding,
        Callback = function(v)
            if id == "hp_check_interval" then MOB_HP_CHECK_INTERVAL = v end
            if id == "zone_switch_delay" then ZONE_SWITCH_DELAY = v end
            if id == "mob_cache_time" then MOB_CACHE_TIME = v end
            if id == "boss_max_wait" then BOSS_MAX_WAIT_TIME = v end
            if id == "boss_wait_after_tp" then BOSS_WAIT_AFTER_TP = v end
            if id == "mob_timeout" then MOB_MAX_WAIT_TIME = v end
        end
    })
    sliders[id] = slider
end

createSlider("hp_check_interval", "Проверка HP моба", 0.1, 2.0, MOB_HP_CHECK_INTERVAL, 2)
createSlider("zone_switch_delay", "Задержка смены зоны", 0.5, 5.0, ZONE_SWITCH_DELAY, 1)
createSlider("mob_cache_time", "Время кэша мобов", 0.5, 5.0, MOB_CACHE_TIME, 1)
createSlider("boss_max_wait", "Макс. время на босса", 30, 300, BOSS_MAX_WAIT_TIME, 0)
createSlider("boss_wait_after_tp", "Пауза после телепорта", 0.5, 5.0, BOSS_WAIT_AFTER_TP, 1)
createSlider("mob_timeout", "Таймаут на одного моба", 30, 300, MOB_MAX_WAIT_TIME, 0)

MainTab:AddButton({
    Title = "ℹ️ О скрипте",
    Callback = function()
        Library:Notify({
            Title = "Fire Farm V5.9",
            Content = "Исправлена ошибка nil в названиях зон.",
            Duration = 4,
        })
    end
})

Library:Notify({
    Title = "✅ Загружено",
    Content = "Fire Farm V5.9 — ошибка конкатенации устранена.",
    Duration = 3,
})
