-- Evolve a Fish Hub (Fluent-Custom) v2
local Fluent = loadstring(game:HttpGet("https://raw.githubusercontent.com/Hund335/Fluent-Custom/main/Fluent.lua"))()
local SaveManager = loadstring(game:HttpGet("https://raw.githubusercontent.com/dawid-scripts/Fluent/master/Addons/SaveManager.lua"))()
local InterfaceManager = loadstring(game:HttpGet("https://raw.githubusercontent.com/dawid-scripts/Fluent/master/Addons/InterfaceManager.lua"))()

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local VirtualUser = game:GetService("VirtualUser")
local LocalPlayer = Players.LocalPlayer
local Camera = workspace.CurrentCamera
local Options = Fluent.Options

local fireTouch = firetouchinterest -- executor function; may be nil
local DrawingLib = Drawing -- executor library; may be nil

local connections = {}
local function connect(signal, fn)
    local c = signal:Connect(fn)
    table.insert(connections, c)
    return c
end

local function getChar() return LocalPlayer.Character end
local function getRoot(char)
    char = char or getChar()
    if not char then return nil end
    return char:FindFirstChild("HumanoidRootPart") or char.PrimaryPart or char:FindFirstChildWhichIsA("BasePart")
end
local function charSize(char)
    local ok, size = pcall(char.GetExtentsSize, char)
    return ok and size.Magnitude or 0
end
local function isPlayerPart(inst)
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr.Character and inst:IsDescendantOf(plr.Character) then return true end
    end
    return false
end
local function posOf(obj)
    if obj:IsA("Model") then return obj:GetPivot().Position end
    return obj.Position
end
local function touchAll(obj, root)
    if not fireTouch then return end
    local parts = obj:IsA("BasePart") and { obj } or obj:GetDescendants()
    for _, p in ipairs(parts) do
        if p:IsA("BasePart") then
            pcall(fireTouch, root, p, 0)
            pcall(fireTouch, root, p, 1)
        end
    end
end
local function moveTo(char, pos)
    local root = getRoot(char)
    if not root then return end
    root.AssemblyLinearVelocity = Vector3.zero
    char:PivotTo(CFrame.new(pos) * (char:GetPivot() - char:GetPivot().Position))
end

local Window = Fluent:CreateWindow({
    Title = "Evolve a Fish Hub",
    SubTitle = "Fluent-Custom",
    TabWidth = 160,
    Size = UDim2.fromOffset(580, 480),
    Acrylic = true,
    Theme = "Aqua",
    MinimizeKey = Enum.KeyCode.LeftControl,
})

local Tabs = {
    Farm = Window:AddTab({ Title = "Auto Farm", Icon = "fish" }),
    Combat = Window:AddTab({ Title = "Auto Kill", Icon = "sword" }),
    Visuals = Window:AddTab({ Title = "ESP", Icon = "eye" }),
    Player = Window:AddTab({ Title = "Player", Icon = "user" }),
    Scanner = Window:AddTab({ Title = "Scanner", Icon = "search" }),
    Settings = Window:AddTab({ Title = "Settings", Icon = "settings" }),
}

----------------------------------------------------------------------
-- Orb detection
----------------------------------------------------------------------
local DEFAULT_WORDS = "orb,food,xp,exp,pellet,plankton,bubble,crumb,algae,shrimp,krill,coin,gem,drop,pickup,collect"
local DANGER = { "kill", "lava", "damage", "death", "dead", "void", "spike", "trap", "border", "wall" }

local function wordList()
    local text = Options.FoodFilter.Value
    if not text or text == "" then text = DEFAULT_WORDS end
    local words = {}
    for w in text:lower():gmatch("[^,%s]+") do table.insert(words, w) end
    return words
end
local function matches(name, words)
    name = name:lower()
    for _, bad in ipairs(DANGER) do
        if name:find(bad, 1, true) then return false end
    end
    for _, w in ipairs(words) do
        if name:find(w, 1, true) then return true end
    end
    return false
end

-- folders with many children (orbs are usually in one)
local function folderPaths()
    local list = {}
    local function add(inst, path, depth)
        for _, child in ipairs(inst:GetChildren()) do
            if (child:IsA("Folder") or child:IsA("Model")) and not Players:GetPlayerFromCharacter(child) then
                local p = path == "" and child.Name or (path .. "/" .. child.Name)
                local n = #child:GetChildren()
                if n >= 8 then table.insert(list, { p, n }) end
                if depth < 2 then add(child, p, depth + 1) end
            end
        end
    end
    add(workspace, "", 1)
    table.sort(list, function(a, b) return a[2] > b[2] end)
    local names = { "Auto" }
    for i = 1, math.min(30, #list) do table.insert(names, list[i][1]) end
    return names
end
local function resolvePath(path)
    local inst = workspace
    for part in path:gmatch("[^/]+") do
        inst = inst and inst:FindFirstChild(part)
    end
    return inst
end

local orbCache, lastScan, visited = {}, 0, {}
local function refreshOrbs()
    local list, seen = {}, {}
    local folderName = Options.FoodFolder.Value or "Auto"
    if folderName ~= "Auto" then
        local folder = resolvePath(folderName)
        local filterOn = (Options.FoodFilter.Value or "") ~= ""
        local words = wordList()
        if folder then
            for _, obj in ipairs(folder:GetChildren()) do
                if (obj:IsA("BasePart") or obj:IsA("Model")) and (not filterOn or matches(obj.Name, words)) then
                    table.insert(list, obj)
                end
            end
        end
    else
        local words = wordList()
        for _, obj in ipairs(workspace:GetDescendants()) do
            if obj:IsA("BasePart") and obj.Size.Magnitude < 60 and not isPlayerPart(obj) then
                local parent = obj.Parent
                local target
                if matches(obj.Name, words) then
                    target = obj
                elseif parent and parent:IsA("Model") and parent ~= workspace and matches(parent.Name, words) then
                    target = parent
                elseif obj:FindFirstChildOfClass("TouchTransmitter") and parent and matches(parent.Name, words) then
                    target = obj
                end
                if target and not seen[target] then
                    seen[target] = true
                    table.insert(list, target)
                end
            end
        end
    end
    orbCache, lastScan = list, os.clock()
end

local function nearestOrb(root)
    if os.clock() - lastScan > 1.5 then refreshOrbs() end
    local best, bestDist = nil, Options.FarmRange.Value
    local now = os.clock()
    for _, obj in ipairs(orbCache) do
        if obj.Parent and (not visited[obj] or now - visited[obj] > 3) then
            local d = (posOf(obj) - root.Position).Magnitude
            if d < bestDist then best, bestDist = obj, d end
        end
    end
    return best
end

----------------------------------------------------------------------
-- Auto Farm tab
----------------------------------------------------------------------
Tabs.Farm:AddParagraph({
    Title = "Tipp",
    Content = "Findet er nichts: Bei 'Orb-Ordner' auf Aktualisieren druecken und den Ordner waehlen, "
        .. "in dem die Orbs liegen (meist der mit den meisten Kindern).",
})

local FolderDrop = Tabs.Farm:AddDropdown("FoodFolder", {
    Title = "Orb-Ordner",
    Description = "Auto = sucht per Namen in der ganzen Map",
    Values = folderPaths(),
    Multi = false,
    Default = 1,
})
FolderDrop:OnChanged(function() lastScan = 0 end)
Tabs.Farm:AddButton({
    Title = "Ordner-Liste aktualisieren",
    Callback = function()
        FolderDrop:SetValues(folderPaths())
        Fluent:Notify({ Title = "Auto Farm", Content = "Ordner-Liste neu geladen.", Duration = 3 })
    end,
})

Tabs.Farm:AddInput("FoodFilter", {
    Title = "Namens-Filter",
    Description = "Leer = Standard (orb, food, xp, ...)",
    Default = "",
    Placeholder = "orb, food, xp",
    Finished = true,
    Callback = function() lastScan = 0 end,
})

Tabs.Farm:AddDropdown("FarmMethod", {
    Title = "Methode",
    Values = { "Teleport + Touch", "Teleport", "Touch only", "Tween" },
    Multi = false,
    Default = 1,
})
Tabs.Farm:AddSlider("FarmRange", {
    Title = "Reichweite", Min = 50, Max = 10000, Default = 3000, Increment = 50, Suffix = " studs",
})
Tabs.Farm:AddSlider("FarmDelay", {
    Title = "Pause pro Orb", Min = 0, Max = 1, Default = 0.1, Increment = 0.05, Suffix = " s",
})

local function collect(obj, char, root)
    local method = Options.FarmMethod.Value
    local pos = posOf(obj)
    if method == "Tween" then
        local start = root.Position
        local steps = math.max(1, math.floor((pos - start).Magnitude / 20))
        for i = 1, steps do
            if not Options.AutoFarm.Value or Fluent.Unloaded or not obj.Parent then return end
            moveTo(char, start:Lerp(pos, i / steps))
            task.wait()
        end
        touchAll(obj, root)
    elseif method == "Touch only" then
        touchAll(obj, root)
    elseif method == "Teleport" then
        moveTo(char, pos)
    else
        moveTo(char, pos)
        task.wait()
        touchAll(obj, root)
    end
end

local collected = 0
local FarmStatus = Tabs.Farm:AddParagraph({ Title = "Status", Content = "Aus" })

Tabs.Farm:AddToggle("AutoFarm", { Title = "Auto Farm", Default = false })
Options.AutoFarm:OnChanged(function(on)
    if not on then FarmStatus:SetDesc("Aus") return end
    lastScan = 0
    task.spawn(function()
        while Options.AutoFarm.Value and not Fluent.Unloaded do
            local char = getChar()
            local root = getRoot(char)
            if root then
                local orb = nearestOrb(root)
                if orb then
                    visited[orb] = os.clock()
                    collect(orb, char, root)
                    collected += 1
                    FarmStatus:SetDesc(string.format("Gesammelt: %d | Gefunden: %d", collected, #orbCache))
                else
                    FarmStatus:SetDesc("Keine Orbs gefunden (" .. #orbCache .. " im Cache). Ordner waehlen!")
                    task.wait(0.5)
                end
            end
            task.wait(Options.FarmDelay.Value)
        end
    end)
end)

----------------------------------------------------------------------
-- Auto Kill tab
----------------------------------------------------------------------
Tabs.Combat:AddParagraph({
    Title = "Info",
    Content = "Teleportiert dich an andere Spieler und beruehrt sie, damit du sie frisst.",
})
Tabs.Combat:AddToggle("KillSmaller", {
    Title = "Nur kleinere Fische", Description = "Vergleicht die Groesse der Charaktere", Default = true,
})
Tabs.Combat:AddSlider("KillRange", {
    Title = "Reichweite", Min = 50, Max = 10000, Default = 2000, Increment = 50, Suffix = " studs",
})
Tabs.Combat:AddSlider("KillTime", {
    Title = "Zeit pro Ziel", Min = 0.1, Max = 3, Default = 0.6, Increment = 0.1, Suffix = " s",
})

local function pickTarget(root)
    local mySize = charSize(getChar())
    local best, bestDist = nil, Options.KillRange.Value
    for _, plr in ipairs(Players:GetPlayers()) do
        local char = plr.Character
        local r = char and getRoot(char)
        local hum = char and char:FindFirstChildOfClass("Humanoid")
        if plr ~= LocalPlayer and r and (not hum or hum.Health > 0)
            and (not Options.KillSmaller.Value or charSize(char) < mySize) then
            local d = (r.Position - root.Position).Magnitude
            if d < bestDist then best, bestDist = plr, d end
        end
    end
    return best
end

local KillStatus = Tabs.Combat:AddParagraph({ Title = "Status", Content = "Aus" })
Tabs.Combat:AddToggle("AutoKill", { Title = "Auto Kill", Default = false })
Options.AutoKill:OnChanged(function(on)
    if not on then KillStatus:SetDesc("Aus") return end
    task.spawn(function()
        while Options.AutoKill.Value and not Fluent.Unloaded do
            local char = getChar()
            local root = getRoot(char)
            local target = root and pickTarget(root)
            if target then
                KillStatus:SetDesc("Ziel: " .. target.DisplayName)
                local untilT = os.clock() + Options.KillTime.Value
                while os.clock() < untilT and Options.AutoKill.Value and not Fluent.Unloaded do
                    local tChar = target.Character
                    local tRoot = tChar and getRoot(tChar)
                    if not tRoot or not getRoot(char) then break end
                    moveTo(char, tRoot.Position)
                    touchAll(tChar, getRoot(char))
                    task.wait()
                end
            else
                KillStatus:SetDesc("Kein passendes Ziel in Reichweite")
                task.wait(0.5)
            end
            task.wait(0.05)
        end
    end)
end)

----------------------------------------------------------------------
-- ESP tab
----------------------------------------------------------------------
Tabs.Visuals:AddToggle("EspOn", { Title = "Highlight", Default = false })
Tabs.Visuals:AddToggle("EspNames", { Title = "Name + Distanz", Default = false })
Tabs.Visuals:AddToggle("EspLines", {
    Title = "ESP Linien", Description = (not DrawingLib) and "Dein Executor hat keine Drawing-Library" or nil, Default = false,
})
Tabs.Visuals:AddDropdown("LineOrigin", {
    Title = "Linien von", Values = { "Unten", "Mitte", "Maus" }, Multi = false, Default = 1,
})
Tabs.Visuals:AddToggle("EspSizeColor", {
    Title = "Farbe nach Groesse", Description = "Gruen = kleiner (essbar), Rot = groesser", Default = true,
})
Tabs.Visuals:AddColorpicker("EspColor", { Title = "ESP Farbe", Default = Color3.fromRGB(96, 205, 255) })

local esp = {} -- [player] = { hl, tag, label, line }

local function clearEsp(plr)
    local o = esp[plr]
    if not o then return end
    if o.hl then o.hl:Destroy() end
    if o.tag then o.tag:Destroy() end
    if o.line then o.line:Remove() end
    esp[plr] = nil
end

local function buildEsp(plr)
    local old = esp[plr]
    local line = old and old.line
    if old then
        if old.hl then old.hl:Destroy() end
        if old.tag then old.tag:Destroy() end
    end
    local char = plr.Character
    if not char then esp[plr] = line and { line = line } or nil return end

    local hl = Instance.new("Highlight")
    hl.FillTransparency = 0.6
    hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    hl.Adornee = char
    hl.Parent = char

    local tag, label
    local root = getRoot(char)
    if root then
        tag = Instance.new("BillboardGui")
        tag.Size = UDim2.fromOffset(200, 30)
        tag.StudsOffset = Vector3.new(0, 3, 0)
        tag.AlwaysOnTop = true
        tag.Adornee = root
        label = Instance.new("TextLabel")
        label.Size = UDim2.fromScale(1, 1)
        label.BackgroundTransparency = 1
        label.TextStrokeTransparency = 0.3
        label.Font = Enum.Font.GothamBold
        label.TextSize = 13
        label.Parent = tag
        tag.Parent = root
    end

    if not line and DrawingLib then
        line = DrawingLib.new("Line")
        line.Thickness = 1.5
        line.Visible = false
    end

    esp[plr] = { hl = hl, tag = tag, label = label, line = line }
end

local function hookPlayer(plr)
    if plr == LocalPlayer then return end
    connect(plr.CharacterAdded, function() task.wait(0.5) buildEsp(plr) end)
    buildEsp(plr)
end
for _, plr in ipairs(Players:GetPlayers()) do hookPlayer(plr) end
connect(Players.PlayerAdded, hookPlayer)
connect(Players.PlayerRemoving, clearEsp)

connect(RunService.RenderStepped, function()
    local myChar = getChar()
    local myRoot = getRoot(myChar)
    local mySize = myChar and charSize(myChar) or 0
    local vp = Camera.ViewportSize
    local origin
    if Options.LineOrigin.Value == "Mitte" then
        origin = vp / 2
    elseif Options.LineOrigin.Value == "Maus" then
        origin = UserInputService:GetMouseLocation()
    else
        origin = Vector2.new(vp.X / 2, vp.Y - 2)
    end

    for plr, o in pairs(esp) do
        local char = plr.Character
        local root = char and getRoot(char)
        local color = Options.EspColor.Value
        if Options.EspSizeColor.Value and char then
            color = charSize(char) < mySize and Color3.fromRGB(80, 230, 110) or Color3.fromRGB(240, 70, 70)
        end

        if o.hl then
            o.hl.Enabled = Options.EspOn.Value
            o.hl.FillColor = color
            o.hl.OutlineColor = color
        end
        if o.tag then
            o.tag.Enabled = Options.EspNames.Value
            if Options.EspNames.Value and root then
                local dist = myRoot and math.floor((root.Position - myRoot.Position).Magnitude) or 0
                o.label.Text = string.format("%s [%dm]", plr.DisplayName, dist)
                o.label.TextColor3 = color
            end
        end
        if o.line then
            local visible = false
            if Options.EspLines.Value and root then
                local screen, onScreen = Camera:WorldToViewportPoint(root.Position)
                if onScreen then
                    o.line.From = origin
                    o.line.To = Vector2.new(screen.X, screen.Y)
                    o.line.Color = color
                    visible = true
                end
            end
            o.line.Visible = visible
        end
    end
end)

----------------------------------------------------------------------
-- Player tab (Fast Swim)
----------------------------------------------------------------------
Tabs.Player:AddToggle("FastSwim", {
    Title = "Fast Swim", Description = "WASD in Blickrichtung, Space hoch, LeftShift runter", Default = false,
})
Tabs.Player:AddSlider("SwimSpeed", {
    Title = "Swim Speed", Min = 20, Max = 500, Default = 100, Increment = 5, Suffix = " studs/s",
})
Tabs.Player:AddKeybind("SwimKey", {
    Title = "Fast Swim Taste",
    Mode = "Toggle",
    Default = "X",
    Callback = function() Options.FastSwim:SetValue(not Options.FastSwim.Value) end,
})

connect(RunService.Heartbeat, function(dt)
    if not Options.FastSwim.Value or UserInputService:GetFocusedTextBox() then return end
    local root = getRoot()
    if not root then return end
    local cf = Camera.CFrame
    local dir = Vector3.zero
    if UserInputService:IsKeyDown(Enum.KeyCode.W) then dir += cf.LookVector end
    if UserInputService:IsKeyDown(Enum.KeyCode.S) then dir -= cf.LookVector end
    if UserInputService:IsKeyDown(Enum.KeyCode.D) then dir += cf.RightVector end
    if UserInputService:IsKeyDown(Enum.KeyCode.A) then dir -= cf.RightVector end
    if UserInputService:IsKeyDown(Enum.KeyCode.Space) then dir += Vector3.yAxis end
    if UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) then dir -= Vector3.yAxis end
    if dir.Magnitude == 0 then return end
    dir = dir.Unit
    -- move by CFrame so custom fish controllers can't cap the speed
    root.CFrame = root.CFrame + dir * Options.SwimSpeed.Value * dt
    root.AssemblyLinearVelocity = dir * Options.SwimSpeed.Value
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
    table.insert(out, "-- Big folders --")
    for i, p in ipairs(folderPaths()) do
        if i > 1 then
            local f = resolvePath(p)
            local sample = f and f:GetChildren()[1]
            table.insert(out, p .. "  (" .. (f and #f:GetChildren() or 0) .. ")  e.g. "
                .. (sample and (sample.ClassName .. " " .. sample.Name) or "-"))
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
    for i = 1, math.min(25, #sorted) do table.insert(out, sorted[i][2] .. "x  " .. sorted[i][1]) end

    table.insert(out, "")
    table.insert(out, "-- My character --")
    local char = getChar()
    if char then
        for _, d in ipairs(char:GetDescendants()) do
            if d:IsA("BodyMover") or d:IsA("Constraint") or d:IsA("Script") or d:IsA("LocalScript") or d:IsA("Humanoid") then
                table.insert(out, d.ClassName .. "  " .. d:GetFullName())
            end
        end
    end

    table.insert(out, "")
    table.insert(out, "-- Player data --")
    local gui = LocalPlayer:FindFirstChildOfClass("PlayerGui")
    for _, obj in ipairs(LocalPlayer:GetDescendants()) do
        if obj:IsA("ValueBase") and not (gui and obj:IsDescendantOf(gui)) then
            table.insert(out, obj:GetFullName() .. " = " .. tostring(obj.Value))
        end
    end
    for k, v in pairs(LocalPlayer:GetAttributes()) do table.insert(out, "Attr " .. k .. " = " .. tostring(v)) end
    if char then
        for k, v in pairs(char:GetAttributes()) do table.insert(out, "CharAttr " .. k .. " = " .. tostring(v)) end
    end
    return table.concat(out, "\n")
end

Tabs.Scanner:AddButton({
    Title = "Spiel scannen",
    Description = "Kopiert Remotes, Ordner, Charakter-Infos und Stats in die Zwischenablage",
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
    for plr in pairs(esp) do clearEsp(plr) end
end)

----------------------------------------------------------------------
-- Settings
----------------------------------------------------------------------
SaveManager:SetLibrary(Fluent)
InterfaceManager:SetLibrary(Fluent)
SaveManager:IgnoreThemeSettings()
SaveManager:SetIgnoreIndexes({ "FoodFolder" })
InterfaceManager:SetFolder("EvolveAFishHub")
SaveManager:SetFolder("EvolveAFishHub/configs")
InterfaceManager:BuildInterfaceSection(Tabs.Settings)
SaveManager:BuildConfigSection(Tabs.Settings)

Window:SelectTab(1)
Fluent:Notify({ Title = "Evolve a Fish Hub v2", Content = "Loaded. LeftCtrl = hide/show, X = Fast Swim.", Duration = 5 })
SaveManager:LoadAutoloadConfig()
