-- ============================================================
-- Universal ESP — clean, lightweight rewrite
-- ============================================================

local _r = tostring(math.random(1e5, 9e5))
local visualFolderName = "ESPVisual_" .. _r

-- Prevent duplicate instances
if getgenv then
    local prev = getgenv().UniversalESP_Instance
    if prev and type(prev.Unload) == "function" then
        pcall(prev.Unload)
    end
end

-- ===========================
-- Services & Environment
-- ===========================
local cref  = cloneref or function(x) return x end
local cwrap = newcclosure or function(fn) return fn end

local function gs(name)
    local ok, svc = pcall(function() return game:GetService(name) end)
    return (ok and svc) and cref(svc) or nil
end

local Players          = gs("Players")
local RunService       = gs("RunService")
local UserInputService = gs("UserInputService")
local Stats            = gs("Stats")
local CoreGui          = gs("CoreGui")
local HttpService      = gs("HttpService")
local TeamsService     = gs("Teams")
local Workspace        = gs("Workspace") or cref(workspace)

local function getCamera()
    return Workspace and (Workspace.CurrentCamera or Workspace:FindFirstChildOfClass("Camera")) or nil
end

local LocalPlayer = Players and cref(Players.LocalPlayer) or nil
if Players and not LocalPlayer then
    pcall(function()
        Players:GetPropertyChangedSignal("LocalPlayer"):Wait()
        LocalPlayer = cref(Players.LocalPlayer)
    end)
end

-- ===========================
-- Config & State
-- ===========================
local TEAM_SOURCES = { "Auto", "Team", "TeamColor", "Attribute", "Folder", "Body color" }

local DEFAULTS = {
    -- ESP Visuals
    Enabled      = true,
    Glow         = true,
    Box          = true,
    HealthBar    = true,
    Name         = true,
    Distance     = true,
    Tool         = false,
    Tracers      = false,
    Range        = 5000,
    Transparency = 0.75,
    VisibleColor = Color3.fromRGB(80, 225, 80),
    HiddenColor  = Color3.fromRGB(235, 60, 60),

    -- Filters & Teams
    TeamCheck       = true,
    TeamColor       = false,
    ShowBots        = true,
    VisibilityCheck = true,
    TeamSource      = "Auto",
    CustomTeamKey   = "",

    -- Settings
    Watermark = true,
    ToggleKey = Enum.KeyCode.F1,
    GuiKey    = Enum.KeyCode.F2,
    UnloadKey = Enum.KeyCode.End,
}

local Config = {}
for k, v in pairs(DEFAULTS) do Config[k] = v end

local State = {
    TrackedCharacters = {},
    Connections       = {},
    Unloaded          = false,
}

local SAVE_FOLDER = "UniversalESP"
local SAVE_FILE   = "config_v2.json"

-- ===========================
-- Config Persistence
-- ===========================
local function c3toHex(c)
    return string.format("%02X%02X%02X",
        math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5))
end

local function hexToC3(hex)
    if type(hex) ~= "string" or #hex < 6 then return nil end
    local r = tonumber(hex:sub(1, 2), 16)
    local g = tonumber(hex:sub(3, 4), 16)
    local b = tonumber(hex:sub(5, 6), 16)
    return (r and g and b) and Color3.fromRGB(r, g, b) or nil
end

local function saveConfig()
    if not (HttpService and writefile and makefolder and isfolder) then return end
    pcall(function()
        if not isfolder(SAVE_FOLDER) then makefolder(SAVE_FOLDER) end
        local data = {}
        for k, def in pairs(DEFAULTS) do
            local val = Config[k]
            if typeof(def) == "Color3" then
                data[k] = c3toHex(val)
            elseif typeof(def) == "EnumItem" then
                data[k] = val.Name
            else
                data[k] = val
            end
        end
        writefile(SAVE_FOLDER .. "/" .. SAVE_FILE, HttpService:JSONEncode(data))
    end)
end

local function loadConfig()
    if not (HttpService and readfile and isfile and isfolder) then return end
    pcall(function()
        local path = SAVE_FOLDER .. "/" .. SAVE_FILE
        if not (isfolder(SAVE_FOLDER) and isfile(path)) then return end
        local raw = readfile(path)
        if type(raw) ~= "string" or raw == "" then return end
        local ok, data = pcall(function() return HttpService:JSONDecode(raw) end)
        if not ok or type(data) ~= "table" then return end

        for k, def in pairs(DEFAULTS) do
            local v = data[k]
            if v ~= nil then
                if typeof(def) == "Color3" then
                    Config[k] = hexToC3(v) or def
                elseif typeof(def) == "EnumItem" and type(v) == "string" then
                    local okK, kc = pcall(function() return Enum.KeyCode[v] end)
                    if okK and kc then Config[k] = kc end
                elseif type(v) == type(def) then
                    Config[k] = v
                end
            end
        end
    end)
end

loadConfig()

-- ===========================
-- Helpers
-- ===========================
local function connect(signal, fn)
    local c = signal:Connect(cwrap(fn))
    table.insert(State.Connections, c)
    return c
end

local HAS_DRAW = false
pcall(function()
    local d = Drawing.new("Text")
    d.Visible = false
    d:Remove()
    HAS_DRAW = true
end)

-- ===========================
-- Team Detection (signal-by-signal, no stale cache)
-- ===========================
local TEAM_ATTR_KEYS = {
    "Team", "team", "TeamId", "TeamID", "teamId", "TeamName", "TeamNumber",
    "Faction", "faction", "Side", "side", "Alliance", "alliance", "Squad", "squad",
}

local GENERIC_FOLDERS = {
    workspace = true, players = true, characters = true, entities = true,
    live = true, bots = true, npcs = true, enemies = true, rigs = true,
}

local function normVal(v)
    if v == nil then return nil end
    if typeof(v) == "Instance" then v = v.Name end
    local s = tostring(v):lower():gsub("^%s+", ""):gsub("%s+$", "")
    if s == "" or s == "nil" or s == "none" then return nil end
    return s
end

local function readCustomKey(obj, char, key)
    if type(key) ~= "string" or key == "" then return nil end
    local function fromInst(inst)
        if not inst then return nil end
        local okA, attr = pcall(function() return inst:GetAttribute(key) end)
        if okA and attr ~= nil then return normVal(attr) end
        local ch = inst:FindFirstChild(key)
        if ch then
            local okV, val = pcall(function() return ch.Value end)
            if okV and val ~= nil then return normVal(val) end
        end
        return nil
    end
    return fromInst(obj) or (char ~= obj and fromInst(char)) or nil
end

local function getAttrTeam(obj, char)
    local custom = readCustomKey(obj, char, Config.CustomTeamKey)
    if custom then return custom end

    for _, k in ipairs(TEAM_ATTR_KEYS) do
        local v = readCustomKey(obj, char, k)
        if v then return v end
    end

    local ls = obj and obj:FindFirstChild("leaderstats")
    if ls then
        for _, k in ipairs(TEAM_ATTR_KEYS) do
            local v = readCustomKey(ls, ls, k)
            if v then return v end
        end
    end
    return nil
end

local function getFolderTeam(char)
    local p = char and char.Parent
    if not p or p == Workspace then return nil end
    local name = p.Name:lower()
    if GENERIC_FOLDERS[name] then return nil end
    return name
end

local function getBodyColorTeam(char)
    if not char then return nil end
    local c
    local bc = char:FindFirstChildOfClass("BodyColors")
    if bc then
        local ok, v = pcall(function() return bc.TorsoColor3 end)
        if ok then c = v end
    end
    if not c then
        local torso = char:FindFirstChild("UpperTorso") or char:FindFirstChild("Torso")
        if torso and torso:IsA("BasePart") then c = torso.Color end
    end
    if c then
        return string.format("%02X%02X%02X",
            math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5))
    end
    return nil
end

-- Checks if all players in the server share the exact same Roblox Team (single-team FFA)
local function isSingleTeamGame()
    if not Players then return false end
    local list = Players:GetPlayers()
    if #list < 2 then return false end
    local first = list[1].Team
    if not first then return false end
    for i = 2, #list do
        if list[i].Team ~= first then return false end
    end
    return true
end

local function isSameTeam(character, player)
    if not LocalPlayer then return false end
    local myChar = LocalPlayer.Character
    local src = Config.TeamSource

    -- 1. Custom key (always highest priority if set)
    if Config.CustomTeamKey ~= "" then
        local mine = readCustomKey(LocalPlayer, myChar, Config.CustomTeamKey)
        local theirs = readCustomKey(player or character, character, Config.CustomTeamKey)
        if mine and theirs then return mine == theirs end
    end

    -- 2. Explicit Roblox Team
    if src == "Team" or src == "Auto" then
        if player and LocalPlayer.Team and player.Team then
            if not isSingleTeamGame() then
                return LocalPlayer.Team == player.Team
            end
        elseif src == "Team" then
            return false
        end
    end

    -- 3. TeamColor (only if players actually have differing colors or explicit mode)
    if src == "TeamColor" or src == "Auto" then
        if player and LocalPlayer.TeamColor and player.TeamColor then
            if src == "TeamColor" then
                return LocalPlayer.TeamColor == player.TeamColor
            elseif not LocalPlayer.Team and not player.Team then
                -- Check that not everyone shares the exact same default TeamColor
                for _, p in ipairs(Players:GetPlayers()) do
                    if p.TeamColor ~= LocalPlayer.TeamColor then
                        return LocalPlayer.TeamColor == player.TeamColor
                    end
                end
            end
        elseif src == "TeamColor" then
            return false
        end
    end

    -- 4. Attributes / ValueObjects / leaderstats
    if src == "Attribute" or src == "Auto" then
        local mine = getAttrTeam(LocalPlayer, myChar)
        local theirs = getAttrTeam(player or character, character)
        if mine and theirs then return mine == theirs end
        if src == "Attribute" then return false end
    end

    -- 5. Character Parent Folder
    if src == "Folder" or src == "Auto" then
        local mine = getFolderTeam(myChar)
        local theirs = getFolderTeam(character)
        if mine and theirs then return mine == theirs end
        if src == "Folder" then return false end
    end

    -- 6. Body Color
    if src == "Body color" then
        local mine = getBodyColorTeam(myChar)
        local theirs = getBodyColorTeam(character)
        if mine and theirs then return mine == theirs end
        return false
    end

    return false
end

local Overrides = { IsEnemy = nil, GetTool = nil }

local function isEnemy(character, player)
    if not character then return false end
    if LocalPlayer and (character == LocalPlayer.Character or player == LocalPlayer) then return false end

    if Overrides.IsEnemy then
        local ok, res = pcall(Overrides.IsEnemy, character, player)
        if ok and res ~= nil then return res and true or false end
    end

    if not player and not Config.ShowBots then return false end
    if not Config.TeamCheck then return true end

    return not isSameTeam(character, player)
end

-- ===========================
-- Visibility Raycast
-- ===========================
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.IgnoreWater = true
rayParams.RespectCanCollide = true

local function isTargetVisible(cam, targetPart, targetModel, excludeTable)
    if not (cam and targetPart and targetPart.Parent and targetModel) then return false end
    local origin = cam.CFrame.Position
    rayParams.FilterDescendantsInstances = excludeTable
    local res = Workspace:Raycast(origin, targetPart.Position - origin, rayParams)
    return res == nil or res.Instance:IsDescendantOf(targetModel)
end

-- ===========================
-- Watermark
-- ===========================
local watermarkDraw, watermarkGui, watermarkLabel = nil, nil, nil

local function initWatermark()
    if HAS_DRAW then
        pcall(function()
            local d = Drawing.new("Text")
            d.Size = 14
            d.Position = Vector2.new(16, 16)
            d.Color = Color3.fromRGB(240, 240, 240)
            d.Outline = true
            d.OutlineColor = Color3.fromRGB(0, 0, 0)
            d.Font = 2
            d.Visible = Config.Watermark
            d.Text = "Universal ESP"
            watermarkDraw = d
        end)
    else
        local parent
        if gethui then pcall(function() parent = cref(gethui()) end) end
        if not parent and CoreGui then pcall(function() local _ = CoreGui.Name; parent = cref(CoreGui) end) end
        if not parent and LocalPlayer then parent = LocalPlayer:FindFirstChildOfClass("PlayerGui") end
        if parent then
            watermarkGui = Instance.new("ScreenGui")
            watermarkGui.Name = "ESPWatermark_" .. _r
            watermarkGui.ResetOnSpawn = false
            watermarkGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

            watermarkLabel = Instance.new("TextLabel")
            watermarkLabel.Position = UDim2.new(0, 16, 0, 16)
            watermarkLabel.Size = UDim2.new(0, 300, 0, 20)
            watermarkLabel.BackgroundTransparency = 1
            watermarkLabel.Font = Enum.Font.GothamMedium
            watermarkLabel.TextSize = 14
            watermarkLabel.TextColor3 = Color3.fromRGB(240, 240, 240)
            watermarkLabel.TextStrokeColor3 = Color3.new(0, 0, 0)
            watermarkLabel.TextStrokeTransparency = 0
            watermarkLabel.TextXAlignment = Enum.TextXAlignment.Left
            watermarkLabel.Visible = Config.Watermark
            watermarkLabel.Parent = watermarkGui
            watermarkGui.Parent = parent
        end
    end
end
initWatermark()

-- ===========================
-- Visual Creation & Cleanup
-- ===========================
local DRAWING_KEYS = { "Box", "BoxOutline", "Tracer", "HpBack", "HpFill" }

local function hideDrawings(data)
    for _, key in ipairs(DRAWING_KEYS) do
        local d = data[key]
        if d and d.Visible then d.Visible = false end
    end
end

local function cleanupESP(character)
    local data = State.TrackedCharacters[character]
    if data then
        if data.DiedConn then pcall(function() data.DiedConn:Disconnect() end) end
        if data.AncestryConn then pcall(function() data.AncestryConn:Disconnect() end) end
        pcall(function() if data.Highlight then data.Highlight.Enabled = false; data.Highlight.Adornee = nil end end)
        pcall(function() if data.Billboard then data.Billboard.Enabled = false; data.Billboard.Adornee = nil end end)
        pcall(function() if data.Visuals then data.Visuals:Destroy() end end)
        for _, key in ipairs(DRAWING_KEYS) do
            if data[key] then pcall(function() data[key]:Remove() end) end
        end
        State.TrackedCharacters[character] = nil
    end
end

local function createVisualForCharacter(character, player)
    if State.Unloaded or not character or not character.Parent then return end
    if State.TrackedCharacters[character] then return end
    if LocalPlayer and (character == LocalPlayer.Character or player == LocalPlayer) then return end

    local humanoid = character:FindFirstChildOfClass("Humanoid")
    if humanoid and humanoid.MaxHealth > 0 and humanoid.Health <= 0 then return end

    local rootPart = character:FindFirstChild("HumanoidRootPart")
        or character:FindFirstChild("Torso")
        or character:FindFirstChild("UpperTorso")
    local head = character:FindFirstChild("Head")
    local adornee = head or rootPart
    if not adornee then return end

    local existing = character:FindFirstChild(visualFolderName)
    if existing then pcall(function() existing:Destroy() end) end

    local visu = Instance.new("Folder")
    visu.Name = visualFolderName
    visu.Parent = character

    local highlight = Instance.new("Highlight")
    highlight.Name = "Highlight_" .. _r
    highlight.Adornee = character
    highlight.Enabled = false
    highlight.OutlineColor = Config.VisibleColor
    highlight.FillColor = Config.VisibleColor
    highlight.OutlineTransparency = 0
    highlight.FillTransparency = Config.Transparency
    highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    highlight.Parent = visu

    local billboard = Instance.new("BillboardGui")
    billboard.Name = "ESPBillboard_" .. _r
    billboard.Size = UDim2.new(0, 160, 0, 56)
    billboard.StudsOffset = (adornee.Name == "Head") and Vector3.new(0, 1.8, 0) or Vector3.new(0, 3.2, 0)
    billboard.AlwaysOnTop = true
    billboard.Enabled = false
    billboard.Adornee = adornee
    billboard.Parent = visu

    local frame = Instance.new("Frame")
    frame.Size = UDim2.new(1, 0, 1, 0)
    frame.BackgroundTransparency = 1
    frame.Parent = billboard

    local nameLabel = Instance.new("TextLabel")
    nameLabel.Size = UDim2.new(1, 0, 0, 18)
    nameLabel.BackgroundTransparency = 1
    nameLabel.Font = Enum.Font.GothamBold
    nameLabel.TextSize = 13
    nameLabel.TextColor3 = Config.VisibleColor
    nameLabel.TextStrokeTransparency = 0
    nameLabel.TextStrokeColor3 = Color3.new(0, 0, 0)
    nameLabel.Text = player and (player.DisplayName or player.Name) or character.Name
    nameLabel.Parent = frame

    local distLabel = Instance.new("TextLabel")
    distLabel.Size = UDim2.new(1, 0, 0, 14)
    distLabel.Position = UDim2.new(0, 0, 0, 18)
    distLabel.BackgroundTransparency = 1
    distLabel.Font = Enum.Font.Gotham
    distLabel.TextSize = 11
    distLabel.TextColor3 = Color3.fromRGB(230, 230, 230)
    distLabel.TextStrokeTransparency = 0
    distLabel.TextStrokeColor3 = Color3.new(0, 0, 0)
    distLabel.Text = "0m"
    distLabel.Parent = frame

    local toolLabel = Instance.new("TextLabel")
    toolLabel.Size = UDim2.new(1, 0, 0, 14)
    toolLabel.Position = UDim2.new(0, 0, 0, 32)
    toolLabel.BackgroundTransparency = 1
    toolLabel.Font = Enum.Font.Gotham
    toolLabel.TextSize = 11
    toolLabel.TextColor3 = Color3.fromRGB(255, 220, 120)
    toolLabel.TextStrokeTransparency = 0
    toolLabel.TextStrokeColor3 = Color3.new(0, 0, 0)
    toolLabel.Visible = false
    toolLabel.Parent = frame

    local box, boxOutline, tracer, hpBack, hpFill
    if HAS_DRAW then
        pcall(function()
            boxOutline = Drawing.new("Square")
            boxOutline.Thickness = 3; boxOutline.Filled = false; boxOutline.Visible = false
            boxOutline.Color = Color3.new(0, 0, 0); boxOutline.ZIndex = 1

            box = Drawing.new("Square")
            box.Thickness = 1; box.Filled = false; box.Visible = false
            box.Color = Config.VisibleColor; box.ZIndex = 2

            tracer = Drawing.new("Line")
            tracer.Thickness = 1; tracer.Visible = false
            tracer.Color = Config.VisibleColor

            hpBack = Drawing.new("Square")
            hpBack.Filled = true; hpBack.Visible = false
            hpBack.Color = Color3.new(0, 0, 0); hpBack.ZIndex = 1

            hpFill = Drawing.new("Square")
            hpFill.Filled = true; hpFill.Visible = false
            hpFill.Color = Color3.fromRGB(80, 225, 80); hpFill.ZIndex = 2
        end)
    end

    local data = {
        Visuals = visu, Player = player, Highlight = highlight, Billboard = billboard,
        NameLabel = nameLabel, DistanceLabel = distLabel, ToolLabel = toolLabel,
        Box = box, BoxOutline = boxOutline, Tracer = tracer, HpBack = hpBack, HpFill = hpFill,
        RootPart = rootPart, Humanoid = humanoid, Head = head,
        LastVisCheck = 0, IsVisible = true,
        LastToolCheck = 0, ShouldDraw = false, DrawColor = Config.VisibleColor,
    }
    State.TrackedCharacters[character] = data

    if humanoid then
        data.DiedConn = humanoid.Died:Connect(function() cleanupESP(character) end)
    end
    data.AncestryConn = character.AncestryChanged:Connect(function(_, parent)
        if not parent then cleanupESP(character) end
    end)
end

-- ===========================
-- Character Scanning
-- ===========================
local function checkModel(model)
    if State.Unloaded or not (model and model:IsA("Model") and model.Parent) then return end
    if State.TrackedCharacters[model] then return end
    local hum = model:FindFirstChildOfClass("Humanoid")
    if not hum or (hum.MaxHealth > 0 and hum.Health <= 0) then return end
    local plr = Players and Players:GetPlayerFromCharacter(model) or nil
    createVisualForCharacter(model, plr)
end

local function setupPlayer(player)
    if State.Unloaded or not player or player == LocalPlayer then return end
    connect(player.CharacterAdded, function(char)
        if State.Unloaded then return end
        task.spawn(function()
            local hum = char:WaitForChild("Humanoid", 5)
            if hum and not State.Unloaded then createVisualForCharacter(char, player) end
        end)
    end)
    connect(player.CharacterRemoving, function(char) cleanupESP(char) end)
    if player.Character then checkModel(player.Character) end
end

local function scanWorkspace(container, depth)
    if State.Unloaded or not container or depth > 4 then return end
    for _, child in ipairs(container:GetChildren()) do
        if child:IsA("Model") then
            checkModel(child)
        elseif child:IsA("Folder") or child:IsA("WorldModel") then
            scanWorkspace(child, depth + 1)
        end
    end
end

if Players then
    for _, p in ipairs(Players:GetPlayers()) do setupPlayer(p) end
    connect(Players.PlayerAdded, setupPlayer)
    connect(Players.PlayerRemoving, function(p)
        if p.Character then cleanupESP(p.Character) end
    end)
end

if Workspace then
    connect(Workspace.DescendantAdded, function(inst)
        if not State.Unloaded and inst:IsA("Model") then
            task.defer(checkModel, inst)
        end
    end)
    scanWorkspace(Workspace, 1)
end

-- ===========================
-- Unload
-- ===========================
local _configGui, _guiRefreshAll, _guiToggle = nil, nil, nil

local function unload()
    if State.Unloaded then return end
    State.Unloaded = true
    saveConfig()

    for _, c in ipairs(State.Connections) do pcall(function() c:Disconnect() end) end
    table.clear(State.Connections)

    for char in pairs(State.TrackedCharacters) do cleanupESP(char) end

    if watermarkDraw then pcall(function() watermarkDraw:Remove() end); watermarkDraw = nil end
    if watermarkGui  then pcall(function() watermarkGui:Destroy() end); watermarkGui = nil end
    if _configGui    then pcall(function() _configGui:Destroy() end); _configGui = nil end
    if cleardrawcache then pcall(cleardrawcache) end
    if getgenv then getgenv().UniversalESP_Instance = nil end
end

if getgenv then
    getgenv().UniversalESP_Instance = { Unload = unload, Config = Config, Overrides = Overrides }
end

-- ===========================
-- Update Loops
-- ===========================
local function setVisible(d, v)
    if d and d.Visible ~= v then d.Visible = v end
end

local function updateDrawings(data)
    if not data.Box then return end
    local wantBox, wantTr, wantHp = Config.Box, Config.Tracers, Config.HealthBar
    local cam = getCamera()
    local rootPart = data.RootPart
    if not (cam and rootPart and rootPart.Parent) or not (wantBox or wantTr or wantHp) then
        hideDrawings(data)
        return
    end

    local rootPos = rootPart.Position
    local center, onScreen = cam:WorldToViewportPoint(rootPos)
    if not onScreen or center.Z <= 0 then
        hideDrawings(data)
        return
    end

    local head = data.Head
    local topWorld = (head and head.Parent) and (head.Position + Vector3.new(0, 1, 0)) or (rootPos + Vector3.new(0, 3, 0))
    local top = cam:WorldToViewportPoint(topWorld)
    local bottom = cam:WorldToViewportPoint(rootPos - Vector3.new(0, 3.5, 0))
    local height = math.abs(bottom.Y - top.Y)
    local width = height * 0.6
    local x0 = center.X - width / 2
    local y0 = math.min(top.Y, bottom.Y)
    local color = data.DrawColor

    if wantBox then
        local size, pos = Vector2.new(width, height), Vector2.new(x0, y0)
        data.Box.Size = size; data.Box.Position = pos; data.Box.Color = color
        data.BoxOutline.Size = size; data.BoxOutline.Position = pos
    end
    setVisible(data.Box, wantBox)
    setVisible(data.BoxOutline, wantBox)

    local hum = data.Humanoid
    local showHp = wantHp and hum ~= nil and hum.MaxHealth > 0
    if showHp and data.HpBack and data.HpFill then
        local pct = math.clamp(hum.Health / hum.MaxHealth, 0, 1)
        local barH = height * pct
        data.HpBack.Position = Vector2.new(x0 - 6, y0 - 1)
        data.HpBack.Size = Vector2.new(4, height + 2)
        data.HpFill.Position = Vector2.new(x0 - 5, y0 + height - barH)
        data.HpFill.Size = Vector2.new(2, barH)
        data.HpFill.Color = Color3.fromHSV(pct * 0.33, 0.85, 1)
    end
    setVisible(data.HpBack, showHp)
    setVisible(data.HpFill, showHp)

    if data.Tracer then
        if wantTr then
            local vp = cam.ViewportSize
            data.Tracer.From = Vector2.new(vp.X / 2, vp.Y)
            data.Tracer.To = Vector2.new(center.X, math.max(top.Y, bottom.Y))
            data.Tracer.Color = color
        end
        setVisible(data.Tracer, wantTr)
    end
end

local lastScan, lastWatermark, excludeCache, toCleanup = 0, 0, {}, {}

connect(RunService.Heartbeat, function(dt)
    if State.Unloaded then return end
    local now = os.clock()

    if now - lastScan >= 1.5 then
        lastScan = now
        if Workspace then scanWorkspace(Workspace, 1) end
    end

    local lpChar = LocalPlayer and LocalPlayer.Character
    local lpRoot = lpChar and lpChar:FindFirstChild("HumanoidRootPart")
    if lpChar then excludeCache[1] = lpChar else table.clear(excludeCache) end

    table.clear(toCleanup)
    for character, data in pairs(State.TrackedCharacters) do
        if not (character and character.Parent and data.Visuals and data.Visuals.Parent) then
            toCleanup[#toCleanup + 1] = character
            continue
        end

        local hum = data.Humanoid
        if hum and hum.MaxHealth > 0 and hum.Health <= 0 then
            data.ShouldDraw = false
            data.Highlight.Enabled = false
            data.Billboard.Enabled = false
            continue
        end

        local plr = data.Player or (Players and Players:GetPlayerFromCharacter(character))
        data.Player = plr

        if not Config.Enabled or not isEnemy(character, plr) then
            data.ShouldDraw = false
            data.Highlight.Enabled = false
            data.Billboard.Enabled = false
            continue
        end

        local rootPart = data.RootPart
        if not (rootPart and rootPart.Parent) then
            data.ShouldDraw = false
            data.Highlight.Enabled = false
            data.Billboard.Enabled = false
            continue
        end

        local dist = (lpRoot and (rootPart.Position - lpRoot.Position).Magnitude or 0) * 0.28
        if dist > Config.Range then
            data.ShouldDraw = false
            data.Highlight.Enabled = false
            data.Billboard.Enabled = false
            continue
        end

        local isVis = data.IsVisible
        if Config.VisibilityCheck then
            if now - data.LastVisCheck >= 0.2 then
                data.LastVisCheck = now
                data.IsVisible = isTargetVisible(getCamera(), data.Head or rootPart, character, excludeCache)
                isVis = data.IsVisible
            end
        else
            isVis = true
        end

        local color = isVis and Config.VisibleColor or Config.HiddenColor
        if Config.TeamColor and plr and plr.Team and plr.Team.TeamColor then
            color = plr.Team.TeamColor.Color
        end

        data.Highlight.OutlineColor = color
        data.Highlight.FillColor = color
        data.Highlight.Enabled = Config.Glow

        data.Billboard.Enabled = Config.Name or Config.Distance or Config.Tool
        data.NameLabel.Visible = Config.Name
        data.NameLabel.TextColor3 = color
        data.DistanceLabel.Visible = Config.Distance
        data.DistanceLabel.Text = math.floor(dist) .. "m"

        if Config.Tool and now - data.LastToolCheck >= 0.25 then
            data.LastToolCheck = now
            local tName = ""
            if Overrides.GetTool then
                local ok, res = pcall(Overrides.GetTool, character, plr)
                if ok and type(res) == "string" then tName = res end
            else
                local tool = character:FindFirstChildOfClass("Tool")
                if tool then tName = tool.Name end
            end
            data.ToolLabel.Text = tName
            data.ToolLabel.Visible = (tName ~= "")
        elseif not Config.Tool then
            data.ToolLabel.Visible = false
        end

        data.ShouldDraw = true
        data.DrawColor = color
    end

    for i = 1, #toCleanup do cleanupESP(toCleanup[i]) end

    -- Watermark
    if Config.Watermark and (watermarkDraw or watermarkLabel) then
        if now - lastWatermark >= 0.2 then
            lastWatermark = now
            local fps = math.floor(1 / math.max(dt or 0.016, 0.0001))
            local ping = 0
            pcall(function()
                ping = math.floor(Stats.Network.ServerStatsItem["Data Ping"]:GetValue())
            end)
            local text = string.format("Universal ESP | FPS: %d | Ping: %dms", fps, ping)
            if watermarkDraw then
                watermarkDraw.Text = text; watermarkDraw.Visible = true
            elseif watermarkLabel then
                watermarkLabel.Text = text; watermarkLabel.Visible = true
            end
        end
    else
        if watermarkDraw then watermarkDraw.Visible = false end
        if watermarkLabel then watermarkLabel.Visible = false end
    end
end)

if HAS_DRAW then
    connect(RunService.RenderStepped, function()
        if State.Unloaded then return end
        for character, data in pairs(State.TrackedCharacters) do
            if data.ShouldDraw and character and character.Parent then
                updateDrawings(data)
            else
                hideDrawings(data)
            end
        end
    end)
end

-- ===========================
-- GUI (Rayfield Gen2)
-- ===========================
task.spawn(function()
    local okLib, Rayfield = pcall(function()
        return loadstring(game:HttpGet("https://sirius.menu/gen2"))()
    end)
    if State.Unloaded or not okLib or not Rayfield then return end

    local window = Rayfield:CreateWindow({
        name = "Universal ESP",
        subtitle = "Rayfield Gen2",
        sidebarLayout = true,
    })

    local refreshers = {}
    local function addRef(fn) refreshers[#refreshers + 1] = fn end
    local function refreshAll() for _, fn in ipairs(refreshers) do pcall(fn) end end

    local function toggle(tab, name, key, onChange)
        local h = tab:CreateToggle({
            name = name,
            value = Config[key] and true or false,
            forgetState = true,
            callback = function(v)
                Config[key] = v
                if onChange then onChange(v) end
            end,
        })
        addRef(function() h:Set(Config[key] and true or false, true) end)
    end

    -- Tab 1: ESP
    local tESP = window:CreateTab({ name = "ESP", icon = 0 })
    tESP:CreateDivider({ text = "Visuals" })
    toggle(tESP, "Enable ESP", "Enabled")
    toggle(tESP, "Highlight (Glow)", "Glow")
    toggle(tESP, "Box (Drawing)", "Box")
    toggle(tESP, "Health Bar", "HealthBar")
    toggle(tESP, "Name", "Name")
    toggle(tESP, "Distance", "Distance")
    toggle(tESP, "Held Tool", "Tool")
    toggle(tESP, "Tracers (Drawing)", "Tracers")

    tESP:CreateDivider({ text = "Appearance" })
    local sRange = tESP:CreateSlider({
        name = "Max Distance", range = { 100, 10000 }, increment = 50,
        value = Config.Range, suffix = " m", forgetState = true,
        callback = function(v) Config.Range = v end,
    })
    addRef(function() sRange:Set(Config.Range, true) end)

    local sTrans = tESP:CreateSlider({
        name = "Glow Transparency", range = { 0, 100 }, increment = 1,
        value = math.floor(Config.Transparency * 100 + 0.5), suffix = "%", forgetState = true,
        callback = function(v)
            Config.Transparency = v / 100
            for _, d in pairs(State.TrackedCharacters) do
                if d.Highlight then d.Highlight.FillTransparency = Config.Transparency end
            end
        end,
    })
    addRef(function() sTrans:Set(math.floor(Config.Transparency * 100 + 0.5), true) end)

    local cpVis = tESP:CreateColorPicker({
        name = "Visible Color", color = Config.VisibleColor, forgetState = true,
        callback = function(c) Config.VisibleColor = c end,
    })
    addRef(function() cpVis:Set(Config.VisibleColor, true) end)

    local cpHid = tESP:CreateColorPicker({
        name = "Hidden Color", color = Config.HiddenColor, forgetState = true,
        callback = function(c) Config.HiddenColor = c end,
    })
    addRef(function() cpHid:Set(Config.HiddenColor, true) end)

    -- Tab 2: Filters & Teams
    local tTeam = window:CreateTab({ name = "Teams", icon = 0 })
    tTeam:CreateDivider({ text = "Filters" })
    toggle(tTeam, "Team Check", "TeamCheck")
    toggle(tTeam, "Use Team Color", "TeamColor")
    toggle(tTeam, "Show NPCs / Bots", "ShowBots")
    toggle(tTeam, "Visibility Check", "VisibilityCheck")

    tTeam:CreateDivider({ text = "Team Detection" })
    local ddSrc = tTeam:CreateDropdown({
        name = "Detection Source", options = TEAM_SOURCES, value = Config.TeamSource, forgetState = true,
        callback = function(sel)
            if type(sel) == "table" then sel = sel[1] end
            if type(sel) == "string" then Config.TeamSource = sel end
        end,
    })
    addRef(function() ddSrc:Set(Config.TeamSource, true) end)

    local inKey = tTeam:CreateInput({
        name = "Custom Team Key (Attr/Value)", placeholder = "e.g. TeamId",
        value = Config.CustomTeamKey, forgetState = true,
        callback = function(txt) Config.CustomTeamKey = (tostring(txt or "")):match("^%s*(.-)%s*$") end,
    })
    addRef(function() inKey:Set(Config.CustomTeamKey, true) end)

    tTeam:CreateButton({
        name = "Print Team Diagnostics (F9)",
        callback = function()
            print("[Universal ESP] === Team Diagnostics ===")
            print("Source:", Config.TeamSource, "| CustomKey:", Config.CustomTeamKey)
            if LocalPlayer then
                print("ME:", LocalPlayer.Name, "| Team:", tostring(LocalPlayer.Team),
                    "| TeamColor:", tostring(LocalPlayer.TeamColor),
                    "| Attr:", tostring(getAttrTeam(LocalPlayer, LocalPlayer.Character)),
                    "| Folder:", tostring(getFolderTeam(LocalPlayer.Character)))
            end
            for _, p in ipairs(Players:GetPlayers()) do
                if p ~= LocalPlayer then
                    print(p.Name, "| Team:", tostring(p.Team),
                        "| TeamColor:", tostring(p.TeamColor),
                        "| Attr:", tostring(getAttrTeam(p, p.Character)),
                        "| Folder:", tostring(getFolderTeam(p.Character)),
                        "| SameTeam:", tostring(isSameTeam(p.Character, p)))
                end
            end
            window:Notify({ title = "Diagnostics", content = "Printed to F9 console.", duration = 4 })
        end,
    })

    -- Tab 3: Settings
    local tSet = window:CreateTab({ name = "Settings", icon = 0 })
    tSet:CreateDivider({ text = "Hotkeys" })
    local function addKey(name, key)
        local h = tSet:CreateKeybind({
            name = name, value = Config[key], forgetState = true,
            callback = function() end,
            onChanged = function(k)
                if typeof(k) == "EnumItem" and k.EnumType == Enum.KeyCode then Config[key] = k end
            end,
        })
        addRef(function() h:Set(Config[key], true) end)
    end
    addKey("Toggle ESP", "ToggleKey")
    addKey("Toggle Menu", "GuiKey")
    addKey("Unload Script", "UnloadKey")

    tSet:CreateDivider({ text = "Interface & Config" })
    toggle(tSet, "Watermark (FPS / Ping)", "Watermark")
    tSet:CreateButton({ name = "Save Config", callback = function() saveConfig(); window:Notify({ title = "Config", content = "Saved.", duration = 3 }) end })
    tSet:CreateButton({
        name = "Reset Defaults",
        callback = function()
            for k, v in pairs(DEFAULTS) do Config[k] = v end
            saveConfig()
            refreshAll()
            window:Notify({ title = "Config", content = "Defaults restored.", duration = 3 })
        end,
    })
    tSet:CreateButton({ name = "Unload Script", callback = unload })

    _configGui = { Destroy = function() pcall(function() window:Unload() end) end }
    _guiRefreshAll = refreshAll
    _guiToggle = function() pcall(function() window:ToggleHide() end); refreshAll() end

    if State.Unloaded then pcall(function() window:Unload() end) end
end)

-- ===========================
-- Input
-- ===========================
connect(UserInputService.InputBegan, function(input, processed)
    if processed then return end
    if input.KeyCode == Config.ToggleKey then
        Config.Enabled = not Config.Enabled
        if _guiRefreshAll then _guiRefreshAll() end
    elseif input.KeyCode == Config.GuiKey then
        if _guiToggle then _guiToggle() end
    elseif input.KeyCode == Config.UnloadKey then
        unload()
    end
end)
