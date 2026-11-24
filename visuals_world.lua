local Rayfield = loadstring(game:HttpGet("https://sirius.menu/gen2"))()

local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local camera = Workspace.CurrentCamera

-- zapamiętujemy oryginalne ustawienia
local original = {
    Brightness = Lighting.Brightness,
    Ambient = Lighting.Ambient,
    OutdoorAmbient = Lighting.OutdoorAmbient,
    FogEnd = Lighting.FogEnd,
    FogStart = Lighting.FogStart,
    ClockTime = Lighting.ClockTime,
    GlobalShadows = Lighting.GlobalShadows,
    FieldOfView = camera.FieldOfView,
}

-- pomocnik: pętla, która utrzymuje ustawienie (niektóre gry je nadpisują)
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

-- unloader: rozłącza pętle, przywraca ustawienia, zamyka GUI
local unloaded = false

local function unload()
    if unloaded then return end
    unloaded = true

    for name, conn in pairs(connections) do
        conn:Disconnect()
        connections[name] = nil
    end

    pcall(function()
        Lighting.Brightness = original.Brightness
        Lighting.Ambient = original.Ambient
        Lighting.OutdoorAmbient = original.OutdoorAmbient
        Lighting.FogEnd = original.FogEnd
        Lighting.FogStart = original.FogStart
        Lighting.ClockTime = original.ClockTime
        Lighting.GlobalShadows = original.GlobalShadows
        camera.FieldOfView = original.FieldOfView
    end)

    -- zamknięcie GUI (metoda z dokumentacji Gen2)
    pcall(function() window:Unload() end)
end

-- okno GUI
local window = Rayfield:CreateWindow({
    name = "Moj Skrypt",
    subtitle = "Rayfield Gen2",
    sidebarLayout = true,
})

----------------------------------------------------------------
-- VISUALS
----------------------------------------------------------------
local visuals = window:CreateTab({ name = "Visuals", icon = 93364949241311 })

visuals:CreateToggle({
    name = "Fullbright",
    callback = function(value)
        bind("fullbright", value, function()
            Lighting.Brightness = 2
            Lighting.Ambient = Color3.new(1, 1, 1)
            Lighting.OutdoorAmbient = Color3.new(1, 1, 1)
        end, function()
            Lighting.Brightness = original.Brightness
            Lighting.Ambient = original.Ambient
            Lighting.OutdoorAmbient = original.OutdoorAmbient
        end)
    end,
})

visuals:CreateToggle({
    name = "No Fog",
    callback = function(value)
        bind("nofog", value, function()
            Lighting.FogStart = 0
            Lighting.FogEnd = 1e6
        end, function()
            Lighting.FogStart = original.FogStart
            Lighting.FogEnd = original.FogEnd
        end)
    end,
})

local fovValue = 90

visuals:CreateToggle({
    name = "Custom FOV",
    callback = function(value)
        bind("fov", value, function()
            camera.FieldOfView = fovValue
        end, function()
            camera.FieldOfView = original.FieldOfView
        end)
    end,
})

visuals:CreateSlider({
    name = "FOV",
    range = { 60, 120 },
    increment = 1,
    value = 90,
    callback = function(value)
        fovValue = value
    end,
})

----------------------------------------------------------------
-- WORLD
----------------------------------------------------------------
local world = window:CreateTab({ name = "World", icon = 93364949241311 })

world:CreateToggle({
    name = "Always Day",
    callback = function(value)
        bind("day", value, function()
            Lighting.ClockTime = 14
        end, function()
            Lighting.ClockTime = original.ClockTime
        end)
    end,
})

world:CreateToggle({
    name = "No Shadows",
    callback = function(value)
        bind("shadows", value, function()
            Lighting.GlobalShadows = false
        end, function()
            Lighting.GlobalShadows = original.GlobalShadows
        end)
    end,
})

----------------------------------------------------------------
-- SETTINGS
----------------------------------------------------------------
local settings = window:CreateTab({ name = "Settings", icon = 93364949241311 })

settings:CreateToggle({
    name = "Unload Script",
    callback = function(value)
        if value then
            unload()
        end
    end,
})
