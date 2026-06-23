-- Fire Elements Farm + Hitbox Expander (event boss) for Matcha
-- by useraymi (default ON H.E x15 + auto-farm mobs only)

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local LocalPlayer = Players.LocalPlayer

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
-- ИЗМЕНЕНО: Добавлен режим "mobs_only" по умолчанию
local FARM_MODE = "mobs_only"
local currentZoneIndex = 1
local mobsKilled = 0
local seashellsCollected = 0
local shellCache = nil
local shellCacheTime = 0

-- Хитбокс включён по умолчанию, множитель 15
local HITBOX_MULT = 15.0
local TARGET_PART = "Torso"
local PART_TRANSPARENCY = 0.7
local SHOW_HIGHLIGHT = true
local originalSizes = {}
local expandedParts = {}
local expandedMobs = {}
local highlights = {}
local HB_ENABLED = true

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

local function isBossAlive() return findSummerBoss() ~= nil end

-- ИЗМЕНЕНО: В режиме "mobs_only" телепорты не блокируются боссом
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

-- Hitbox Expander (Только для Ивентового Босса)
local TORSO_NAMES = {"Torso", "UpperTorso", "LowerTorso", "HumanoidRootPart", "Chest", "Body"}
local ARM_NAMES = {"Left Arm", "Right Arm", "LeftUpperArm", "RightUpperArm", "LeftLowerArm", "RightLowerArm", "LeftHand", "RightHand", "Arm"}
local LEG_NAMES = {"Left Leg", "Right Leg", "LeftUpperLeg", "RightUpperLeg", "LeftLowerLeg", "RightLowerLeg", "LeftFoot", "RightFoot", "Leg"}

local function getTargetParts(model, target)
    local parts = {}
    if target == "All" then
        for _, part in ipairs(model:GetDescendants()) do
            if part:IsA("BasePart") then table.insert(parts, part) end
        end
    elseif target == "Head" then
        local head = model:FindFirstChild("Head")
        if head then table.insert(parts, head) end
    elseif target == "Torso" then
        for _, name in ipairs(TORSO_NAMES) do
            local part = model:FindFirstChild(name)
            if part then table.insert(parts, part) end
        end
    elseif target == "HumanoidRootPart" then
        local hrp = model:FindFirstChild("HumanoidRootPart")
        if hrp then table.insert(parts, hrp) end
    elseif target == "Arms" then
        for _, name in ipairs(ARM_NAMES) do
            local part = model:FindFirstChild(name)
            if part then table.insert(parts, part) end
        end
    elseif target == "Legs" then
        for _, name in ipairs(LEG_NAMES) do
            local part = model:FindFirstChild(name)
            if part then table.insert(parts, part) end
        end
    end
    return parts
end

local function saveOriginal(part)
    if not originalSizes[part] then
        originalSizes[part] = {size = part.Size, transparency = part.Transparency}
    end
end

local function restorePart(part)
    local orig = originalSizes[part]
    if orig then
        pcall(function()
            part.Size = orig.size
            part.Transparency = orig.transparency
        end)
        originalSizes[part] = nil
    end
end

local function addHighlight(part)
    if not SHOW_HIGHLIGHT or highlights[part] then return end
    pcall(function()
        local hl = Instance.new("Highlight")
        hl.Name = "HBHighlight"
        hl.FillColor = Color3.fromRGB(255, 50, 50)
        hl.FillTransparency = 0.5
        hl.OutlineColor = Color3.fromRGB(255, 255, 255)
        hl.OutlineTransparency = 0
        hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
        hl.Parent = part
        highlights[part] = hl
    end)
end

local function removeHighlight(part)
    if highlights[part] then
        pcall(function() highlights[part]:Destroy() end)
        highlights[part] = nil
    end
end

local function expandPart(part, mult)
    if not part or not part:IsA("BasePart") or expandedParts[part] then return end
    saveOriginal(part)
    pcall(function()
        local orig = originalSizes[part]
        part.Size = Vector3.new(orig.size.X * mult, orig.size.Y * mult, orig.size.Z * mult)
        part.Transparency = PART_TRANSPARENCY
    end)
    addHighlight(part)
    expandedParts[part] = true
end

local function expandMob(mob, mult, target)
    if not mob then return end
    for _, part in ipairs(getTargetParts(mob, target)) do expandPart(part, mult) end
end

local function restoreAllHitboxes()
    for part, _ in pairs(expandedParts) do
        restorePart(part)
        removeHighlight(part)
    end
    expandedParts = {}
    originalSizes = {}
    expandedMobs = {}
    highlights = {}
end

local function refreshHitboxes()
    if not HB_ENABLED then return end

    for mob, _ in pairs(expandedMobs) do
        if not mob.Parent then expandedMobs[mob] = nil end
    end
    for part, _ in pairs(expandedParts) do
        if not part.Parent then
            restorePart(part)
            removeHighlight(part)
            expandedParts[part] = nil
        end
    end

    local boss = findSummerBoss()
    if not boss or not boss:IsA("Model") then
        safeSet("hbStatus", "Boss not found")
        return
    end

    local mult = tonumber(UI.GetValue("hbMult")) or HITBOX_MULT
    local target = UI.GetValue("hbTarget") or TARGET_PART
    local transp = tonumber(UI.GetValue("hbTransp")) or PART_TRANSPARENCY
    PART_TRANSPARENCY = transp

    local currentBossMob = nil
    for mob, _ in pairs(expandedMobs) do currentBossMob = mob; break end

    if currentBossMob ~= boss then
        restoreAllHitboxes()
        expandMob(boss, mult, target)
        expandedMobs[boss] = true
        safeSet("hbStatus", "Expanded | " .. target .. " x" .. mult)
    else
        for part, _ in pairs(expandedParts) do
            pcall(function() part.Transparency = transp end)
        end
    end
end

task.spawn(function()
    while true do
        if HB_ENABLED then
            local ok, err = pcall(refreshHitboxes)
            if not ok then safeSet("hbStatus", "Error: " .. tostring(err)) end
            task.wait(0.5)
        else
            task.wait(2.0)
        end
    end
end)

task.spawn(function()
    while true do
        task.wait(0.5)
        if HB_ENABLED then
            local count = 0
            for _ in pairs(expandedParts) do count = count + 1 end
            safeSet("hbCount", tostring(count))
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

-- ИЗМЕНЕНО: В режиме "mobs_only" босс не прерывает фарм моба
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

-- Auto Boss Checker
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

-- ИЗМЕНЕНО: В режиме "mobs_only" цикл игнорирует босса
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

-- ИЗМЕНЕНО: Добавлен запуск для "mobs_only"
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
    -- ИЗМЕНЕНО: Добавлена кнопка Mobs Only и переименована старая
    main:Button("Mobs Only (Ignore Boss)", function() FARM_MODE = "mobs_only"; safeSet("status", "Mode: Mobs Only") end)
    main:Button("Mobs + Boss (Auto-Boss)", function() FARM_MODE = "mobs"; safeSet("status", "Mode: Mobs + Boss") end)
    main:Button("Shells Only", function() FARM_MODE = "seashells"; safeSet("status", "Mode: Shells") end)

    local tpSection = tab:Section("Teleports (Blocked if Boss Alive)", "Right")
    tpSection:Text("=== SHOP ===")
    tpSection:Button("Sell", function() safeTeleport(TP_POS.Sell, 2.5) end)
    tpSection:Button("Buy", function() safeTeleport(TP_POS.Buy, 2.5) end)
    tpSection:Text("")
    tpSection:Text("=== FIRE ZONES ===")
    tpSection:Button("ElementZones", function() safeTeleport(MOB_ZONES[1].farmPos, 3) end)
    tpSection:Button("TP Pad (Elem->Adv)", function() safeTeleport(MOB_ZONES[1].exitPad, 3) end)
    tpSection:Button("AdvancedFire", function() safeTeleport(MOB_ZONES[2].farmPos, 3) end)
    tpSection:Text("")
    tpSection:Text("=== SUMMER EVENT ===")
    tpSection:Button("Summer Event Pin", function() safeTeleport(SUMMER_TP_PAD, 3) end)
    tpSection:Button("Summer Boss Pad", function() safeTeleport(BOSS_TP_PAD, 3) end)
end)

UI.AddTab("Hitbox Expander", function(tab)
    if not tab then return end
    local main = tab:Section("Control", "Left")
    main:Text("=== HITBOX EXPANDER ===")
    main:Text("Target: SummerEvent26 Boss")
    main:Text("")
    main:Text("=== STATUS ===")
    main:InputText("hbStatus", "", "OFF")
    main:InputText("hbCount", "Parts:", "0")
    main:Text("")
    main:Button("Toggle ON / OFF", function()
        HB_ENABLED = not HB_ENABLED
        if HB_ENABLED then
            safeSet("hbStatus", "ON")
            refreshHitboxes()
        else
            safeSet("hbStatus", "OFF")
            restoreAllHitboxes()
            safeSet("hbCount", "0")
        end
    end)
    main:Text("")
    main:Text("=== SIZE ===")
    main:InputText("hbMult", "Multiplier:", tostring(HITBOX_MULT))
    main:Button("Apply Size", function()
        local val = tonumber(UI.GetValue("hbMult"))
        if val and val > 0 then
            HITBOX_MULT = val
            restoreAllHitboxes()
            if HB_ENABLED then task.wait(0.1); refreshHitboxes() end
            safeSet("hbStatus", "ON | x" .. val)
        end
    end)
    main:Text("")
    main:Text("=== TARGET PART ===")
    main:Button("Target: Torso", function() TARGET_PART = "Torso"; safeSet("hbTarget", "Torso"); if HB_ENABLED then restoreAllHitboxes(); task.wait(0.1); refreshHitboxes() end end)
    main:Button("Target: HumanoidRootPart", function() TARGET_PART = "HumanoidRootPart"; safeSet("hbTarget", "HumanoidRootPart"); if HB_ENABLED then restoreAllHitboxes(); task.wait(0.1); refreshHitboxes() end end)
    main:Button("Target: All", function() TARGET_PART = "All"; safeSet("hbTarget", "All"); if HB_ENABLED then restoreAllHitboxes(); task.wait(0.1); refreshHitboxes() end end)
    main:Button("Target: Head", function() TARGET_PART = "Head"; safeSet("hbTarget", "Head"); if HB_ENABLED then restoreAllHitboxes(); task.wait(0.1); refreshHitboxes() end end)
    main:Button("Target: Arms", function() TARGET_PART = "Arms"; safeSet("hbTarget", "Arms"); if HB_ENABLED then restoreAllHitboxes(); task.wait(0.1); refreshHitboxes() end end)
    main:Button("Target: Legs", function() TARGET_PART = "Legs"; safeSet("hbTarget", "Legs"); if HB_ENABLED then restoreAllHitboxes(); task.wait(0.1); refreshHitboxes() end end)
end)

safeSet("status", "Waiting")
safeSet("mobStatus", "-")
safeSet("mobKills", "0")
safeSet("shellCount", "0")
safeSet("zoneDisplay", MOB_ZONES[1].name)
safeSet("bossInfo", "Loading...")
safeSet("hbStatus", "OFF")
safeSet("hbCount", "0")
safeSet("hbMult", tostring(HITBOX_MULT))
safeSet("hbTarget", TARGET_PART)
safeSet("hbTransp", tostring(PART_TRANSPARENCY))

-- Автоматическое включение хитбокса
task.spawn(function()
    task.wait(0.5)
    if HB_ENABLED then
        refreshHitboxes()
        safeSet("hbStatus", "Expanded | " .. TARGET_PART .. " x" .. HITBOX_MULT)
    end
end)

-- Автоматический запуск фарма (режим Mobs Only по умолчанию)
task.spawn(startFarming)

print("by useraymi (default ON x15, auto-farm mobs_only)")
