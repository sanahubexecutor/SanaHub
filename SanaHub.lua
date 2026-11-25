-- SanaHub | Steal an Egg v5
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local UIS = game:GetService("UserInputService")
local TS = game:GetService("TweenService")
local RunS = game:GetService("RunService")
local HttpS = game:GetService("HttpService")
local lp = Players.LocalPlayer

local function getParent()
    local ok, p = pcall(function() return (gethui and gethui()) or game:GetService("CoreGui") end)
    if ok and p then return p end
    return lp:WaitForChild("PlayerGui")
end
local root = getParent()
local env = (getgenv and getgenv()) or _G
if env.SanaHubGui then pcall(function() env.SanaHubGui:Destroy() end) end

local function rnd(n)
    local s = ""
    for _ = 1, n do s = s .. string.char(math.random(97, 122)) end
    return s
end

-- State
local autoSteal, basePos = false, nil
local flying, speed = false, 50
local safeMode, moveSpeed = true, 80
local depositWait = 1.5
local antiGuard, guardRadius = true, 30
local searchRadius = 100
local upHeld, downHeld = false, false
local bv, bg
local tried = {}
local busy = false

-- Spot
local spots, activeSpot = {}, 0
local FILE = "SanaHub_StealEgg_spots.json"

local function saveSpots()
    if not writefile then return end
    pcall(function()
        local data = {}
        for _, s in ipairs(spots) do
            table.insert(data, {n = s.name, x = s.pos.X, y = s.pos.Y, z = s.pos.Z})
        end
        writefile(FILE, HttpS:JSONEncode(data))
    end)
end

local function loadSpots()
    if not (isfile and readfile) then return end
    pcall(function()
        if isfile(FILE) then
            for _, d in ipairs(HttpS:JSONDecode(readfile(FILE))) do
                table.insert(spots, {name = d.n, pos = Vector3.new(d.x, d.y, d.z)})
            end
        end
    end)
end
loadSpots()

local function hrpGet()
    local c = lp.Character
    return c and c:FindFirstChild("HumanoidRootPart")
end

local function jitter(a, b)
    task.wait(a + math.random() * (b - a))
end

-- Base otomatis = posisi awal
task.spawn(function()
    for _ = 1, 20 do
        local h = hrpGet()
        if h then
            if not basePos then basePos = h.CFrame end
            return
        end
        task.wait(0.5)
    end
end)

-- ===== FLY =====
local controls
task.spawn(function()
    pcall(function()
        local ps = lp:WaitForChild("PlayerScripts", 5)
        local pm = ps and ps:WaitForChild("PlayerModule", 5)
        if pm then controls = require(pm):GetControls() end
    end)
end)

local function getMove()
    if controls then
        local ok, v = pcall(function() return controls:GetMoveVector() end)
        if ok and v then return v end
    end
    local h = lp.Character and lp.Character:FindFirstChildOfClass("Humanoid")
    if h then
        local rel = workspace.CurrentCamera.CFrame:VectorToObjectSpace(h.MoveDirection)
        return Vector3.new(rel.X, 0, rel.Z)
    end
    return Vector3.zero
end

local function stopFly()
    if bv then bv:Destroy() bv = nil end
    if bg then bg:Destroy() bg = nil end
    local h = lp.Character and lp.Character:FindFirstChildOfClass("Humanoid")
    if h then h.PlatformStand = false end
end

local function startFly()
    local hrp = hrpGet()
    local hum = lp.Character and lp.Character:FindFirstChildOfClass("Humanoid")
    if not (hrp and hum) then return end
    stopFly()
    bv = Instance.new("BodyVelocity")
    bv.MaxForce = Vector3.new(9e9, 9e9, 9e9)
    bv.Velocity = Vector3.zero
    bv.Parent = hrp
    bg = Instance.new("BodyGyro")
    bg.MaxTorque = Vector3.new(9e9, 9e9, 9e9)
    bg.P = 9e4
    bg.CFrame = hrp.CFrame
    bg.Parent = hrp
    hum.PlatformStand = true
end

RunS.Heartbeat:Connect(function()
    if not flying or not bv or not bv.Parent then return end
    local cam = workspace.CurrentCamera
    local m = getMove()
    local dir = cam.CFrame:VectorToWorldSpace(Vector3.new(m.X, 0, m.Z))
    local vert = (upHeld and 1 or 0) - (downHeld and 1 or 0)
    bv.Velocity = dir * speed + Vector3.new(0, vert * speed, 0)
    local look = cam.CFrame.LookVector
    bg.CFrame = CFrame.lookAt(Vector3.zero, Vector3.new(look.X, 0, look.Z) + Vector3.new(0, 0, 0.001))
end)

lp.CharacterAdded:Connect(function(c)
    c:WaitForChild("HumanoidRootPart")
    task.wait(0.5)
    if flying then startFly() end
end)

-- ===== MOVEMENT =====
local function moveTo(pos)
    local hrp = hrpGet()
    if not hrp then return false end
    if not safeMode then
        hrp.CFrame = CFrame.new(pos) * (hrp.CFrame - hrp.CFrame.Position)
        return true
    end
    local t0 = tick()
    while tick() - t0 < 30 do
        hrp = hrpGet()
        if not hrp then return false end
        local diff = pos - hrp.Position
        local dist = diff.Magnitude
        if dist <= 2 then return true end
        local dt = RunS.Heartbeat:Wait()
        local step = math.min(dist, moveSpeed * dt)
        hrp.CFrame = CFrame.new(hrp.Position + diff.Unit * step) * (hrp.CFrame - hrp.CFrame.Position)
        hrp.AssemblyLinearVelocity = Vector3.zero
    end
    return false
end

-- ===== GUARD =====
local guardWords = {"guard", "snake", "enemy", "monster", "boss", "penjaga", "ular"}
local guards, lastG = {}, 0

local function bodyPart(m)
    return m:FindFirstChild("HumanoidRootPart") or m.PrimaryPart or m:FindFirstChildWhichIsA("BasePart")
end

local function badName(n)
    return n:find("egg") or n:find("pet")
end

local function refreshGuards()
    lastG = tick()
    local list = {}
    for _, d in ipairs(workspace:GetDescendants()) do
        if d:IsA("Humanoid") then
            local m = d.Parent
            if m and m:IsA("Model") and not Players:GetPlayerFromCharacter(m) and not badName(m.Name:lower()) then
                local p = bodyPart(m)
                if p then table.insert(list, p) end
            end
        elseif d:IsA("Model") then
            local n = d.Name:lower()
            if not badName(n) then
                for _, w in ipairs(guardWords) do
                    if n:find(w) then
                        local p = bodyPart(d)
                        if p then table.insert(list, p) end
                        break
                    end
                end
            end
        end
    end
    guards = list
end

local function guardNear(pos, r)
    if tick() - lastG > 2.5 then refreshGuards() end
    for _, p in ipairs(guards) do
        if p.Parent and (p.Position - pos).Magnitude < r then return true end
    end
    return false
end

-- ===== STEAL =====
local function promptPos(pr)
    local p = pr.Parent
    if not p then return nil end
    if p:IsA("BasePart") then return p.Position end
    if p:IsA("Attachment") then return p.WorldPosition end
    local bp = (p:IsA("Model") and p.PrimaryPart) or p:FindFirstChildWhichIsA("BasePart", true)
    return bp and bp.Position
end

local function promptPart(pr)
    local p = pr.Parent
    if not p then return nil end
    if p:IsA("BasePart") then return p end
    return p:FindFirstChildWhichIsA("BasePart", true)
end

local good = {"egg", "steal", "grab", "take", "collect", "pick", "claim"}
local bad = {"buy", "sell", "shop", "robux", "upgrade", "rebirth", "gift", "trade", "index", "open"}

local function matches(pr)
    local t = ((pr.ActionText or "") .. " " .. (pr.ObjectText or "") .. " " .. pr:GetFullName()):lower()
    for _, w in ipairs(bad) do if t:find(w) then return false end end
    for _, w in ipairs(good) do if t:find(w) then return true end end
    return false
end

local function nearest()
    local hrp = hrpGet()
    if not hrp then return nil end
    local spot = spots[activeSpot]
    local best, bd
    for _, d in ipairs(workspace:GetDescendants()) do
        if d:IsA("ProximityPrompt") and d.Enabled and matches(d) then
            local pos = promptPos(d)
            if pos then
                local atBase = basePos and (pos - basePos.Position).Magnitude < 40
                local recent = tried[d] and (tick() - tried[d] < 4)
                local outSpot = spot and (pos - spot.pos).Magnitude > searchRadius
                if not atBase and not recent and not outSpot then
                    local dist = (pos - hrp.Position).Magnitude
                    if not bd or dist < bd then best, bd = d, dist end
                end
            end
        end
    end
    return best
end

local function toolCount()
    local n = 0
    local bp = lp:FindFirstChildOfClass("Backpack")
    if bp then
        for _, t in ipairs(bp:GetChildren()) do
            if t:IsA("Tool") then n = n + 1 end
        end
    end
    local c = lp.Character
    if c then
        for _, t in ipairs(c:GetChildren()) do
            if t:IsA("Tool") then n = n + 1 end
        end
    end
    return n
end

local function grab(pr)
    local pos = promptPos(pr)
    local part = promptPart(pr)
    if not (hrpGet() and pos) then return false end
    local before = toolCount()
    pcall(function()
        pr.HoldDuration = 0
        pr.RequiresLineOfSight = false
        pr.MaxActivationDistance = math.max(pr.MaxActivationDistance, 30)
    end)
    local targetPos = pos + Vector3.new(0, 2.5, 0)
    moveTo(targetPos)
    for _ = 1, 20 do
        local hrp = hrpGet()
        if not hrp then return false end
        if antiGuard and guardNear(hrp.Position, math.min(guardRadius, 15)) then
            return false, "guard"
        end
        if (hrp.Position - targetPos).Magnitude > 4 then
            hrp.CFrame = CFrame.new(targetPos)
        end
        if fireproximityprompt then pcall(fireproximityprompt, pr) end
        pcall(function()
            pr:InputHoldBegin()
            task.wait()
            pr:InputHoldEnd()
        end)
        if part and firetouchinterest then
            pcall(function()
                firetouchinterest(hrp, part, 0)
                firetouchinterest(hrp, part, 1)
            end)
        end
        task.wait(0.1)
        if toolCount() > before or not pr.Parent or not pr:IsDescendantOf(workspace) or not pr.Enabled then
            return true
        end
    end
    return false
end

-- Taruh telur di base (tekan prompt taruh/simpan kalau ada)
local dropWords = {"place", "put", "store", "deposit", "drop", "simpan", "taruh"}
local function dropAtBase()
    if not basePos then return end
    for _, d in ipairs(workspace:GetDescendants()) do
        if d:IsA("ProximityPrompt") and d.Enabled then
            local pos = promptPos(d)
            if pos and (pos - basePos.Position).Magnitude < 30 then
                local t = ((d.ActionText or "") .. " " .. (d.ObjectText or "")):lower()
                for _, w in ipairs(dropWords) do
                    if t:find(w) then
                        pcall(function()
                            d.HoldDuration = 0
                            d.RequiresLineOfSight = false
                        end)
                        if fireproximityprompt then pcall(fireproximityprompt, d) end
                        break
                    end
                end
            end
        end
    end
end

-- ===== GUI =====
local gui = Instance.new("ScreenGui")
gui.Name = rnd(10)
gui.ResetOnSpawn = false
gui.DisplayOrder = 999
gui.Parent = root
env.SanaHubGui = gui

local function corner(o, r)
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, r)
    c.Parent = o
end

local function style(b, text, size)
    b.BackgroundColor3 = Color3.fromRGB(45, 45, 65)
    b.Text = text
    b.TextColor3 = Color3.new(1, 1, 1)
    b.Font = Enum.Font.GothamBold
    b.TextSize = size or 15
    corner(b, 10)
end

local openBtn = Instance.new("TextButton")
openBtn.Size = UDim2.fromOffset(46, 46)
openBtn.Position = UDim2.new(0, 15, 0.5, -23)
openBtn.BackgroundColor3 = Color3.fromRGB(150, 80, 255)
openBtn.Text = "S"
openBtn.TextColor3 = Color3.new(1, 1, 1)
openBtn.Font = Enum.Font.GothamBold
openBtn.TextSize = 22
openBtn.Parent = gui
corner(openBtn, 23)

local main = Instance.new("Frame")
main.Size = UDim2.fromOffset(270, 380)
main.Position = UDim2.new(0.5, -135, 0.5, -190)
main.BackgroundColor3 = Color3.fromRGB(22, 22, 32)
main.Visible = false
main.Parent = gui
corner(main, 14)
local stroke = Instance.new("UIStroke")
stroke.Color = Color3.fromRGB(150, 80, 255)
stroke.Thickness = 2
stroke.Parent = main

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, -50, 0, 40)
title.Position = UDim2.fromOffset(15, 0)
title.BackgroundTransparency = 1
title.Text = "SanaHub | Steal an Egg"
title.TextColor3 = Color3.new(1, 1, 1)
title.Font = Enum.Font.GothamBold
title.TextSize = 16
title.TextXAlignment = Enum.TextXAlignment.Left
title.Parent = main

local close = Instance.new("TextButton")
close.Size = UDim2.fromOffset(28, 28)
close.Position = UDim2.new(1, -38, 0, 6)
close.BackgroundColor3 = Color3.fromRGB(220, 60, 70)
close.Text = "X"
close.TextColor3 = Color3.new(1, 1, 1)
close.Font = Enum.Font.GothamBold
close.TextSize = 14
close.Parent = main
corner(close, 8)

local scroll = Instance.new("ScrollingFrame")
scroll.Size = UDim2.new(1, -20, 1, -92)
scroll.Position = UDim2.fromOffset(10, 44)
scroll.BackgroundTransparency = 1
scroll.BorderSizePixel = 0
scroll.ScrollBarThickness = 4
scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
scroll.Parent = main
local list = Instance.new("UIListLayout")
list.Padding = UDim.new(0, 8)
list.SortOrder = Enum.SortOrder.LayoutOrder
list.Parent = scroll

local status = Instance.new("TextLabel")
status.Size = UDim2.new(1, -30, 0, 40)
status.Position = UDim2.fromOffset(15, 336)
status.BackgroundTransparency = 1
status.Text = "Status: siap"
status.TextColor3 = Color3.fromRGB(170, 170, 200)
status.Font = Enum.Font.Gotham
status.TextSize = 12
status.TextWrapped = true
status.TextXAlignment = Enum.TextXAlignment.Left
status.TextYAlignment = Enum.TextYAlignment.Top
status.Parent = main
local function setStatus(t) status.Text = "Status: " .. t end

local function mkBtn(text, cb)
    local b = Instance.new("TextButton")
    b.Size = UDim2.new(1, -8, 0, 38)
    style(b, text)
    b.Parent = scroll
    b.MouseButton1Click:Connect(function() cb(b) end)
    return b
end

local function mkRow()
    local f = Instance.new("Frame")
    f.Size = UDim2.new(1, -8, 0, 38)
    f.BackgroundTransparency = 1
    f.Parent = scroll
    return f
end

local function setOn(b, on)
    TS:Create(b, TweenInfo.new(0.2), {
        BackgroundColor3 = on and Color3.fromRGB(60, 180, 100) or Color3.fromRGB(45, 45, 65)
    }):Play()
end

local function mkStepper(name, get, set, minV, maxV, stepV)
    local row = mkRow()
    local minus = Instance.new("TextButton")
    minus.Size = UDim2.fromOffset(50, 38)
    style(minus, "-", 20)
    minus.Parent = row
    local plus = Instance.new("TextButton")
    plus.Size = UDim2.fromOffset(50, 38)
    plus.AnchorPoint = Vector2.new(1, 0)
    plus.Position = UDim2.new(1, 0, 0, 0)
    style(plus, "+", 20)
    plus.Parent = row
    local lbl = Instance.new("TextLabel")
    lbl.Size = UDim2.new(1, -110, 1, 0)
    lbl.Position = UDim2.fromOffset(55, 0)
    lbl.BackgroundTransparency = 1
    lbl.Text = name .. ": " .. get()
    lbl.TextColor3 = Color3.fromRGB(200, 200, 220)
    lbl.Font = Enum.Font.GothamBold
    lbl.TextSize = 12
    lbl.TextWrapped = true
    lbl.Parent = row
    local function chg(d)
        set(math.clamp(get() + d, minV, maxV))
        lbl.Text = name .. ": " .. get()
    end
    minus.MouseButton1Click:Connect(function() chg(-stepV) end)
    plus.MouseButton1Click:Connect(function() chg(stepV) end)
end

local function deliver()
    if not basePos then
        setStatus("base belum disimpan")
        return
    end
    setStatus("bawa telur ke base...")
    task.wait(0.2)
    moveTo(basePos.Position)
    setStatus("taruh telur di base")
    dropAtBase()
    task.wait(depositWait)
end

-- satu siklus: ke spot -> cari telur -> ambil -> bawa ke base
local function runOnce()
    local hrp = hrpGet()
    if not hrp then return end
    local spot = spots[activeSpot]
    if spot and (hrp.Position - spot.pos).Magnitude > searchRadius + 20 then
        setStatus("pergi ke " .. spot.name)
        moveTo(spot.pos + Vector3.new(0, 3, 0))
    end
    local pr = nearest()
    if not pr then
        setStatus("mencari telur di " .. (spot and spot.name or "semua map") .. "...")
        return
    end
    local epos = promptPos(pr)
    if antiGuard and epos and guardNear(epos, guardRadius) then
        tried[pr] = tick() + 6
        setStatus("guard dekat telur, dilewati")
        return
    end
    tried[pr] = tick()
    setStatus("ambil " .. tostring(pr.Parent and pr.Parent.Name))
    local ok, why = grab(pr)
    if ok then
        deliver()
        setStatus("dapat telur, ulangi")
    elseif why == "guard" then
        setStatus("kabur dari guard")
        if basePos then moveTo(basePos.Position) end
    else
        setStatus("gagal ambil, tekan Dump Info")
    end
end

-- Auto Steal
mkBtn("Auto Steal: OFF", function(b)
    autoSteal = not autoSteal
    b.Text = autoSteal and "Auto Steal: ON" or "Auto Steal: OFF"
    setOn(b, autoSteal)
    if autoSteal and not basePos and hrpGet() then
        basePos = hrpGet().CFrame
    end
    setStatus(autoSteal and "auto steal jalan" or "auto steal mati")
end)

mkBtn("Ambil 1 Telur (tes)", function()
    if busy then return end
    busy = true
    task.spawn(function()
        runOnce()
        busy = false
    end)
end)

-- Pilih spot
local spotBtn
local function refreshSpotBtn()
    local s = spots[activeSpot]
    if s then
        spotBtn.Text = "Spot: " .. s.name .. " (" .. activeSpot .. "/" .. #spots .. ")"
    else
        spotBtn.Text = "Spot: semua map (" .. #spots .. " tersimpan)"
    end
end

spotBtn = mkBtn("Spot", function()
    activeSpot = activeSpot + 1
    if activeSpot > #spots then activeSpot = 0 end
    refreshSpotBtn()
end)
spotBtn.TextSize = 13
refreshSpotBtn()

mkBtn("Simpan Spot (posisi ini)", function()
    local hrp = hrpGet()
    if not hrp then return end
    table.insert(spots, {name = "Spot " .. (#spots + 1), pos = hrp.Position})
    activeSpot = #spots
    saveSpots()
    refreshSpotBtn()
    setStatus("spot disimpan")
end)

mkBtn("Pergi ke Spot aktif", function()
    local s = spots[activeSpot]
    if not s then
        setStatus("pilih spot dulu")
        return
    end
    if busy then return end
    busy = true
    task.spawn(function()
        moveTo(s.pos + Vector3.new(0, 3, 0))
        setStatus("sampai di " .. s.name)
        busy = false
    end)
end)

mkBtn("Hapus Spot aktif", function()
    if spots[activeSpot] then
        table.remove(spots, activeSpot)
        activeSpot = 0
        saveSpots()
        refreshSpotBtn()
        setStatus("spot dihapus")
    end
end)

mkStepper("Radius cari", function() return searchRadius end, function(v) searchRadius = v end, 30, 400, 10)

local guardBtn
guardBtn = mkBtn("Anti Guard: ON", function(b)
    antiGuard = not antiGuard
    b.Text = antiGuard and "Anti Guard: ON" or "Anti Guard: OFF"
    setOn(b, antiGuard)
end)
setOn(guardBtn, true)

mkStepper("Jarak guard", function() return guardRadius end, function(v) guardRadius = v end, 10, 80, 5)

local safeBtn
safeBtn = mkBtn("Mode Aman: ON", function(b)
    safeMode = not safeMode
    b.Text = safeMode and "Mode Aman: ON" or "Mode Aman: OFF"
    setOn(b, safeMode)
end)
setOn(safeBtn, true)

mkStepper("Jalan", function() return moveSpeed end, function(v) moveSpeed = v end, 20, 300, 10)

-- Fly
mkBtn("Fly: OFF", function(b)
    flying = not flying
    b.Text = flying and "Fly: ON" or "Fly: OFF"
    setOn(b, flying)
    if flying then startFly() else stopFly() end
end)

mkStepper("Fly", function() return speed end, function(v) speed = v end, 10, 300, 10)

do
    local row = mkRow()
    local function hold(text, anchorX, cb)
        local b = Instance.new("TextButton")
        b.Size = UDim2.new(0.5, -4, 1, 0)
        b.AnchorPoint = Vector2.new(anchorX, 0)
        b.Position = UDim2.new(anchorX, 0, 0, 0)
        style(b, text)
        b.Parent = row
        b.InputBegan:Connect(function(i)
            if i.UserInputType == Enum.UserInputType.Touch or i.UserInputType == Enum.UserInputType.MouseButton1 then cb(true) end
        end)
        b.InputEnded:Connect(function(i)
            if i.UserInputType == Enum.UserInputType.Touch or i.UserInputType == Enum.UserInputType.MouseButton1 then cb(false) end
        end)
    end
    hold("▲ Naik", 0, function(v) upHeld = v end)
    hold("▼ Turun", 1, function(v) downHeld = v end)
end

UIS.InputBegan:Connect(function(i, gp)
    if gp then return end
    if i.KeyCode == Enum.KeyCode.E then upHeld = true end
    if i.KeyCode == Enum.KeyCode.Q then downHeld = true end
end)
UIS.InputEnded:Connect(function(i)
    if i.KeyCode == Enum.KeyCode.E then upHeld = false end
    if i.KeyCode == Enum.KeyCode.Q then downHeld = false end
end)

mkStepper("Tunggu base (dtk)", function() return depositWait end, function(v) depositWait = v end, 0.5, 6, 0.5)

mkBtn("Simpan Base (posisi ini)", function()
    local hrp = hrpGet()
    if hrp then
        basePos = hrp.CFrame
        setStatus("base disimpan (depan safe zone)")
    end
end)

mkBtn("Pergi ke Base", function()
    if busy then return end
    busy = true
    task.spawn(function()
        if basePos then
            moveTo(basePos.Position)
            setStatus("sampai di base")
        else
            setStatus("base belum disimpan")
        end
        busy = false
    end)
end)

mkBtn("Dump Info (salin)", function()
    local out = {"== PROMPT =="}
    local n = 0
    for _, d in ipairs(workspace:GetDescendants()) do
        if d:IsA("ProximityPrompt") then
            n = n + 1
            if n <= 60 then
                table.insert(out, d:GetFullName() .. " | " .. tostring(d.ActionText) .. " | " .. tostring(d.ObjectText))
            end
        end
    end
    table.insert(out, "== REMOTE ==")
    local r = 0
    for _, d in ipairs(RS:GetDescendants()) do
        if d:IsA("RemoteEvent") or d:IsA("RemoteFunction") then
            r = r + 1
            if r <= 80 then table.insert(out, d.ClassName .. " " .. d:GetFullName()) end
        end
    end
    table.insert(out, "== GUARD TERDETEKSI ==")
    refreshGuards()
    for i, p in ipairs(guards) do
        if i <= 30 then table.insert(out, p:GetFullName()) end
    end
    table.insert(out, "== INVENTARIS ==")
    local bp = lp:FindFirstChildOfClass("Backpack")
    if bp then
        for _, t in ipairs(bp:GetChildren()) do table.insert(out, t.ClassName .. " " .. t.Name) end
    end
    local text = table.concat(out, "\n")
    print(text)
    if setclipboard then
        setclipboard(text)
        setStatus("disalin: " .. n .. " prompt, " .. r .. " remote, " .. #guards .. " guard")
    else
        setStatus("lihat console: " .. n .. " prompt, " .. r .. " remote")
    end
end)

-- Loop auto steal
task.spawn(function()
    while gui.Parent do
        if autoSteal and not busy then
            busy = true
            pcall(runOnce)
            busy = false
            jitter(0.4, 1.0)
        end
        task.wait(0.4)
    end
end)

openBtn.MouseButton1Click:Connect(function() main.Visible = not main.Visible end)
close.MouseButton1Click:Connect(function() main.Visible = false end)

local function drag(frame, handle)
    local dragging, start, startPos
    handle.InputBegan:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
            dragging, start, startPos = true, i.Position, frame.Position
        end
    end)
    UIS.InputChanged:Connect(function(i)
        if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
            local d = i.Position - start
            frame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
        end
    end)
    UIS.InputEnded:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then dragging = false end
    end)
end
drag(main, title)
drag(openBtn, openBtn)
