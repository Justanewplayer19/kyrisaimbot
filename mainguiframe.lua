-- Kyri's Ultimate Town Sandbox GUI
local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Rayfield = loadstring(game:HttpGet("https://sirius.menu/rayfield"))()
local Window = Rayfield:CreateWindow({
    Name = "Kyri's Ultimate Town Sandbox GUI",
    LoadingTitle = "Loading...",
    LoadingSubtitle = "UTS",
    ConfigurationSaving = { Enabled = true, FolderName = "Kyri_UTS", FileName = "Config" },
    KeySystem = false
})

-- ===== internals =====
local function char() return LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait() end
local function hum() local c = char(); return c:FindFirstChildOfClass("Humanoid") end
local function hrp() local c = char(); return c:FindFirstChild("HumanoidRootPart") end
local function root(modelOrPlayer)
    local c = modelOrPlayer
    if modelOrPlayer and modelOrPlayer.Character then c = modelOrPlayer.Character end
    if not c then return nil end
    return c:FindFirstChild("HumanoidRootPart") or c.PrimaryPart
end
local function alive(modelOrPlayer)
    local c = modelOrPlayer and (modelOrPlayer.Character or modelOrPlayer) or nil
    local h = c and c:FindFirstChildOfClass("Humanoid")
    return h and h.Health > 0 and h
end

-- jump fix after TPs (force JumpHeight mode)
local savedJumpHeight = 7.2
LocalPlayer.CharacterAdded:Connect(function()
    local h = hum()
    if h then
        savedJumpHeight = h.JumpHeight
    end
end)
local function fixJump()
    local h = hum()
    if not h then return end
    pcall(function()
        h.UseJumpPower = false
        h.JumpHeight = savedJumpHeight or 7.2
    end)
end

local function hardtp(cf)
    local c = char()
    local h = hum()
    local r = hrp()
    if h then
        h.Sit = false
        h.PlatformStand = false
        h:ChangeState(Enum.HumanoidStateType.RunningNoPhysics)
    end
    if r then
        r.AssemblyLinearVelocity = Vector3.zero
        r.AssemblyAngularVelocity = Vector3.zero
    end
    local ok = pcall(function() c:PivotTo(cf) end)
    if not ok and r then r.CFrame = cf end
    fixJump()
end

-- ===== Teleports =====
local TeleTab = Window:CreateTab("Teleports")

-- fixed spots (kept light)
local function addSpot(n, pos)
    TeleTab:CreateButton({
        Name = n,
        Callback = function()
            local r = hrp(); if r then hardtp(CFrame.new(pos)) end
        end
    })
end
addSpot("Burger Bite", Vector3.new(415.43,12,28.73))
addSpot("Hospital", Vector3.new(557.5,10.5,118.32))
addSpot("Bandit Hideout", Vector3.new(413.02,11.5,-108.47))

-- live player TP
local function others()
    local t = {}
    for _,p in ipairs(Players:GetPlayers()) do
        if p ~= LocalPlayer then table.insert(t, p.Name) end
    end
    table.sort(t); return t
end
local sel
local dd = TeleTab:CreateDropdown({
    Name = "Select player",
    Options = others(),
    CurrentOption = nil,
    Multiple = false,
    Flag = "tp_sel",
    Callback = function(opt) sel = (type(opt)=="table") and opt[1] or opt end
})
TeleTab:CreateButton({
    Name = "Teleport to player",
    Callback = function()
        if type(sel) ~= "string" then return end
        local p = Players:FindFirstChild(sel); if not p then return end
        local r = root(p); if not r then return end
        hardtp(r.CFrame * CFrame.new(0,3,-2))
    end
})
local function refreshDD()
    local list = others()
    dd:Refresh(list, true)
    if sel and not table.find(list, sel) then sel = nil end
end
Players.PlayerAdded:Connect(refreshDD)
Players.PlayerRemoving:Connect(refreshDD)
LocalPlayer.CharacterAdded:Connect(function() task.defer(refreshDD) end)

-- ===== Food (GhostBurger) =====
local FoodTab = Window:CreateTab("Food")
local function deps()
    local events = RS:FindFirstChild("Events")
    local globals = RS:FindFirstChild("GlobalVariables")
    local prices = globals and globals:FindFirstChild("FoodBuyPrices")
    local burgerPlace = prices and prices:FindFirstChild("BurgerPlace")
    return events, burgerPlace
end
FoodTab:CreateButton({
    Name = "Buy GhostBurger (24.99)",
    Callback = function()
        local events, burgerPlace = deps()
        if events and burgerPlace then
            pcall(function() events.BuyConsumable:FireServer("GhostBurger", burgerPlace) end)
        end
    end
})
local autoGB, gbInterval, autoEat = false, 5, true
FoodTab:CreateToggle({ Name="Auto-Buy GhostBurger", CurrentValue=autoGB, Callback=function(v) autoGB=v end })
FoodTab:CreateSlider({ Name="Auto-Buy Interval (s)", Range={2,30}, Increment=1, CurrentValue=gbInterval, Callback=function(v) gbInterval=v end })
FoodTab:CreateToggle({ Name="Auto-Eat After Purchase", CurrentValue=autoEat, Callback=function(v) autoEat=v end })
task.spawn(function()
    while true do
        if autoGB then
            local events, burgerPlace = deps()
            if events and burgerPlace then
                pcall(function() events.BuyConsumable:FireServer("GhostBurger", burgerPlace) end)
                if autoEat and events:FindFirstChild("UseConsumable") then
                    pcall(function() events.UseConsumable:FireServer("GhostBurger") end)
                end
            end
            task.wait(gbInterval)
        else
            task.wait(0.25)
        end
    end
end)

-- ===== Autos Tab =====
local AutosTab = Window:CreateTab("Autos")

-- Added combat functionality to Autos tab
local EquipRemote = RS:WaitForChild("Events"):WaitForChild("Equip")
local UnequipRemote = RS:WaitForChild("Events"):WaitForChild("Unequip")

-- Combat settings
local autoEquip = false
local autoHit = false
local behindDist = 2.5
local searchRadius = 80

-- Player whitelist system
local playerWhitelist = {}

local function getOtherPlayers()
    local t = {}
    for _,p in ipairs(Players:GetPlayers()) do
        if p ~= LocalPlayer then table.insert(t, p.Name) end
    end
    table.sort(t)
    return t
end

local selectedPlayer = nil
local whitelistDD = AutosTab:CreateDropdown({
    Name = "Select Player to Whitelist",
    Options = getOtherPlayers(),
    CurrentOption = nil,
    Multiple = false,
    Flag = "whitelist_sel",
    Callback = function(opt) 
        selectedPlayer = (type(opt)=="table") and opt[1] or opt 
    end
})

AutosTab:CreateButton({
    Name = "Add Selected Player to Whitelist",
    Callback = function()
        if selectedPlayer and not table.find(playerWhitelist, selectedPlayer) then
            table.insert(playerWhitelist, selectedPlayer)
            print("Added " .. selectedPlayer .. " to whitelist")
        elseif selectedPlayer then
            print(selectedPlayer .. " is already whitelisted")
        else
            print("No player selected")
        end
    end
})

AutosTab:CreateButton({
    Name = "Clear Whitelist",
    Callback = function()
        playerWhitelist = {}
        print("Whitelist cleared")
    end
})

-- Combat toggles and settings
AutosTab:CreateToggle({ 
    Name="Auto-Equip Fists", 
    CurrentValue=autoEquip, 
    Callback=function(v) autoEquip=v end 
})

AutosTab:CreateToggle({ 
    Name="Auto-Attack (Left Click)", 
    CurrentValue=autoHit,
    Callback=function(v) 
        autoHit=v 
    end 
})

AutosTab:CreateSlider({ 
    Name="Behind Distance", 
    Range={1,6}, 
    Increment=0.5, 
    CurrentValue=behindDist, 
    Callback=function(v) behindDist=v end 
})

AutosTab:CreateSlider({ 
    Name="Target Radius", 
    Range={20,200}, 
    Increment=5, 
    CurrentValue=searchRadius, 
    Callback=function(v) searchRadius=v end 
})

-- Combat functions
local function findTarget()
    local myRoot = hrp()
    if not myRoot then return nil end
    
    local myPosition = myRoot.Position
    local closestTarget = nil
    local closestDistance = math.huge
    
    -- Check players in PlayerCharacters folder (skip whitelisted players)
    local playerCharacters = workspace:FindFirstChild("PlayerCharacters")
    if playerCharacters then
        for _, playerModel in ipairs(playerCharacters:GetChildren()) do
            if playerModel:IsA("Model") and playerModel.Name ~= LocalPlayer.Name then
                local isWhitelisted = table.find(playerWhitelist, playerModel.Name)
                if not isWhitelisted then
                    local targetRoot = playerModel:FindFirstChild("HumanoidRootPart")
                    local targetHumanoid = playerModel:FindFirstChildOfClass("Humanoid")
                    
                    if targetRoot and targetHumanoid and targetHumanoid.Health > 0 then
                        local distance = (targetRoot.Position - myPosition).Magnitude
                        if distance <= searchRadius and distance < closestDistance then
                            closestTarget = playerModel
                            closestDistance = distance
                        end
                    end
                end
            end
        end
    end
    
    -- Check NPCs
    local npcFolder = workspace:FindFirstChild("NPCs")
    if npcFolder then
        local sidewalkNPCs = npcFolder:FindFirstChild("SidewalkNPCs")
        if sidewalkNPCs then
            for _, npcModel in ipairs(sidewalkNPCs:GetChildren()) do
                if npcModel:IsA("Model") and npcModel.Name == "NPC" then
                    local targetRoot = npcModel:FindFirstChild("HumanoidRootPart")
                    local targetHumanoid = npcModel:FindFirstChildOfClass("Humanoid")
                    
                    if targetRoot and targetHumanoid and targetHumanoid.Health > 0 then
                        local distance = (targetRoot.Position - myPosition).Magnitude
                        if distance <= searchRadius and distance < closestDistance then
                            closestTarget = npcModel
                            closestDistance = distance
                        end
                    end
                end
            end
        end
    end
    
    return closestTarget
end

local function hasFists()
    local c = char()
    return c and c:FindFirstChild("Fists") ~= nil
end

local function teleportBehind(target)
    if not target or not target:IsA("Model") then return end
    local targetRoot = target:FindFirstChild("HumanoidRootPart") or target.PrimaryPart
    if not targetRoot then return end
    local cf = targetRoot.CFrame
    local behindPos = cf.Position - (cf.LookVector * behindDist)
    local spot = CFrame.new(behindPos + Vector3.new(0, 0.5, 0), cf.Position)
    hardtp(spot)
end

local function simulateLeftClick()
    pcall(function()
        local vim = game:GetService("VirtualInputManager")
        vim:SendMouseButtonEvent(0, 0, 0, true, game, 1)
        task.wait(0.05)
        vim:SendMouseButtonEvent(0, 0, 0, false, game, 1)
    end)
end

-- Refresh whitelist dropdown
local function refreshWhitelistDD()
    local list = getOtherPlayers()
    whitelistDD:Refresh(list, true)
    if selectedPlayer and not table.find(list, selectedPlayer) then 
        selectedPlayer = nil 
    end
end

Players.PlayerAdded:Connect(refreshWhitelistDD)
Players.PlayerRemoving:Connect(refreshWhitelistDD)
LocalPlayer.CharacterAdded:Connect(function() task.defer(refreshWhitelistDD) end)

-- Auto-equip task
task.spawn(function()
    while true do
        if autoEquip and autoHit and not hasFists() then
            pcall(function() EquipRemote:FireServer("Fists") end)
        end
        task.wait(1)
    end
end)

-- Combat loop
task.spawn(function()
    while true do
        if autoHit and hasFists() then
            local target = findTarget()
            
            if target then
                local targetHumanoid = target:FindFirstChildOfClass("Humanoid")
                if targetHumanoid and targetHumanoid.Health > 0 then
                    teleportBehind(target)
                    task.wait(0.1)
                    simulateLeftClick()
                end
            end
        end
        
        task.wait(0.1)
    end
end)

-- Added autoloot system for dead bodies
local autoLoot = false
AutosTab:CreateToggle({
    Name = "Auto Loot Dead Bodies",
    CurrentValue = autoLoot,
    Callback = function(v)
        autoLoot = v
        if not v then return end
        coroutine.wrap(function()
            local start = hrp() and hrp().CFrame
            while autoLoot do
                for _, obj in ipairs(workspace:GetDescendants()) do
                    if not autoLoot then break end
                    if obj:IsA("ProximityPrompt") and obj.Enabled then
                        local actionText = obj.ActionText or ""
                        
                        -- Only activate for "Loot" prompts, ignore "Drag" prompts
                        if actionText:lower():find("loot") and not actionText:lower():find("drag") then
                            local part = obj.Parent:IsA("Model") and obj.Parent.PrimaryPart or obj.Parent
                            local r = hrp()
                            if part and r then
                                r.CFrame = part.CFrame + Vector3.new(0,3,0)
                                task.wait(0.05)
                                pcall(function() fireproximityprompt(obj) end)
                            end
                        end
                    end
                end
                task.wait(0.1)
            end
            if start and hrp() then task.wait(0.2) hrp().CFrame = start end
        end)()
    end
})

-- Moved existing autofarm features to Autos tab
local farmPlants = false
AutosTab:CreateToggle({
    Name = "Farm Plants/Flowers",
    CurrentValue = farmPlants,
    Callback = function(v)
        farmPlants = v
        if not v then return end
        coroutine.wrap(function()
            local start = hrp() and hrp().CFrame
            while farmPlants do
                for _, obj in ipairs(workspace:GetDescendants()) do
                    if not farmPlants then break end
                    if obj:IsA("ProximityPrompt") and obj.Enabled then
                        local part = obj.Parent:IsA("Model") and obj.Parent.PrimaryPart or obj.Parent
                        local r = hrp()
                        if part and r then
                            r.CFrame = part.CFrame + Vector3.new(0,3,0)
                            task.wait(0.04)
                            pcall(function() fireproximityprompt(obj) end)
                        end
                    end
                end
                task.wait(0.08)
            end
            if start and hrp() then task.wait(0.2) hrp().CFrame = start end
        end)()
    end
})

local farmTrash = false
AutosTab:CreateToggle({
    Name = "Loot Trash/Chests",
    CurrentValue = farmTrash,
    Callback = function(v)
        farmTrash = v
        if not v then return end
        coroutine.wrap(function()
            local start = hrp() and hrp().CFrame
            local keys = {"trashcan","trashcans","trashbags","dumpster","treasurechest","mayorssafe","mayorstreasure","banditsafe","winterbanditsafe"}
            while farmTrash do
                for _, obj in ipairs(workspace:GetDescendants()) do
                    if not farmTrash then break end
                    if obj:IsA("ProximityPrompt") and obj.Enabled then
                        local pn = (obj.Parent and obj.Parent.Name or ""):lower()
                        local hit = false
                        for _,kw in ipairs(keys) do if pn:find(kw) then hit=true break end end
                        if hit then
                            local part = obj.Parent:IsA("Model") and obj.Parent.PrimaryPart or obj.Parent
                            local r = hrp()
                            if part and r then
                                r.CFrame = part.CFrame + Vector3.new(0,3,0)
                                task.wait(0.05)
                                pcall(function() fireproximityprompt(obj) end)
                            end
                        end
                    end
                end
                task.wait(0.08)
            end
            if start and hrp() then task.wait(0.2) hrp().CFrame = start end
        end)()
    end
})

local antiAfk, afkConn = false, nil
AutosTab:CreateToggle({
    Name = "AntiAfk",
    CurrentValue = antiAfk,
    Callback = function(v)
        antiAfk = v
        local vu = game:GetService("VirtualUser")
        if v then
            afkConn = LocalPlayer.Idled:Connect(function()
                vu:Button2Down(Vector2.new(), workspace.CurrentCamera.CFrame)
                task.wait(1)
                vu:Button2Up(Vector2.new(), workspace.CurrentCamera.CFrame)
            end)
        elseif afkConn then
            afkConn:Disconnect(); afkConn = nil
        end
    end
})

-- ===== Misc Tab =====
local MiscTab = Window:CreateTab("Misc")

-- Execute Custom Script button
MiscTab:CreateButton({
    Name = "Execute Infinite Yield",
    Callback = function()
        pcall(function()
            -- Replace this loadstring with your own script
            loadstring(game:HttpGet("https://raw.githubusercontent.com/EdgeIY/infiniteyield/master/source"))()
            print("Custom script executed successfully")
        end)
    end
})

-- Replaced aimbot toggle with AimCtl system from attachment
local ctlBusyUntil = 0
MiscTab:CreateToggle({
    Name = "Load Aimlock (OFF = Kill/Cleanup)",
    CurrentValue = false,
    Flag = "kyri_aim_controller_toggle",
    Callback = function(v)
        if tick() < ctlBusyUntil then return end
        ctlBusyUntil = tick() + 0.35

        -- If ON: ensure module exists, then init it (shows tiny GUI, backtick toggle lives there)
        if v then
            if not getgenv().kyri_aim then
            loadstring(game:HttpGet("https://raw.githubusercontent.com/Justanewplayer19/kyrisaimbot/main/aimbot.lua"))()

            end
            if getgenv().kyri_aim and getgenv().kyri_aim.init then
                getgenv().kyri_aim.init()
            end
        else
            -- If OFF: tell it to fully kill itself and clean up
            if getgenv().kyri_aim and getgenv().kyri_aim.kill then
                getgenv().kyri_aim.kill("rayfield_off")
            end
        end
    end
})
MiscTab:CreateToggle({
    Name = "Shift Lock",
    CurrentValue = false, -- default OFF
    Callback = function(state)
        if state then
            -- load module + init
            loadstring(game:HttpGet("https://raw.githubusercontent.com/Justanewplayer19/kyrisaimbot/main/shiftlock.lua"))()
            if getgenv().KYRI_SHIFTLOCK and getgenv().KYRI_SHIFTLOCK.init then
                getgenv().KYRI_SHIFTLOCK.init()
            end
        else
            -- kill/cleanup
            if getgenv().KYRI_SHIFTLOCK and getgenv().KYRI_SHIFTLOCK.kill then
                getgenv().KYRI_SHIFTLOCK.kill()
            elseif getgenv().kyri_shiftlock_kill then
                getgenv().kyri_shiftlock_kill()
            end
        end
    end
})
