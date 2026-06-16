-- Pet Simulator 99 - L3y Hub (Auto Rank & Farm)
-- Mobile compatible (no keybinds)

local player = game:GetService("Players").LocalPlayer
local runService = game:GetService("RunService")
local workspace = game:GetService("Workspace")
local tweenService = game:GetService("TweenService")
local userInput = game:GetService("UserInputService")
local virtualInput = game:GetService("VirtualInputManager")

-- ===== CONFIGURATION =====
local CONFIG = {
    autoRank = true,
    autoBreak = true,
    autoHatch = true,
    autoConsume = true,
    autoCollect = true,
    autoMakePets = true,
    autoAreaQuests = true,
    autoDiamonds = true,
    useItems = true,
    clickDelay = 0.03,
    hatchDelay = 0.5,
    useDelay = 0.3,
    stop = false,
}

-- ===== QUEST TYPES =====
local QUEST_TYPES = {
    collect_potions = "Collect Potions",
    collect_enchants = "Collect Enchants",
    use_potions = "Use Potions",
    breakables = "Breakables",
    diamond_breakables = "Diamond Breakables",
    coin_jars = "Break Coin Jars",
    comets = "Break Comets",
    mini_chests = "Break Mini Chests",
    eggs = "Eggs",
    rare_eggs = "Rare Eggs",
    make_golden = "Make Golden Pets",
    make_rainbow = "Make Rainbow Pets",
    diamonds = "Diamonds",
    lucky_blocks = "Break Lucky Block Event",
    pinatas = "Break Pinata",
    superior_chests = "Break Superior Chests",
    area_quest = "Area Quest",
}

-- ===== INPUT WRAPPER (fallback to mouse1click) =====
local function clickAt(x, y)
    pcall(function()
        if syn and syn.input then syn.input:SendMouseButtonEvent(x, y, 0, true, 0) end
    end)
    pcall(function()
        if syn and syn.input then syn.input:SendMouseButtonEvent(x, y, 0, false, 0) end
    end)
    pcall(function() mouse1click(x, y) end)
end

local function keyPress(key)
    pcall(function()
        if syn and syn.input then syn.input:SendKeyEvent(true, key, false, nil) end
    end)
    task.wait(0.05)
    pcall(function()
        if syn and syn.input then syn.input:SendKeyEvent(false, key, false, nil) end
    end)
    pcall(function() keypress(key) end)
end

-- ===== ROBUST QUEST DETECTION =====
local function getQuests()
    local quests = {}
    local playerGui = player:FindFirstChild("PlayerGui")
    if not playerGui then return quests end

    for _, child in ipairs(playerGui:GetDescendants()) do
        if child:IsA("TextLabel") or child:IsA("TextButton") or child:IsA("TextBox") then
            local text = child.Text or ""
            for key, name in pairs(QUEST_TYPES) do
                if text:find(name) or text:find(key:gsub("_", " ")) then
                    local quest = {raw = text, type = key}
                    local count = text:match("(%d+)/%d+") or text:match("(%d+)$")
                    quest.count = count and tonumber(count) or 0
                    quest.target = text:match("([%w%s]+)$") or ""
                    table.insert(quests, quest)
                    break
                end
            end
            if text:find("Obby") or text:find("Minefield") or text:find("Fishing") or
               text:find("Digsite") or text:find("Fuse") or text:find("Plant") or
               text:find("Cart Ride") or text:find("Atlantis") or text:find("Classic") then
                table.insert(quests, {raw = text, type = "area_quest", count = 0, target = text})
            end
        end
    end
    return quests
end

-- ===== BEST AREA DETECTION =====
local bestAreaCache = nil
local lastAreaScan = 0

local function getBestArea()
    if os.clock() - lastAreaScan < 5 and bestAreaCache then
        return bestAreaCache, bestAreaCache.num
    end
    local highest = nil
    local highestNum = 0
    for _, child in ipairs(workspace:GetChildren()) do
        if child:IsA("Model") and child.Name:match("Area") then
            local num = tonumber(child.Name:match("%d+")) or 0
            if num > highestNum then
                highestNum = num
                highest = child
            end
        end
    end
    bestAreaCache = highest
    bestAreaCache.num = highestNum
    lastAreaScan = os.clock()
    return highest, highestNum
end

-- ===== AREA TELEPORT (improved) =====
local function teleportToBestArea()
    if not CONFIG.autoRank or CONFIG.stop then return false end
    local best, num = getBestArea()
    if not best then return false end

    local currentArea = workspace:FindFirstChild("CurrentArea")
    if currentArea and currentArea:IsA("StringValue") then
        if currentArea.Value == best.Name then return true end
    end

    local playerGui = player:FindFirstChild("PlayerGui")
    if playerGui then
        for _, btn in ipairs(playerGui:GetDescendants()) do
            if btn:IsA("TextButton") and (btn.Name:match("Teleport") or btn.Text:match("Teleport")) then
                pcall(function() btn:FireClick() end)
                task.wait(1)
                if currentArea and currentArea.Value == best.Name then return true end
            end
        end
    end

    local spawn = best:FindFirstChild("SpawnLocation")
    if spawn then
        local char = player.Character
        if char and char:FindFirstChild("HumanoidRootPart") then
            local hrp = char.HumanoidRootPart
            local dist = (hrp.Position - spawn.Position).Magnitude
            if dist > 200 then
                local hum = char:FindFirstChild("Humanoid")
                if hum then
                    hum:MoveTo(spawn.Position)
                    task.wait(2)
                end
            end
        end
    end
    return true
end

-- ===== OBJECT CLICK WITH RETRY =====
local function clickObject(obj, retries)
    retries = retries or 3
    for i = 1, retries do
        if not obj then return false end
        local success, err = pcall(function()
            local clickDetector = obj:FindFirstChild("ClickDetector")
            if clickDetector then
                clickDetector:FireClick(player.Mouse)
                return true
            end
        end)
        if success then
            task.wait(CONFIG.clickDelay)
            return true
        end
        task.wait(0.2)
    end
    return false
end

-- ===== ITEM USE WITH EXACT MATCHING =====
local function useItem(pattern, exact)
    for _, item in ipairs(player.Backpack:GetChildren()) do
        local name = item.Name
        if exact then
            if name == pattern then
                pcall(function() item:FireServer("Use") end)
                task.wait(CONFIG.useDelay)
                return true
            end
        else
            if name:match(pattern) then
                pcall(function() item:FireServer("Use") end)
                task.wait(CONFIG.useDelay)
                return true
            end
        end
    end
    return false
end

-- ===== QUEST ACTIONS =====
local breakableCache = {}

local function getBreakablesInArea(area)
    if not area then return {} end
    local key = area.Name
    if breakableCache[key] and os.clock() - breakableCache[key].time < 2 then
        return breakableCache[key].list
    end
    local list = {}
    for _, obj in ipairs(area:GetDescendants()) do
        if obj:IsA("BasePart") and (obj.Name:match("Break") or obj.Name:match("Crate") or obj.Name:match("Chest")) then
            table.insert(list, obj)
        end
    end
    breakableCache[key] = {list = list, time = os.clock()}
    return list
end

local function doBreakables()
    teleportToBestArea()
    local bestArea = getBestArea()
    if not bestArea then return false end
    if CONFIG.useItems then useItem("TNT") end
    local breakables = getBreakablesInArea(bestArea)
    for _, obj in ipairs(breakables) do
        if clickObject(obj) then return true end
    end
    return false
end

local function doDiamondBreakables()
    teleportToBestArea()
    for _, obj in ipairs(workspace:GetDescendants()) do
        if obj:IsA("BasePart") and (obj.Name:match("Diamond") or obj.Name:match("Crystal")) then
            if clickObject(obj) then return true end
        end
    end
    return false
end

local function doCoinJars()
    teleportToBestArea()
    for _, obj in ipairs(workspace:GetDescendants()) do
        if obj:IsA("BasePart") and obj.Name:match("Coin") and obj.Name:match("Jar") then
            if clickObject(obj) then return true end
        end
    end
    return false
end

local function doComets()
    teleportToBestArea()
    for _, obj in ipairs(workspace:GetDescendants()) do
        if obj:IsA("BasePart") and obj.Name:match("Comet") then
            if clickObject(obj) then return true end
        end
    end
    return false
end

local function doMiniChests()
    teleportToBestArea()
    for _, obj in ipairs(workspace:GetDescendants()) do
        if obj:IsA("BasePart") and obj.Name:match("Mini") and obj.Name:match("Chest") then
            if clickObject(obj) then return true end
        end
    end
    return false
end

local function doHatchEggs()
    teleportToBestArea()
    local bestArea = getBestArea()
    if not bestArea then return false end
    for _, obj in ipairs(bestArea:GetDescendants()) do
        if obj:IsA("Model") and obj.Name:match("Egg") then
            local clickDetector = obj:FindFirstChild("ClickDetector")
            if clickDetector then
                pcall(function() clickDetector:FireClick(player.Mouse) end)
                task.wait(CONFIG.hatchDelay)
                clickAt(0,0)
                return true
            end
        end
    end
    return false
end

local function doRareEggs() return doHatchEggs() end

local function doMakeGolden()
    teleportToBestArea()
    local bestArea = getBestArea()
    if not bestArea then return false end
    for _, obj in ipairs(bestArea:GetDescendants()) do
        if obj:IsA("Model") and obj.Name:match("Golden") then
            if clickObject(obj) then return true end
        end
    end
    return false
end

local function doMakeRainbow()
    teleportToBestArea()
    local bestArea = getBestArea()
    if not bestArea then return false end
    for _, obj in ipairs(bestArea:GetDescendants()) do
        if obj:IsA("Model") and obj.Name:match("Rainbow") then
            if clickObject(obj) then return true end
        end
    end
    return false
end

local function doDiamonds() return doBreakables() end

local function doCollectPotions()
    teleportToBestArea()
    for _, obj in ipairs(workspace:GetDescendants()) do
        if obj:IsA("BasePart") and (obj.Name:match("Potion") or obj.Name:match("Free")) then
            if clickObject(obj) then return true end
        end
    end
    for _, obj in ipairs(workspace:GetDescendants()) do
        if obj:IsA("Model") and obj.Name:match("Vending") and obj.Name:match("Potion") then
            local clickDetector = obj:FindFirstChild("ClickDetector")
            if clickDetector then
                pcall(function() clickDetector:FireClick(player.Mouse) end)
                task.wait(0.5)
                return true
            end
        end
    end
    return false
end

local function doCollectEnchants()
    teleportToBestArea()
    for _, obj in ipairs(workspace:GetDescendants()) do
        if obj:IsA("BasePart") and (obj.Name:match("Enchant") or obj.Name:match("Free")) then
            if clickObject(obj) then return true end
        end
    end
    for _, obj in ipairs(workspace:GetDescendants()) do
        if obj:IsA("Model") and obj.Name:match("Vending") and obj.Name:match("Enchant") then
            local clickDetector = obj:FindFirstChild("ClickDetector")
            if clickDetector then
                pcall(function() clickDetector:FireClick(player.Mouse) end)
                task.wait(0.5)
                return true
            end
        end
    end
    return false
end

local function doUsePotions()
    local quests = getQuests()
    for _, q in ipairs(quests) do
        if q.type == "use_potions" then
            local name = q.raw:match("Use (%w+ Potion)") or q.raw:match("Use (%w+%s*Potion)")
            if name then
                if useItem(name, true) then return true end
            end
        end
    end
    return useItem("Potion")
end

local function doLuckyBlocks()
    teleportToBestArea()
    if useItem("Lucky.*Block") then
        task.wait(1)
        for _, obj in ipairs(workspace:GetDescendants()) do
            if obj:IsA("BasePart") and obj.Name:match("Lucky") and obj.Name:match("Block") then
                if clickObject(obj) then return true end
            end
        end
    end
    return false
end

local function doPinatas()
    teleportToBestArea()
    if useItem("Pinata") then
        task.wait(1)
        for _, obj in ipairs(workspace:GetDescendants()) do
            if obj:IsA("BasePart") and obj.Name:match("Pinata") then
                if clickObject(obj) then return true end
            end
        end
    end
    return false
end

local function doSuperiorChests()
    teleportToBestArea()
    local bestArea = getBestArea()
    if not bestArea then return false end
    for _, obj in ipairs(bestArea:GetDescendants()) do
        if obj:IsA("BasePart") and obj.Name:match("Superior") and obj.Name:match("Chest") then
            if clickObject(obj) then return true end
        end
    end
    return false
end

local function doAreaQuest(text)
    teleportToBestArea()
    if text:find("Obby") then
        for _, obj in ipairs(workspace:GetDescendants()) do
            if obj:IsA("BasePart") and obj.Name:match("Obby") then
                if clickObject(obj) then return true end
            end
        end
    elseif text:find("Minefield") then
        for _, obj in ipairs(workspace:GetDescendants()) do
            if obj:IsA("BasePart") and obj.Name:match("Minefield") then
                if clickObject(obj) then return true end
            end
        end
    elseif text:find("Fishing") then
        for _, obj in ipairs(workspace:GetDescendants()) do
            if obj:IsA("BasePart") and obj.Name:match("Fishing") then
                if clickObject(obj) then return true end
            end
        end
    elseif text:find("Digsite") then
        for _, obj in ipairs(workspace:GetDescendants()) do
            if obj:IsA("BasePart") and obj.Name:match("Digsite") then
                if clickObject(obj) then return true end
            end
        end
    elseif text:find("Fuse") then
        for _, obj in ipairs(workspace:GetDescendants()) do
            if obj:IsA("Model") and obj.Name:match("Fuse") then
                if clickObject(obj) then return true end
            end
        end
    elseif text:find("Plant") or text:find("Seed") then
        for _, obj in ipairs(workspace:GetDescendants()) do
            if obj:IsA("BasePart") and (obj.Name:match("Garden") or obj.Name:match("Seed")) then
                if clickObject(obj) then return true end
            end
        end
    elseif text:find("Cart Ride") or text:find("Atlantis") or text:find("Classic") then
        for _, obj in ipairs(workspace:GetDescendants()) do
            if obj:IsA("BasePart") and (obj.Name:match("Cart") or obj.Name:match("Atlantis") or obj.Name:match("Classic")) then
                if clickObject(obj) then return true end
            end
        end
    end
    return false
end

-- ===== MAIN LOOP WITH PROGRESS =====
local questProgress = {}

local function autoRank()
    if CONFIG.stop then return end
    if not CONFIG.autoRank then return end

    local quests = getQuests()
    for _, q in ipairs(quests) do
        if CONFIG.stop then break end
        local success = false
        local actionName = q.type or "unknown"

        if q.type == "collect_potions" and CONFIG.autoCollect then
            success = doCollectPotions()
        elseif q.type == "collect_enchants" and CONFIG.autoCollect then
            success = doCollectEnchants()
        elseif q.type == "use_potions" and CONFIG.autoConsume then
            success = doUsePotions()
        elseif q.type == "breakables" and CONFIG.autoBreak then
            success = doBreakables()
        elseif q.type == "diamond_breakables" and CONFIG.autoBreak then
            success = doDiamondBreakables()
        elseif q.type == "coin_jars" and CONFIG.autoBreak then
            success = doCoinJars()
        elseif q.type == "comets" and CONFIG.autoBreak then
            success = doComets()
        elseif q.type == "mini_chests" and CONFIG.autoBreak then
            success = doMiniChests()
        elseif q.type == "eggs" and CONFIG.autoHatch then
            success = doHatchEggs()
        elseif q.type == "rare_eggs" and CONFIG.autoHatch then
            success = doRareEggs()
        elseif q.type == "make_golden" and CONFIG.autoMakePets then
            success = doMakeGolden()
        elseif q.type == "make_rainbow" and CONFIG.autoMakePets then
            success = doMakeRainbow()
        elseif q.type == "diamonds" and CONFIG.autoDiamonds then
            success = doDiamonds()
        elseif q.type == "lucky_blocks" and CONFIG.autoBreak then
            success = doLuckyBlocks()
        elseif q.type == "pinatas" and CONFIG.autoBreak then
            success = doPinatas()
        elseif q.type == "superior_chests" and CONFIG.autoBreak then
            success = doSuperiorChests()
        elseif q.type == "area_quest" and CONFIG.autoAreaQuests then
            success = doAreaQuest(q.raw)
        end

        if success then
            questProgress.action = actionName
            questProgress.count = q.count
            task.wait(0.1)
        end
    end
end

-- ===== GUI =====
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "L3yHubGUI"
screenGui.Parent = player:WaitForChild("PlayerGui")

local mainFrame = Instance.new("Frame")
mainFrame.Size = UDim2.new(0, 260, 0, 400)
mainFrame.Position = UDim2.new(0, 10, 0, 10)
mainFrame.BackgroundColor3 = Color3.fromRGB(15, 15, 20)
mainFrame.BackgroundTransparency = 0.15
mainFrame.BorderSizePixel = 1
mainFrame.BorderColor3 = Color3.fromRGB(80, 80, 120)
mainFrame.Parent = screenGui

-- Title (draggable)
local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, 0, 0, 30)
title.Position = UDim2.new(0, 0, 0, 0)
title.Text = "L3y Hub"
title.TextColor3 = Color3.fromRGB(255, 200, 100)
title.TextScaled = true
title.BackgroundTransparency = 1
title.Parent = mainFrame

-- Drag logic
local dragging = false
local dragStart, startPos
title.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 then
        dragging = true
        dragStart = input.Position
        startPos = mainFrame.Position
    end
end)
title.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 then
        dragging = false
    end
end)
userInput.InputChanged:Connect(function(input)
    if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
        local delta = input.Position - dragStart
        mainFrame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
    end
end)

-- Toggle buttons
local function createToggle(text, y, configKey)
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(0, 230, 0, 28)
    btn.Position = UDim2.new(0, 15, 0, y)
    btn.Text = text .. ": ON"
    btn.TextColor3 = Color3.fromRGB(255, 255, 255)
    btn.BackgroundColor3 = Color3.fromRGB(0, 180, 0)
    btn.BorderSizePixel = 0
    btn.Parent = mainFrame
    btn.MouseButton1Click:Connect(function()
        CONFIG[configKey] = not CONFIG[configKey]
        btn.Text = text .. ": " .. (CONFIG[configKey] and "ON" or "OFF")
        btn.BackgroundColor3 = CONFIG[configKey] and Color3.fromRGB(0, 180, 0) or Color3.fromRGB(180, 0, 0)
    end)
    return btn
end

createToggle("Auto Rank", 35, "autoRank")
createToggle("Auto Break", 68, "autoBreak")
createToggle("Auto Hatch", 101, "autoHatch")
createToggle("Auto Consume", 134, "autoConsume")
createToggle("Auto Collect", 167, "autoCollect")
createToggle("Auto Make Pets", 200, "autoMakePets")
createToggle("Auto Area Quests", 233, "autoAreaQuests")
createToggle("Auto Diamonds", 266, "autoDiamonds")

-- Emergency Stop button
local stopBtn = Instance.new("TextButton")
stopBtn.Size = UDim2.new(0, 230, 0, 28)
stopBtn.Position = UDim2.new(0, 15, 0, 300)
stopBtn.Text = "STOP (Reset)"
stopBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
stopBtn.BackgroundColor3 = Color3.fromRGB(200, 0, 0)
stopBtn.BorderSizePixel = 0
stopBtn.Parent = mainFrame
stopBtn.MouseButton1Click:Connect(function()
    CONFIG.stop = true
    CONFIG.autoRank = false
    for _, btn in ipairs(mainFrame:GetDescendants()) do
        if btn:IsA("TextButton") and btn.Text:match("Auto Rank") then
            btn.Text = "Auto Rank: OFF"
            btn.BackgroundColor3 = Color3.fromRGB(180, 0, 0)
        end
    end
    statusBar.Text = "Status: Stopped"
    task.wait(2)
    CONFIG.stop = false
    CONFIG.autoRank = true
    for _, btn in ipairs(mainFrame:GetDescendants()) do
        if btn:IsA("TextButton") and btn.Text:match("Auto Rank") then
            btn.Text = "Auto Rank: ON"
            btn.BackgroundColor3 = Color3.fromRGB(0, 180, 0)
        end
    end
end)

-- Status bar with progress
local statusBar = Instance.new("TextLabel")
statusBar.Size = UDim2.new(1, 0, 0, 20)
statusBar.Position = UDim2.new(0, 0, 1, -20)
statusBar.Text = "Status: Idle"
statusBar.TextColor3 = Color3.fromRGB(150, 255, 150)
statusBar.TextScaled = true
statusBar.BackgroundTransparency = 1
statusBar.Parent = mainFrame

local function updateStatus(text)
    statusBar.Text = "Status: " .. text
    if questProgress.action then
        statusBar.Text = statusBar.Text .. " | " .. questProgress.action
        if questProgress.count then
            statusBar.Text = statusBar.Text .. " (" .. questProgress.count .. ")"
        end
    end
end

-- ===== MAIN LOOP =====
local lastHeartbeat = 0
runService.Heartbeat:Connect(function()
    if os.clock() - lastHeartbeat < 0.2 then return end
    lastHeartbeat = os.clock()
    if CONFIG.stop then
        updateStatus("Stopped")
        return
    end
    if CONFIG.autoRank then
        updateStatus("Running...")
        autoRank()
    else
        updateStatus("Paused")
    end
end)

print("L3y Hub loaded (mobile version). Use GUI buttons to control.")