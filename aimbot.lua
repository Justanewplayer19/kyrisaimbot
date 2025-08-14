-- ======= guard / antispam =======
local now = tick
if getgenv().KYRI_AIM_BUSY and now() - getgenv().KYRI_AIM_BUSY < 0.4 then return end
getgenv().KYRI_AIM_BUSY = now()

if getgenv().KYRI_AIM_RUNNING then
    warn("[kyri_aim] already running")
else
    getgenv().KYRI_AIM_RUNNING = true
end

-- ======= services =======
local Players = game:GetService("Players")
local UIS     = game:GetService("UserInputService")
local RS      = game:GetService("RunService")
local LP      = Players.LocalPlayer
local Cam     = workspace.CurrentCamera

-- ======= rayfield window + toggle =======
local Rayfield = rawget(getfenv(), "Rayfield") or loadstring(game:HttpGet("https://sirius.menu/rayfield"))()
local AimWin = Rayfield:CreateWindow({
    Name = "Kyri's Aimlock Controls",
    LoadingTitle = "Aimlock",
    LoadingSubtitle = "Sticky • HRP",
    DisableIntro = true,
    ConfigurationSaving = { Enabled = false },
    KeySystem = false
})
local AimTab = AimWin:CreateTab("Aimlock", 4483362458)

-- ======= module state =======
local cfg = {
    aimFOV = 80,           -- pixels, initial acquisition only
    smooth = 0.25,         -- camera turn lerp
    scanNPCsEverywhere = true
}

local running = false       -- module loaded (Rayfield toggle ON)
local locked  = false       -- currently locked on a target
local gui, btn, ring, stroke
local currentModel, currentHum, currentHRP
local conns = {}
local deathConn, goneConn
local debounceUntil = 0

local function addConn(c) if c then table.insert(conns, c) end end

-- ======= UI (mini) =======
local function buildUI()
    gui = Instance.new("ScreenGui")
    gui.Name = "kyri_aim_gui"
    gui.ResetOnSpawn = false
    gui.IgnoreGuiInset = true
    pcall(function() gui.Parent = game:GetService("CoreGui") end)
    if not gui.Parent then gui.Parent = LP:WaitForChild("PlayerGui") end

    local panel = Instance.new("Frame")
    panel.Size = UDim2.fromOffset(170, 64)
    panel.Position = UDim2.fromOffset(20, 180)
    panel.BackgroundColor3 = Color3.fromRGB(28,28,30)
    panel.BorderSizePixel = 0
    panel.Parent = gui
    Instance.new("UICorner", panel).CornerRadius = UDim.new(0,10)

    local title = Instance.new("TextLabel")
    title.Size = UDim2.fromOffset(170, 18)
    title.Position = UDim2.fromOffset(0, 6)
    title.BackgroundTransparency = 1
    title.Text = "Sticky Aimlock (HRP)"
    title.TextColor3 = Color3.fromRGB(200,200,200)
    title.Font = Enum.Font.GothamBold
    title.TextSize = 14
    title.Parent = panel

    btn = Instance.new("TextButton")
    btn.Size = UDim2.fromOffset(150, 28)
    btn.Position = UDim2.fromOffset(10, 30)
    btn.BackgroundColor3 = Color3.fromRGB(40,40,42)
    btn.TextColor3 = Color3.fromRGB(255,255,255)
    btn.BorderSizePixel = 0
    btn.Text = "Lock: OFF  (`)"
    btn.Font = Enum.Font.Gotham
    btn.TextSize = 13
    btn.AutoButtonColor = true
    btn.Parent = panel
    Instance.new("UICorner", btn).CornerRadius = UDim.new(0,8)

    ring = Instance.new("Frame")
    ring.AnchorPoint = Vector2.new(0.5,0.5)
    ring.Position = UDim2.fromScale(0.5,0.5)
    ring.Size = UDim2.fromOffset(cfg.aimFOV*2, cfg.aimFOV*2)
    ring.BackgroundTransparency = 1
    ring.Parent = gui
    stroke = Instance.new("UIStroke", ring)
    stroke.Thickness = 1
    stroke.Color = Color3.fromRGB(120,120,120)
    stroke.Transparency = 0.3
    Instance.new("UICorner", ring).CornerRadius = UDim.new(1,0)
end

local function updateButton()
    if not btn then return end
    if not locked then
        btn.Text = "Lock: OFF  (`)"
        if stroke then stroke.Color = Color3.fromRGB(120,120,120); stroke.Transparency = 0.3 end
    else
        btn.Text = "Lock: ON   (`)"
        if stroke then stroke.Color = Color3.fromRGB(0,200,255); stroke.Transparency = 0 end
    end
end

-- ======= targeting helpers =======
local function isPlayerModel(m) return Players:GetPlayerFromCharacter(m) ~= nil end

local function validModelHRP(m)
    if not (m and m:IsA("Model")) then return nil,nil end
    local hum = m:FindFirstChildOfClass("Humanoid")
    if not hum or hum.Health <= 0 then return nil,nil end
    local hrp = m:FindFirstChild("HumanoidRootPart")
    if not hrp or not hrp:IsA("BasePart") then return nil,nil end
    return hum, hrp
end

local function distToCrosshair(worldPos)
    local center = Vector2.new(Cam.ViewportSize.X/2, Cam.ViewportSize.Y/2)
    local v, on = Cam:WorldToViewportPoint(worldPos)
    if not on then return math.huge end
    return (Vector2.new(v.X, v.Y) - center).Magnitude
end

local function acquireTarget()
    local bestModel, bestDist = nil, cfg.aimFOV

    -- players
    for _, pl in ipairs(Players:GetPlayers()) do
        if pl ~= LP and pl.Character then
            local hum, hrp = validModelHRP(pl.Character)
            if hum and hrp then
                local d = distToCrosshair(hrp.Position)
                if d < bestDist then bestDist, bestModel = d, pl.Character end
            end
        end
    end

    -- npcs
    if cfg.scanNPCsEverywhere then
        for _, inst in ipairs(workspace:GetDescendants()) do
            if inst:IsA("Model") and not isPlayerModel(inst) then
                local hum, hrp = validModelHRP(inst)
                if hum and hrp then
                    local d = distToCrosshair(hrp.Position)
                    if d < bestDist then bestDist, bestModel = d, inst end
                end
            end
        end
    else
        local npcs = workspace:FindFirstChild("NPCs")
        if npcs then
            for _, inst in ipairs(npcs:GetDescendants()) do
                if inst:IsA("Model") then
                    local hum, hrp = validModelHRP(inst)
                    if hum and hrp then
                        local d = distToCrosshair(hrp.Position)
                        if d < bestDist then bestDist, bestModel = d, inst end
                    end
                end
            end
        end
    end

    return bestModel
end

local function dropLock()
    locked = false
    if deathConn then deathConn:Disconnect(); deathConn = nil end
    if goneConn  then goneConn:Disconnect();  goneConn  = nil end
    currentModel, currentHum, currentHRP = nil, nil, nil
    updateButton()
end

local function setLock(v)
    if v == locked then return end
    locked = v
    updateButton()

    if not locked then
        dropLock()
        return
    end

    -- acquire once
    local m = acquireTarget()
    if not m then
        locked = false
        updateButton()
        return
    end
    local hum, hrp = validModelHRP(m)
    if not hum or not hrp then
        locked = false
        updateButton()
        return
    end
    currentModel, currentHum, currentHRP = m, hum, hrp

    -- sticky-until-death: stop locking on death/despawn; user must press Lock again
    deathConn = hum.Died:Connect(function()
        dropLock()
    end)
    goneConn = m.AncestryChanged:Connect(function(_, parent)
        if parent == nil then dropLock() end
    end)
end

-- ======= runtime loops =======
local function startLoops()
    addConn(RS.RenderStepped:Connect(function()
        if locked and currentModel and currentHum and currentHRP then
            local newHRP = currentModel:FindFirstChild("HumanoidRootPart")
            if newHRP then currentHRP = newHRP end
            if currentHum.Health <= 0 then
                dropLock()
                return
            end
            local look = CFrame.new(Cam.CFrame.Position, currentHRP.Position)
            Cam.CFrame = Cam.CFrame:Lerp(look, cfg.smooth)
        end
    end))

    -- button + backtick
    btn.MouseButton1Click:Connect(function()
        if tick() < debounceUntil then return end
        debounceUntil = tick() + 0.25
        setLock(not locked)
    end)

    addConn(UIS.InputBegan:Connect(function(input, gpe)
        if gpe or UIS:GetFocusedTextBox() then return end
        if input.KeyCode == Enum.KeyCode.Backquote then
            if tick() < debounceUntil then return end
            debounceUntil = tick() + 0.25
            setLock(not locked)
        end
    end))
end

-- ======= module lifecycle =======
local function destroyAll(reason)
    -- prevent spam
    if tick() < debounceUntil then return end
    debounceUntil = tick() + 0.4

    dropLock()
    for _,c in ipairs(conns) do pcall(function() c:Disconnect() end) end
    table.clear(conns)
    if gui then pcall(function() gui:Destroy() end); gui = nil end
    running = false
    getgenv().KYRI_AIM_RUNNING = false
    -- leave Rayfield window; v0.dev may kill it separately if desired
    print("[kyri_aim] cleaned up" .. (reason and (" ("..tostring(reason)..")") or ""))
end

-- Expose to v0.dev:
getgenv().kyri_aim_kill = function() destroyAll("external") end
getgenv().kyri_aim_is_running = function() return running end

local function startModule()
    if running then return end
    running = true
    buildUI()
    updateButton()
    startLoops()
end

-- ======= Rayfield toggle control =======
local rfToggle
rfToggle = AimTab:CreateToggle({
    Name = "Load Aimlock (toggle OFF = kill/cleanup)",
    CurrentValue = false,
    Flag = "kyri_aim_rf_toggle",
    Callback = function(v)
        -- antispam
        if tick() < debounceUntil then return end
        debounceUntil = tick() + 0.4

        if v then
            if getgenv().KYRI_AIM_RUNNING then
                Rayfield:Notify({ Title="Aimlock", Content="Already running.", Duration=3 })
                return
            end
            getgenv().KYRI_AIM_RUNNING = true
            startModule()
            Rayfield:Notify({ Title="Aimlock", Content="Loaded. Use ` or the button to lock.", Duration=4 })
        else
            destroyAll("rayfield_off")
            Rayfield:Notify({ Title="Aimlock", Content="Unloaded & cleaned.", Duration=3 })
        end
    end
})

-- (Optional) small controls in tab
AimTab:CreateSlider({
    Name = "Smooth",
    Range = {0.05, 0.6},
    Increment = 0.01,
    CurrentValue = cfg.smooth,
    Callback = function(v) cfg.smooth = tonumber(string.format("%.2f", v)) end
})
AimTab:CreateSlider({
    Name = "Acquire FOV (px)",
    Range = {20, 400},
    Increment = 2,
    CurrentValue = cfg.aimFOV,
    Callback = function(v)
        cfg.aimFOV = math.clamp(v, 20, 400)
        if ring then ring.Size = UDim2.fromOffset(cfg.aimFOV*2, cfg.aimFOV*2) end
    end
})
AimTab:CreateToggle({
    Name = "Scan NPCs Everywhere",
    CurrentValue = cfg.scanNPCsEverywhere,
    Callback = function(v) cfg.scanNPCsEverywhere = v end
})

-- Safety: if script unexpectedly reloaded and GUI exists, ensure consistent state
if gui then updateButton() end
