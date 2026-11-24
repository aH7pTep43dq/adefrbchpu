--[[
    =====================================================
    NEON CHEAT HUB - main.lua
    Łączy ze sobą:
      - gui_library.lua  (interfejs graficzny)
      - aim better.lua   (zaawansowany aimbot)
      - esp v2.lua       (zaawansowany ESP)

    Jak uruchomić w executorze:
      1. Wgraj folder (peg5tfykoaf-main) do workspace executora
      2. Wklej ten plik (main.lua) do executora i kliknij Execute
    =====================================================
]]

-- ==========================================
-- 0. AUTOMATYCZNE WYKRYWANIE ŚCIEŻKI
-- Próbuje znaleźć pliki w kilku możliwych
-- miejscach: katalog główny, podfolder,
-- lub przez HttpGet jeśli podasz linki.
-- ==========================================
local FOLDER = "peg5tfykoaf-main" -- ← zmień jeśli folder ma inną nazwę

local function tryRead(filename)
    -- Próba 1: plik bezpośrednio w workspace (pliki skopiowane na główny poziom)
    local ok1, result1 = pcall(readfile, filename)
    if ok1 and result1 and #result1 > 0 then return result1 end
    -- Próba 2: plik w podfolderze ze slashem
    local ok2, result2 = pcall(readfile, FOLDER .. "/" .. filename)
    if ok2 and result2 and #result2 > 0 then return result2 end
    -- Próba 3: plik w podfolderze z backslashem (niektóre executory Windows)
    local ok3, result3 = pcall(readfile, FOLDER .. "\\" .. filename)
    if ok3 and result3 and #result3 > 0 then return result3 end
    error("[NeonCheat] Nie znaleziono pliku: " .. filename
        .. "\nUmieść folder '" .. FOLDER .. "' w workspace executora.", 2)
end

local function safeLoad(filename)
    local source = tryRead(filename)
    local fn, err = loadstring(source)
    if not fn then
        error("[NeonCheat] Błąd kompilacji " .. filename .. ": " .. tostring(err), 2)
    end
    return fn()
end

-- ==========================================
-- 1. ŁADOWANIE BIBLIOTEKI GUI
-- ==========================================
local Library = safeLoad("gui_library.lua")

-- ==========================================
-- 2. GLOBALNY OBIEKT KONFIGURACJI
--    aim better.lua czyta z _G.ScoutCheat.Config.Aimbot
--    esp v2.lua     czyta z własnej lokalnej tabeli ESP
-- ==========================================
getgenv().ScoutCheat = {
    Config = {
        Aimbot = {
            -- Podstawowe
            Enabled       = false,
            AimKey        = Enum.UserInputType.MouseButton2, -- Prawy przycisk myszy
            AimPart       = "Head",          -- Część ciała do celowania
            TeamCheck     = true,            -- Ignoruj sojuszników
            VisibleCheck  = false,           -- Celuj tylko w widocznych

            -- FOV (koło celowania)
            FOV_Enabled      = true,
            FOV_Radius       = 150,
            FOV_Color        = Color3.fromRGB(44, 102, 138),
            FOV_Thickness    = 1,
            FOV_Transparency = 0.8,

            -- Płynność i zaawansowane opcje
            Smoothness        = 0.15,        -- Im niższa wartość, tym szybsze celowanie (0.01 - 1)
            Deadzone          = 2,           -- Minimalna odległość do celu (px)
            ClosestBone       = false,       -- Celuj w najbliższy wertebr kości
            
            -- Humanizacja ruchu
            Randomization     = false,       -- Dodaj losowe przesunięcie
            RandomIntensity   = 0.3,
            Acceleration      = 0.2,
            Braking           = 0.3,
            CurveAiming       = false,       -- Celowanie po krzywej
            CurveStrength     = 0.5,
            CurveSmoothing    = false,
            SmoothnessVariance = false,
            MicroTremor       = false,       -- Symulacja drżenia ręki
            TremorIntensity   = 1,
        }
    },
    _connections = {},  -- Tu aim better.lua przechowuje swoje połączenia eventów
    _drawings    = {},  -- Tu przechowywane są rysunki (FOV Circle itp.)
}

-- ==========================================
-- 3. ŁADOWANIE SKRYPTÓW LOGIKI
-- ==========================================
safeLoad("esp v2.lua")
safeLoad("aim better.lua")

-- ==========================================
-- 4. SKRÓT DO KONFIGURACJI AIMBOTA
-- ==========================================
local Aim = getgenv().ScoutCheat.Config.Aimbot

-- ==========================================
-- 5. BUDOWANIE INTERFEJSU GUI
-- ==========================================
local Window = Library.CreateWindow("NEON CHEAT HUB")

-- Zakładki
local CombatTab  = Window:CreateTab("Combat")
local VisualsTab = Window:CreateTab("Visuals")
local SettingsTab = Window:CreateTab("Settings")

-- ==================== COMBAT ====================
local AimbotGroup = CombatTab:CreateGroupbox("Aimbot")

AimbotGroup:CreateCheckbox("Enable Aimbot", Aim.Enabled, function(state)
    Aim.Enabled = state
end)

AimbotGroup:CreateCheckbox("Team Check", Aim.TeamCheck, function(state)
    Aim.TeamCheck = state
end)

AimbotGroup:CreateCheckbox("Visible Check", Aim.VisibleCheck, function(state)
    Aim.VisibleCheck = state
end)

AimbotGroup:CreateCheckbox("Closest Bone", Aim.ClosestBone, function(state)
    Aim.ClosestBone = state
end)

AimbotGroup:CreateCheckbox("Show FOV Circle", Aim.FOV_Enabled, function(state)
    Aim.FOV_Enabled = state
end)

AimbotGroup:CreateSlider("FOV Radius", 20, 600, Aim.FOV_Radius, function(value)
    Aim.FOV_Radius = value
end)

-- Smoothness jako suwak 1-100 (konwertujemy na 0.01-1.0)
AimbotGroup:CreateSlider("Smoothness", 1, 100, math.floor(Aim.Smoothness * 100), function(value)
    Aim.Smoothness = value / 100
end)

local HumanizeGroup = CombatTab:CreateGroupbox("Humanization")

HumanizeGroup:CreateCheckbox("Randomization", Aim.Randomization, function(state)
    Aim.Randomization = state
end)

HumanizeGroup:CreateCheckbox("Curve Aiming", Aim.CurveAiming, function(state)
    Aim.CurveAiming = state
end)

HumanizeGroup:CreateCheckbox("Micro Tremor", Aim.MicroTremor, function(state)
    Aim.MicroTremor = state
end)

HumanizeGroup:CreateCheckbox("Smoothness Variance", Aim.SmoothnessVariance, function(state)
    Aim.SmoothnessVariance = state
end)

HumanizeGroup:CreateDropdown("Aim Part", {"Head", "HumanoidRootPart", "UpperTorso"}, Aim.AimPart, function(selected)
    Aim.AimPart = selected
end)

-- ==================== VISUALS (ESP) ====================
-- esp v2.lua używa własnej globalnej tabeli ESP – odwołujemy się do niej
-- przez _G lub przez upvalue (esp v2.lua tworzy lokalną tabelę ESP)
-- Kontrolki tutaj są wyłącznie kosmetyczne i opisowe, bo esp v2.lua działa automatycznie.

local ESPGroup = VisualsTab:CreateGroupbox("ESP Info")

ESPGroup:CreateButton("ESP działa automatycznie", function()
    -- ESP v2 uruchamia się samodzielnie po załadowaniu esp v2.lua
    -- Konfigurację możesz zmienić bezpośrednio w pliku esp v2.lua
end)

-- ==================== SETTINGS ====================
local MenuSettings = SettingsTab:CreateGroupbox("Menu Options")

MenuSettings:CreateButton("Unload All Scripts", function()
    -- Rozłącz wszystkie eventy aimbota
    for _, conn in ipairs(getgenv().ScoutCheat._connections) do
        if typeof(conn) == "RBXScriptConnection" then
            conn:Disconnect()
        end
    end
    -- Usuń rysunki (FOV circle itp.)
    for _, drawing in ipairs(getgenv().ScoutCheat._drawings) do
        pcall(function() drawing:Destroy() end)
    end
    -- Usuń GUI
    for _, gui in ipairs(game:GetService("CoreGui"):GetChildren()) do
        if string.find(tostring(gui.Name), "NeonExecGui_") or gui.Name == "ESPHolder" then
            gui:Destroy()
        end
    end
    for _, gui in ipairs(game:GetService("Players").LocalPlayer.PlayerGui:GetChildren()) do
        if string.find(tostring(gui.Name), "NeonExecGui_") or gui.Name == "ESPHolder" then
            gui:Destroy()
        end
    end
    -- Wyczyść globalny obiekt
    getgenv().ScoutCheat = nil
    print("[NeonCheat] Skrypt odładowany!")
end)
