-- ============================================================
-- aim better.lua  –  Universal Aimbot
-- Loaded by main.lua via: loadstring(readfile("aim better.lua"))()
-- Reads config from: getgenv().ScoutCheat.Config.Aimbot
-- ============================================================

local Workspace        = game:GetService("Workspace")
local RunService       = game:GetService("RunService")
local Players          = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local lplayer = Players.LocalPlayer
while not lplayer do task.wait(); lplayer = Players.LocalPlayer end

-- ── Config reference (set up by main.lua before this file loads) ─────────────
local genv = (getgenv and getgenv()) or _G
genv.ScoutCheat = genv.ScoutCheat or {}
genv.ScoutCheat.Config = genv.ScoutCheat.Config or {}
genv.ScoutCheat.Config.Aimbot = genv.ScoutCheat.Config.Aimbot or {}
genv.ScoutCheat._connections  = genv.ScoutCheat._connections  or {}
genv.ScoutCheat._drawings     = genv.ScoutCheat._drawings     or {}

local Aim = genv.ScoutCheat.Config.Aimbot

-- Apply missing defaults so the script also runs standalone
local DEFAULTS = {
    Enabled           = true,
    AimKey            = Enum.UserInputType.MouseButton2,
    AlwaysOn          = false,
    ShowAimButton     = nil,
    AimPart           = "Head",
    ClosestBone       = false,
    TeamCheck         = true,
    VisibleCheck      = false,
    FOV_Enabled       = true,
    FOV_Radius        = 150,
    FOV_Color         = Color3.fromRGB(44, 102, 138),
    FOV_Thickness     = 1,
    FOV_Transparency  = 0.8,
    Deadzone          = 2,
    Smoothness        = 0.15,
    SmoothnessVariance = false,
    CurveSmoothing    = false,
    Randomization     = false,
    RandomIntensity   = 0.3,
    CurveAiming       = false,
    CurveStrength     = 0.5,
    Acceleration      = 0.2,
    Braking           = 0.3,
    MicroTremor       = false,
    TremorIntensity   = 1,
}
for k, v in pairs(DEFAULTS) do
    if Aim[k] == nil then Aim[k] = v end
end

-- ── Prevent double-loading ───────────────────────────────────────────────────
if genv.ScoutCheat.UnloadAimbot then
    pcall(genv.ScoutCheat.UnloadAimbot)
end

local myConnections = {}
local function reg(c)
    table.insert(genv.ScoutCheat._connections, c)
    table.insert(myConnections, c)
    return c
end

-- ── State ─────────────────────────────────────────────────────────────────────
local aiming          = false
local touchAiming     = false
local wasHeld         = false
local randomOffset    = Vector3.zero
local lastOffsetChange = 0
local currentTarget   = nil
local curveSign       = 1
local boneCache       = {}   -- [character] = { parts... }

local touchOnly = UserInputService.TouchEnabled
    and not UserInputService.KeyboardEnabled
    and not UserInputService.MouseEnabled

-- ── Helpers ───────────────────────────────────────────────────────────────────
local function randomVec(intensity)
    return Vector3.new(
        (math.random() - 0.5) * intensity,
        (math.random() - 0.5) * intensity,
        (math.random() - 0.5) * intensity
    )
end

-- ── GUI Parent ────────────────────────────────────────────────────────────────
local CoreGui = game:GetService("CoreGui")
local function getGuiParent()
    if gethui then
        local ok, hui = pcall(gethui)
        if ok and hui then return hui end
    end
    local ok = pcall(function()
        local p = Instance.new("Folder"); p.Parent = CoreGui; p:Destroy()
    end)
    if ok then return CoreGui end
    return lplayer:WaitForChild("PlayerGui")
end

local gui
local function getGui()
    if gui and gui.Parent then return gui end
    gui = Instance.new("ScreenGui")
    gui.Name           = "ScoutAimbotUI"
    gui.ResetOnSpawn   = false
    gui.IgnoreGuiInset = true
    gui.DisplayOrder   = 999
    gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    gui.Parent         = getGuiParent()
    return gui
end

-- ── FOV Circle ────────────────────────────────────────────────────────────────
-- Try Drawing API first; fall back to a GUI Frame circle.
local drawingCircle
do
    local hasDrawing = (type(Drawing) == "table" or typeof(Drawing) == "userdata")
        and rawget and rawget(Drawing, "new") ~= nil
    if not hasDrawing then
        -- Some executors expose Drawing directly
        hasDrawing = Drawing ~= nil and type(Drawing.new) == "function"
    end
    if hasDrawing then
        local ok, obj = pcall(Drawing.new, "Circle")
        if ok and obj then
            drawingCircle = obj
            drawingCircle.Filled = false
            table.insert(genv.ScoutCheat._drawings, drawingCircle)
        end
    end
end

local circleFrame, circleStroke
if not drawingCircle then
    circleFrame = Instance.new("Frame")
    circleFrame.Name                   = "FOVCircle"
    circleFrame.AnchorPoint            = Vector2.new(0.5, 0.5)
    circleFrame.BackgroundTransparency = 1
    circleFrame.BorderSizePixel        = 0
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(1, 0)
    corner.Parent       = circleFrame
    circleStroke = Instance.new("UIStroke")
    circleStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    circleStroke.Parent          = circleFrame
    circleFrame.Parent = getGui()
end

local function updateCircle(pos)
    local radius = Aim.FOV_Radius
    if drawingCircle then
        drawingCircle.Position    = pos
        drawingCircle.Radius      = radius
        drawingCircle.Color       = Aim.FOV_Color
        drawingCircle.Thickness   = Aim.FOV_Thickness
        drawingCircle.Transparency = Aim.FOV_Transparency
        drawingCircle.Visible     = Aim.FOV_Enabled
    elseif circleFrame then
        circleFrame.Position      = UDim2.fromOffset(pos.X, pos.Y)
        circleFrame.Size          = UDim2.fromOffset(radius * 2, radius * 2)
        circleStroke.Color        = Aim.FOV_Color
        circleStroke.Thickness    = Aim.FOV_Thickness
        circleStroke.Transparency = 1 - Aim.FOV_Transparency
        circleFrame.Visible       = Aim.FOV_Enabled
    end
end

-- ── Mobile AIM button ─────────────────────────────────────────────────────────
local showButton = Aim.ShowAimButton
if showButton == nil then showButton = touchOnly end

if showButton then
    local button = Instance.new("TextButton")
    button.Name                   = "AimButton"
    button.Size                   = UDim2.fromOffset(72, 72)
    button.Position               = UDim2.new(0.78, 0, 0.5, 0)
    button.BackgroundColor3       = Color3.fromRGB(20, 20, 20)
    button.BackgroundTransparency = 0.35
    button.AutoButtonColor        = false
    button.Text                   = "AIM"
    button.TextColor3             = Color3.fromRGB(255, 255, 255)
    button.TextSize               = 18
    button.Font                   = Enum.Font.GothamBold
    button.Active                 = true
    local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(1,0); c.Parent = button
    local s = Instance.new("UIStroke"); s.Color = Color3.fromRGB(255,255,255); s.Transparency = 0.5; s.Thickness = 2; s.Parent = button

    local function isPress(i)
        return i.UserInputType == Enum.UserInputType.Touch
            or i.UserInputType == Enum.UserInputType.MouseButton1
    end
    reg(button.InputBegan:Connect(function(i)
        if isPress(i) then touchAiming = true;  button.BackgroundTransparency = 0.1  end
    end))
    reg(button.InputEnded:Connect(function(i)
        if isPress(i) then touchAiming = false; button.BackgroundTransparency = 0.35 end
    end))
    button.Parent = getGui()
end

-- ── Visibility Raycast ────────────────────────────────────────────────────────
-- One shared RaycastParams (no GC per-frame).
local rayParams = RaycastParams.new()
rayParams.FilterType  = Enum.RaycastFilterType.Exclude
rayParams.IgnoreWater = true
pcall(function() rayParams.RespectCanCollide = true end)

local function isVisible(cam, character, part)
    local origin = cam.CFrame.Position
    local result = Workspace:Raycast(origin, part.Position - origin, rayParams)
    return result == nil
        or (result.Instance ~= nil and result.Instance:IsDescendantOf(character))
end

-- ── Aim Point (mouse / screen-centre) ────────────────────────────────────────
local function getAimPoint(cam)
    if touchOnly or UserInputService.MouseBehavior == Enum.MouseBehavior.LockCenter then
        return cam.ViewportSize / 2
    end
    return UserInputService:GetMouseLocation()
end

-- ── Rig-aware bone list (cached, invalidated on character change) ─────────────
local PREFERRED = {
    "Head", "UpperTorso", "LowerTorso",
    "RightUpperArm","LeftUpperArm","RightUpperLeg","LeftUpperLeg",
    "RightLowerArm","LeftLowerArm","RightLowerLeg","LeftLowerLeg",
    "RightHand","LeftHand","RightFoot","LeftFoot",
    "Torso","Right Arm","Left Arm","Right Leg","Left Leg",
    "HumanoidRootPart",
}

local function getBones(character)
    if boneCache[character] then return boneCache[character] end
    local bones, seen = {}, {}
    for _, name in ipairs(PREFERRED) do
        local p = character:FindFirstChild(name)
        if p and p:IsA("BasePart") and not seen[p] then
            seen[p] = true; table.insert(bones, p)
        end
    end
    for _, d in ipairs(character:GetDescendants()) do
        if d:IsA("BasePart") and not seen[d] then
            seen[d] = true; table.insert(bones, d)
        end
    end
    boneCache[character] = bones
    -- Invalidate when rig changes (respawn / morph)
    character.DescendantAdded:Connect(   function() boneCache[character] = nil end)
    character.DescendantRemoving:Connect(function() boneCache[character] = nil end)
    return bones
end

-- ── Target selection ──────────────────────────────────────────────────────────
local bestPlayer, bestPart, bestDist

local function consider(cam, point, plr, character, part)
    if not part or not part.Parent then return end
    local pos, onScreen = cam:WorldToViewportPoint(part.Position)
    if not onScreen then return end
    local d = (Vector2.new(pos.X, pos.Y) - point).Magnitude
    if d >= bestDist then return end
    if Aim.VisibleCheck and not isVisible(cam, character, part) then return end
    bestPlayer, bestPart, bestDist = plr, part, d
end

local function getTarget(cam, point)
    bestPlayer, bestPart, bestDist = nil, nil, Aim.FOV_Radius
    local myTeam = lplayer.Team

    for _, plr in ipairs(Players:GetPlayers()) do
        if plr == lplayer then continue end
        local character = plr.Character
        if not character then continue end
        local humanoid = character:FindFirstChildOfClass("Humanoid")
        if not humanoid or humanoid.Health <= 0 then continue end
        if Aim.TeamCheck and myTeam ~= nil and plr.Team == myTeam then continue end

        if Aim.ClosestBone then
            for _, bone in ipairs(getBones(character)) do
                consider(cam, point, plr, character, bone)
            end
        else
            local part = character:FindFirstChild(Aim.AimPart)
                      or character:FindFirstChild("HumanoidRootPart")
                      or character:FindFirstChildWhichIsA("BasePart")
            consider(cam, point, plr, character, part)
        end
    end

    return bestPlayer, bestDist, bestPart
end

-- ── Key/button held – polled every frame (avoids InputBegan sink issue) ───────
local function keyHeld()
    if UserInputService:GetFocusedTextBox() then return false end
    local key = Aim.AimKey
    if typeof(key) ~= "EnumItem" then return false end
    if key.EnumType == Enum.KeyCode then
        return UserInputService:IsKeyDown(key)
    elseif key == Enum.UserInputType.MouseButton1
        or key == Enum.UserInputType.MouseButton2
        or key == Enum.UserInputType.MouseButton3 then
        return UserInputService:IsMouseButtonPressed(key)
    end
    return false
end

-- ── Main render step ──────────────────────────────────────────────────────────
local function step(dt)
    local cam = Workspace.CurrentCamera
    if not cam then return end

    local point = getAimPoint(cam)
    updateCircle(point)

    local held = Aim.AlwaysOn or touchAiming or keyHeld()
    if held and not wasHeld and Aim.Randomization then
        randomOffset = randomVec(Aim.RandomIntensity)
    end
    wasHeld = held
    aiming  = held

    if not (Aim.Enabled and aiming) then
        currentTarget = nil
        return
    end

    -- Refresh exclusion filter once per frame
    local filter = { cam }
    if lplayer.Character then filter[2] = lplayer.Character end
    rayParams.FilterDescendantsInstances = filter

    local target, distToPoint, part = getTarget(cam, point)
    if not (target and part) then currentTarget = nil; return end

    if target ~= currentTarget then
        currentTarget = target
        curveSign = math.random() > 0.5 and 1 or -1
    end

    if distToPoint <= Aim.Deadzone then return end

    local camPos = cam.CFrame.Position
    local tPos   = part.Position

    -- Randomization
    if Aim.Randomization then
        local now = tick()
        if now - lastOffsetChange > 0.2 then
            randomOffset     = randomOffset:Lerp(randomVec(Aim.RandomIntensity), 0.1)
            lastOffsetChange = now
        end
        tPos += randomOffset
    end

    -- Curve aiming
    if Aim.CurveAiming then
        local toTarget = tPos - camPos
        local rightVec = toTarget:Cross(Vector3.yAxis)
        rightVec = (rightVec.Magnitude > 0) and rightVec.Unit or cam.CFrame.RightVector
        local scale = (distToPoint / Aim.FOV_Radius) * (toTarget.Magnitude * 0.1 * Aim.CurveStrength)
        tPos += rightVec * curveSign * scale
    end

    -- Smoothness
    local smoothness = Aim.Smoothness

    if Aim.Acceleration > 0 or Aim.Braking > 0 then
        local toTarget = tPos - camPos
        if toTarget.Magnitude > 0 then
            local angle = math.deg(math.acos(
                math.clamp(cam.CFrame.LookVector:Dot(toTarget.Unit), -1, 1)
            ))
            smoothness *= math.clamp(angle / (Aim.FOV_Radius * 0.5), Aim.Braking * 0.1, 1)
        end
    end

    if Aim.CurveSmoothing then
        smoothness *= math.clamp(distToPoint / Aim.FOV_Radius, 0.15, 1)
    end

    if Aim.SmoothnessVariance then
        smoothness += (math.random() - 0.5) * (smoothness * 0.2)
    end

    -- Micro-tremor
    if Aim.MicroTremor then
        tPos += randomVec(0.05 * Aim.TremorIntensity)
    end

    -- Frame-rate independent lerp (same feel at 30 / 60 / 240 FPS)
    local base  = math.clamp(smoothness, 0.005, 1)
    local alpha = 1 - (1 - base) ^ (math.min(dt, 0.1) * 60)

    cam.CFrame = cam.CFrame:Lerp(CFrame.new(camPos, tPos), alpha)
end

-- Bind at the very end of the render queue so game camera code runs first
local RENDER_NAME = "ScoutAimbot"
pcall(function() RunService:UnbindFromRenderStep(RENDER_NAME) end)

local warned = false
RunService:BindToRenderStep(RENDER_NAME, Enum.RenderPriority.Last.Value + 1, function(dt)
    local ok, err = pcall(step, dt)
    if not ok and not warned then
        warned = true
        warn("[Aimbot] " .. tostring(err))
    end
end)

-- ── Unload ────────────────────────────────────────────────────────────────────
genv.ScoutCheat.UnloadAimbot = function()
    aiming = false; touchAiming = false; currentTarget = nil
    pcall(function() RunService:UnbindFromRenderStep(RENDER_NAME) end)
    for _, c in ipairs(myConnections) do pcall(function() c:Disconnect() end) end
    table.clear(myConnections)
    table.clear(boneCache)
    if drawingCircle then pcall(function() drawingCircle:Remove() end) end
    if circleFrame   then pcall(function() circleFrame:Destroy()  end) end
    if gui           then pcall(function() gui:Destroy()          end) end
    genv.ScoutCheat.UnloadAimbot = nil
end
