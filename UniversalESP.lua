-- ============================================================
-- Universal ESP — fixed and optimized version
-- Visual ideas (box outline, health bar next to the box, held item
-- display, the Overrides pattern) taken from the ESP library
-- IonHub (tatar0071, tested). Code rewritten from scratch for this script.
-- ============================================================

local _r = tostring(math.random(1e5, 9e5))
local visualFolderName = "ESPVisual_" .. _r

-- ===========================
-- Preventing multiple instances
-- ===========================
if getgenv then
    local prev = getgenv().UniversalESP_Instance
    if prev and type(prev.Unload) == "function" then
        pcall(prev.Unload)
    end
end

-- ===========================
-- Environment helpers
-- ===========================
local cref  = cloneref  or function(x) return x end
local cwrap = newcclosure or function(fn) return fn end

local function gs(name)
    local ok, service = pcall(function() return game:GetService(name) end)
    return (ok and service) and cref(service) or nil
end

local rawPlayers       = game:GetService("Players")
local Players          = gs("Players") or rawPlayers
local RunService       = gs("RunService")
local UserInputService = gs("UserInputService")
local Stats            = gs("Stats")
local CoreGui          = gs("CoreGui")
local Workspace        = gs("Workspace") or cref(workspace)
local function getCamera()
    return Workspace and (Workspace.CurrentCamera or Workspace:FindFirstChildOfClass("Camera")) or nil
end
local rawRaycast       = Workspace and Workspace.Raycast

local LocalPlayer = Players and cref(Players.LocalPlayer) or nil
if Players and not LocalPlayer then
    local pOk = pcall(function()
        Players:GetPropertyChangedSignal("LocalPlayer"):Wait()
        LocalPlayer = cref(Players.LocalPlayer)
    end)
    if not pOk then LocalPlayer = Players.LocalPlayer end
end

-- ===========================
-- Config & State
-- ===========================
local Config = {
    ToggleKey       = Enum.KeyCode.F1,
    UnloadKey       = Enum.KeyCode.End,
    GuiKey          = Enum.KeyCode.F2,
    TeamCheck       = true,
    IgnoreNeutral   = true,
    ShowBots        = true,
    Watermark       = true,
    VisibilityCheck = true,
    VisibleColor    = Color3.fromRGB(80, 225, 80),
    HiddenColor     = Color3.fromRGB(235, 60, 60),

    ExtraContainerNames = {
        "live","char","player","npc","bot","enem","entit","mob",
        "unit","world","agent","pawn","actor","creature","humanoid",
        "character","figure","model","rig","dummy",
    },
    ScanDepth    = 4,
    ScanTerrain  = false,
    ScanInterval = 1.0,
    DeepRigSearch = false,

    UseNilScan           = false,
    NilScanInterval      = 5.0,
    UseGetInstances      = false,
    GetInstancesInterval = 10.0,
    UseMetaHook          = false,
    UseScriptEnvScan     = false,
    ScriptEnvInterval    = 15.0,
    ScriptEnvKeys        = {
        "enemies","players","characters","entities","npcs","mobs",
        "targets","units","agents","bots","pawns","actors",
        "Enemies","Players","Characters","Entities","NPCs",
    },

    -- Only names that unambiguously denote a team. "Class", "Group", "Guild", "Clan"
    -- were removed on purpose: allies with different classes were then counted as enemies.
    TeamAttributeNames = {
        "Team","team","TeamId","TeamID","teamId","TeamName","TeamNumber",
        "Faction","faction","Side","side","Alliance","alliance",
    },
    TeamValueNames = {
        "Team","TeamId","TeamName","Faction","FactionName","Side","Alliance",
    },
    TeamLeaderstatsKeys = {
        "Team","Faction","Side","Alliance",
    },
    -- Team info source: Auto / Team / TeamColor / Attribute / Folder / Body color
    TeamSource    = "Auto",
    -- Custom attribute or Value object name holding the team (empty = none)
    CustomTeamKey = "",
    NeutralIsEnemy   = true,
    AutoFFA          = false,  -- one shared team = FFA (disabled in co-op)
    NameEnemiesOnly  = true,   -- name only on enemies (allies without a name)
    UseEnemyCache    = true,
    EnemyCacheTTL    = 1.5,

    SaveEnabled = true,
    SaveFolder  = "UniversalESP",
    SaveFile    = "config.json",
}

local State = {
    ESP = {
        Enabled      = true,
        Glow         = true,
        Name         = true,
        Distance     = true,
        Range        = 5000,
        TeamColor    = false,
        Transparency = 0.75,
        HealthBar    = true,
        Box          = true,
        Tracers      = false,
        Tool         = false,
    },
    Watermark         = { Enabled = Config.Watermark },
    TrackedPlayers    = {},
    TrackedCharacters = {},
    Connections       = {},
    Unloaded          = false,
}

-- ===========================
-- Saving / Loading config
-- ===========================
local HttpService = gs("HttpService")

-- Keys saved from Config (whitelist – protects tables like ExtraContainerNames)
local CONFIG_KEYS = {
    "TeamCheck","IgnoreNeutral","ShowBots","Watermark","VisibilityCheck","AutoFFA","NameEnemiesOnly","TeamSource","CustomTeamKey",
    "ScanDepth","ScanTerrain","ScanInterval","DeepRigSearch",
    "UseNilScan","UseGetInstances","UseMetaHook","UseScriptEnvScan",
}
-- Keys saved from State.ESP (in the file with the ESP_ prefix)
local ESP_KEYS = {
    "Enabled","Glow","Name","Distance","Range","TeamColor","Transparency",
    "HealthBar","Box","Tracers","Tool",
}

local CONFIG_VERSION = 3
-- Performance-affecting options – ignored from files in the old format
local PERF_KEYS = {
    ScanInterval = true, UseNilScan = true, UseGetInstances = true,
    UseMetaHook = true, UseScriptEnvScan = true, AutoFFA = true,
}

local function c3toHex(c)
    return string.format("%02X%02X%02X",
        math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5))
end

local function hexToC3(hex)
    if type(hex) ~= "string" or #hex < 6 then return nil end
    local r = tonumber(hex:sub(1, 2), 16)
    local g = tonumber(hex:sub(3, 4), 16)
    local b = tonumber(hex:sub(5, 6), 16)
    if not (r and g and b) then return nil end
    return Color3.fromRGB(r, g, b)
end

local function saveConfig()
    if not (Config.SaveEnabled and HttpService and writefile and makefolder and isfolder) then return end
    pcall(function()
        if not isfolder(Config.SaveFolder) then
            makefolder(Config.SaveFolder)
        end
        Config.Watermark = State.Watermark.Enabled  -- the GUI changes State, not Config
        local data = {}
        for _, k in ipairs(CONFIG_KEYS) do data[k] = Config[k] end
        for _, k in ipairs(ESP_KEYS)    do data["ESP_" .. k] = State.ESP[k] end
        data.Version      = CONFIG_VERSION
        data.ToggleKey    = Config.ToggleKey.Name
        data.GuiKey       = Config.GuiKey.Name
        data.UnloadKey    = Config.UnloadKey.Name
        data.VisibleColor = c3toHex(Config.VisibleColor)
        data.HiddenColor  = c3toHex(Config.HiddenColor)

        writefile(Config.SaveFolder .. "/" .. Config.SaveFile, HttpService:JSONEncode(data))
    end)
end

local function loadConfig()
    if not (Config.SaveEnabled and HttpService and readfile and isfile and isfolder) then return end
    pcall(function()
        local path = Config.SaveFolder .. "/" .. Config.SaveFile
        if not isfolder(Config.SaveFolder) or not isfile(path) then return end
        local raw = readfile(path)
        if type(raw) ~= "string" or raw == "" then return end

        -- A corrupted file must not crash the script
        local ok, data = pcall(function() return HttpService:JSONDecode(raw) end)
        if not ok or type(data) ~= "table" then
            warn("[Universal ESP] Corrupted config file – using defaults.")
            return
        end

        local oldFormat = data.Version ~= CONFIG_VERSION
        for _, k in ipairs(CONFIG_KEYS) do
            local v = data[k]
            if v ~= nil and type(v) == type(Config[k]) and not (oldFormat and PERF_KEYS[k]) then
                Config[k] = v
            end
        end
        for _, k in ipairs(ESP_KEYS) do
            local v = data["ESP_" .. k]
            if v ~= nil and type(v) == type(State.ESP[k]) then State.ESP[k] = v end
        end
        Config.VisibleColor = hexToC3(data.VisibleColor) or Config.VisibleColor
        Config.HiddenColor  = hexToC3(data.HiddenColor)  or Config.HiddenColor
        State.Watermark.Enabled = Config.Watermark

        -- migrate legacy (Polish) TeamSource values from older config files
        if Config.TeamSource == "Atrybut" then Config.TeamSource = "Attribute"
        elseif Config.TeamSource == "Kolor ciała" then Config.TeamSource = "Body color" end

        for _, kname in ipairs({ "ToggleKey", "GuiKey", "UnloadKey" }) do
            local nm = data[kname]
            if type(nm) == "string" then
                local okK, kc = pcall(function() return Enum.KeyCode[nm] end)
                if okK and kc then Config[kname] = kc end
            end
        end
    end)
end

loadConfig()

-- ===========================
-- Roblox teams cache
-- ===========================
local _teamsCache     = nil
local _teamsCacheTime = 0
local TEAMS_CACHE_TTL = 2.0

local function getCachedTeams()
    local now = os.clock()
    if _teamsCache == nil or (now - _teamsCacheTime) >= TEAMS_CACHE_TTL then
        local TeamsService = gs("Teams")
        _teamsCache     = TeamsService and TeamsService:GetTeams() or {}
        _teamsCacheTime = now
    end
    return _teamsCache
end

-- ===========================
-- Connection helper
-- ===========================
local function connect(signal, fn)
    local c = signal:Connect(cwrap(fn))
    table.insert(State.Connections, c)
    return c
end

-- ===========================
-- Advanced TeamCheck
-- ===========================
local _enemyCache      = {}
local _enemyCacheConns = {}

local function invalidateEnemyCache(character)
    _enemyCache[character] = nil
    if _enemyCacheConns[character] then
        for _, c in ipairs(_enemyCacheConns[character]) do
            pcall(function() c:Disconnect() end)
        end
        _enemyCacheConns[character] = nil
    end
end

local TEAM_SOURCES = { "Auto", "Team", "TeamColor", "Attribute", "Folder", "Body color" }

local function normId(v)
    local str = tostring(v):lower():gsub("^%s+", ""):gsub("%s+$", "")
    if str == "" or str == "nil" or str == "0" or str == "false" or str == "none" then
        return nil
    end
    return str
end

-- Value with the given name: an attribute or a ValueBase object inside the instance
local function readNamed(inst, name)
    local ok, val = pcall(function() return inst:GetAttribute(name) end)
    if ok and val ~= nil then return val end
    local child = inst:FindFirstChild(name)
    if child then
        local ok2, v = pcall(function() return child.Value end)
        if ok2 and v ~= nil then
            if typeof(v) == "Instance" then return v.Name end
            return v
        end
    end
    return nil
end

-- 1. Roblox team (name + color so teams with the same name don't merge)
local function srcRobloxTeam(obj)
    local ok, team = pcall(function() return obj.Team end)
    if ok and team and typeof(team) == "Instance" and team:IsA("Team") then
        local nm = normId(team.Name)
        if nm then return nm .. "#" .. tostring(team.TeamColor.Number) end
    end
    return nil
end

-- 2. TeamColor (force = default colors too)
local function srcTeamColor(obj, force)
    local ok, tc = pcall(function() return obj.TeamColor end)
    if ok and tc and typeof(tc) == "BrickColor" then
        if force then return "tc_" .. tostring(tc.Number) end
        if tc ~= BrickColor.new("Medium stone grey") and tc ~= BrickColor.new("White") then
            return "tc_" .. tostring(tc.Number)
        end
    end
    return nil
end

-- 3. Custom key set in the menu
local function srcKey(obj, character)
    local key = Config.CustomTeamKey
    if type(key) ~= "string" or key == "" then return nil end
    local id = normId(readNamed(obj, key) or "")
    if id then return id end
    if character and character ~= obj then
        local v = readNamed(character, key)
        if v ~= nil then return normId(v) end
    end
    return nil
end

-- 4. Attributes, Value objects and leaderstats with typical names
local function srcCustom(obj, character)
    for _, attrName in ipairs(Config.TeamAttributeNames) do
        local ok, val = pcall(function() return obj:GetAttribute(attrName) end)
        if ok and val ~= nil then
            local id = normId(val)
            if id then return id end
        end
    end
    if character and character ~= obj then
        for _, attrName in ipairs(Config.TeamAttributeNames) do
            local ok, val = pcall(function() return character:GetAttribute(attrName) end)
            if ok and val ~= nil then
                local id = normId(val)
                if id then return id end
            end
        end
    end
    for _, valName in ipairs(Config.TeamValueNames) do
        local child = obj:FindFirstChild(valName)
        if child then
            local ok, val = pcall(function() return child.Value end)
            if ok and val ~= nil then
                local id = typeof(val) == "Instance" and normId(val.Name) or normId(val)
                if id then return id end
            end
        end
    end
    if character and character ~= obj then
        for _, valName in ipairs(Config.TeamValueNames) do
            local child = character:FindFirstChild(valName)
            if child then
                local ok, val = pcall(function() return child.Value end)
                if ok and val ~= nil then
                    local id = typeof(val) == "Instance" and normId(val.Name) or normId(val)
                    if id then return id end
                end
            end
        end
    end
    local ls = obj:FindFirstChild("leaderstats")
    if ls then
        for _, key in ipairs(Config.TeamLeaderstatsKeys) do
            local child = ls:FindFirstChild(key)
            if child then
                local ok, val = pcall(function() return child.Value end)
                if ok and val ~= nil then
                    local id = normId(val)
                    if id then return id end
                end
            end
        end
    end
    return nil
end

-- 5. Folder containing the character (e.g. Workspace.Teams.Red.Player)
local function srcFolder(character)
    local par = character and character.Parent
    if par and par ~= Workspace then return normId(par.Name) end
    return nil
end

-- 6. Body color (teams told apart by uniforms / model color)
local function srcBodyColor(character)
    if not character then return nil end
    local c
    local bc = character:FindFirstChildOfClass("BodyColors")
    if bc then
        local ok, v = pcall(function() return bc.TorsoColor3 end)
        if ok then c = v end
    end
    if not c then
        local torso = character:FindFirstChild("UpperTorso") or character:FindFirstChild("Torso")
        if torso and torso:IsA("BasePart") then c = torso.Color end
    end
    if c then
        return string.format("bc_%02X%02X%02X",
            math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5))
    end
    return nil
end

local function getTeamId(obj, character)
    if not obj then return nil end
    local mode = Config.TeamSource

    if mode == "Team"        then return srcRobloxTeam(obj) end
    if mode == "TeamColor"   then return srcTeamColor(obj, true) end
    if mode == "Attribute"     then return srcKey(obj, character) or srcCustom(obj, character) end
    if mode == "Folder"      then return srcFolder(character or obj) end
    if mode == "Body color" then return srcBodyColor(character or obj) end

    -- Auto: custom key > Team > TeamColor (when no Team) > attributes/Value/leaderstats
    local id = srcKey(obj, character)
    if id then return id end
    id = srcRobloxTeam(obj)
    if id then return id end
    local okT, team = pcall(function() return obj.Team end)
    if okT and team == nil then
        id = srcTeamColor(obj, false)
        if id then return id end
    end
    return srcCustom(obj, character)
end

-- Description of player/character data for diagnostics (attributes, Value objects, leaderstats)
local function describeTeamData(inst)
    if not inst then return "(none)" end
    local parts = {}
    local okT, t = pcall(function() return inst.Team end)
    if okT then parts[#parts + 1] = "Team=" .. tostring(t and t.Name or "nil") end
    local okA, attrs = pcall(function() return inst:GetAttributes() end)
    if okA and type(attrs) == "table" then
        for k, v in pairs(attrs) do parts[#parts + 1] = "@" .. tostring(k) .. "=" .. tostring(v) end
    end
    local function addValues(container, prefix)
        local okC, kids = pcall(function() return container:GetChildren() end)
        if not okC then return end
        for _, ch in ipairs(kids) do
            if ch:IsA("ValueBase") then
                local okV, v = pcall(function() return ch.Value end)
                parts[#parts + 1] = prefix .. ch.Name .. "=" .. tostring(okV and v or "?")
            end
        end
    end
    addValues(inst, "")
    local ls = inst:FindFirstChild("leaderstats")
    if ls then addValues(ls, "ls.") end
    if #parts > 16 then
        local cut = {}
        for i = 1, 16 do cut[i] = parts[i] end
        parts = cut
        parts[#parts + 1] = "…"
    end
    return #parts > 0 and table.concat(parts, ", ") or "(none)"
end

-- Clears all team caches (called e.g. when I change team)
local _myTeamId, _myTeamTime = nil, -1e9
local _singleTeam, _singleTeamTime = false, -1e9
local _allyCache = {}

local function clearAllEnemyCache()
    for char in pairs(_enemyCache) do _enemyCache[char] = nil end
    for char in pairs(_allyCache)  do _allyCache[char]  = nil end
    _myTeamTime, _singleTeamTime = -1e9, -1e9
end

local function getMyTeamId()
    local now = os.clock()
    if now - _myTeamTime >= 1 then
        _myTeamTime = now
        _myTeamId = LocalPlayer and getTeamId(LocalPlayer, LocalPlayer.Character) or nil
    end
    return _myTeamId
end

-- true when all players (min. 3) are on the same Roblox team,
-- which usually means a game without real teams (FFA with a single default team)
local function isSingleTeamServer()
    local now = os.clock()
    if now - _singleTeamTime >= 2 then
        _singleTeamTime = now
        local first, count, same = nil, 0, true
        for _, p in ipairs(Players:GetPlayers()) do
            local ok, t = pcall(function() return p.Team end)
            if not ok then t = nil end
            count += 1
            if count == 1 then
                first = t
            elseif t ~= first then
                same = false
                break
            end
        end
        _singleTeam = same and count >= 3 and first ~= nil
    end
    return _singleTeam
end

local NEUTRAL_PATTERNS = {
    "spectat","lobby","afk","choosing","menu","waiting","pregame","spectator","neutral","unassigned",
}
local function isNeutralTeamName(name)
    local lower = name:lower()
    for _, pat in ipairs(NEUTRAL_PATTERNS) do
        if lower:find(pat, 1, true) then return true end
    end
    return false
end

local function setupEnemyCacheInvalidation(player, character)
    if not Config.UseEnemyCache then return end
    local conns = {}

    pcall(function()
        local c = player:GetPropertyChangedSignal("Team"):Connect(function()
            invalidateEnemyCache(character)
        end)
        table.insert(conns, c)
    end)
    pcall(function()
        local c = player:GetPropertyChangedSignal("TeamColor"):Connect(function()
            invalidateEnemyCache(character)
        end)
        table.insert(conns, c)
    end)
    pcall(function()
        local c = player.AttributeChanged:Connect(function(attr)
            for _, name in ipairs(Config.TeamAttributeNames) do
                if attr == name then invalidateEnemyCache(character); break end
            end
        end)
        table.insert(conns, c)
    end)
    if character then
        pcall(function()
            local c = character.AttributeChanged:Connect(function(attr)
                for _, name in ipairs(Config.TeamAttributeNames) do
                    if attr == name then invalidateEnemyCache(character); break end
                end
            end)
            table.insert(conns, c)
        end)
    end

    _enemyCacheConns[character] = conns
end

-- ===========================
-- isEnemy
-- ===========================
-- Optional per-game overrides, e.g. from the executor console:
--   getgenv().UniversalESP_Instance.Overrides.IsEnemy = function(char, plr) return true end
--   getgenv().UniversalESP_Instance.Overrides.GetTool = function(char, plr) return "..." end
local Overrides = { IsEnemy = nil, GetTool = nil }

local function isEnemy(character, player)
    if not character then return false end
    if character == (LocalPlayer and LocalPlayer.Character) then return false end
    if player and player == LocalPlayer then return false end
    if LocalPlayer and character.Name == LocalPlayer.Name then return false end

    local ovEnemy = Overrides.IsEnemy
    if ovEnemy then
        local okO, res = pcall(ovEnemy, character, player)
        if okO and res ~= nil then return res and true or false end
    end

    if not player then
        if not Config.ShowBots then return false end
        if Config.TeamCheck and LocalPlayer then
            local myTeamId = getMyTeamId()
            if myTeamId then
                local botTeamId = getTeamId(character, character)
                if botTeamId and botTeamId == myTeamId then return false end
            end
        end
        return true
    end

    if Config.UseEnemyCache then
        local cached = _enemyCache[character]
        if cached then
            if (os.clock() - cached.time) < Config.EnemyCacheTTL then
                return cached.result
            else
                _enemyCache[character] = nil
            end
        end
    end

    local result = (function()
        local myTeamId    = getMyTeamId()
        local theirTeamId = getTeamId(player, character)

        if myTeamId and theirTeamId then
            if Config.TeamCheck and myTeamId == theirTeamId then
                -- Everyone on one team = no real teams, so nobody is an ally
                if not (Config.AutoFFA and isSingleTeamServer()) then
                    return false
                end
            end
            if Config.IgnoreNeutral then
                if player.Team and isNeutralTeamName(player.Team.Name) then return false end
                if isNeutralTeamName(theirTeamId) then return false end
            end
            return true
        end

        if myTeamId and not theirTeamId then
            if Config.NeutralIsEnemy then return true end
            if Config.IgnoreNeutral  then return false end
            return true
        end

        if not myTeamId and not theirTeamId then
            local hasGameTeams = #getCachedTeams() > 0
            if not hasGameTeams then return true end
            if Config.NeutralIsEnemy then return true end
            if Config.IgnoreNeutral  then return false end
            return true
        end

        -- not myTeamId and theirTeamId
        if Config.IgnoreNeutral and isNeutralTeamName(theirTeamId) then return false end
        return true
    end)()

    if Config.UseEnemyCache then
        if not _enemyCacheConns[character] then
            setupEnemyCacheInvalidation(player, character)
        end
        _enemyCache[character] = { result = result, time = os.clock() }
    end

    return result
end

-- ===========================
-- isAlly: whether the character is on MY team (regardless of TeamCheck)
-- ===========================
local function isAlly(character, player)
    if not character then return false end
    local cached = _allyCache[character]
    local ttl = math.max(Config.EnemyCacheTTL, 0.5)
    if cached and (os.clock() - cached.time) < ttl then return cached.result end

    local result  = false
    local handled = false

    local ov = Overrides.IsEnemy
    if ov then
        local ok, res = pcall(ov, character, player)
        if ok and res ~= nil then result = not res; handled = true end
    end

    if not handled then
        local myId = getMyTeamId()
        if myId then
            local theirId = player and getTeamId(player, character) or getTeamId(character, character)
            if theirId and theirId == myId and not (Config.AutoFFA and isSingleTeamServer()) then
                result = true
            end
        end
    end

    _allyCache[character] = { result = result, time = os.clock() }
    return result
end

-- ===========================
-- Raycast
-- ===========================
local function makeRayParams()
    local p = RaycastParams.new()
    p.FilterType  = Enum.RaycastFilterType.Exclude
    p.IgnoreWater = true
    return p
end

local _sharedRayParams = makeRayParams()

local function _castRay(origin, dir, excludeTable)
    _sharedRayParams.FilterDescendantsInstances = excludeTable
    local ok, result
    if rawRaycast then
        ok, result = pcall(rawRaycast, Workspace, origin, dir, _sharedRayParams)
    else
        ok, result = pcall(function() return Workspace:Raycast(origin, dir, _sharedRayParams) end)
    end
    if not (ok and result) then return nil end

    local hit = result.Instance
    if hit and hit:IsA("BasePart") and (hit.Transparency >= 0.85 or not hit.CanCollide) then
        local extExclude = {}
        for i = 1, #excludeTable do extExclude[i] = excludeTable[i] end
        extExclude[#extExclude + 1] = hit
        _sharedRayParams.FilterDescendantsInstances = extExclude
        local ok2, result2
        if rawRaycast then
            ok2, result2 = pcall(rawRaycast, Workspace, origin, dir, _sharedRayParams)
        else
            ok2, result2 = pcall(function() return Workspace:Raycast(origin, dir, _sharedRayParams) end)
        end
        if ok2 and result2 then return result2 end
        return nil
    end

    return result
end

local function _hitIsPartOfModel(hit, targetModel)
    if not (hit and targetModel) then return false end
    return hit:IsDescendantOf(targetModel)
end

local function isTargetVisible(cam, targetPart, targetModel, excludeTable)
    if not (cam and targetPart and targetPart.Parent and targetModel) then return false end
    local origin = cam.CFrame.Position

    local res1 = _castRay(origin, targetPart.Position - origin, excludeTable)
    if not res1 then return true end
    if _hitIsPartOfModel(res1.Instance, targetModel) then return true end

    local head      = targetModel:FindFirstChild("Head")
    local checkPart = (targetPart == head)
        and (targetModel:FindFirstChild("HumanoidRootPart") or targetModel:FindFirstChild("Torso"))
        or head
    if checkPart and checkPart:IsA("BasePart") and checkPart.Parent then
        local res2 = _castRay(origin, checkPart.Position - origin, excludeTable)
        if not res2 then return true end
        if _hitIsPartOfModel(res2.Instance, targetModel) then return true end
    end

    return false
end

-- ===========================
-- Watermark
-- ===========================
local HAS_DRAW = false
pcall(function()
    local d = Drawing.new("Text"); d.Visible = false; d:Remove(); HAS_DRAW = true
end)

local function getSafeGuiParent()
    if gethui then
        local ok, h = pcall(gethui)
        if ok and h then return cref(h) end
    end
    if CoreGui then
        local ok = pcall(function() return CoreGui.Name end)
        if ok then return cref(CoreGui) end
    end
    if LocalPlayer then
        local pg = LocalPlayer:FindFirstChildOfClass("PlayerGui")
        if pg then return cref(pg) end
    end
    return nil
end

local watermarkDraw  = nil
local watermarkGui   = nil
local watermarkLabel = nil

if State.Watermark.Enabled then
    if HAS_DRAW then
        pcall(function()
            local d = Drawing.new("Text")
            d.Size = 14; d.Position = Vector2.new(16, 16)
            d.Color = Color3.fromRGB(240, 240, 240); d.Outline = true
            d.OutlineColor = Color3.fromRGB(0, 0, 0); d.Font = 2
            d.Visible = true; d.Text = "Universal ESP | Initializing..."
            watermarkDraw = d
        end)
    else
        local parent = getSafeGuiParent()
        if parent then
            watermarkGui = Instance.new("ScreenGui")
            watermarkGui.Name = "ESPWatermark_" .. _r
            watermarkGui.ResetOnSpawn   = false
            watermarkGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
            pcall(function() if syn and syn.protect_gui then syn.protect_gui(watermarkGui) end end)
            pcall(function() if protect_gui then protect_gui(watermarkGui) end end)

            watermarkLabel = Instance.new("TextLabel")
            watermarkLabel.Name = "WatermarkText_" .. _r
            watermarkLabel.Position = UDim2.new(0, 16, 0, 16)
            watermarkLabel.Size = UDim2.new(0, 300, 0, 20)
            watermarkLabel.BackgroundTransparency = 1
            watermarkLabel.Font = Enum.Font.GothamMedium
            watermarkLabel.TextSize = 14
            watermarkLabel.TextColor3 = Color3.fromRGB(240, 240, 240)
            watermarkLabel.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
            watermarkLabel.TextStrokeTransparency = 0
            watermarkLabel.TextXAlignment = Enum.TextXAlignment.Left
            watermarkLabel.Text = "Universal ESP | Initializing..."
            watermarkLabel.Parent = watermarkGui
            watermarkGui.Parent = parent
        end
    end
end

-- ===========================
-- Visual Cleanup
-- ===========================
local DRAWING_KEYS = { "Box", "BoxOutline", "Tracer", "HpBack", "HpFill" }

local function cleanupESP(character)
    invalidateEnemyCache(character)
    _allyCache[character] = nil
    local data = State.TrackedCharacters[character]
    if data and data ~= false then
        if data.DiedConn then pcall(function() data.DiedConn:Disconnect() end); data.DiedConn = nil end
        if data.AncestryConn then pcall(function() data.AncestryConn:Disconnect() end); data.AncestryConn = nil end
        pcall(function()
            if data.Highlight then data.Highlight.Enabled = false; data.Highlight.Adornee = nil end
        end)
        pcall(function()
            if data.Billboard then data.Billboard.Enabled = false; data.Billboard.Adornee = nil end
        end)
        pcall(function() if data.Visuals then data.Visuals:Destroy() end end)
        for _, key in ipairs(DRAWING_KEYS) do
            local d = data[key]
            if d then pcall(function() d:Remove() end) end
        end
    end
    State.TrackedCharacters[character] = nil
    if character and character.Parent then
        local folder = character:FindFirstChild(visualFolderName)
        if folder then pcall(function() folder:Destroy() end) end
    end
end

-- ===========================
-- Visual Creation
-- ===========================
local function createVisualForCharacter(character, player)
    if State.Unloaded then return end
    if not character or not character.Parent then return end
    if State.TrackedCharacters[character] then return end

    local existing = character:FindFirstChild(visualFolderName)
    if existing then pcall(function() existing:Destroy() end) end

    local humanoid = character:FindFirstChildOfClass("Humanoid")
    if humanoid and humanoid.MaxHealth > 0 and humanoid.Health <= 0 then return end

    local rootPart = character:FindFirstChild("HumanoidRootPart")
        or character:FindFirstChild("Torso")
        or character:FindFirstChild("UpperTorso")
    local head          = character:FindFirstChild("Head")
    local targetAdornee = head or rootPart
    if not targetAdornee then return end

    local visu = Instance.new("Folder")
    visu.Name = visualFolderName; visu.Parent = character

    local highlight = Instance.new("Highlight")
    highlight.Name = "Highlight_" .. _r; highlight.Parent = visu
    highlight.Adornee = character; highlight.Enabled = false
    highlight.OutlineColor = Config.VisibleColor; highlight.FillColor = Config.VisibleColor
    highlight.OutlineTransparency = 0; highlight.FillTransparency = State.ESP.Transparency
    highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop

    local billboard = Instance.new("BillboardGui")
    billboard.Name = "ESPBillboard_" .. _r
    billboard.Size = UDim2.new(0, 160, 0, 56)
    billboard.StudsOffset = (targetAdornee.Name == "Head") and Vector3.new(0, 1.8, 0) or Vector3.new(0, 3.2, 0)
    billboard.AlwaysOnTop = true; billboard.Enabled = false
    billboard.Adornee = targetAdornee; billboard.Parent = visu

    local mainFrame = Instance.new("Frame")
    mainFrame.Name = "MainFrame"; mainFrame.Size = UDim2.new(1, 0, 1, 0)
    mainFrame.BackgroundTransparency = 1; mainFrame.Parent = billboard

    local nameLabel = Instance.new("TextLabel")
    nameLabel.Name = "NameLabel"; nameLabel.Size = UDim2.new(1, 0, 0, 18)
    nameLabel.Position = UDim2.new(0, 0, 0, 0); nameLabel.BackgroundTransparency = 1
    nameLabel.Font = Enum.Font.GothamBold; nameLabel.TextSize = 13
    nameLabel.TextColor3 = Config.VisibleColor; nameLabel.TextStrokeTransparency = 0
    nameLabel.TextStrokeColor3 = Color3.new(0, 0, 0)
    nameLabel.Text = player and (player.DisplayName or player.Name) or character.Name
    nameLabel.Parent = mainFrame

    local distanceLabel = Instance.new("TextLabel")
    distanceLabel.Name = "DistanceLabel"; distanceLabel.Size = UDim2.new(1, 0, 0, 14)
    distanceLabel.Position = UDim2.new(0, 0, 0, 18); distanceLabel.BackgroundTransparency = 1
    distanceLabel.Font = Enum.Font.Gotham; distanceLabel.TextSize = 11
    distanceLabel.TextColor3 = Color3.fromRGB(230, 230, 230); distanceLabel.TextStrokeTransparency = 0
    distanceLabel.TextStrokeColor3 = Color3.new(0, 0, 0)
    distanceLabel.Text = "0m"; distanceLabel.Parent = mainFrame

    local toolLabel = Instance.new("TextLabel")
    toolLabel.Name = "ToolLabel"; toolLabel.Size = UDim2.new(1, 0, 0, 14)
    toolLabel.Position = UDim2.new(0, 0, 0, 32); toolLabel.BackgroundTransparency = 1
    toolLabel.Font = Enum.Font.Gotham; toolLabel.TextSize = 11
    toolLabel.TextColor3 = Color3.fromRGB(255, 220, 120); toolLabel.TextStrokeTransparency = 0
    toolLabel.TextStrokeColor3 = Color3.new(0, 0, 0)
    toolLabel.Text = ""; toolLabel.Visible = false; toolLabel.Parent = mainFrame

    -- Health bar (works without the Drawing API)
    local healthBack = Instance.new("Frame")
    healthBack.Name = "HealthBack"
    healthBack.Size = UDim2.new(0, 80, 0, 5)
    healthBack.Position = UDim2.new(0.5, -40, 0, 48)
    healthBack.BackgroundColor3 = Color3.fromRGB(15, 15, 15)
    healthBack.BorderSizePixel = 0
    healthBack.Visible = false
    healthBack.Parent = mainFrame

    local healthFill = Instance.new("Frame")
    healthFill.Name = "HealthFill"
    healthFill.Size = UDim2.new(1, 0, 1, 0)
    healthFill.BackgroundColor3 = Color3.fromRGB(80, 225, 80)
    healthFill.BorderSizePixel = 0
    healthFill.Parent = healthBack

    -- Box, outline, tracer and health bar next to the box (require the Drawing API)
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
        NameLabel = nameLabel, DistanceLabel = distanceLabel,
        HealthBack = healthBack, HealthFill = healthFill, LastHpPct = -1,
        Box = box, BoxOutline = boxOutline, Tracer = tracer, HpBack = hpBack, HpFill = hpFill,
        ToolLabel = toolLabel, LastToolCheck = 0,
        RootPart = rootPart, Humanoid = humanoid, Head = head,
        LastVisCheck = os.clock() - math.random() * 0.25, IsVisible = false,
        ShouldDraw = false, DrawColor = Config.VisibleColor,
    }
    State.TrackedCharacters[character] = data

    if humanoid then
        data.DiedConn = humanoid.Died:Connect(function()
            cleanupESP(character)
        end)
    end
    data.AncestryConn = character.AncestryChanged:Connect(function(_, parent)
        if not parent then cleanupESP(character) end
    end)
end

-- ===========================
-- Unload
-- ===========================
local _configGui = nil
local _guiRefreshAll = nil   -- set by the GUI
local _guiToggle = nil       -- show/hide the window (set by the GUI)

local function unload()
    if State.Unloaded then return end
    State.Unloaded = true

    saveConfig()

    for _, c in ipairs(State.Connections) do pcall(function() c:Disconnect() end) end
    table.clear(State.Connections)

    for char in pairs(State.TrackedCharacters) do cleanupESP(char) end
    table.clear(State.TrackedCharacters)
    table.clear(State.TrackedPlayers)

    if watermarkDraw then pcall(function() watermarkDraw:Remove() end);  watermarkDraw = nil end
    if watermarkGui  then pcall(function() watermarkGui:Destroy() end);  watermarkGui  = nil end
    if _configGui    then pcall(function() _configGui:Destroy() end);    _configGui    = nil end

    if cleardrawcache then pcall(cleardrawcache) end

    if getgenv and getgenv().UniversalESP_Instance then
        getgenv().UniversalESP_Instance = nil
    end
    print("[Universal ESP] Script fully cleaned up.")
end

if getgenv then
    getgenv().UniversalESP_Instance = { Unload = unload, State = State, Config = Config, Overrides = Overrides }
end

-- ===========================
-- Visual Update
-- ===========================
local _toCleanup = {}

local function hideDrawings(data)
    for _, key in ipairs(DRAWING_KEYS) do
        local d = data[key]
        if d and d.Visible then d.Visible = false end
    end
end

local function setVisible(d, v)
    if d and d.Visible ~= v then d.Visible = v end
end

local function hpColor(pct)
    return Color3.fromHSV(pct * 0.33, 0.85, 1)  -- red -> green
end

-- Health bar in the billboard: only when the Drawing API is missing
local function updateHealthBar(data, humanoid)
    local back, fill = data.HealthBack, data.HealthFill
    if not (back and fill) then return end
    local show = State.ESP.HealthBar and not data.HpFill
        and humanoid ~= nil and humanoid.MaxHealth > 0
    if back.Visible ~= show then back.Visible = show end
    if not show then return end
    local pct = math.clamp(humanoid.Health / humanoid.MaxHealth, 0, 1)
    if data.LastHpPct ~= pct then
        data.LastHpPct = pct
        fill.Size = UDim2.new(pct, 0, 1, 0)
        fill.BackgroundColor3 = hpColor(pct)
    end
end

-- Name of the held item (refreshed 4x/s)
local function updateTool(data, character, now)
    local label = data.ToolLabel
    if not label then return end
    if not State.ESP.Tool then
        if label.Visible then label.Visible = false end
        return
    end
    if now - data.LastToolCheck >= 0.25 then
        data.LastToolCheck = now
        local name = ""
        local ov = Overrides.GetTool
        if ov then
            local ok, res = pcall(ov, character, data.Player)
            if ok and type(res) == "string" then name = res end
        else
            local tool = character:FindFirstChildOfClass("Tool")
            if tool then name = tool.Name end
        end
        if label.Text ~= name then label.Text = name end
        label.Visible = (name ~= "")
    end
end

local function updateDrawings(data, rootPart, color, humanoid)
    if not data.Box then return end  -- no Drawing API

    local wantBox, wantTr, wantHp = State.ESP.Box, State.ESP.Tracers, State.ESP.HealthBar
    local cam = getCamera()
    if not (cam and rootPart and rootPart.Parent) or not (wantBox or wantTr or wantHp) then
        hideDrawings(data); return
    end

    local rootPos = rootPart.Position
    local center, onScreen = cam:WorldToViewportPoint(rootPos)
    if not onScreen or center.Z <= 0 then hideDrawings(data); return end

    local head = data.Head
    local topWorld = (head and head.Parent) and (head.Position + Vector3.new(0, 1, 0)) or (rootPos + Vector3.new(0, 3, 0))
    local top    = cam:WorldToViewportPoint(topWorld)
    local bottom = cam:WorldToViewportPoint(rootPos - Vector3.new(0, 3.5, 0))
    local height = math.abs(bottom.Y - top.Y)
    local width  = height * 0.6
    local x0     = center.X - width / 2
    local y0     = math.min(top.Y, bottom.Y)

    -- Box with a black outline
    if wantBox then
        local size, pos = Vector2.new(width, height), Vector2.new(x0, y0)
        data.Box.Size = size;        data.Box.Position = pos;        data.Box.Color = color
        data.BoxOutline.Size = size; data.BoxOutline.Position = pos
    end
    setVisible(data.Box, wantBox)
    setVisible(data.BoxOutline, wantBox)

    -- Health bar on the left side of the box (outline + fill)
    local showHp = wantHp and humanoid ~= nil and humanoid.MaxHealth > 0
    if showHp and data.HpBack and data.HpFill then
        local pct  = math.clamp(humanoid.Health / humanoid.MaxHealth, 0, 1)
        local barH = height * pct
        data.HpBack.Position = Vector2.new(x0 - 6, y0 - 1)
        data.HpBack.Size     = Vector2.new(4, height + 2)
        data.HpFill.Position = Vector2.new(x0 - 5, y0 + height - barH)
        data.HpFill.Size     = Vector2.new(2, barH)
        data.HpFill.Color    = hpColor(pct)
    end
    setVisible(data.HpBack, showHp)
    setVisible(data.HpFill, showHp)

    -- Tracer
    if data.Tracer then
        if wantTr then
            local vp = cam.ViewportSize
            data.Tracer.From  = Vector2.new(vp.X / 2, vp.Y)
            data.Tracer.To    = Vector2.new(center.X, math.max(top.Y, bottom.Y))
            data.Tracer.Color = color
        end
        setVisible(data.Tracer, wantTr)
    end
end

local function updateVisual(character, data, lpChar, lpRoot, excludeTable)
    if not (character and data) then return end
    if not (data.Visuals and data.Visuals.Parent) then hideDrawings(data); return end
    if not (data.Highlight and data.Billboard) then return end

    local function hideAll()
        data.ShouldDraw = false
        hideDrawings(data)
        if data.Highlight.Enabled then data.Highlight.Enabled = false end
        if data.Billboard.Enabled  then data.Billboard.Enabled  = false end
    end

    local humanoid = data.Humanoid
    if not humanoid or not humanoid.Parent then
        humanoid = character:FindFirstChildOfClass("Humanoid"); data.Humanoid = humanoid
    end
    if humanoid and humanoid.MaxHealth > 0 and humanoid.Health <= 0 then hideAll(); return end

    local player = data.Player
    if not player then
        player = Players:GetPlayerFromCharacter(character); data.Player = player
    end
    if player == LocalPlayer then return end
    if not State.ESP.Enabled then hideAll(); return end
    if not isEnemy(character, player) then hideAll(); return end

    local rootPart = data.RootPart
    if not (rootPart and rootPart.Parent) then
        data.RootPart = character:FindFirstChild("HumanoidRootPart")
            or character:FindFirstChild("Torso") or character:FindFirstChild("UpperTorso")
        rootPart = data.RootPart
        if not rootPart then hideAll(); return end
    end

    local distance = (lpRoot and (rootPart.Position - lpRoot.Position).Magnitude or 0) * 0.28  -- studs -> meters
    if distance > State.ESP.Range then hideAll(); return end

    local targetAdornee = data.Head
    if not (targetAdornee and targetAdornee.Parent) then
        targetAdornee = character:FindFirstChild("Head") or rootPart
        data.Head = targetAdornee
    end
    if targetAdornee and targetAdornee:IsA("BasePart") then
        if data.AdorneeCache ~= targetAdornee then
            data.AdorneeCache = targetAdornee
            data.Billboard.Adornee = targetAdornee
            data.Billboard.StudsOffset = (targetAdornee.Name == "Head")
                and Vector3.new(0, 1.8, 0) or Vector3.new(0, 3.2, 0)
        end
    end

    local isVisible = data.IsVisible
    if Config.VisibilityCheck then
        local now = os.clock()
        if now - data.LastVisCheck >= 0.25 then
            data.LastVisCheck = now
            local safeExclude = excludeTable[1] and excludeTable or {}
            data.IsVisible    = isTargetVisible(getCamera(), targetAdornee or rootPart, character, safeExclude)
            isVisible         = data.IsVisible
        end
    else
        isVisible = true
    end

    local currentColor = isVisible and Config.VisibleColor or Config.HiddenColor
    if State.ESP.TeamColor and player and player.Team and player.Team.TeamColor then
        currentColor = player.Team.TeamColor.Color
    end

    if data.Highlight.OutlineColor ~= currentColor then data.Highlight.OutlineColor = currentColor end
    if data.Highlight.FillColor    ~= currentColor then data.Highlight.FillColor    = currentColor end
    if data.Highlight.Enabled      ~= State.ESP.Glow then data.Highlight.Enabled    = State.ESP.Glow end

    local showName = State.ESP.Name and not (Config.NameEnemiesOnly and isAlly(character, player))
    local bbShow = showName or State.ESP.Distance or State.ESP.Tool
        or (State.ESP.HealthBar and not data.HpFill)
    if data.Billboard.Enabled     ~= bbShow            then data.Billboard.Enabled     = bbShow            end
    if data.NameLabel.Visible ~= showName then data.NameLabel.Visible = showName end
    if data.NameLabel.TextColor3  ~= currentColor        then data.NameLabel.TextColor3  = currentColor        end
    if data.DistanceLabel.Visible ~= State.ESP.Distance then data.DistanceLabel.Visible = State.ESP.Distance end

    local distText = math.floor(distance) .. "m"
    if data.DistanceLabel.Text ~= distText then data.DistanceLabel.Text = distText end

    updateHealthBar(data, humanoid)
    updateTool(data, character, os.clock())
    data.ShouldDraw = true
    data.DrawColor  = currentColor
end

-- ===========================
-- Character detection
-- ===========================
local function looksLikeCharacter(model)
    local humanoid
    if Config.DeepRigSearch then
        humanoid = model:FindFirstChildWhichIsA("Humanoid", true)
    else
        humanoid = model:FindFirstChildOfClass("Humanoid")
    end
    if not humanoid then return false, nil end

    local hasRoot = model:FindFirstChild("HumanoidRootPart")
        or model:FindFirstChild("Torso")
        or model:FindFirstChild("UpperTorso")
        or model:FindFirstChild("Head")
        or model.PrimaryPart

    return hasRoot ~= nil, humanoid
end

local _nonChar = setmetatable({}, { __mode = "k" })
local NON_CHAR_TTL = 6

local function checkModelCandidate(model)
    if State.Unloaded then return end
    if not (model and model:IsA("Model") and model.Parent) then return end
    if not LocalPlayer then return end
    if model == LocalPlayer.Character then return end
    if model.Name == LocalPlayer.Name then return end
    if State.TrackedCharacters[model] then return end

    local checkedAt = _nonChar[model]
    if checkedAt and (os.clock() - checkedAt) < NON_CHAR_TTL then return end

    local ok, humanoid = looksLikeCharacter(model)
    if not ok then _nonChar[model] = os.clock(); return end
    if humanoid.MaxHealth > 0 and humanoid.Health <= 0 then return end

    local player = Players:GetPlayerFromCharacter(model)
    if not player then
        player = Players:FindFirstChild(model.Name)
    end
    if not player then
        local dn = model:GetAttribute("DisplayName")
            or (model:FindFirstChild("DisplayName") and model.DisplayName.Value)
        if dn then
            for _, p in ipairs(Players:GetPlayers()) do
                if p.DisplayName == dn then player = p; break end
            end
        end
    end

    createVisualForCharacter(model, player)
end

local function scanContainerRecursive(container, depth)
    if State.Unloaded or not container or depth > Config.ScanDepth then return end
    local ok, children = pcall(function() return container:GetChildren() end)
    if not ok or not children then return end
    for _, item in ipairs(children) do
        if item:IsA("Model") then
            checkModelCandidate(item)
        elseif item:IsA("Folder") or item:IsA("Configuration") or item:IsA("WorldModel") then
            scanContainerRecursive(item, depth + 1)
        end
    end
end

local _watchedContainers = {}

local function watchContainer(container)
    if not container or _watchedContainers[container] then return end
    _watchedContainers[container] = true
    connect(container.ChildAdded, function(child)
        if State.Unloaded then return end
        if child:IsA("Model") then
            task.defer(function() checkModelCandidate(child) end)
        elseif child:IsA("Folder") or child:IsA("Configuration") or child:IsA("WorldModel") then
            watchContainer(child)
            task.defer(function() scanContainerRecursive(child, 1) end)
        end
    end)
end

local function nameMatchesContainerList(name)
    local lower = name:lower()
    for _, pattern in ipairs(Config.ExtraContainerNames) do
        if lower:find(pattern, 1, true) then return true end
    end
    return false
end

-- ===========================
-- setupPlayer (before use in scanScriptEnvironments)
-- ===========================
local function setupPlayer(player)
    if State.Unloaded then return end
    if player == LocalPlayer or State.TrackedPlayers[player] then return end
    State.TrackedPlayers[player] = true

    local function onCharacterAdded(character)
        if State.Unloaded or not character then return end
        task.spawn(function()
            if State.Unloaded then return end
            local humanoid = character:WaitForChild("Humanoid", 6)
                or character:FindFirstChildOfClass("Humanoid")
            if not humanoid or State.Unloaded then return end
            createVisualForCharacter(character, player)
        end)
    end

    connect(player.CharacterAdded, onCharacterAdded)
    connect(player.CharacterRemoving, function(char) cleanupESP(char) end)
    if player.Character then onCharacterAdded(player.Character) end
end

-- ===========================
-- Tier 1A: Nil Instance Scan
-- ===========================
local _nilObserved = setmetatable({}, { __mode = "k" })
local _lastNilScan = 0

local function scanNilInstances()
    if not Config.UseNilScan then return end
    if not getnilinstances then return end
    local ok, instances = pcall(getnilinstances)
    if not ok or not instances then return end

    local n = 0
    for _, inst in ipairs(instances) do
        n += 1
        if n % 300 == 0 then
            task.wait()
            if State.Unloaded or not Config.UseNilScan then return end
        end
        if inst and inst:IsA("Model") and inst.Parent == nil then
            if State.Unloaded then return end
            if _nilObserved[inst] then continue end
            if LocalPlayer and (inst == LocalPlayer.Character or inst.Name == LocalPlayer.Name) then continue end

            local hasHum, humanoid = looksLikeCharacter(inst)
            if not (hasHum and not (humanoid.MaxHealth > 0 and humanoid.Health <= 0)) then continue end

            local rootPart = inst:FindFirstChild("HumanoidRootPart")
                or inst:FindFirstChild("Torso") or inst:FindFirstChild("Head")
            if not rootPart then continue end

            _nilObserved[inst] = true
            local ancConn
            ancConn = connect(inst.AncestryChanged, function(_, newParent)
                if newParent then
                    if ancConn then pcall(function() ancConn:Disconnect() end); ancConn = nil end
                    _nilObserved[inst] = nil
                    if not State.TrackedCharacters[inst] then
                        task.defer(function() checkModelCandidate(inst) end)
                    end
                end
            end)
        end
    end
end

-- ===========================
-- Tier 1B: Full Memory Scan
-- ===========================
local _lastGetInstancesScan = 0

local function _getClass(i)  return i.ClassName end
local function _getParent(i) return i.Parent end

local function scanAllInstances()
    if not Config.UseGetInstances then return end
    if not getinstances then return end
    local ok, instances = pcall(getinstances)
    if not ok or not instances then return end

    local n = 0
    for _, inst in ipairs(instances) do
        n += 1
        if n % 400 == 0 then
            task.wait()  -- yield the frame, the scan continues in the background
            if State.Unloaded or not Config.UseGetInstances then return end
        end
        local okc, className = pcall(_getClass, inst)
        if okc and className == "Humanoid" then
            local okp, model = pcall(_getParent, inst)
            if okp and model and not State.TrackedCharacters[model] then
                task.defer(checkModelCandidate, model)
            end
        end
    end
end

-- ===========================
-- Tier 1C: hookmetamethod
-- ===========================
local _metaHookInstalled     = false
local _newIndexHookInstalled = false

local function installMetaHook()
    if not Config.UseMetaHook then return end
    if _metaHookInstalled then return end
    if not hookmetamethod then return end
    pcall(function()
        local original
        original = hookmetamethod(game, "__index", newcclosure(function(self, key)
            local result = original(self, key)
            if Config.UseMetaHook and not State.Unloaded and result and typeof(result) == "Instance" then
                local ok, isModel = pcall(function() return result:IsA("Model") end)
                if ok and isModel and not State.TrackedCharacters[result] then
                    task.defer(function() checkModelCandidate(result) end)
                end
            end
            return result
        end))
        _metaHookInstalled = true
    end)
end

local function installNewIndexHook()
    if not Config.UseMetaHook then return end
    if _newIndexHookInstalled then return end
    if not hookmetamethod then return end
    pcall(function()
        local originalNamecall
        originalNamecall = hookmetamethod(game, "__namecall", newcclosure(function(self, ...)
            local method = getnamecallmethod and getnamecallmethod() or ""
            local result = originalNamecall(self, ...)
            if Config.UseMetaHook and not State.Unloaded
                and (method == "GetChildren" or method == "GetDescendants")
                and typeof(self) == "Instance" then
                local ok, isDesc = pcall(function()
                    return self == Workspace or self:IsDescendantOf(Workspace)
                end)
                if ok and isDesc and type(result) == "table" then
                    for _, item in ipairs(result) do
                        if typeof(item) == "Instance"
                            and item:IsA("Model")
                            and not State.TrackedCharacters[item] then
                            task.defer(function() checkModelCandidate(item) end)
                        end
                    end
                end
            end
            return result
        end))
        _newIndexHookInstalled = true
    end)
end

-- ===========================
-- Tier 1D: Script Environment Scan
-- ===========================
local _lastScriptEnvScan = 0
local _scannedScripts    = {}

local function scanScriptEnvironments()
    if not Config.UseScriptEnvScan then return end
    _scannedScripts = {}

    local function tryScanEnv(env)
        if type(env) ~= "table" then return end
        for _, key in ipairs(Config.ScriptEnvKeys) do
            local val = env[key]
            if type(val) == "table" then
                for _, item in pairs(val) do
                    if typeof(item) == "Instance" then
                        if item:IsA("Model") then
                            task.defer(function() checkModelCandidate(item) end)
                        elseif item:IsA("Player") and item ~= LocalPlayer then
                            setupPlayer(item)
                        end
                    end
                end
            end
        end
    end

    if getrunningscripts then
        local ok, scripts = pcall(getrunningscripts)
        if ok and scripts then
            for _, script in ipairs(scripts) do
                if _scannedScripts[script] then continue end
                _scannedScripts[script] = true
                if getsenv then
                    local ok2, env = pcall(getsenv, script)
                    if ok2 and env then tryScanEnv(env) end
                end
                if getscriptclosure and debug and debug.getupvalues then
                    local ok3, closure = pcall(getscriptclosure, script)
                    if ok3 and closure then
                        local ok4, upvals = pcall(debug.getupvalues, closure)
                        if ok4 and upvals then
                            for _, uv in pairs(upvals) do
                                if type(uv) == "table" then tryScanEnv(uv) end
                            end
                        end
                    end
                end
            end
        end
    end

    if getloadedmodules then
        local ok, modules = pcall(getloadedmodules)
        if ok and modules then
            for _, mod in ipairs(modules) do
                if _scannedScripts[mod] then continue end
                _scannedScripts[mod] = true
                if getsenv then
                    local ok2, env = pcall(getsenv, mod)
                    if ok2 and env then tryScanEnv(env) end
                end
            end
        end
    end

    if getrenv then
        local ok, renv = pcall(getrenv)
        if ok and renv then tryScanEnv(renv) end
    end
end

-- ===========================
-- scanAll
-- ===========================
local function scanAll()
    if State.Unloaded then return end

    if Players then
        for _, player in ipairs(Players:GetPlayers()) do
            if player ~= LocalPlayer then
                if not State.TrackedPlayers[player] then setupPlayer(player) end
                local char = player.Character
                if char and char.Parent and not State.TrackedCharacters[char] then
                    checkModelCandidate(char)
                end
            end
        end
    end

    if not Workspace then return end

    local function scan(container, depth)
        if State.Unloaded or depth > Config.ScanDepth then return end
        local ok, children = pcall(container.GetChildren, container)
        if not ok then return end
        for _, child in ipairs(children) do
            if child:IsA("Model") then
                checkModelCandidate(child)
            elseif child:IsA("Folder") or child:IsA("Configuration") or child:IsA("WorldModel") then
                if nameMatchesContainerList(child.Name) then watchContainer(child) end
                scan(child, depth + 1)
            elseif Config.ScanTerrain and child:IsA("Terrain") then
                scan(child, depth + 1)
            end
        end
    end
    scan(Workspace, 1)
end

-- ===========================
-- Players + Workspace listeners initialization
-- ===========================
if LocalPlayer then
    pcall(function()
        connect(LocalPlayer:GetPropertyChangedSignal("Team"),      clearAllEnemyCache)
        connect(LocalPlayer:GetPropertyChangedSignal("TeamColor"), clearAllEnemyCache)
        connect(LocalPlayer.CharacterAdded,                        clearAllEnemyCache)
        connect(LocalPlayer.AttributeChanged, function(attr)
            for _, name in ipairs(Config.TeamAttributeNames) do
                if attr == name then clearAllEnemyCache(); break end
            end
        end)
    end)
end
if Players then
    for _, player in ipairs(Players:GetPlayers()) do setupPlayer(player) end
    connect(rawPlayers.PlayerAdded,    function(player) setupPlayer(player) end)
    connect(rawPlayers.PlayerRemoving, function(player)
        State.TrackedPlayers[player] = nil
        if player.Character then cleanupESP(player.Character) end
    end)
end

if Workspace then
    for _, obj in ipairs(Workspace:GetChildren()) do
        if (obj:IsA("Folder") or obj:IsA("Configuration") or obj:IsA("WorldModel"))
            and nameMatchesContainerList(obj.Name) then
            watchContainer(obj)
        end
    end
    connect(Workspace.ChildAdded, function(child)
        if State.Unloaded then return end
        if child:IsA("Model") then
            task.defer(function() checkModelCandidate(child) end)
        elseif child:IsA("Folder") or child:IsA("Configuration") or child:IsA("WorldModel") then
            if nameMatchesContainerList(child.Name) then
                watchContainer(child)
                task.defer(function() scanContainerRecursive(child, 1) end)
            else
                watchContainer(child)
            end
        end
    end)
end

task.defer(function()
    installMetaHook()
    installNewIndexHook()
end)

-- ===========================
-- Config GUI (F2) — Rayfield Gen2
-- ===========================
local function buildConfigGui()
    local okLib, Rayfield = pcall(function()
        return loadstring(game:HttpGet("https://sirius.menu/gen2"))()
    end)
    if State.Unloaded then return end
    if not okLib or not Rayfield then
        warn("[Universal ESP] Failed to load Rayfield Gen2: " .. tostring(Rayfield))
        return
    end

    local window = Rayfield:CreateWindow({
        name = "Universal ESP",
        subtitle = "Rayfield Gen2",
        sidebarLayout = true,
    })

    -- Widget refresh registry (after F1, after reset, after opening the menu)
    local refreshers = {}
    local function addRefresher(fn) refreshers[#refreshers + 1] = fn end
    local function refreshAll()
        for _, fn in ipairs(refreshers) do pcall(fn) end
    end

    local function notify(a, b, dur)
        local title, text = "Universal ESP", a
        if b then title, text = a, b end
        pcall(function()
            window:Notify({ title = title, content = text, duration = dur or 4 })
        end)
    end

    -- ===========================
    -- Element helpers (all with forgetState: the script does its own saving)
    -- ===========================
    local function divider(tab, text)
        tab:CreateDivider({ text = text })
    end

    -- Toggle bound to a table field (Config / State.ESP)
    local function bind(tab, text, tbl, key, onChange)
        local h = tab:CreateToggle({
            name = text,
            value = tbl[key] and true or false,
            forgetState = true,
            callback = function(v)
                tbl[key] = v
                if onChange then onChange(v) end
            end,
        })
        addRefresher(function() h:Set(tbl[key] and true or false, true) end)
        return h
    end

    local function slider(tab, text, minV, maxV, step, getter, setter, suffix)
        local h = tab:CreateSlider({
            name = text,
            range = { minV, maxV },
            increment = step,
            value = getter(),
            suffix = suffix,
            forgetState = true,
            callback = function(v) setter(v) end,
        })
        addRefresher(function() h:Set(getter(), true) end)
        return h
    end

    local function colorPicker(tab, text, cfgKey)
        local h = tab:CreateColorPicker({
            name = text,
            color = Config[cfgKey],
            forgetState = true,
            callback = function(c) Config[cfgKey] = c end,
        })
        addRefresher(function() h:Set(Config[cfgKey], true) end)
        return h
    end

    local function keybind(tab, text, cfgKey)
        local h = tab:CreateKeybind({
            name = text,
            value = Config[cfgKey],
            forgetState = true,
            callback = function() end,
            onChanged = function(key)
                if typeof(key) == "EnumItem" and key.EnumType == Enum.KeyCode then
                    Config[cfgKey] = key
                end
            end,
        })
        addRefresher(function() h:Set(Config[cfgKey], true) end)
        return h
    end

    local function button(tab, text, callback)
        return tab:CreateButton({
            name = text,
            callback = function()
                local ok, err = pcall(callback)
                if not ok then warn("[Universal ESP] Button error: " .. tostring(err)) end
            end,
        })
    end

    -- ===========================
    -- Logic helper functions
    -- ===========================
    local function updateHighlightTransparency()
        for _, d in pairs(State.TrackedCharacters) do
            if d and d.Highlight then d.Highlight.FillTransparency = State.ESP.Transparency end
        end
    end

    local function resetDefaults()
        State.ESP.Enabled = true; State.ESP.Glow = true; State.ESP.Name = true
        State.ESP.Distance = true; State.ESP.Range = 5000
        State.ESP.TeamColor = false; State.ESP.Transparency = 0.75
        State.ESP.HealthBar = true; State.ESP.Box = true; State.ESP.Tracers = false; State.ESP.Tool = false
        Config.TeamCheck = true; Config.IgnoreNeutral = true
        Config.NeutralIsEnemy = true; Config.AutoFFA = false; Config.NameEnemiesOnly = true
        Config.TeamSource = "Auto"; Config.CustomTeamKey = ""
        Config.ShowBots = true; Config.VisibilityCheck = true
        Config.UseEnemyCache = true; Config.EnemyCacheTTL = 1.5
        Config.ScanDepth = 4; Config.ScanInterval = 1.0
        Config.DeepRigSearch = false; Config.ScanTerrain = false
        Config.UseNilScan = false; Config.UseGetInstances = false
        Config.UseMetaHook = false; Config.UseScriptEnvScan = false
        Config.NilScanInterval = 5.0; Config.GetInstancesInterval = 10.0
        Config.ScriptEnvInterval = 15.0
        Config.VisibleColor = Color3.fromRGB(80, 225, 80)
        Config.HiddenColor  = Color3.fromRGB(235, 60, 60)
        Config.ToggleKey = Enum.KeyCode.F1
        Config.GuiKey    = Enum.KeyCode.F2
        Config.UnloadKey = Enum.KeyCode.End
        clearAllEnemyCache()
        _teamsCache = nil
        updateHighlightTransparency()
        saveConfig()
        refreshAll()
    end

    -- ===========================
    -- Tab: ESP
    -- ===========================
    local tESP = window:CreateTab({ name = "ESP", icon = 0 })
    divider(tESP, "Display")
    bind(tESP, "Enable ESP",            State.ESP, "Enabled")
    bind(tESP, "Highlight (Glow)", State.ESP, "Glow")
    bind(tESP, "Player name",         State.ESP, "Name")
    bind(tESP, "Distance",              State.ESP, "Distance")
    bind(tESP, "Held item",     State.ESP, "Tool")
    bind(tESP, "Health bar",        State.ESP, "HealthBar")
    bind(tESP, "Box ESP (Drawing)",    State.ESP, "Box")
    bind(tESP, "Tracers (Drawing)",    State.ESP, "Tracers")
    bind(tESP, "Team color",        State.ESP, "TeamColor")
    divider(tESP, "Parameters")
    slider(tESP, "Range", 100, 10000, 50,
        function() return State.ESP.Range end,
        function(v) State.ESP.Range = v end, " m")
    slider(tESP, "Fill transparency", 0, 100, 1,
        function() return math.floor(State.ESP.Transparency * 100 + 0.5) end,
        function(v) State.ESP.Transparency = v / 100; updateHighlightTransparency() end, "%")
    divider(tESP, "Colors")
    colorPicker(tESP, "Visible",  "VisibleColor")
    colorPicker(tESP, "Behind wall", "HiddenColor")

    -- ===========================
    -- Tab: Filters
    -- ===========================
    local tFilt = window:CreateTab({ name = "Filters", icon = 0 })
    divider(tFilt, "Teams")
    bind(tFilt, "Team check",      Config, "TeamCheck",       clearAllEnemyCache)
    bind(tFilt, "Ignore neutrals",  Config, "IgnoreNeutral",   clearAllEnemyCache)
    bind(tFilt, "Neutral = Enemy",       Config, "NeutralIsEnemy",  clearAllEnemyCache)
    bind(tFilt, "Auto-FFA (1 team)", Config, "AutoFFA",         clearAllEnemyCache)
    bind(tFilt, "Name enemies only",    Config, "NameEnemiesOnly", clearAllEnemyCache)
    divider(tFilt, "Targets")
    bind(tFilt, "Show bots / NPCs",     Config, "ShowBots")
    bind(tFilt, "Visibility check",   Config, "VisibilityCheck")

    -- ===========================
    -- Tab: Teams
    -- ===========================
    local tTeam = window:CreateTab({ name = "Teams", icon = 0 })
    divider(tTeam, "Team source")
    local ddSource = tTeam:CreateDropdown({
        name = "Detection source",
        options = TEAM_SOURCES,
        value = Config.TeamSource,
        forgetState = true,
        callback = function(sel)
            if type(sel) == "table" then sel = sel[1] end
            if type(sel) == "string" then
                Config.TeamSource = sel
                clearAllEnemyCache()
            end
        end,
    })
    addRefresher(function() ddSource:Set(Config.TeamSource, true) end)

    local inKey = tTeam:CreateInput({
        name = "Custom key (attribute/Value)",
        placeholder = "e.g. TeamId",
        value = Config.CustomTeamKey,
        forgetState = true,
        callback = function(text)
            Config.CustomTeamKey = (tostring(text or "")):match("^%s*(.-)%s*$")
            clearAllEnemyCache()
        end,
    })
    addRefresher(function() inKey:Set(Config.CustomTeamKey, true) end)

    divider(tTeam, "Tools")
    button(tTeam, "Show detected team system", function()
        local teamsList = getCachedTeams()
        local myId = getMyTeamId()
        local line
        if #teamsList > 0 then
            line = "Roblox Teams: " .. #teamsList .. " | Me: " .. tostring(myId or "?")
        elseif myId then
            line = "Custom system | Me: " .. tostring(myId)
        else
            line = "FFA / no teams"
        end
        local ffa = Config.AutoFFA and isSingleTeamServer()
        notify("Team system", line .. " | Auto-FFA: " .. (ffa and "yes" or "no"), 6)
    end)
    button(tTeam, "Refresh teams", function()
        _teamsCache = nil
        clearAllEnemyCache()
        notify("Teams cache", "Team info refreshed.")
    end)
    button(tTeam, "Diagnostics (output in the F9 console)", function()
        clearAllEnemyCache()
        local function folderName(ch) return (ch and ch.Parent and ch.Parent.Name) or "-" end
        print("[Universal ESP] ===== Team diagnostics =====")
        print(string.format("Source: %s | custom key: '%s' | Auto-FFA active: %s",
            tostring(Config.TeamSource), tostring(Config.CustomTeamKey),
            tostring(Config.AutoFFA and isSingleTeamServer())))
        if LocalPlayer then
            print(string.format("ME %s | id: %s | folder: %s",
                LocalPlayer.Name, tostring(getMyTeamId()), folderName(LocalPlayer.Character)))
            print("  player:    " .. describeTeamData(LocalPlayer))
            print("  character: " .. describeTeamData(LocalPlayer.Character))
        end
        for _, p in ipairs(Players:GetPlayers()) do
            if p ~= LocalPlayer then
                local ch = p.Character
                print(string.format("%s | id: %s | enemy: %s | ally: %s | folder: %s",
                    p.Name, tostring(getTeamId(p, ch)), tostring(ch and isEnemy(ch, p)),
                    tostring(ch and isAlly(ch, p)), folderName(ch)))
                print("  player:    " .. describeTeamData(p))
                print("  character: " .. describeTeamData(ch))
            end
        end
        notify("Diagnostics", "Output printed to the console (F9).")
    end)
    divider(tTeam, "Cache")
    bind(tTeam, "Teams cache (faster)", Config, "UseEnemyCache", clearAllEnemyCache)
    slider(tTeam, "Cache TTL", 1, 10, 1,
        function() return math.floor(Config.EnemyCacheTTL) end,
        function(v) Config.EnemyCacheTTL = v; clearAllEnemyCache() end, " s")

    -- ===========================
    -- Tab: Scan
    -- ===========================
    local tScan = window:CreateTab({ name = "Scan", icon = 0 })
    divider(tScan, "Character detection")
    bind(tScan, "Deep rig search", Config, "DeepRigSearch")
    bind(tScan, "Scan Terrain",     Config, "ScanTerrain")
    slider(tScan, "Scan depth", 1, 6, 1,
        function() return Config.ScanDepth end,
        function(v) Config.ScanDepth = v end)
    slider(tScan, "Scan interval", 100, 3000, 100,
        function() return math.floor(Config.ScanInterval * 1000 + 0.5) end,
        function(v) Config.ScanInterval = v / 1000 end, " ms")

    -- ===========================
    -- Tab: Advanced
    -- ===========================
    local tAdv = window:CreateTab({ name = "Advanced", icon = 0 })
    divider(tAdv, "Methods (heavy – may lower FPS)")
    bind(tAdv, "Nil Instance Scan", Config, "UseNilScan")
    bind(tAdv, "Full Memory Scan",  Config, "UseGetInstances")
    bind(tAdv, "Meta Hook", Config, "UseMetaHook", function(v)
        if v then installMetaHook(); installNewIndexHook() end
    end)
    bind(tAdv, "Script Env Scan",   Config, "UseScriptEnvScan")
    divider(tAdv, "Intervals")
    slider(tAdv, "Nil Scan every", 2, 30, 1,
        function() return math.floor(Config.NilScanInterval) end,
        function(v) Config.NilScanInterval = v end, " s")
    slider(tAdv, "Memory Scan every", 5, 60, 1,
        function() return math.floor(Config.GetInstancesInterval) end,
        function(v) Config.GetInstancesInterval = v end, " s")
    slider(tAdv, "Script Scan every", 5, 60, 1,
        function() return math.floor(Config.ScriptEnvInterval) end,
        function(v) Config.ScriptEnvInterval = v end, " s")

    -- ===========================
    -- Tab: Settings
    -- ===========================
    local tSet = window:CreateTab({ name = "Settings", icon = 0 })
    divider(tSet, "Hotkeys")
    keybind(tSet, "Toggle ESP",    "ToggleKey")
    keybind(tSet, "Open / close menu", "GuiKey")
    keybind(tSet, "Unload script",        "UnloadKey")
    divider(tSet, "Interface")
    bind(tSet, "Watermark (FPS / Ping)", State.Watermark, "Enabled")
    button(tSet, "Show ESP status", function()
        local tracked, shown = 0, 0
        for _, d in pairs(State.TrackedCharacters) do
            if d then
                tracked += 1
                if (d.Billboard and d.Billboard.Enabled) or (d.Highlight and d.Highlight.Enabled) then
                    shown += 1
                end
            end
        end
        notify("Status", string.format("Tracked: %d | visible: %d | ESP %s",
            tracked, shown, State.ESP.Enabled and "ON" or "OFF"))
    end)
    divider(tSet, "Config")
    bind(tSet, "Auto-save on unload", Config, "SaveEnabled")
    button(tSet, "Save now", function()
        saveConfig()
        notify("Config", "Settings saved.")
    end)
    button(tSet, "Reset to defaults", function()
        resetDefaults()
        notify("Config", "Defaults restored.")
    end)
    button(tSet, "Unload script", function()
        unload()
    end)

    -- ===========================
    -- Hooking into the rest of the script
    -- ===========================
    _configGui = { Destroy = function() pcall(function() window:Unload() end) end }
    _guiRefreshAll = refreshAll
    _guiToggle = function()
        pcall(function() window:ToggleHide() end)
        refreshAll()
    end

    if State.Unloaded then
        pcall(function() window:Unload() end)
        return
    end

    notify("Universal ESP", Config.GuiKey.Name .. " – menu  |  " .. Config.ToggleKey.Name
        .. " – ESP  |  " .. Config.UnloadKey.Name .. " – unload", 5)
end

task.spawn(function()
    local ok, err = pcall(buildConfigGui)
    if not ok then warn("[Universal ESP] GUI build error: " .. tostring(err)) end
end)

-- ===========================
-- Main Heartbeat loop
-- ===========================
local lastWatermarkUpdate = 0
local lastEntityScan      = 0
local excludeCache        = {}

local updateConnection = RunService.Heartbeat:Connect(cwrap(function(dt)
    if State.Unloaded then return end

    local ok, err = pcall(function()
        local now = os.clock()

        if now - lastEntityScan >= Config.ScanInterval then
            lastEntityScan = now
            scanAll()
        end

        if Config.UseNilScan and (now - _lastNilScan) >= Config.NilScanInterval then
            _lastNilScan = now
            task.spawn(scanNilInstances)
        end

        if Config.UseGetInstances and (now - _lastGetInstancesScan) >= Config.GetInstancesInterval then
            _lastGetInstancesScan = now
            task.spawn(scanAllInstances)
        end

        if Config.UseScriptEnvScan and (now - _lastScriptEnvScan) >= Config.ScriptEnvInterval then
            _lastScriptEnvScan = now
            task.spawn(scanScriptEnvironments)
        end

        local lpChar = LocalPlayer and LocalPlayer.Character
        local lpHum  = lpChar and lpChar:FindFirstChildOfClass("Humanoid")

        if lpHum and lpHum.MaxHealth > 0 and lpHum.Health <= 0 then
            for _, data in pairs(State.TrackedCharacters) do
                if data and data ~= false then
                    data.ShouldDraw = false
                    hideDrawings(data)
                    if data.Highlight and data.Highlight.Enabled then data.Highlight.Enabled = false end
                    if data.Billboard and data.Billboard.Enabled  then data.Billboard.Enabled  = false end
                end
            end
            return
        end

        local lpRoot = lpChar and lpChar:FindFirstChild("HumanoidRootPart")
        if lpChar then
            excludeCache[1] = lpChar
        else
            table.clear(excludeCache)
        end

        table.clear(_toCleanup)
        for character, data in pairs(State.TrackedCharacters) do
            if data == false then continue end
            if character and character.Parent then
                updateVisual(character, data, lpChar, lpRoot, excludeCache)
            else
                _toCleanup[#_toCleanup + 1] = character
            end
        end
        for i = 1, #_toCleanup do cleanupESP(_toCleanup[i]) end

        -- Watermark
        if State.Watermark.Enabled and (watermarkDraw or watermarkLabel) then
            if now - lastWatermarkUpdate >= 0.15 then
                lastWatermarkUpdate = now
                local fps  = math.floor(1 / math.max(dt or 0.016, 0.0001))
                local ping = 0
                if Stats and Stats.Network and Stats.Network.ServerStatsItem then
                    pcall(function()
                        local val = Stats.Network.ServerStatsItem["Data Ping"]:GetValue()
                        if type(val) == "number" then
                            ping = math.floor(val)
                        end
                    end)
                end
                local text = string.format("Universal ESP | FPS: %d | Ping: %dms", fps, ping)
                if watermarkDraw then
                    if setrenderproperty then
                        pcall(setrenderproperty, watermarkDraw, "Text",    text)
                        pcall(setrenderproperty, watermarkDraw, "Visible", true)
                    else
                        watermarkDraw.Text = text; watermarkDraw.Visible = true
                    end
                elseif watermarkLabel then
                    watermarkLabel.Text = text; watermarkLabel.Visible = true
                end
            end
        else
            if watermarkDraw then
                if setrenderproperty then pcall(setrenderproperty, watermarkDraw, "Visible", false)
                else watermarkDraw.Visible = false end
            end
            if watermarkLabel then watermarkLabel.Visible = false end
        end
    end)

    if not ok then
        warn("[Universal ESP] Heartbeat loop error: " .. tostring(err))
    end
end))
table.insert(State.Connections, updateConnection)

if HAS_DRAW then
    local renderConnection = RunService.RenderStepped:Connect(cwrap(function()
        if State.Unloaded then return end
        for character, data in pairs(State.TrackedCharacters) do
            if data and data ~= false then
                if data.ShouldDraw and character and character.Parent then
                    updateDrawings(data, data.RootPart, data.DrawColor, data.Humanoid)
                else
                    hideDrawings(data)
                end
            end
        end
    end))
    table.insert(State.Connections, renderConnection)
end

-- ===========================
-- Input
-- ===========================
connect(UserInputService.InputBegan, function(input, processed)
    if processed then return end
    if input.KeyCode == Config.ToggleKey then
        State.ESP.Enabled = not State.ESP.Enabled
        print("[Universal ESP] ESP: " .. (State.ESP.Enabled and "Enabled" or "Disabled"))
        if _guiRefreshAll then _guiRefreshAll() end
    elseif input.KeyCode == Config.GuiKey then
        if _guiToggle then _guiToggle() end
    elseif input.KeyCode == Config.UnloadKey then
        unload()
    end
end)

print("[Universal ESP] Loaded! [F1] Toggle | [F2] Config | [END] Unload")
print("[Universal ESP] Detection methods: Workspace | NilScan | MemoryScan | MetaHook | ScriptEnv")
print("[Universal ESP] Config: " .. Config.SaveFolder .. "/" .. Config.SaveFile)
