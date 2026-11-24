if getgenv then
    local prev = getgenv().VisualsWorld_Instance
    if prev and type(prev.Unload) == "function" then
        pcall(prev.Unload)
    end
end

local okLib, Rayfield = pcall(function()
    return loadstring(game:HttpGet("https://sirius.menu/gen2"))()
end)
if not okLib or not Rayfield then
    warn("[Visuals / World] Failed to load Rayfield Gen2: " .. tostring(Rayfield))
    return
end

local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")

local function getCamera()
    return Workspace.CurrentCamera
end

local localPlayer = Players.LocalPlayer
local initCam = getCamera()

-- remember the original settings
local original = {
    Brightness = Lighting.Brightness,
    Ambient = Lighting.Ambient,
    OutdoorAmbient = Lighting.OutdoorAmbient,
    ExposureCompensation = Lighting.ExposureCompensation,
    FogEnd = Lighting.FogEnd,
    FogStart = Lighting.FogStart,
    FogColor = Lighting.FogColor,
    ClockTime = Lighting.ClockTime,
    GlobalShadows = Lighting.GlobalShadows,
    FieldOfView = initCam and initCam.FieldOfView or 70,
    MaxZoom = localPlayer.CameraMaxZoomDistance,
    MinZoom = localPlayer.CameraMinZoomDistance,
}

-- current values chosen in the GUI
local value = {
    Brightness = 2,
    Ambient = Color3.fromRGB(255, 255, 255),
    Exposure = 0,
    FogColor = Color3.fromRGB(190, 190, 200),
    FOV = 90,
    Time = 14,
    MaxZoom = 500,
}
local ambientOn = false

----------------------------------------------------------------
-- HELPERS
----------------------------------------------------------------

-- loop that keeps a setting applied (some games overwrite it)
local connections = {}

local function bind(name, enabled, onTick, onRestore)
    if connections[name] then
        connections[name]:Disconnect()
        connections[name] = nil
    end

    if enabled then
        connections[name] = RunService.RenderStepped:Connect(onTick)
    else
        onRestore()
    end
end

-- applies a change to every matching instance under some roots (also to ones
-- added later) and remembers the original values so they can be restored
local function makeEffect(getRoots, matches, apply, restore)
    local saved = {}
    local conns = {}
    local token = 0

    local function handle(inst)
        if saved[inst] ~= nil then return end
        local okM, hit = pcall(matches, inst)
        if not (okM and hit) then return end
        local okA, orig = pcall(apply, inst)
        if okA then saved[inst] = (orig == nil) and true or orig end
    end

    return function(enabled)
        token += 1
        local my = token
        for _, c in ipairs(conns) do c:Disconnect() end
        table.clear(conns)

        if enabled then
            for _, root in ipairs(getRoots()) do
                conns[#conns + 1] = root.DescendantAdded:Connect(handle)
                task.spawn(function()
                    local n = 0
                    for _, inst in ipairs(root:GetDescendants()) do
                        if token ~= my then return end
                        handle(inst)
                        n += 1
                        if n % 300 == 0 then task.wait() end -- don't freeze the game
                    end
                end)
            end
        else
            for inst, orig in pairs(saved) do
                pcall(restore, inst, orig)
                saved[inst] = nil
            end
        end
    end
end

-- GUI window (declared before unload() so that function can see it)
local window

-- every toggle is stored here so "Disable all" and unload can switch them off
local toggles = {}

local function toggle(tab, name, description, callback)
    local h = tab:CreateToggle({
        name = name,
        description = description,
        value = false,
        forgetState = true,
        callback = callback,
    })
    toggles[#toggles + 1] = h
    return h
end

local function slider(tab, name, min, max, step, start, suffix, callback)
    return tab:CreateSlider({
        name = name,
        range = { min, max },
        increment = step,
        value = start,
        suffix = suffix,
        forgetState = true,
        callback = callback,
    })
end

local function colorPicker(tab, name, start, callback)
    return tab:CreateColorPicker({
        name = name,
        color = start,
        forgetState = true,
        callback = function(c) callback(c) end,
    })
end

local function terrain()
    return Workspace:FindFirstChildOfClass("Terrain")
end

local function disableAll()
    for _, h in ipairs(toggles) do
        pcall(function() h:Set(false) end)
    end
end

-- unloader: switches everything off, restores settings, closes the GUI
local unloaded = false

local function unload()
    if unloaded then return end
    unloaded = true

    pcall(disableAll)

    for name, conn in pairs(connections) do
        conn:Disconnect()
        connections[name] = nil
    end

    pcall(function()
        Lighting.Brightness = original.Brightness
        Lighting.Ambient = original.Ambient
        Lighting.OutdoorAmbient = original.OutdoorAmbient
        Lighting.ExposureCompensation = original.ExposureCompensation
        Lighting.FogEnd = original.FogEnd
        Lighting.FogStart = original.FogStart
        Lighting.FogColor = original.FogColor
        Lighting.ClockTime = original.ClockTime
        Lighting.GlobalShadows = original.GlobalShadows
        local cam = getCamera()
        if cam then cam.FieldOfView = original.FieldOfView end
        localPlayer.CameraMaxZoomDistance = original.MaxZoom
        localPlayer.CameraMinZoomDistance = original.MinZoom
    end)

    if getgenv and getgenv().VisualsWorld_Instance then
        getgenv().VisualsWorld_Instance = nil
    end

    -- close the GUI (method from the Gen2 docs)
    pcall(function() window:Unload() end)
end

if getgenv then
    getgenv().VisualsWorld_Instance = { Unload = unload }
end

window = Rayfield:CreateWindow({
    name = "Visuals / World",
    subtitle = "Rayfield Gen2",
    sidebarLayout = true,
})

----------------------------------------------------------------
-- VISUALS
----------------------------------------------------------------
local visuals = window:CreateTab({ name = "Visuals", icon = 93364949241311 })

visuals:CreateDivider({ text = "Lighting" })

toggle(visuals, "Fullbright", "Bright lighting everywhere, no dark areas.", function(on)
    bind("fullbright", on, function()
        Lighting.Brightness = value.Brightness
        local c = ambientOn and value.Ambient or Color3.new(1, 1, 1)
        Lighting.Ambient = c
        Lighting.OutdoorAmbient = c
    end, function()
        Lighting.Brightness = original.Brightness
        Lighting.Ambient = original.Ambient
        Lighting.OutdoorAmbient = original.OutdoorAmbient
    end)
end)

slider(visuals, "Brightness", 0, 5, 0.1, 2, nil, function(v)
    value.Brightness = v
end)

toggle(visuals, "Custom Ambient", "Tint the ambient light with the color below.", function(on)
    ambientOn = on
    bind("ambient", on, function()
        Lighting.Ambient = value.Ambient
        Lighting.OutdoorAmbient = value.Ambient
    end, function()
        Lighting.Ambient = original.Ambient
        Lighting.OutdoorAmbient = original.OutdoorAmbient
    end)
end)

colorPicker(visuals, "Ambient Color", value.Ambient, function(c)
    value.Ambient = c
end)

toggle(visuals, "Custom Exposure", "Overall brightness of the image.", function(on)
    bind("exposure", on, function()
        Lighting.ExposureCompensation = value.Exposure
    end, function()
        Lighting.ExposureCompensation = original.ExposureCompensation
    end)
end)

slider(visuals, "Exposure", -3, 3, 0.1, 0, nil, function(v)
    value.Exposure = v
end)

visuals:CreateDivider({ text = "Effects" })

toggle(visuals, "Remove Post-Processing", "Disables blur, bloom, sun rays, color correction and depth of field.",
    makeEffect(
        function()
            local cam = getCamera()
            return cam and { Lighting, cam } or { Lighting }
        end,
        function(i) return i:IsA("PostEffect") end,
        function(i) local o = i.Enabled; i.Enabled = false; return o end,
        function(i, o) i.Enabled = o end
    )
)

toggle(visuals, "No Fog", "Removes fog completely.", function(on)
    bind("nofog", on, function()
        Lighting.FogStart = 0
        Lighting.FogEnd = 1e6
    end, function()
        Lighting.FogStart = original.FogStart
        Lighting.FogEnd = original.FogEnd
    end)
end)

visuals:CreateDivider({ text = "Camera" })

toggle(visuals, "Custom FOV", "Applies the field of view from the slider.", function(on)
    bind("fov", on, function()
        local cam = getCamera()
        if cam then cam.FieldOfView = value.FOV end
    end, function()
        local cam = getCamera()
        if cam then cam.FieldOfView = original.FieldOfView end
    end)
end)

slider(visuals, "FOV", 60, 120, 1, 90, nil, function(v)
    value.FOV = v
end)

toggle(visuals, "Unlock Camera Zoom", "Lets you zoom out much further than the game allows.", function(on)
    bind("zoom", on, function()
        localPlayer.CameraMaxZoomDistance = value.MaxZoom
        localPlayer.CameraMinZoomDistance = 0.5
    end, function()
        localPlayer.CameraMaxZoomDistance = original.MaxZoom
        localPlayer.CameraMinZoomDistance = original.MinZoom
    end)
end)

slider(visuals, "Max Zoom Distance", 50, 2000, 50, 500, nil, function(v)
    value.MaxZoom = v
end)

----------------------------------------------------------------
-- WORLD
----------------------------------------------------------------
local world = window:CreateTab({ name = "World", icon = 93364949241311 })

world:CreateDivider({ text = "Time & Sky" })

toggle(world, "Custom Time", "Locks the time of day to the slider value.", function(on)
    bind("time", on, function()
        Lighting.ClockTime = value.Time
    end, function()
        Lighting.ClockTime = original.ClockTime
    end)
end)

slider(world, "Time of Day", 0, 24, 0.5, 14, "h", function(v)
    value.Time = v
end)

toggle(world, "No Shadows", "Turns global shadows off (also helps FPS).", function(on)
    bind("shadows", on, function()
        Lighting.GlobalShadows = false
    end, function()
        Lighting.GlobalShadows = original.GlobalShadows
    end)
end)

toggle(world, "Remove Skybox", "Removes the sky textures.",
    makeEffect(
        function() return { Lighting } end,
        function(i) return i:IsA("Sky") end,
        function(i) local p = i.Parent; i.Parent = nil; return p end,
        function(i, p) i.Parent = p end
    )
)

toggle(world, "No Sun / Moon / Stars", "Hides the celestial bodies in the sky.",
    makeEffect(
        function() return { Lighting } end,
        function(i) return i:IsA("Sky") end,
        function(i)
            local o = { Bodies = i.CelestialBodiesShown, Stars = i.StarCount }
            i.CelestialBodiesShown = false
            i.StarCount = 0
            return o
        end,
        function(i, o)
            i.CelestialBodiesShown = o.Bodies
            i.StarCount = o.Stars
        end
    )
)

toggle(world, "No Clouds", "Hides the terrain clouds.",
    makeEffect(
        function()
            local t = terrain()
            return t and { t } or {}
        end,
        function(i) return i:IsA("Clouds") end,
        function(i) local o = i.Enabled; i.Enabled = false; return o end,
        function(i, o) i.Enabled = o end
    )
)

toggle(world, "Remove Atmosphere", "Removes the atmospheric haze and glare.",
    makeEffect(
        function() return { Lighting } end,
        function(i) return i:IsA("Atmosphere") end,
        function(i)
            local o = { Density = i.Density, Haze = i.Haze, Glare = i.Glare }
            i.Density = 0
            i.Haze = 0
            i.Glare = 0
            return o
        end,
        function(i, o)
            i.Density = o.Density
            i.Haze = o.Haze
            i.Glare = o.Glare
        end
    )
)

toggle(world, "Custom Fog Color", "Colors the fog with the picker below.", function(on)
    bind("fogcolor", on, function()
        Lighting.FogColor = value.FogColor
    end, function()
        Lighting.FogColor = original.FogColor
    end)
end)

colorPicker(world, "Fog Color", value.FogColor, function(c)
    value.FogColor = c
end)

world:CreateDivider({ text = "Terrain" })

local waterOriginal = nil

toggle(world, "Clear Water", "Transparent water without waves.", function(on)
    local t = terrain()
    if not t then return end
    if on and not waterOriginal then
        waterOriginal = {
            Transparency = t.WaterTransparency,
            WaveSize = t.WaterWaveSize,
        }
    end
    bind("water", on, function()
        t.WaterTransparency = 1
        t.WaterWaveSize = 0
    end, function()
        if waterOriginal then
            t.WaterTransparency = waterOriginal.Transparency
            t.WaterWaveSize = waterOriginal.WaveSize
        end
    end)
end)

world:CreateDivider({ text = "Performance" })

toggle(world, "Remove Particles", "Disables particles, trails, smoke, fire and sparkles.",
    makeEffect(
        function() return { Workspace } end,
        function(i)
            return i:IsA("ParticleEmitter") or i:IsA("Trail") or i:IsA("Smoke")
                or i:IsA("Fire") or i:IsA("Sparkles")
        end,
        function(i) local o = i.Enabled; i.Enabled = false; return o end,
        function(i, o) i.Enabled = o end
    )
)

toggle(world, "Hide Decals / Textures", "Makes all decals and textures invisible.",
    makeEffect(
        function() return { Workspace } end,
        function(i) return i:IsA("Decal") end, -- Texture inherits from Decal
        function(i) local o = i.Transparency; i.Transparency = 1; return o end,
        function(i, o) i.Transparency = o end
    )
)

toggle(world, "Smooth Materials", "Switches every part to SmoothPlastic (client-side, may slightly change local friction).",
    makeEffect(
        function() return { Workspace } end,
        function(i) return i:IsA("BasePart") and not i:IsA("Terrain") end,
        function(i) local o = i.Material; i.Material = Enum.Material.SmoothPlastic; return o end,
        function(i, o) i.Material = o end
    )
)

----------------------------------------------------------------
-- SETTINGS
----------------------------------------------------------------
local settings = window:CreateTab({ name = "Settings", icon = 93364949241311 })

settings:CreateButton({
    name = "Disable All",
    description = "Switches every toggle off and restores the original settings.",
    callback = disableAll,
})

settings:CreateButton({
    name = "Unload Script",
    description = "Restores everything and closes this window.",
    callback = unload,
})
