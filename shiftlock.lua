-- kyri shiftlock toggle (ALT/ALT/RightCtrl)

local Players = game:GetService("Players")
local UIS     = game:GetService("UserInputService")
local RS      = game:GetService("RunService")

local LP      = Players.LocalPlayer
local Cam     = workspace.CurrentCamera

getgenv().KYRI_SHIFTLOCK = getgenv().KYRI_SHIFTLOCK or {}
local M = getgenv().KYRI_SHIFTLOCK

-- internal state
local running = false        -- module loaded (GUI exists)
local active  = false        -- lock is ON
local gui, btn, cursor
local stepConn, inputConn, charConn
local debounceUntil = 0

local function now() return tick() end
local function debounced(sec)
    if now() < debounceUntil then return true end
    debounceUntil = now() + (sec or 0.25)
end

-- square helper
local function makeSquare(instance)
    local arc = Instance.new("UIAspectRatioConstraint")
    arc.AspectRatio = 1
    arc.Parent = instance
end

local function setAutoRotate(flag)
    local char = LP.Character
    if not char then return end
    local hum = char:FindFirstChildOfClass("Humanoid")
    if hum then hum.AutoRotate = flag end
end

local function enableLock()
    if active then return end
    active = true
    if btn then btn.Image = "rbxasset://textures/ui/mouseLock_on@2x.png" end
    if cursor then cursor.Visible = true end

    setAutoRotate(false)
    stepConn = RS.RenderStepped:Connect(function()
        local char = LP.Character
        if not char then return end
        local hum = char:FindFirstChildOfClass("Humanoid")
        local hrp = char:FindFirstChild("HumanoidRootPart")
        if not hum or not hrp then return end
        -- face where the camera is looking, fixed Y to HRP height
        hum.AutoRotate = false
        local look = Cam.CFrame.LookVector
        hrp.CFrame = CFrame.new(
            hrp.Position,
            Vector3.new(look.X * 900000, hrp.Position.Y, look.Z * 900000)
        )
    end)
end

local function disableLock()
    if not active then return end
    active = false
    if stepConn then stepConn:Disconnect() stepConn = nil end
    setAutoRotate(true)
    if btn then btn.Image = "rbxasset://textures/ui/mouseLock_off@2x.png" end
    if cursor then cursor.Visible = false end
end

local function toggleLock()
    if active then disableLock() else enableLock() end
end

local function buildGUI()
    gui = Instance.new("ScreenGui")
    gui.Name = "kyri_shiftlock_gui"
    gui.ResetOnSpawn = false
    gui.IgnoreGuiInset = true
    pcall(function() gui.Parent = game:GetService("CoreGui") end)
    if not gui.Parent then gui.Parent = LP:WaitForChild("PlayerGui") end

    btn = Instance.new("ImageButton")
    btn.Name = "Toggle"
    btn.Size = UDim2.fromOffset(44, 44)
    btn.Position = UDim2.new(0.7, 0, 0.75, 0)
    btn.BackgroundTransparency = 1
    btn.Image = "rbxasset://textures/ui/mouseLock_off@2x.png"
    btn.ZIndex = 10
    btn.Parent = gui
    makeSquare(btn)

    cursor = Instance.new("ImageLabel")
    cursor.Name = "Cursor"
    cursor.Size = UDim2.fromOffset(34, 34)
    cursor.AnchorPoint = Vector2.new(0.5, 0.5)
    cursor.Position = UDim2.new(0.5, 0, 0.5, 0)
    cursor.BackgroundTransparency = 1
    cursor.Image = "rbxasset://textures/MouseLockedCursor.png"
    cursor.Visible = false
    cursor.ZIndex = 10
    cursor.Parent = gui
    makeSquare(cursor)

    btn.MouseButton1Click:Connect(function()
        if debounced(0.2) then return end
        toggleLock()
    end)
end

local function bindInputs()
    if inputConn then inputConn:Disconnect() end
    inputConn = UIS.InputBegan:Connect(function(input, gp)
        if gp then return end
        if debounced(0.12) then return end
        if input.KeyCode == Enum.KeyCode.LeftAlt
            or input.KeyCode == Enum.KeyCode.RightAlt
            or input.KeyCode == Enum.KeyCode.RightControl then
            toggleLock()
        end
    end)

    if charConn then charConn:Disconnect() end
    charConn = LP.CharacterAdded:Connect(function()
        -- if locking when we respawn, re-assert the state
        if active then task.defer(function() setAutoRotate(false) end) end
    end)
end

local function destroyAll()
    disableLock() -- ensures AutoRotate true + stepConn disconnected
    if inputConn then inputConn:Disconnect() inputConn = nil end
    if charConn  then charConn:Disconnect()  charConn  = nil end
    if gui then gui:Destroy() gui = nil btn = nil cursor = nil end
    running = false
end

-- public API
function M.init()
    if running then return end
    running = true
    buildGUI()
    bindInputs()
end

function M.kill()
    destroyAll()
end

-- optional global kill for your Rayfield OFF callback
getgenv().kyri_shiftlock_kill = M.kill
