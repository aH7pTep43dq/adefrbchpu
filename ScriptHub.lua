local Rayfield = loadstring(game:HttpGet("https://sirius.menu/gen2"))()

----------------------------------------------------------------
-- LISTA SKRYPTÓW
-- Każdy wpis = jedna zakładka w lewym panelu.
--   name        - nazwa zakładki
--   description - opis pod przyciskiem
--   url         - link do surowego kodu (raw GitHub, Pastebin raw itp.)
--   source      - alternatywnie: kod wklejony bezpośrednio jako tekst
--   unload      - (opcjonalnie) funkcja wyłączająca skrypt
----------------------------------------------------------------
local SCRIPTS = {
    {
        name = "Universal ESP",
        description = "ESP: glow, box, tracery, pasek zdrowia, filtry drużyn.",
        url = "https://raw.githubusercontent.com/aH7pTep43dq/adefrbchpu/main/UniversalESP.lua",
        unload = function()
            local inst = getgenv and getgenv().UniversalESP_Instance
            if inst and inst.Unload then inst.Unload() end
        end,
    },
    {
        name = "Visuals / World",
        description = "Fullbright, No Fog, FOV, Always Day, No Shadows.",
        url = "https://raw.githubusercontent.com/aH7pTep43dq/adefrbchpu/main/visuals_world.lua",
    },
    {
        name = "Przykład (inline)",
        description = "Przykład skryptu wklejonego bezpośrednio do huba.",
        source = [[
            print("Skrypt z huba działa!")
        ]],
    },
}

----------------------------------------------------------------
-- OKNO
----------------------------------------------------------------
local window = Rayfield:CreateWindow({
    name = "Script Hub",
    subtitle = "Rayfield Gen2",
    sidebarLayout = true, -- zakładki (skrypty) po lewej stronie
})

local function notify(title, content, duration)
    pcall(function()
        window:Notify({ title = title, content = content, duration = duration or 4 })
    end)
end

-- pobiera i uruchamia skrypt
local function runScript(entry)
    if entry.url and entry.url:find("TWOJ_NICK", 1, true) then
        notify(entry.name, "Ustaw prawdziwy link w tabeli SCRIPTS.", 5)
        return false
    end

    local ok, err = pcall(function()
        local code = entry.source or game:HttpGet(entry.url)
        local fn, compileErr = loadstring(code)
        if not fn then error(compileErr, 0) end
        fn()
    end)

    if ok then
        notify(entry.name, "Załadowano.")
    else
        warn("[Script Hub] " .. entry.name .. ": " .. tostring(err))
        notify(entry.name, "Błąd ładowania (szczegóły w konsoli F9).", 5)
    end
    return ok
end

----------------------------------------------------------------
-- ZAKŁADKA HOME
----------------------------------------------------------------
local home = window:CreateTab({ name = "Home", icon = 0 })

home:CreateDivider({ text = "Hub" })

home:CreateButton({
    name = "Załaduj wszystkie skrypty",
    description = "Uruchamia po kolei każdy skrypt z listy.",
    callback = function()
        for _, entry in ipairs(SCRIPTS) do
            runScript(entry)
            task.wait(0.2)
        end
    end,
})

home:CreateButton({
    name = "Wyładuj hub",
    description = "Zamyka okno huba (załadowane skrypty działają dalej).",
    callback = function()
        window:Unload()
    end,
})

----------------------------------------------------------------
-- ZAKŁADKI SKRYPTÓW (lewy panel)
----------------------------------------------------------------
for _, entry in ipairs(SCRIPTS) do
    local tab = window:CreateTab({ name = entry.name, icon = 0 })

    tab:CreateDivider({ text = entry.name })

    tab:CreateButton({
        name = "Uruchom",
        description = entry.description,
        callback = function()
            runScript(entry)
        end,
    })

    if entry.unload then
        tab:CreateButton({
            name = "Wyłącz",
            description = "Wyładowuje ten skrypt.",
            callback = function()
                local ok, err = pcall(entry.unload)
                if ok then
                    notify(entry.name, "Wyładowano.")
                else
                    warn("[Script Hub] " .. entry.name .. ": " .. tostring(err))
                    notify(entry.name, "Nie udało się wyładować.", 5)
                end
            end,
        })
    end
end
