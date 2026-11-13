-- Sarab Hub (Fluent-Custom)
local Fluent = loadstring(game:HttpGet("https://raw.githubusercontent.com/Hund335/Fluent-Custom/main/Fluent.lua"))()
local SaveManager = loadstring(game:HttpGet("https://raw.githubusercontent.com/dawid-scripts/Fluent/master/Addons/SaveManager.lua"))()
local InterfaceManager = loadstring(game:HttpGet("https://raw.githubusercontent.com/dawid-scripts/Fluent/master/Addons/InterfaceManager.lua"))()

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local VirtualUser = game:GetService("VirtualUser")
local LocalPlayer = Players.LocalPlayer
local Camera = workspace.CurrentCamera
local Options = Fluent.Options

local connections = {}
local function connect(signal, fn)
    local c = signal:Connect(fn)
    table.insert(connections, c)
    return c
end

local function getChar() return LocalPlayer.Character end
local function getHum()
    local c = getChar()
    return c and c:FindFirstChildOfClass("Humanoid")
end
local function getRoot()
    local c = getChar()
    return c and c:FindFirstChild("HumanoidRootPart")
end

local Window = Fluent:CreateWindow({
    Title = "Sarab Hub",
    SubTitle = "Fluent-Custom",
    TabWidth = 160,
    Size = UDim2.fromOffset(580, 460),
    Acrylic = true,
    Theme = "Dark",
    MinimizeKey = Enum.KeyCode.LeftControl,
})

local Tabs = {
    Player = Window:AddTab({ Title = "Player", Icon = "user" }),
    Visuals = Window:AddTab({ Title = "Visuals", Icon = "eye" }),
    Teleport = Window:AddTab({ Title = "Teleport", Icon = "map-pin" }),
    Misc = Window:AddTab({ Title = "Misc", Icon = "box" }),
    Settings = Window:AddTab({ Title = "Settings", Icon = "settings" }),
}

----------------------------------------------------------------------
-- Player
----------------------------------------------------------------------
local Movement = Tabs.Player:AddSection("Movement")

Movement:AddSlider("WalkSpeed", {
    Title = "Walk Speed", Min = 16, Max = 200, Default = 16, Increment = 1, Suffix = " studs/s",
})
Movement:AddSlider("JumpPower", {
    Title = "Jump Power", Min = 50, Max = 300, Default = 50, Increment = 5,
})

local function applyStats()
    local hum = getHum()
    if not hum then return end
    hum.WalkSpeed = Options.WalkSpeed.Value
    hum.UseJumpPower = true
    hum.JumpPower = Options.JumpPower.Value
end
Options.WalkSpeed:OnChanged(applyStats)
Options.JumpPower:OnChanged(applyStats)

-- some games reset WalkSpeed; keep it applied
connect(RunService.Heartbeat, function()
    local hum = getHum()
    if hum and Options.WalkSpeed.Value ~= 16 and hum.WalkSpeed ~= Options.WalkSpeed.Value then
        hum.WalkSpeed = Options.WalkSpeed.Value
    end
end)
connect(LocalPlayer.CharacterAdded, function(char)
    char:WaitForChild("Humanoid")
    applyStats()
end)

Movement:AddToggle("InfJump", { Title = "Infinite Jump", Default = false })
connect(UserInputService.JumpRequest, function()
    if not Options.InfJump.Value then return end
    local hum = getHum()
    if hum then hum:ChangeState(Enum.HumanoidStateType.Jumping) end
end)

Movement:AddToggle("Noclip", { Title = "Noclip", Default = false })
connect(RunService.Stepped, function()
    if not Options.Noclip.Value then return end
    local char = getChar()
    if not char then return end
    for _, part in ipairs(char:GetDescendants()) do
        if part:IsA("BasePart") then part.CanCollide = false end
    end
end)

local FlySection = Tabs.Player:AddSection("Fly")
FlySection:AddToggle("Fly", { Title = "Fly", Description = "WASD + Space / LeftShift", Default = false })
FlySection:AddSlider("FlySpeed", { Title = "Fly Speed", Min = 10, Max = 300, Default = 60, Increment = 5 })
FlySection:AddKeybind("FlyKey", {
    Title = "Fly Key",
    Mode = "Toggle",
    Default = "F",
    Callback = function()
        Options.Fly:SetValue(not Options.Fly.Value)
    end,
})

Options.Fly:OnChanged(function(on)
    local hum = getHum()
    if hum then hum.PlatformStand = on end
end)

connect(RunService.Heartbeat, function()
    if not Options.Fly.Value then return end
    local root, hum = getRoot(), getHum()
    if not root or not hum then return end
    hum.PlatformStand = true
    local look, right = Camera.CFrame.LookVector, Camera.CFrame.RightVector
    local dir = Vector3.zero
    if UserInputService:IsKeyDown(Enum.KeyCode.W) then dir += look end
    if UserInputService:IsKeyDown(Enum.KeyCode.S) then dir -= look end
    if UserInputService:IsKeyDown(Enum.KeyCode.D) then dir += right end
    if UserInputService:IsKeyDown(Enum.KeyCode.A) then dir -= right end
    if UserInputService:IsKeyDown(Enum.KeyCode.Space) then dir += Vector3.yAxis end
    if UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) then dir -= Vector3.yAxis end
    if dir.Magnitude > 0 then dir = dir.Unit end
    root.AssemblyLinearVelocity = dir * Options.FlySpeed.Value
end)

----------------------------------------------------------------------
-- Visuals (ESP)
----------------------------------------------------------------------
local Esp = Tabs.Visuals:AddSection("Player ESP")
Esp:AddToggle("EspOn", { Title = "Highlight Players", Default = false })
Esp:AddToggle("EspNames", { Title = "Show Names + Distance", Default = false })
Esp:AddColorpicker("EspColor", { Title = "ESP Color", Default = Color3.fromRGB(96, 205, 255) })

local espObjects = {} -- [player] = { hl = Highlight, tag = BillboardGui, label = TextLabel }

local function clearEsp(plr)
    local o = espObjects[plr]
    if not o then return end
    if o.hl then o.hl:Destroy() end
    if o.tag then o.tag:Destroy() end
    espObjects[plr] = nil
end

local function buildEsp(plr)
    clearEsp(plr)
    local char = plr.Character
    if plr == LocalPlayer or not char then return end
    local head = char:FindFirstChild("Head") or char:FindFirstChild("HumanoidRootPart")

    local hl = Instance.new("Highlight")
    hl.FillTransparency = 0.6
    hl.OutlineTransparency = 0
    hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    hl.Adornee = char
    hl.Parent = char

    local tag, label
    if head then
        tag = Instance.new("BillboardGui")
        tag.Size = UDim2.fromOffset(200, 30)
        tag.StudsOffset = Vector3.new(0, 2.5, 0)
        tag.AlwaysOnTop = true
        tag.Adornee = head
        label = Instance.new("TextLabel")
        label.Size = UDim2.fromScale(1, 1)
        label.BackgroundTransparency = 1
        label.TextStrokeTransparency = 0.3
        label.Font = Enum.Font.GothamBold
        label.TextSize = 13
        label.Parent = tag
        tag.Parent = head
    end

    espObjects[plr] = { hl = hl, tag = tag, label = label }
end

local function hookPlayer(plr)
    if plr == LocalPlayer then return end
    connect(plr.CharacterAdded, function()
        task.wait(0.5)
        buildEsp(plr)
    end)
    if plr.Character then buildEsp(plr) end
end
for _, plr in ipairs(Players:GetPlayers()) do hookPlayer(plr) end
connect(Players.PlayerAdded, hookPlayer)
connect(Players.PlayerRemoving, clearEsp)

connect(RunService.RenderStepped, function()
    local color = Options.EspColor.Value
    local myRoot = getRoot()
    for plr, o in pairs(espObjects) do
        if o.hl then
            o.hl.Enabled = Options.EspOn.Value
            o.hl.FillColor = color
            o.hl.OutlineColor = color
        end
        if o.tag then
            o.tag.Enabled = Options.EspNames.Value
            if Options.EspNames.Value then
                local r = plr.Character and plr.Character:FindFirstChild("HumanoidRootPart")
                local dist = (r and myRoot) and math.floor((r.Position - myRoot.Position).Magnitude) or 0
                o.label.Text = string.format("%s [%dm]", plr.DisplayName, dist)
                o.label.TextColor3 = color
            end
        end
    end
end)

----------------------------------------------------------------------
-- Teleport
----------------------------------------------------------------------
local function otherPlayerNames()
    local names = {}
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= LocalPlayer then table.insert(names, plr.Name) end
    end
    table.sort(names)
    return names
end

local TpTarget = Tabs.Teleport:AddDropdown("TpTarget", {
    Title = "Player",
    Values = otherPlayerNames(),
    Multi = false,
    Default = 1,
})

local function refreshPlayers() TpTarget:SetValues(otherPlayerNames()) end
connect(Players.PlayerAdded, refreshPlayers)
connect(Players.PlayerRemoving, function() task.defer(refreshPlayers) end)

Tabs.Teleport:AddButton({
    Title = "Teleport to Player",
    Callback = function()
        local target = Players:FindFirstChild(Options.TpTarget.Value or "")
        local tRoot = target and target.Character and target.Character:FindFirstChild("HumanoidRootPart")
        local root = getRoot()
        if tRoot and root then
            root.CFrame = tRoot.CFrame * CFrame.new(0, 0, 3)
        else
            Fluent:Notify({ Title = "Teleport", Content = "Player not found.", Duration = 3 })
        end
    end,
})

local savedPos
Tabs.Teleport:AddButton({
    Title = "Save Position",
    Callback = function()
        local root = getRoot()
        if root then
            savedPos = root.CFrame
            Fluent:Notify({ Title = "Teleport", Content = "Position saved.", Duration = 3 })
        end
    end,
})
Tabs.Teleport:AddButton({
    Title = "Teleport to Saved Position",
    Callback = function()
        local root = getRoot()
        if root and savedPos then root.CFrame = savedPos end
    end,
})

----------------------------------------------------------------------
-- Misc
----------------------------------------------------------------------
Tabs.Misc:AddToggle("AntiAfk", { Title = "Anti AFK", Default = true })
connect(LocalPlayer.Idled, function()
    if not Options.AntiAfk.Value then return end
    VirtualUser:CaptureController()
    VirtualUser:ClickButton2(Vector2.new())
end)

Tabs.Misc:AddSlider("Fov", {
    Title = "Field of View", Min = 70, Max = 120, Default = 70, Increment = 1,
    Callback = function(v) Camera.FieldOfView = v end,
})

Tabs.Misc:AddButton({
    Title = "Rejoin",
    Callback = function()
        Window:Dialog({
            Title = "Rejoin",
            Content = "Rejoin this server?",
            Buttons = {
                { Title = "Yes", Callback = function()
                    game:GetService("TeleportService"):TeleportToPlaceInstance(game.PlaceId, game.JobId, LocalPlayer)
                end },
                { Title = "No", Callback = function() end },
            },
        })
    end,
})

Tabs.Misc:AddButton({
    Title = "Unload Script",
    Callback = function() Fluent:Destroy() end,
})

----------------------------------------------------------------------
-- Cleanup on unload
----------------------------------------------------------------------
task.spawn(function()
    repeat task.wait(1) until Fluent.Unloaded
    for _, c in ipairs(connections) do c:Disconnect() end
    for plr in pairs(espObjects) do clearEsp(plr) end
    local hum = getHum()
    if hum then
        hum.PlatformStand = false
        hum.WalkSpeed = 16
        hum.JumpPower = 50
    end
    Camera.FieldOfView = 70
end)

----------------------------------------------------------------------
-- Settings
----------------------------------------------------------------------
SaveManager:SetLibrary(Fluent)
InterfaceManager:SetLibrary(Fluent)
SaveManager:IgnoreThemeSettings()
SaveManager:SetIgnoreIndexes({ "TpTarget" })
InterfaceManager:SetFolder("SarabHub")
SaveManager:SetFolder("SarabHub/configs")
InterfaceManager:BuildInterfaceSection(Tabs.Settings)
SaveManager:BuildConfigSection(Tabs.Settings)

Window:SelectTab(1)
Fluent:Notify({ Title = "Sarab Hub", Content = "Loaded. LeftCtrl = hide/show.", Duration = 5 })
SaveManager:LoadAutoloadConfig()
