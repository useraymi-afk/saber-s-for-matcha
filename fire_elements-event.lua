-- Fire Elements Farm + Hitbox Expander (event boss) for Matcha
-- by useraymi (default ON H.E x15 + auto-farm mobs only)

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local LocalPlayer = Players.LocalPlayer

-- [ANTI-AFK] (Адаптировано для Matcha - без события Idled)
task.spawn(function()
    local VirtualUser = game:GetService("VirtualUser")
    while true do
        task.wait(30) -- Каждые 30 секунд симулируем активность
        pcall(function()
            VirtualUser:CaptureController()
            VirtualUser:ClickButton2(Vector2.new())
        end)
    end
end)

-- Config
local SEARCH_PATH = "Workspace.Gameplay.RegionsLoaded.SummerEvent26.CurrencyPickup.CurrencyHolder"
local TARGET_SIZE = Vector3.new(4.04, 3.6, 1.98)
local SIZE_TOLERANCE = 0.5
local TELEPORT_OFFSET = 2.0
local COLLECT_DELAY = 0.35
local COLLECT_VERIFY_DELAY = 0.15
local LOOP_DELAY = 0.05
local SHELL_CACHE_TIME = 0.5

local BOSS_HOLDER_PATH = "ReplicatedStorage.HiddenRegions.SummerEvent26.Boss.BossHolder"
local SUMMER_TP_PAD = Vector3.new(609.14, 208.54, 74.28)
local BOSS_TP_PAD = Vector3.new(1030.07, 89.31, 1530.62)
local BOSS_WAIT_AFTER_TP = 2.0
local BOSS_FARM_OFFSET = 5.0 
local BOSS_MAX_WAIT_TIME = 120

-- НАСТРОЙКИ ХИТБОКСОВ (Скрыты, меняй только тут)
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
    },
}

local MOB_PRIORITY = {"Fire Boss", "Fire Golem"}
local MOB_TELEPORT_OFFSET = 4.0
local MOB_HP_CHECK_INTERVAL = 0.1
local MOB_MAX_WAIT_TIME = 90
local MOB_CHASE_DISTANCE = 8
local ZONE_SWITCH_DELAY = 1.0

local TP_POS = {
    Sell = Vector3.new(760.59, 82.74, 1313.59),
    Buy = Vector3.new(450.32, 184.37, 50.05),
}

-- State
local IS_RUNNING = false
local FARM_MODE = "mobs_only"
local currentZoneIndex = 1
local mobsKilled = 0
local seashellsCollected = 0
local shellCache = nil
local shellCacheTime = 0

-- [1] SUMMER BOSS H.E. STATE
local summerOrigSizes = {}
local summerExpParts = {}
local summerExpMobs = {}
local summerHighlights = {}

-- [2] NORMAL BOSS H.E. STATE
local normOrigSizes = {}
local normExpParts = {}
local normExpMobs = {}
local normHighlights = {}

local bossDeathTime = nil
local bossRespawnTime = 180

-- Utils
local function safeSet(key, val)
    pcall(function() UI.SetValue(key, tostring(val)) end)
end

local function findObject(path)
    local parts = {}
    for part in string.gmatch(path, "[^%.]+") do table.insert(parts, part) end
    local current = game
    for i = 1, #parts do
        if current then current = current:FindFirstChild(parts[i]) else return nil end
    end
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

-- Mob HP
local function getMobHP(model)
    if not model then return nil, nil end
    local hum = model:FindFirstChildOfClass("Humanoid")
    if hum then return hum.Health, hum.MaxHealth end
    local attrHp = model:GetAttribute("Health")
    if attrHp and type(attrHp) == "number" then
        return attrHp, model:GetAttribute("MaxHealth") or attrHp
    end
    for _, d in ipairs(model:GetDescendants()) do
        if d:IsA("TextLabel") and d.Text then
            local hpStr, maxHpStr = d.Text:match("(%d+)%s*/%s*(%d+)")
            if hpStr and maxHpStr then return tonumber(hpStr), tonumber(maxHpStr) end
        end
    end
    return nil, nil
end

local function isMobAlive(model)
    if not model or not model.Parent then return false end
    local root = model:FindFirstChild("HumanoidRootPart")
    if not root or not root.Parent then return false end
    local hp = getMobHP(model)
    if hp ~= nil then return hp > 0 end
    return true
end

-- Boss Detection
local function findSummerBoss()
    local holder = findObject(BOSS_HOLDER_PATH)
    if not holder then holder = findObject("Workspace.Gameplay.RegionsLoaded.SummerEvent26.Boss.BossHolder") end
    if not holder then return nil end
    local bossModel = holder:FindFirstChild("Boss")
    if bossModel and bossModel:IsA("Model") then
        local root = bossModel:FindFirstChild("HumanoidRootPart")
        if root then
            local hp = getMobHP(bossModel)
            if hp == nil or hp > 0 then return bossModel end
        end
    end
    for _, obj in ipairs(holder:GetChildren()) do
        if obj:IsA("Model") then
            local root = obj:FindFirstChild("HumanoidRootPart")
            if root then
                local hp = getMobHP(obj)
                if hp == nil or hp > 0 then return obj end
            end
        end
    end
    return nil
end

local function findNormalBoss()
    local holder = findObject("Workspace.Gameplay.Boss.BossHolder")
    if not holder then return nil end
    local bossModel = holder:FindFirstChild("Boss")
    if bossModel and bossModel:IsA("Model") then
        local root = bossModel:FindFirstChild("HumanoidRootPart")
        if root then
            local hp = getMobHP(bossModel)
            if hp == nil or hp > 0 then return bossModel end
        end
    end
    return nil
end

local function isBossAlive() return findSummerBoss() ~= nil end

local function safeTeleport(pos, offset, forceAllow)
    if FARM_MODE ~= "mobs_only" and not forceAllow and isBossAlive() then
        safeSet("status", "⚠️ TP BLOCKED!")
        safeSet("mobStatus", "Boss is alive! Kill him first.")
        return false
    end
    offset = offset or 0
    local root = getPlayerRoot()
    if not root then return false end
    local targetPos = pos + Vector3.new(0, offset, 0)
    local success = pcall(function()
        root.Velocity = Vector3.new(0, 0, 0)
        root.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
        local bv = root:FindFirstChild("BodyVelocity")
        if bv then bv:Destroy() end
        root.CFrame = CFrame.new(targetPos.X, targetPos.Y, targetPos.Z)
    end)
    return success
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

-- Boss Timer
task.spawn(function()
    while true do
        task.wait(0.5)
        local boss = findSummerBoss()
        if boss then
            local hp, maxHp = getMobHP(boss)
            local timeLeft = boss:GetAttribute("TimeLeft")
            bossDeathTime = nil
            local timeStr = ""
            if timeLeft and timeLeft > 0 then
                local mins = math.floor(timeLeft / 60)
                local secs = math.floor(timeLeft % 60)
                timeStr = " | Time: " .. mins .. "m " .. secs .. "s"
            end
            safeSet("bossInfo", "ALIVE | HP: " .. (hp or 0) .. " / " .. (maxHp or 0) .. timeStr)
        else
            if not bossDeathTime then bossDeathTime = tick() end
            local elapsed = tick() - bossDeathTime
            local remaining = math.max(0, bossRespawnTime - elapsed)
            local mins = math.floor(remaining / 60)
            local secs = math.floor(remaining % 60)
            safeSet("bossInfo", string.format("DEAD | Respawn in %d:%02d", mins, secs))
        end
    end
end)

-- ======================================================
-- БАЗОВАЯ ЛОГИКА ХИТБОКСОВ (Строго HRP)
-- ======================================================
local function saveOriginal(part, tbl)
    if not tbl[part] then
        tbl[part] = {size = part.Size, transparency = part.Transparency}
    end
end

local function restorePart(part, tbl)
    local orig = tbl[part]
    if orig then
        pcall(function()
            part.Size = orig.size
            part.Transparency = orig.transparency
        end)
        tbl[part] = nil
    end
end

local function addHighlight(part, tbl, color)
    if tbl[part] then return end
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
    if not part or not part:IsA("BasePart") or expTbl[part] then return end
    saveOriginal(part, origTbl)
    pcall(function()
        local orig = origTbl[part]
        part.Size = Vector3.new(orig.size.X * mult, orig.size.Y * mult, orig.size.Z * mult)
        part.Transparency = 1 -- HRP всегда невидим
    end)
    if color then
        addHighlight(part, hlTbl, color)
    end
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

-- Фоновый цикл Летнего босса
task.spawn(function()
    while true do
        task.wait(0.5)
        for mob, _ in pairs(summerExpMobs) do
            if not mob.Parent then summerExpMobs[mob] = nil end
        end
        for part, _ in pairs(summerExpParts) do
            if not part.Parent then
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
    end
end)

-- Фоновый цикл Обычного босса
task.spawn(function()
    while true do
        task.wait(0.5)
        for mob, _ in pairs(normExpMobs) do
            if not mob.Parent then normExpMobs[mob] = nil end
        end
        for part, _ in pairs(normExpParts) do
            if not part.Parent then
                restorePart(part, normOrigSizes)
                removeHighlight(part, normHighlights)
                normExpParts[part] = nil
            end
        end

        local boss = findNormalBoss()
        if boss then
            local currentBossMob = nil
            for mob, _ in pairs(normExpMobs) do currentBossMob = mob; break end
            if currentBossMob ~= boss then
                restoreAllHitboxes(normOrigSizes, normExpParts, normHighlights)
                local hrp = boss:FindFirstChild("HumanoidRootPart")
                if hrp then
                    expandHRP(hrp, HB_MULT, normOrigSizes, normExpParts, normHighlights, nil)
                    normExpMobs[boss] = true
                end
            end
        end
    end
end)

-- Farm Logic
local function extractMobData(model, zoneName)
    if not model or not model:IsA("Model") then return nil end
    local root = model:FindFirstChild("HumanoidRootPart")
    if not root then return nil end
    local hp = getMobHP(model)
    if hp and hp <= 0 then return nil end
    local pPos = getPlayerPos()
    local dist = pPos and (root.Position - pPos).Magnitude or 0
    local priority = 99
    for i = 1, #MOB_PRIORITY do
        if model.Name:find(MOB_PRIORITY[i]) then priority = i; break end
    end
    return {model = model, root = root, pos = root.Position, dist = dist, hp = hp or 0, maxHp = 0, name = model.Name, zone = zoneName or "?", priority = priority}
end

local function findMobsInZone(zone)
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
    return results
end

local function farmSingleMob(mobData, offset, maxWait)
    local mob = mobData.model
    local mobName = mobData.name
    local mobZone = mobData.zone
    local startTime = tick()
    local lastFollowTp = 0
    local tpOffset = offset or MOB_TELEPORT_OFFSET
    local waitTime = maxWait or MOB_MAX_WAIT_TIME

    if not getPlayerRoot() then waitForCharacter() end
    safeSet("status", "Killing: " .. mobName .. " [" .. mobZone .. "]")
    safeTeleport(mobData.pos, tpOffset, true)
    task.wait(0.5)

    while IS_RUNNING and isMobAlive(mob) do
        if FARM_MODE ~= "mobs_only" and isBossAlive() then
            safeSet("status", "⚠️ Boss Spawned! Interrupting...")
            break
        end
        if tick() - startTime > waitTime then
            safeSet("mobStatus", mobName .. " | TIMEOUT")
            break
        end
        if mobData.root and mobData.root.Parent then
            local mobPos = mobData.root.Position
            mobData.pos = mobPos
            local root = getPlayerRoot()
            if root then
                local distToMob = (mobPos - root.Position).Magnitude
                local chaseDist = (mobName:find("Boss") and 12) or MOB_CHASE_DISTANCE
                if distToMob > chaseDist then
                    local now = tick()
                    if now - lastFollowTp > 0.2 then
                        safeTeleport(mobPos, tpOffset, true)
                        lastFollowTp = now
                    end
                end
            else
                waitForCharacter()
            end
        end
        local currentHp = getMobHP(mob)
        if currentHp then
            safeSet("mobStatus", string.format("%s | HP:%d | %s", mobName, currentHp, mobZone))
        else
            safeSet("mobStatus", mobName .. " | alive | " .. mobZone)
        end
        task.wait(MOB_HP_CHECK_INTERVAL)
    end
    if not isMobAlive(mob) then
        mobsKilled = mobsKilled + 1
        safeSet("mobKills", tostring(mobsKilled))
        safeSet("mobStatus", mobName .. " DEAD | " .. mobsKilled .. " kills")
    end
end

local function farmSummerBoss()
    safeSet("status", "Checking Summer Boss...")
    local boss = findSummerBoss()
    if not boss then return false end
    if not getPlayerRoot() then waitForCharacter() end
    safeSet("status", "🔒 BOSS PRIORITY | TP to Event...")
    safeSet("mobStatus", "Teleporting to Summer Event...")
    safeTeleport(SUMMER_TP_PAD, 3, true)
    task.wait(BOSS_WAIT_AFTER_TP)
    safeSet("mobStatus", "Teleporting to Boss...")
    safeTeleport(BOSS_TP_PAD, 3, true)
    task.wait(1.5)
    boss = findSummerBoss()
    if not boss then
        safeSet("mobStatus", "Summer Boss lost after TP")
        return false
    end
    local bossRoot = boss:FindFirstChild("HumanoidRootPart")
    if not bossRoot then return false end
    local bossData = extractMobData(boss, "SummerEvent")
    if bossData then
        safeSet("zoneDisplay", "SUMMER BOSS (PRIORITY)")
        safeSet("status", "⚔️ KILLING BOSS ⚔️")
        safeTeleport(bossRoot.Position, BOSS_FARM_OFFSET, true)
        task.wait(0.5)
        local startTime = tick()
        while IS_RUNNING and isMobAlive(boss) do
            if tick() - startTime > BOSS_MAX_WAIT_TIME then break end
            local currentHp = getMobHP(boss)
            if currentHp then safeSet("mobStatus", string.format("BOSS HP: %d", currentHp)) end
            local myPos = getPlayerPos()
            if myPos and (bossRoot.Position - myPos).Magnitude > 15 then
                safeTeleport(bossRoot.Position, BOSS_FARM_OFFSET, true)
            end
            task.wait(0.2)
        end
        if not isMobAlive(boss) then
            safeSet("status", "✅ BOSS KILLED!")
            safeSet("mobStatus", "Waiting for respawn...")
            bossDeathTime = tick()
            return true
        end
    end
    return false
end

task.spawn(function()
    while true do
        task.wait(30)
        if IS_RUNNING and FARM_MODE == "mobs" and isBossAlive() then
            safeSet("status", "️ AUTO-CHECK: Boss Found!")
            farmSummerBoss()
        end
    end
end)

-- Main Loops
local function transitionToNextZone(fromZone)
    local nextIdx = currentZoneIndex + 1
    if nextIdx > #MOB_ZONES then nextIdx = 1 end
    local nextZone = MOB_ZONES[nextIdx]
    safeSet("status", fromZone.name .. " cleared! Switching to " .. nextZone.name)
    safeSet("mobStatus", "Moving to " .. nextZone.name)
    if fromZone.exitPad then
        safeTeleport(fromZone.exitPad, 3, true)
        task.wait(2.0)
    end
    if not getPlayerRoot() then waitForCharacter() end
    safeTeleport(nextZone.farmPos, 3, true)
    task.wait(ZONE_SWITCH_DELAY)
    currentZoneIndex = nextIdx
    safeSet("zoneDisplay", nextZone.name)
end

local function mobFarmingLoop()
    while IS_RUNNING do
        if not getPlayerRoot() then waitForCharacter() end
        if FARM_MODE ~= "mobs_only" and isBossAlive() then
            farmSummerBoss()
            task.wait(1.0)
        else
            local zone = MOB_ZONES[currentZoneIndex]
            local mobs = findMobsInZone(zone)
            if #mobs > 0 then
                while IS_RUNNING and #mobs > 0 do
                    if FARM_MODE ~= "mobs_only" and isBossAlive() then break end
                    farmSingleMob(mobs[1], MOB_TELEPORT_OFFSET, MOB_MAX_WAIT_TIME)
                    if not IS_RUNNING then break end
                    mobs = findMobsInZone(zone)
                end
            else
                safeSet("status", "No mobs in " .. zone.name)
                safeSet("mobStatus", "Checking next zone...")
                if FARM_MODE ~= "mobs_only" and isBossAlive() then
                    farmSummerBoss()
                else
                    transitionToNextZone(zone)
                end
            end
        end
        task.wait(0.1)
    end
end

local function checkSize(part)
    if not part or not part:IsA("BasePart") then return false end
    local s = part.Size
    return math.abs(s.X - TARGET_SIZE.X) <= SIZE_TOLERANCE
       and math.abs(s.Y - TARGET_SIZE.Y) <= SIZE_TOLERANCE
       and math.abs(s.Z - TARGET_SIZE.Z) <= SIZE_TOLERANCE
end

local function findAllSeashells()
    local now = os.clock()
    if shellCache and (now - shellCacheTime) < SHELL_CACHE_TIME then return shellCache end
    local results = {}
    local container = findObject(SEARCH_PATH)
    if not container then shellCache = results; shellCacheTime = now; return results end
    for _, obj in ipairs(container:GetDescendants()) do
        if obj:IsA("BasePart") and obj.Name:find("Seashell") and checkSize(obj) then
            local pos = obj.Position
            local parent = obj.Parent
            if parent and parent:IsA("Model") and parent.PrimaryPart then pos = parent.PrimaryPart.Position end
            table.insert(results, { pos = pos, obj = obj })
        end
    end
    shellCache = results
    shellCacheTime = now
    return results
end

local function isValidShell(data) return data and data.obj and data.obj.Parent ~= nil end

local function farmSeashellsOnce()
    local shells = findAllSeashells()
    if #shells == 0 then return 0 end
    local pPos = getPlayerPos()
    if pPos then
        for i = 1, #shells do shells[i].dist = (shells[i].pos - pPos).Magnitude end
        table.sort(shells, function(a, b) return a.dist < b.dist end)
    end
    local collected = 0
    for i = 1, #shells do
        if not IS_RUNNING then return collected end
        local data = shells[i]
        if isValidShell(data) then
            local currentPos = getPlayerPos()
            if currentPos then
                local distToShell = (data.pos - currentPos).Magnitude
                if distToShell < 3 then
                    task.wait(COLLECT_VERIFY_DELAY)
                    if not isValidShell(data) then
                        collected = collected + 1
                        seashellsCollected = seashellsCollected + 1
                        safeSet("shellCount", tostring(seashellsCollected))
                        shellCache = nil
                    end
                else
                    if safeTeleport(data.pos, TELEPORT_OFFSET, true) then
                        task.wait(COLLECT_VERIFY_DELAY)
                        if not isValidShell(data) then
                            collected = collected + 1
                            seashellsCollected = seashellsCollected + 1
                            safeSet("shellCount", tostring(seashellsCollected))
                            shellCache = nil
                        else
                            task.wait(COLLECT_DELAY)
                            if not isValidShell(data) then
                                collected = collected + 1
                                seashellsCollected = seashellsCollected + 1
                                safeSet("shellCount", tostring(seashellsCollected))
                                shellCache = nil
                            end
                        end
                    end
                end
            end
        end
    end
    if collected > 0 then shellCache = nil end
    return collected
end

local function shellFarmingLoop()
    while IS_RUNNING do
        if not getPlayerRoot() then waitForCharacter() end
        safeSet("status", "Farming shells")
        local collected = farmSeashellsOnce()
        if collected == 0 then
            safeSet("status", "No shells | Waiting...")
            task.wait(1.0)
        end
        task.wait(LOOP_DELAY)
    end
end

function startFarming()
    if IS_RUNNING then return end
    IS_RUNNING = true
    safeSet("status", "Running")
    if FARM_MODE == "mobs" or FARM_MODE == "mobs_only" then
        task.spawn(function()
            if not getPlayerRoot() then waitForCharacter() end
            local zone = MOB_ZONES[currentZoneIndex]
            safeSet("status", "TP to " .. zone.name .. "...")
            safeTeleport(zone.farmPos, 3, true)
            task.wait(1.0)
            mobFarmingLoop()
        end)
    elseif FARM_MODE == "seashells" then
        task.spawn(shellFarmingLoop)
    end
end

function stopFarming()
    if not IS_RUNNING then return end
    IS_RUNNING = false
    safeSet("status", "Stopped")
    safeSet("mobStatus", "-")
end

-- UI
UI.AddTab("Fire Farm", function(tab)
    local main = tab:Section("Control", "Left")
    main:Text("=== STATUS ===")
    main:InputText("status", "", "Waiting")
    main:InputText("mobStatus", "", "-")
    main:Text("")
    main:Text("=== SUMMER BOSS ===")
    main:InputText("bossInfo", "Boss:", "Loading...")
    main:Text("")
    main:Text("=== COUNTERS ===")
    main:InputText("mobKills", "Kills:", "0")
    main:InputText("shellCount", "Shells:", "0")
    main:Text("")
    main:Text("=== ZONE ===")
    main:InputText("zoneDisplay", "Zone:", MOB_ZONES[1].name)
    main:Text("")
    main:Text("=== CONTROL ===")
    main:Button("Start / Stop", function() if IS_RUNNING then stopFarming() else startFarming() end end)
    main:Text("")
    main:Text("=== MODE ===")
    main:Button("Mobs Only (Ignore Boss)", function() FARM_MODE = "mobs_only"; safeSet("status", "Mode: Mobs Only") end)
    main:Button("Mobs + Boss (Auto-Boss)", function() FARM_MODE = "mobs"; safeSet("status", "Mode: Mobs + Boss") end)
    main:Button("Shells Only", function() FARM_MODE = "seashells"; safeSet("status", "Mode: Shells") end)

    local tpSection = tab:Section("Teleports", "Right")
    tpSection:Text("=== SHOP ===")
    tpSection:Button("Sell", function() safeTeleport(TP_POS.Sell, 2.5) end)
    tpSection:Button("Buy", function() safeTeleport(TP_POS.Buy, 2.5) end)
    tpSection:Text("")
    tpSection:Text("=== FIRE ZONES ===")
    tpSection:Button("ElementZones", function() safeTeleport(MOB_ZONES[1].farmPos, 3) end)
    tpSection:Button("TP Pad (Elem->Adv)", function() safeTeleport(MOB_ZONES[1].exitPad, 3) end)
    tpSection:Button("MasterFire TP Pad", function() safeTeleport(MOB_ZONES[2].exitPad, 3) end)
    tpSection:Text("")
    tpSection:Text("=== SUMMER EVENT ===")
    tpSection:Button("Summer Event Pin", function() safeTeleport(SUMMER_TP_PAD, 3) end)
    tpSection:Button("Summer Boss Pad", function() safeTeleport(BOSS_TP_PAD, 3) end)
end)

safeSet("status", "Waiting")
safeSet("mobStatus", "-")
safeSet("mobKills", "0")
safeSet("shellCount", "0")
safeSet("zoneDisplay", MOB_ZONES[1].name)
safeSet("bossInfo", "Loading...")

task.spawn(startFarming)
print("by useraymi | H.E. Built-in (HRP x" .. HB_MULT .. ") | Anti-AFK Enabled")
