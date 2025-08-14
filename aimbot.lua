do
    if getgenv().kyri_aim and getgenv().kyri_aim.__alive then
        -- already defined
        return
    end

    local Players = game:GetService("Players")
    local UIS     = game:GetService("UserInputService")
    local RS      = game:GetService("RunService")
    local LP      = Players.LocalPlayer
    local Cam     = workspace.CurrentCamera

    local M = { __alive = true }
    getgenv().kyri_aim = M -- export the module table

    -- config
    local aimFOV = 80           -- pixels used only for first acquire
    local smooth = 0.25         -- camera lerp speed (lower = faster)
    local scanNPCsEverywhere = true

    -- state
    local running = false       -- module loaded (GUI exists)
    local locked  = false       -- currently locked on a target
    local gui, btn, ring, ringStroke
    local currentModel, currentHum, currentHRP
    local conns = {}
    local deathConn, goneConn
    local debounceUntil = 0

    local function addConn(c) if c then table.insert(conns, c) end end
    local function onCooldown(sec) if tick() < debounceUntil then return true end debounceUntil = tick() + (sec or 0.3) end

    -- helpers
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
        local bestModel, bestDist = nil, aimFOV
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
        if scanNPCsEverywhere then
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

    local function updateButton()
        if not btn then return end
        if not locked then
            btn.Text = "Lock: OFF  (`)"
            if ringStroke then ringStroke.Color = Color3.fromRGB(120,120,120); ringStroke.Transparency = 0.3 end
        else
            btn.Text = "Lock: ON   (`)"
            if ringStroke then ringStroke.Color = Color3.fromRGB(0,200,255); ringStroke.Transparency = 0 end
        end
    end

    local function dropLock()
        locked = false
        if deathConn then deathConn:Disconnect(); deathConn=nil end
        if goneConn  then goneConn:Disconnect();  goneConn=nil  end
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
            dropLock()
            return
        end
        local hum, hrp = validModelHRP(m)
        if not hum or not hrp then
            dropLock()
            return
        end
        currentModel, currentHum, currentHRP = m, hum, hrp

        -- sticky-until-death: stop locking when target dies/despawns; user must press Lock again
        deathConn = hum.Died:Connect(function()
            dropLock()
        end)
        goneConn = m.AncestryChanged:Connect(function(_, parent)
            if parent == nil then dropLock() end
        end)
    end

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

        -- FOV ring (used only for initial acquire)
        ring = Instance.new("Frame")
        ring.AnchorPoint = Vector2.new(0.5,0.5)
        ring.Position = UDim2.fromScale(0.5,0.5)
        ring.Size = UDim2.fromOffset(aimFOV*2, aimFOV*2)
        ring.BackgroundTransparency = 1
        ring.Parent = gui
        ringStroke = Instance.new("UIStroke", ring)
        ringStroke.Thickness = 1
        ringStroke.Color = Color3.fromRGB(120,120,120)
        ringStroke.Transparency = 0.3
        Instance.new("UICorner", ring).CornerRadius = UDim.new(1,0)
    end

    local function startLoops()
        -- camera follow loop
        addConn(RS.RenderStepped:Connect(function()
            if not locked or not currentModel or not currentHum or not currentHRP then return end
            local newHRP = currentModel:FindFirstChild("HumanoidRootPart")
            if newHRP then currentHRP = newHRP end
            if currentHum.Health <= 0 then dropLock(); return end

            local look = CFrame.new(Cam.CFrame.Position, currentHRP.Position)
            Cam.CFrame = Cam.CFrame:Lerp(look, smooth)
        end))

        -- mobile button
        btn.MouseButton1Click:Connect(function()
            if onCooldown(0.25) then return end
            setLock(not locked)
        end)

        -- PC backtick `
        addConn(UIS.InputBegan:Connect(function(input, gpe)
            if gpe or UIS:GetFocusedTextBox() then return end
            if input.KeyCode == Enum.KeyCode.Backquote then
                if onCooldown(0.25) then return end
                setLock(not locked)
            end
        end))
    end

    local function destroyAll(reason)
        dropLock()
        for _,c in ipairs(conns) do pcall(function() c:Disconnect() end) end
        table.clear(conns)
        if gui then pcall(function() gui:Destroy() end); gui = nil end
        running = false
        -- keep module table so the controller can re-init without re-defining
        print("[kyri_aim] cleaned" .. (reason and (" ("..tostring(reason)..")") or ""))
    end

    -- exported API
    function M.init()
        if running then return end
        running = true
        buildUI()
        updateButton()
        startLoops()
    end
    function M.kill(reason) destroyAll(reason) end
    function M.is_running() return running end
    getgenv().kyri_aim_kill = M.kill -- optional external kill for v0.dev
end
