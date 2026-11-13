-- Standalone game scanner: copies a report to the clipboard and prints it (F9)
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")
local LocalPlayer = Players.LocalPlayer

local function isPlayerPart(inst)
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr.Character and inst:IsDescendantOf(plr.Character) then return true end
    end
    return false
end

local out = { "=== Scan | PlaceId " .. game.PlaceId .. " ===", "", "-- Remotes --" }
for _, obj in ipairs(game:GetDescendants()) do
    local ok, isRemote = pcall(function()
        return obj:IsA("RemoteEvent") or obj:IsA("RemoteFunction") or obj:IsA("UnreliableRemoteEvent")
    end)
    if ok and isRemote then table.insert(out, obj.ClassName .. "  " .. obj:GetFullName()) end
end

table.insert(out, "")
table.insert(out, "-- Big folders in Workspace --")
local big = {}
local function walk(inst, depth)
    for _, child in ipairs(inst:GetChildren()) do
        if not Players:GetPlayerFromCharacter(child) then
            local n = #child:GetChildren()
            if n >= 8 then table.insert(big, { child, n }) end
            if depth < 3 then walk(child, depth + 1) end
        end
    end
end
walk(workspace, 1)
table.sort(big, function(a, b) return a[2] > b[2] end)
for i = 1, math.min(30, #big) do
    local f, n = big[i][1], big[i][2]
    local s = f:GetChildren()[1]
    table.insert(out, string.format("%s  (%d)  e.g. %s %s", f:GetFullName(), n, s and s.ClassName or "-", s and s.Name or ""))
end

table.insert(out, "")
table.insert(out, "-- Touchable parts --")
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
local char = LocalPlayer.Character
if char then
    table.insert(out, "Character: " .. char:GetFullName() .. "  PrimaryPart: " .. tostring(char.PrimaryPart))
    for _, d in ipairs(char:GetDescendants()) do
        if d:IsA("BodyMover") or d:IsA("Constraint") or d:IsA("LuaSourceContainer") or d:IsA("Humanoid")
            or d:IsA("ValueBase") or d:IsA("Attachment") then
            table.insert(out, d.ClassName .. "  " .. d:GetFullName())
        end
    end
    for k, v in pairs(char:GetAttributes()) do table.insert(out, "CharAttr " .. k .. " = " .. tostring(v)) end
else
    table.insert(out, "(no character)")
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

table.insert(out, "")
table.insert(out, "-- Client scripts --")
local ps = LocalPlayer:FindFirstChild("PlayerScripts")
for _, root in ipairs({ ps, ReplicatedStorage, gui }) do
    if root then
        for _, s in ipairs(root:GetDescendants()) do
            if s:IsA("LocalScript") or s:IsA("ModuleScript") then
                table.insert(out, s.ClassName .. "  " .. s:GetFullName())
            end
        end
    end
end

local report = table.concat(out, "\n")
print(report)
local copied = false
if setclipboard then copied = pcall(setclipboard, report) end
pcall(function()
    StarterGui:SetCore("SendNotification", {
        Title = "Scan fertig",
        Text = copied and "In Zwischenablage kopiert. Im Chat mit Strg+V einfuegen." or "Steht in der Konsole (F9).",
        Duration = 8,
    })
end)
