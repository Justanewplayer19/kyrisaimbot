-- kyri Shift Lock toggle
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local Player = Players.LocalPlayer
local Active = false
local Connection

local States = {
    Off = "rbxasset://textures/ui/mouseLock_off@2x.png",
    On = "rbxasset://textures/ui/mouseLock_on@2x.png",
    Lock = "rbxasset://textures/MouseLockedCursor.png"
}

-- UI
local gui = Instance.new("ScreenGui")
gui.Name = "ShiftLockToggle"
gui.ResetOnSpawn = false
pcall(function() gui.Parent = game:GetService("CoreGui") end)
if not gui.Parent then gui.Parent = Player:WaitForChild("PlayerGui") end

local btn = Instance.new("ImageButton")
btn.Size = UDim2.new(0.06, 0, 0.06, 0)
btn.Position = UDim2.new(0.7, 0, 0.75, 0)
btn.BackgroundTransparency = 1
btn.Image = States.Off
btn.Parent = gui

local cursor = Instance.new("ImageLabel")
cursor.Size = UDim2.new(0.03, 0, 0.03, 0)
cursor.AnchorPoint = Vector2.new(0.5, 0.5)
cursor.Position = UDim2.new(0.5, 0, 0.5, 0)
cursor.BackgroundTransparency = 1
cursor.Image = States.Lock
cursor.Visible = false
cursor.Parent = gui

local function enableLock()
    if Active then return end
    Active = true
    btn.Image = States.On
    cursor.Visible = true
    Connection = RunService.RenderStepped:Connect(function()
        local hrp = Player.Character and Player.Character:FindFirstChild("HumanoidRootPart")
        local hum = Player.Character and Player.Character:FindFirstChildOfClass("Humanoid")
        if hrp and hum then
            hum.AutoRotate = false
            hrp.CFrame = CFrame.new(hrp.Position, Vector3.new(
                workspace.CurrentCamera.CFrame.LookVector.X * 900000,
                hrp.Position.Y,
                workspace.CurrentCamera.CFrame.LookVector.Z * 900000
            ))
        end
    end)
end

local function disableLock()
    if not Active then return end
    Active = false
    btn.Image = States.Off
    cursor.Visible = false
    local hum = Player.Character and Player.Character:FindFirstChildOfClass("Humanoid")
    if hum then hum.AutoRotate = true end
    if Connection then Connection:Disconnect() Connection = nil end
end

local function toggleLock()
    if Active then
        disableLock()
    else
        enableLock()
    end
end

-- UI button toggle
btn.MouseButton1Click:Connect(toggleLock)

-- Keybinds: Left Alt, Right Alt, Right Ctrl
UserInputService.InputBegan:Connect(function(input, gp)
    if gp then return end
    if input.KeyCode == Enum.KeyCode.LeftAlt or
       input.KeyCode == Enum.KeyCode.RightAlt or
       input.KeyCode == Enum.KeyCode.RightControl then
        toggleLock()
    end
end)

-- Cleanup API for Rayfield or external
getgenv().kyri_shiftlock_kill = function()
    disableLock()
    if gui then gui:Destroy() end
end
