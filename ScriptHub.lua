local Rayfield = loadstring(game:HttpGet("https://sirius.menu/gen2"))()

----------------------------------------------------------------
-- SCRIPT LIST
-- Each entry = one tab in the left panel.
--   name        - tab name
--   description - text under the button
--   url         - link to the raw code (raw GitHub, Pastebin raw, etc.)
--   source      - alternatively: code pasted directly as text
--   unload      - (optional) function that turns the script off
----------------------------------------------------------------
local SCRIPTS = {
    {
        name = "Universal ESP",
        description = "ESP: glow, box, tracers, health bar, team filters.",
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
        unload = function()
            local inst = getgenv and getgenv().VisualsWorld_Instance
            if inst and inst.Unload then inst.Unload() end
        end,
    },
    {
        name = "Aimbot",
        description = "Smooth camera aimbot with FOV circle, visibility & team check.",
        url = "https://raw.githubusercontent.com/aH7pTep43dq/adefrbchpu/main/Aimbot.lua",
        unload = function()
            local sc = getgenv and getgenv().ScoutCheat
            if sc and sc.UnloadAimbot then sc.UnloadAimbot() end
        end,
    },
}

----------------------------------------------------------------
-- WINDOW
----------------------------------------------------------------
local window = Rayfield:CreateWindow({
    name = "Script Hub",
    subtitle = "Rayfield Gen2",
    sidebarLayout = true, -- tabs (scripts) on the left side
})

local function notify(title, content, duration)
    pcall(function()
        window:Notify({ title = title, content = content, duration = duration or 4 })
    end)
end

-- after a script starts, the hub unloads so it doesn't cover the script's window
local autoUnload = true

local function unloadHub()
    task.delay(0.6, function()
        pcall(function() window:Unload() end)
    end)
end

-- downloads and runs a script (keepOpen = don't unload the hub after a successful start)
local function runScript(entry, keepOpen)
    if entry.url and entry.url:find("YOUR_USERNAME", 1, true) then
        notify(entry.name, "Set a real link in the SCRIPTS table.", 5)
        return false
    end

    local ok, err = pcall(function()
        local code = entry.source or game:HttpGet(entry.url)
        local fn, compileErr = loadstring(code)
        if not fn then error(compileErr, 0) end
        fn()
    end)

    if ok then
        notify(entry.name, "Loaded.")
        if autoUnload and not keepOpen then unloadHub() end
    else
        warn("[Script Hub] " .. entry.name .. ": " .. tostring(err))
        notify(entry.name, "Failed to load (details in the F9 console).", 5)
    end
    return ok
end

----------------------------------------------------------------
-- HOME TAB
----------------------------------------------------------------
local home = window:CreateTab({ name = "Home", icon = 0 })

home:CreateDivider({ text = "Hub" })

home:CreateToggle({
    name = "Unload hub after launching a script",
    description = "The hub disappears once a script starts. Run it again to bring it back.",
    value = true,
    forgetState = true,
    callback = function(v)
        autoUnload = v
    end,
})

home:CreateButton({
    name = "Load all scripts",
    description = "Runs every script from the list, one after another.",
    callback = function()
        for _, entry in ipairs(SCRIPTS) do
            runScript(entry, true)
            task.wait(0.2)
        end
        if autoUnload then unloadHub() end
    end,
})

home:CreateButton({
    name = "Unload hub",
    description = "Closes the hub window (loaded scripts keep running).",
    callback = function()
        window:Unload()
    end,
})

----------------------------------------------------------------
-- SCRIPT TABS (left panel)
----------------------------------------------------------------
for _, entry in ipairs(SCRIPTS) do
    local tab = window:CreateTab({ name = entry.name, icon = 0 })

    tab:CreateDivider({ text = entry.name })

    tab:CreateButton({
        name = "Run",
        description = entry.description,
        callback = function()
            runScript(entry)
        end,
    })

    if entry.unload then
        tab:CreateButton({
            name = "Turn off",
            description = "Unloads this script.",
            callback = function()
                local ok, err = pcall(entry.unload)
                if ok then
                    notify(entry.name, "Unloaded.")
                else
                    warn("[Script Hub] " .. entry.name .. ": " .. tostring(err))
                    notify(entry.name, "Failed to unload.", 5)
                end
            end,
        })
    end
end
