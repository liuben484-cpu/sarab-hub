-- Evolve a Fish Hub (Fluent-Custom)
local Fluent = loadstring(game:HttpGet("https://raw.githubusercontent.com/Hund335/Fluent-Custom/main/Fluent.lua"))()
local SaveManager = loadstring(game:HttpGet("https://raw.githubusercontent.com/dawid-scripts/Fluent/master/Addons/SaveManager.lua"))()
local InterfaceManager = loadstring(game:HttpGet("https://raw.githubusercontent.com/dawid-scripts/Fluent/master/Addons/InterfaceManager.lua"))()

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local VirtualUser = game:GetService("VirtualUser")
local LocalPlayer = Players.LocalPlayer
local Options = Fluent.Options

local fireTouch = firetouchinterest -- executor function; may be nil

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
    return c and (c:FindFirstChild("HumanoidRootPart") or c.PrimaryPart)
end

local Window = Fluent:CreateWindow({
    Title = "Evolve a Fish Hub",
    SubTitle = "Fluent-Custom",
    TabWidth = 160,
    Size = UDim2.fromOffset(580, 460),
    Acrylic = true,
    Theme = "Aqua",
    MinimizeKey = Enum.KeyCode.LeftControl,
})

local Tabs = {
    Farm = Window:AddTab({ Title = "Auto Farm", Icon = "fish" }),
    Player = Window:AddTab({ Title = "Player", Icon = "user" }),
    Scanner = Window:AddTab({ Title = "Scanner", Icon = "search" }),
    Settings = Window:AddTab({ Title = "Settings", Icon = "settings" }),
}

----------------------------------------------------------------------
-- Food detection
----------------------------------------------------------------------
local DANGER = { "kill", "lava", "damage", "death", "dead", "void", "spike", "trap" }

local function isPlayerPart(part)
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr.Character and part:IsDescendantOf(plr.Character) then return true end
    end
    return false
end

local function nameMatches(part, filter)
    local name = (part.Name .. " " .. (part.Parent and part.Parent.Name or "")):lower()
    for _, bad in ipairs(DANGER) do
        if name:find(bad, 1, true) then return false end
    end
    if filter == "" then return true end
    for word in filter:lower():gmatch("[^,%s]+") do
        if name:find(word, 1, true) then return true end
    end
    return false
end

local foodCache, lastScan = {}, 0
local function refreshFood()
    local filter = Options.FoodFilter.Value or ""
    local list = {}
    for _, obj in ipairs(workspace:GetDescendants()) do
        if obj:IsA("TouchTransmitter") then
            local part = obj.Parent
            if part and part:IsA("BasePart") and part.Size.Magnitude < 60
                and not isPlayerPart(part) and nameMatches(part, filter) then
                table.insert(list, part)
            end
        end
    end
    foodCache, lastScan = list, os.clock()
end

local function nearestFood(root)
    if os.clock() - lastScan > 2 then refreshFood() end
    local best, bestDist = nil, Options.FarmRange.Value
    for _, part in ipairs(foodCache) do
        if part.Parent then
            local d = (part.Position - root.Position).Magnitude
            if d < bestDist then best, bestDist = part, d end
        end
    end
    return best
end

----------------------------------------------------------------------
-- Auto Farm tab
----------------------------------------------------------------------
Tabs.Farm:AddParagraph({
    Title = "So funktioniert's",
    Content = "Sucht Teile, die man beruehren kann (Food, Orbs, XP), und sammelt das naechste ein.\n"
        .. "Ohne Filter wird alles Beruehrbare genommen (Kill-Bricks werden uebersprungen).\n"
        .. "Kein XP? Im Scanner-Tab scannen und mir die Ausgabe schicken.",
})

Tabs.Farm:AddInput("FoodFilter", {
    Title = "Food-Filter",
    Description = "Woerter im Teilnamen, mit Komma getrennt (leer = alles)",
    Default = "",
    Placeholder = "food, orb, xp, plankton",
    Finished = true,
    Callback = function() lastScan = 0 end,
})

Tabs.Farm:AddDropdown("FarmMethod", {
    Title = "Methode",
    Values = { "Touch", "Teleport", "Tween" },
    Multi = false,
    Default = fireTouch and 1 or 2,
})

Tabs.Farm:AddSlider("FarmRange", {
    Title = "Reichweite", Min = 50, Max = 5000, Default = 1000, Increment = 50, Suffix = " studs",
})
Tabs.Farm:AddSlider("FarmDelay", {
    Title = "Pause zwischen Food", Min = 0.05, Max = 2, Default = 0.2, Increment = 0.05, Suffix = " s",
})

local function collect(part, root)
    local method = Options.FarmMethod.Value
    if method == "Touch" and fireTouch then
        fireTouch(root, part, 0)
        task.wait()
        fireTouch(root, part, 1)
    elseif method == "Tween" then
        local dist = (part.Position - root.Position).Magnitude
        local steps = math.max(1, math.floor(dist / 15))
        local start = root.Position
        for i = 1, steps do
            if not Options.AutoFarm.Value or Fluent.Unloaded or not part.Parent then return end
            root.CFrame = CFrame.new(start:Lerp(part.Position, i / steps))
            task.wait()
        end
    else
        root.CFrame = part.CFrame
    end
end

local collected = 0
local Stats = Tabs.Farm:AddParagraph({ Title = "Status", Content = "Aus" })

Tabs.Farm:AddToggle("AutoFarm", { Title = "Auto Farm (Food sammeln)", Default = false })
Options.AutoFarm:OnChanged(function(on)
    if not on then Stats:SetDesc("Aus") return end
    lastScan = 0
    task.spawn(function()
        while Options.AutoFarm.Value and not Fluent.Unloaded do
            local root = getRoot()
            if root then
                local food = nearestFood(root)
                if food then
                    collect(food, root)
                    collected += 1
                    Stats:SetDesc(string.format("Gesammelt: %d | Im Cache: %d", collected, #foodCache))
                else
                    Stats:SetDesc("Kein Food in Reichweite (" .. #foodCache .. " gefunden)")
                    task.wait(0.5)
                end
            end
            task.wait(Options.FarmDelay.Value)
        end
    end)
end)

Tabs.Farm:AddToggle("AutoRespawn", {
    Title = "Auto Respawn",
    Description = "Klickt Respawn/Play-Buttons, wenn du stirbst",
    Default = false,
})
connect(LocalPlayer.CharacterRemoving, function()
    if not Options.AutoRespawn.Value then return end
    task.delay(2, function()
        local gui = LocalPlayer:FindFirstChildOfClass("PlayerGui")
        if not gui then return end
        for _, b in ipairs(gui:GetDescendants()) do
            if b:IsA("GuiButton") and b.Visible then
                local t = ((b:IsA("TextButton") and b.Text or "") .. " " .. b.Name):lower()
                if t:find("respawn") or t:find("play") or t:find("spawn") then
                    pcall(function() firesignal(b.MouseButton1Click) end)
                    pcall(function() firesignal(b.Activated) end)
                end
            end
        end
    end)
end)

----------------------------------------------------------------------
-- Player tab
----------------------------------------------------------------------
Tabs.Player:AddSlider("WalkSpeed", {
    Title = "Swim / Walk Speed", Min = 16, Max = 250, Default = 16, Increment = 1, Suffix = " studs/s",
})
local function applySpeed()
    local hum = getHum()
    if hum then hum.WalkSpeed = Options.WalkSpeed.Value end
end
Options.WalkSpeed:OnChanged(applySpeed)
connect(RunService.Heartbeat, function()
    local hum = getHum()
    if hum and Options.WalkSpeed.Value ~= 16 and hum.WalkSpeed ~= Options.WalkSpeed.Value then
        hum.WalkSpeed = Options.WalkSpeed.Value
    end
end)
connect(LocalPlayer.CharacterAdded, function(char)
    char:WaitForChild("Humanoid", 10)
    applySpeed()
end)

Tabs.Player:AddToggle("AntiAfk", { Title = "Anti AFK", Default = true })
connect(LocalPlayer.Idled, function()
    if not Options.AntiAfk.Value then return end
    VirtualUser:CaptureController()
    VirtualUser:ClickButton2(Vector2.new())
end)

Tabs.Player:AddButton({ Title = "Unload Script", Callback = function() Fluent:Destroy() end })

----------------------------------------------------------------------
-- Scanner tab
----------------------------------------------------------------------
local LiveStats = Tabs.Scanner:AddParagraph({ Title = "Deine Stats", Content = "..." })
task.spawn(function()
    while not Fluent.Unloaded do
        local ls = LocalPlayer:FindFirstChild("leaderstats")
        local lines = {}
        if ls then
            for _, v in ipairs(ls:GetChildren()) do
                if v:IsA("ValueBase") then table.insert(lines, v.Name .. ": " .. tostring(v.Value)) end
            end
        end
        LiveStats:SetDesc(#lines > 0 and table.concat(lines, "\n") or "Keine leaderstats gefunden")
        task.wait(1)
    end
end)

local function buildReport()
    local out = { "=== Evolve a Fish Scan | PlaceId " .. game.PlaceId .. " ===", "", "-- Remotes --" }
    for _, obj in ipairs(ReplicatedStorage:GetDescendants()) do
        if obj:IsA("RemoteEvent") or obj:IsA("RemoteFunction") or obj:IsA("UnreliableRemoteEvent") then
            table.insert(out, obj.ClassName .. "  " .. obj:GetFullName())
        end
    end

    table.insert(out, "")
    table.insert(out, "-- Workspace (top level) --")
    for _, obj in ipairs(workspace:GetChildren()) do
        if not Players:GetPlayerFromCharacter(obj) then
            table.insert(out, obj.ClassName .. "  " .. obj.Name .. "  (" .. #obj:GetChildren() .. " children)")
        end
    end

    table.insert(out, "")
    table.insert(out, "-- Touchable parts by name --")
    local counts = {}
    for _, obj in ipairs(workspace:GetDescendants()) do
        if obj:IsA("TouchTransmitter") and obj.Parent and not isPlayerPart(obj.Parent) then
            local key = obj.Parent:GetFullName():gsub("%d+$", "#")
            counts[key] = (counts[key] or 0) + 1
        end
    end
    local sorted = {}
    for k, v in pairs(counts) do table.insert(sorted, { k, v }) end
    table.sort(sorted, function(a, b) return a[2] > b[2] end)
    for i = 1, math.min(25, #sorted) do
        table.insert(out, sorted[i][2] .. "x  " .. sorted[i][1])
    end

    table.insert(out, "")
    table.insert(out, "-- Player data --")
    for _, obj in ipairs(LocalPlayer:GetDescendants()) do
        if obj:IsA("ValueBase") and not obj:IsDescendantOf(LocalPlayer:FindFirstChildOfClass("PlayerGui") or Instance.new("Folder")) then
            table.insert(out, obj:GetFullName() .. " = " .. tostring(obj.Value))
        end
    end
    local attrs = LocalPlayer:GetAttributes()
    for k, v in pairs(attrs) do table.insert(out, "Attr " .. k .. " = " .. tostring(v)) end

    return table.concat(out, "\n")
end

Tabs.Scanner:AddButton({
    Title = "Spiel scannen",
    Description = "Kopiert Remotes, Food-Teile und Stats in die Zwischenablage",
    Callback = function()
        local report = buildReport()
        print(report)
        if setclipboard then
            setclipboard(report)
            Fluent:Notify({ Title = "Scanner", Content = "In Zwischenablage kopiert. Schick es mir!", Duration = 6 })
        else
            Fluent:Notify({ Title = "Scanner", Content = "Kein setclipboard - steht in der Konsole (F9).", Duration = 6 })
        end
    end,
})

----------------------------------------------------------------------
-- Cleanup
----------------------------------------------------------------------
task.spawn(function()
    repeat task.wait(1) until Fluent.Unloaded
    for _, c in ipairs(connections) do c:Disconnect() end
    local hum = getHum()
    if hum then hum.WalkSpeed = 16 end
end)

----------------------------------------------------------------------
-- Settings
----------------------------------------------------------------------
SaveManager:SetLibrary(Fluent)
InterfaceManager:SetLibrary(Fluent)
SaveManager:IgnoreThemeSettings()
SaveManager:SetIgnoreIndexes({})
InterfaceManager:SetFolder("EvolveAFishHub")
SaveManager:SetFolder("EvolveAFishHub/configs")
InterfaceManager:BuildInterfaceSection(Tabs.Settings)
SaveManager:BuildConfigSection(Tabs.Settings)

Window:SelectTab(1)
Fluent:Notify({ Title = "Evolve a Fish Hub", Content = "Loaded. LeftCtrl = hide/show.", Duration = 5 })
SaveManager:LoadAutoloadConfig()
