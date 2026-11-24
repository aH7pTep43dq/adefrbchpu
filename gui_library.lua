--[[
    NEON EXEC STYLE UI LIBRARY (CLEAN RETRO STYLE)
    A clean, flat, dark-themed GUI library for Roblox executors.
    Theme: Anthracite background, sharp corners, thin cyan-blue borders, monospace styling.
    This version excludes the top status bar, bottom script editor, and UICorners for a retro look.
]]

local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer

local Library = {}

-- Helper function to make UI elements draggable
local function MakeDraggable(dragFrame, parentFrame)
    local dragging
    local dragInput
    local dragStart
    local startPos

    local function update(input)
        local delta = input.Position - dragStart
        parentFrame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
    end

    dragFrame.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragStart = input.Position
            startPos = parentFrame.Position

            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then
                    dragging = false
                end
            end)
        end
    end)

    dragFrame.InputChanged:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
            dragInput = input
        end
    end)

    UserInputService.InputChanged:Connect(function(input)
        if input == dragInput and dragging then
            update(input)
        end
    end)
end

function Library.CreateWindow(titleText)
    titleText = titleText or "NEON EXECUTER"
    
    -- Create Main ScreenGui
    local ScreenGui = Instance.new("ScreenGui")
    ScreenGui.Name = "NeonExecGui_" .. math.random(1000, 9999)
    if syn and syn.protect_gui then
        syn.protect_gui(ScreenGui)
        ScreenGui.Parent = game:GetService("CoreGui")
    elseif gethui then
        ScreenGui.Parent = gethui()
    else
        ScreenGui.Parent = game:GetService("CoreGui") or LocalPlayer:WaitForChild("PlayerGui")
    end

    -- Main Frame (Sharp corners)
    local MainFrame = Instance.new("Frame")
    MainFrame.Name = "MainFrame"
    MainFrame.Size = UDim2.new(0, 550, 0, 400)
    MainFrame.Position = UDim2.new(0.5, -275, 0.5, -200)
    MainFrame.BackgroundColor3 = Color3.fromRGB(18, 22, 26)
    MainFrame.BorderSizePixel = 1
    MainFrame.BorderColor3 = Color3.fromRGB(44, 102, 138)
    MainFrame.Active = true
    MainFrame.Parent = ScreenGui

    -- Inner Stroke/Border (Neon style, sharp)
    local MainStroke = Instance.new("UIStroke")
    MainStroke.Color = Color3.fromRGB(44, 102, 138)
    MainStroke.Thickness = 1.2
    MainStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    MainStroke.Parent = MainFrame

    -- Header / Title Bar
    local Header = Instance.new("Frame")
    Header.Name = "Header"
    Header.Size = UDim2.new(1, 0, 0, 35)
    Header.BackgroundColor3 = Color3.fromRGB(15, 18, 22)
    Header.BorderSizePixel = 0
    Header.Parent = MainFrame

    local TitleLabel = Instance.new("TextLabel")
    TitleLabel.Name = "TitleLabel"
    TitleLabel.Size = UDim2.new(1, 0, 1, 0)
    TitleLabel.BackgroundTransparency = 1
    TitleLabel.Text = titleText
    TitleLabel.TextColor3 = Color3.fromRGB(200, 210, 220)
    TitleLabel.TextSize = 14
    TitleLabel.Font = Enum.Font.Code
    TitleLabel.TextXAlignment = Enum.TextXAlignment.Center
    TitleLabel.Parent = Header

    -- Make it draggable using the header
    MakeDraggable(Header, MainFrame)

    -- Divider Line under Header
    local HeaderLine = Instance.new("Frame")
    HeaderLine.Name = "HeaderLine"
    HeaderLine.Size = UDim2.new(1, 0, 0, 1)
    HeaderLine.Position = UDim2.new(0, 0, 1, -1)
    HeaderLine.BackgroundColor3 = Color3.fromRGB(44, 102, 138)
    HeaderLine.BorderSizePixel = 0
    HeaderLine.Parent = Header

    -- Main Content Area
    local ContentArea = Instance.new("Frame")
    ContentArea.Name = "ContentArea"
    ContentArea.Size = UDim2.new(1, 0, 1, -35)
    ContentArea.Position = UDim2.new(0, 0, 0, 35)
    ContentArea.BackgroundTransparency = 1
    ContentArea.Parent = MainFrame

    -- Sidebar (Left panel for tabs)
    local Sidebar = Instance.new("Frame")
    Sidebar.Name = "Sidebar"
    Sidebar.Size = UDim2.new(0, 120, 1, 0)
    Sidebar.BackgroundColor3 = Color3.fromRGB(14, 17, 21)
    Sidebar.BorderSizePixel = 0
    Sidebar.Parent = ContentArea

    -- Vertical line separating sidebar from main content
    local SidebarLine = Instance.new("Frame")
    SidebarLine.Name = "SidebarLine"
    SidebarLine.Size = UDim2.new(0, 1, 1, 0)
    SidebarLine.Position = UDim2.new(1, -1, 0, 0)
    SidebarLine.BackgroundColor3 = Color3.fromRGB(44, 102, 138)
    SidebarLine.BorderSizePixel = 0
    SidebarLine.Parent = Sidebar

    -- Tabs Container
    local TabButtonsContainer = Instance.new("ScrollingFrame")
    TabButtonsContainer.Name = "TabButtonsContainer"
    TabButtonsContainer.Size = UDim2.new(1, -6, 1, -10)
    TabButtonsContainer.Position = UDim2.new(0, 3, 0, 5)
    TabButtonsContainer.BackgroundTransparency = 1
    TabButtonsContainer.BorderSizePixel = 0
    TabButtonsContainer.ScrollBarThickness = 2
    TabButtonsContainer.ScrollBarImageColor3 = Color3.fromRGB(44, 102, 138)
    TabButtonsContainer.CanvasSize = UDim2.new(0, 0, 0, 0)
    TabButtonsContainer.Parent = Sidebar

    local TabButtonsLayout = Instance.new("UIListLayout")
    TabButtonsLayout.Parent = TabButtonsContainer
    TabButtonsLayout.SortOrder = Enum.SortOrder.LayoutOrder
    TabButtonsLayout.Padding = UDim.new(0, 4)

    -- Container for Tab Pages
    local PagesContainer = Instance.new("Frame")
    PagesContainer.Name = "PagesContainer"
    PagesContainer.Size = UDim2.new(1, -135, 1, -20)
    PagesContainer.Position = UDim2.new(0, 130, 0, 10)
    PagesContainer.BackgroundTransparency = 1
    PagesContainer.Parent = ContentArea

    local Window = {
        CurrentTab = nil,
        Tabs = {}
    }

    function Window:CreateTab(tabName)
        local TabButton = Instance.new("TextButton")
        TabButton.Name = tabName .. "Button"
        TabButton.Size = UDim2.new(1, -5, 0, 30)
        TabButton.BackgroundTransparency = 1
        TabButton.Text = tabName
        TabButton.TextColor3 = Color3.fromRGB(130, 140, 150)
        TabButton.TextSize = 13
        TabButton.Font = Enum.Font.Code
        TabButton.TextXAlignment = Enum.TextXAlignment.Center
        TabButton.Parent = TabButtonsContainer

        -- Left indicator line for active tab
        local ActiveIndicator = Instance.new("Frame")
        ActiveIndicator.Name = "ActiveIndicator"
        ActiveIndicator.Size = UDim2.new(0, 2, 1, 0)
        ActiveIndicator.Position = UDim2.new(0, 0, 0, 0)
        ActiveIndicator.BackgroundColor3 = Color3.fromRGB(44, 102, 138)
        ActiveIndicator.BorderSizePixel = 0
        ActiveIndicator.Visible = false
        ActiveIndicator.Parent = TabButton

        -- Create Page for this Tab
        local Page = Instance.new("ScrollingFrame")
        Page.Name = tabName .. "Page"
        Page.Size = UDim2.new(1, 0, 1, 0)
        Page.BackgroundTransparency = 1
        Page.BorderSizePixel = 0
        Page.ScrollBarThickness = 3
        Page.ScrollBarImageColor3 = Color3.fromRGB(44, 102, 138)
        Page.Visible = false
        Page.CanvasSize = UDim2.new(0, 0, 0, 0)
        Page.Parent = PagesContainer

        local PageLayout = Instance.new("UIListLayout")
        PageLayout.Parent = Page
        PageLayout.SortOrder = Enum.SortOrder.LayoutOrder
        PageLayout.Padding = UDim.new(0, 15) -- Space between groupboxes

        -- Auto-scale canvas size
        PageLayout.Changed:Connect(function()
            Page.CanvasSize = UDim2.new(0, 0, 0, PageLayout.AbsoluteContentSize.Y + 20)
        end)

        local Tab = {
            Page = Page,
            Button = TabButton
        }

        local function Select()
            if Window.CurrentTab then
                Window.CurrentTab.Page.Visible = false
                Window.CurrentTab.Button.TextColor3 = Color3.fromRGB(130, 140, 150)
                Window.CurrentTab.Button.ActiveIndicator.Visible = false
            end
            Window.CurrentTab = Tab
            Page.Visible = true
            TabButton.TextColor3 = Color3.fromRGB(44, 102, 138)
            ActiveIndicator.Visible = true
        end

        TabButton.MouseButton1Click:Connect(Select)

        if not Window.CurrentTab then
            Select()
        end

        -- Groupbox creator inside Tab (completely sharp corners)
        function Tab:CreateGroupbox(groupName)
            local GroupFrame = Instance.new("Frame")
            GroupFrame.Name = groupName .. "Groupbox"
            GroupFrame.Size = UDim2.new(1, -5, 0, 40)
            GroupFrame.BackgroundColor3 = Color3.fromRGB(18, 22, 26)
            GroupFrame.BorderSizePixel = 0
            GroupFrame.Parent = Page

            -- Sharp Groupbox border
            local GroupStroke = Instance.new("UIStroke")
            GroupStroke.Color = Color3.fromRGB(35, 42, 50)
            GroupStroke.Thickness = 1
            GroupStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
            GroupStroke.Parent = GroupFrame

            -- Header Text embedded in the top border (ZekeHub style)
            local GroupTitle = Instance.new("TextLabel")
            GroupTitle.Name = "GroupTitle"
            GroupTitle.Size = UDim2.new(0, 0, 0, 15)
            GroupTitle.Position = UDim2.new(0, 10, 0, -8)
            GroupTitle.BackgroundColor3 = Color3.fromRGB(18, 22, 26)
            GroupTitle.Text = " " .. groupName .. " "
            GroupTitle.TextColor3 = Color3.fromRGB(180, 190, 200)
            GroupTitle.TextSize = 12
            GroupTitle.Font = Enum.Font.Code
            GroupTitle.TextXAlignment = Enum.TextXAlignment.Left
            GroupTitle.SizeToContents = true
            GroupTitle.Parent = GroupFrame

            local ContentLayout = Instance.new("UIListLayout")
            ContentLayout.Parent = GroupFrame
            ContentLayout.SortOrder = Enum.SortOrder.LayoutOrder
            ContentLayout.Padding = UDim.new(0, 8)

            -- Add padding inside the groupbox
            local Padding = Instance.new("UIPadding")
            Padding.PaddingTop = UDim.new(0, 12)
            Padding.PaddingBottom = UDim.new(0, 12)
            Padding.PaddingLeft = UDim.new(0, 10)
            Padding.PaddingRight = UDim.new(0, 10)
            Padding.Parent = GroupFrame

            -- Auto resize Groupbox height based on content
            ContentLayout.Changed:Connect(function()
                GroupFrame.Size = UDim2.new(1, -5, 0, ContentLayout.AbsoluteContentSize.Y + 24)
            end)

            local Groupbox = {}

            -- Checkbox component (sharp)
            function Groupbox:CreateCheckbox(text, default, callback)
                local value = default or false
                callback = callback or function() end

                local CheckboxFrame = Instance.new("TextButton")
                CheckboxFrame.Name = text .. "Checkbox"
                CheckboxFrame.Size = UDim2.new(1, 0, 0, 20)
                CheckboxFrame.BackgroundTransparency = 1
                CheckboxFrame.Text = ""
                CheckboxFrame.Parent = GroupFrame

                local Box = Instance.new("Frame")
                Box.Name = "Box"
                Box.Size = UDim2.new(0, 14, 0, 14)
                Box.Position = UDim2.new(0, 0, 0.5, -7)
                Box.BackgroundColor3 = Color3.fromRGB(12, 14, 17)
                Box.BorderSizePixel = 0
                Box.Parent = CheckboxFrame

                local BoxStroke = Instance.new("UIStroke")
                BoxStroke.Color = Color3.fromRGB(35, 42, 50)
                BoxStroke.Thickness = 1
                BoxStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
                BoxStroke.Parent = Box

                local Indicator = Instance.new("Frame")
                Indicator.Name = "Indicator"
                Indicator.Size = UDim2.new(1, -4, 1, -4)
                Indicator.Position = UDim2.new(0, 2, 0, 2)
                Indicator.BackgroundColor3 = Color3.fromRGB(44, 102, 138)
                Indicator.BorderSizePixel = 0
                Indicator.Visible = value
                Indicator.Parent = Box

                local Label = Instance.new("TextLabel")
                Label.Name = "Label"
                Label.Size = UDim2.new(1, -22, 1, 0)
                Label.Position = UDim2.new(0, 22, 0, 0)
                Label.BackgroundTransparency = 1
                Label.Text = text
                Label.TextColor3 = Color3.fromRGB(150, 160, 170)
                Label.TextSize = 12
                Label.Font = Enum.Font.Code
                Label.TextXAlignment = Enum.TextXAlignment.Left
                Label.Parent = CheckboxFrame

                local function toggle()
                    value = not value
                    Indicator.Visible = value
                    BoxStroke.Color = value and Color3.fromRGB(44, 102, 138) or Color3.fromRGB(35, 42, 50)
                    callback(value)
                end

                CheckboxFrame.MouseButton1Click:Connect(toggle)

                local Checkbox = {}
                function Checkbox:Set(val)
                    value = val
                    Indicator.Visible = value
                    BoxStroke.Color = value and Color3.fromRGB(44, 102, 138) or Color3.fromRGB(35, 42, 50)
                    callback(value)
                end
                return Checkbox
            end

            -- Slider component (sharp)
            function Groupbox:CreateSlider(text, min, max, default, callback)
                min = min or 0
                max = max or 100
                local value = default or min
                callback = callback or function() end

                local SliderContainer = Instance.new("Frame")
                SliderContainer.Name = text .. "Slider"
                SliderContainer.Size = UDim2.new(1, 0, 0, 34)
                SliderContainer.BackgroundTransparency = 1
                SliderContainer.Parent = GroupFrame

                local Label = Instance.new("TextLabel")
                Label.Name = "Label"
                Label.Size = UDim2.new(1, 0, 0, 15)
                Label.BackgroundTransparency = 1
                Label.Text = text
                Label.TextColor3 = Color3.fromRGB(150, 160, 170)
                Label.TextSize = 12
                Label.Font = Enum.Font.Code
                Label.TextXAlignment = Enum.TextXAlignment.Left
                Label.Parent = SliderContainer

                local ValueLabel = Instance.new("TextLabel")
                ValueLabel.Name = "ValueLabel"
                ValueLabel.Size = UDim2.new(1, 0, 0, 15)
                ValueLabel.BackgroundTransparency = 1
                ValueLabel.Text = tostring(value)
                ValueLabel.TextColor3 = Color3.fromRGB(44, 102, 138)
                ValueLabel.TextSize = 12
                ValueLabel.Font = Enum.Font.Code
                ValueLabel.TextXAlignment = Enum.TextXAlignment.Right
                ValueLabel.Parent = SliderContainer

                local Track = Instance.new("TextButton")
                Track.Name = "Track"
                Track.Size = UDim2.new(1, 0, 0, 6)
                Track.Position = UDim2.new(0, 0, 0, 22)
                Track.BackgroundColor3 = Color3.fromRGB(12, 14, 17)
                Track.BorderSizePixel = 0
                Track.Text = ""
                Track.Parent = SliderContainer

                local Fill = Instance.new("Frame")
                Fill.Name = "Fill"
                Fill.Size = UDim2.new((value - min) / (max - min), 0, 1, 0)
                Fill.BackgroundColor3 = Color3.fromRGB(44, 102, 138)
                Fill.BorderSizePixel = 0
                Fill.Parent = Track

                local Handle = Instance.new("Frame")
                Handle.Name = "Handle"
                Handle.Size = UDim2.new(0, 10, 0, 10)
                Handle.Position = UDim2.new((value - min) / (max - min), -5, 0.5, -5)
                Handle.BackgroundColor3 = Color3.fromRGB(90, 100, 110)
                Handle.BorderSizePixel = 0
                Handle.Parent = Track

                local sliding = false

                local function update(input)
                    local pos = math.clamp((input.Position.X - Track.AbsolutePosition.X) / Track.AbsoluteWidth, 0, 1)
                    local newValue = math.floor(min + (max - min) * pos)
                    value = newValue
                    ValueLabel.Text = tostring(value)
                    Fill.Size = UDim2.new(pos, 0, 1, 0)
                    Handle.Position = UDim2.new(pos, -5, 0.5, -5)
                    callback(value)
                end

                Track.InputBegan:Connect(function(input)
                    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                        sliding = true
                        update(input)
                    end
                end)

                UserInputService.InputEnded:Connect(function(input)
                    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                        sliding = false
                    end
                end)

                UserInputService.InputChanged:Connect(function(input)
                    if sliding and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
                        update(input)
                    end
                end)

                local Slider = {}
                function Slider:Set(val)
                    value = math.clamp(val, min, max)
                    ValueLabel.Text = tostring(value)
                    local percent = (value - min) / (max - min)
                    Fill.Size = UDim2.new(percent, 0, 1, 0)
                    Handle.Position = UDim2.new(percent, -5, 0.5, -5)
                    callback(value)
                end
                return Slider
            end

            -- Button component (sharp)
            function Groupbox:CreateButton(text, callback)
                callback = callback or function() end

                local Button = Instance.new("TextButton")
                Button.Name = text .. "Button"
                Button.Size = UDim2.new(1, 0, 0, 24)
                Button.BackgroundColor3 = Color3.fromRGB(22, 27, 33)
                Button.TextColor3 = Color3.fromRGB(180, 190, 200)
                Button.TextSize = 12
                Button.Font = Enum.Font.Code
                Button.Text = text
                Button.Parent = GroupFrame

                local ButtonStroke = Instance.new("UIStroke")
                ButtonStroke.Color = Color3.fromRGB(35, 42, 50)
                ButtonStroke.Thickness = 1
                ButtonStroke.Parent = Button

                Button.MouseEnter:Connect(function()
                    ButtonStroke.Color = Color3.fromRGB(44, 102, 138)
                    Button.TextColor3 = Color3.fromRGB(220, 230, 240)
                end)

                Button.MouseLeave:Connect(function()
                    ButtonStroke.Color = Color3.fromRGB(35, 42, 50)
                    Button.TextColor3 = Color3.fromRGB(180, 190, 200)
                end)

                Button.MouseButton1Click:Connect(callback)
            end

            -- Dropdown component (sharp)
            function Groupbox:CreateDropdown(text, options, default, callback)
                options = options or {}
                local currentOption = default or options[1] or ""
                callback = callback or function() end

                local DropdownContainer = Instance.new("Frame")
                DropdownContainer.Name = text .. "Dropdown"
                DropdownContainer.Size = UDim2.new(1, 0, 0, 42)
                DropdownContainer.BackgroundTransparency = 1
                DropdownContainer.Parent = GroupFrame

                local Label = Instance.new("TextLabel")
                Label.Name = "Label"
                Label.Size = UDim2.new(1, 0, 0, 15)
                Label.BackgroundTransparency = 1
                Label.Text = text
                Label.TextColor3 = Color3.fromRGB(150, 160, 170)
                Label.TextSize = 12
                Label.Font = Enum.Font.Code
                Label.TextXAlignment = Enum.TextXAlignment.Left
                Label.Parent = DropdownContainer

                local DropButton = Instance.new("TextButton")
                DropButton.Name = "DropButton"
                DropButton.Size = UDim2.new(1, 0, 0, 22)
                DropButton.Position = UDim2.new(0, 0, 0, 18)
                DropButton.BackgroundColor3 = Color3.fromRGB(12, 14, 17)
                DropButton.Text = " " .. currentOption
                DropButton.TextColor3 = Color3.fromRGB(160, 170, 180)
                DropButton.TextSize = 12
                DropButton.Font = Enum.Font.Code
                DropButton.TextXAlignment = Enum.TextXAlignment.Left
                DropButton.Parent = DropdownContainer

                local DropStroke = Instance.new("UIStroke")
                DropStroke.Color = Color3.fromRGB(35, 42, 50)
                DropStroke.Thickness = 1
                DropStroke.Parent = DropButton

                local ItemsFrame = Instance.new("Frame")
                ItemsFrame.Name = "ItemsFrame"
                ItemsFrame.Size = UDim2.new(1, 0, 0, 0)
                ItemsFrame.Position = UDim2.new(0, 0, 1, 2)
                ItemsFrame.BackgroundColor3 = Color3.fromRGB(12, 14, 17)
                ItemsFrame.BorderSizePixel = 0
                ItemsFrame.Visible = false
                ItemsFrame.ZIndex = 5
                ItemsFrame.Parent = DropButton

                local ItemsStroke = Instance.new("UIStroke")
                ItemsStroke.Color = Color3.fromRGB(44, 102, 138)
                ItemsStroke.Thickness = 1
                ItemsStroke.Parent = ItemsFrame

                local ItemsLayout = Instance.new("UIListLayout")
                ItemsLayout.Parent = ItemsFrame
                ItemsLayout.SortOrder = Enum.SortOrder.LayoutOrder

                local function populateItems()
                    for _, child in ipairs(ItemsFrame:GetChildren()) do
                        if child:IsA("TextButton") then child:Destroy() end
                    end

                    for i, opt in ipairs(options) do
                        local Item = Instance.new("TextButton")
                        Item.Name = opt .. "Item"
                        Item.Size = UDim2.new(1, 0, 0, 20)
                        Item.BackgroundTransparency = 1
                        Item.Text = " " .. opt
                        Item.TextColor3 = Color3.fromRGB(130, 140, 150)
                        Item.TextSize = 11
                        Item.Font = Enum.Font.Code
                        Item.TextXAlignment = Enum.TextXAlignment.Left
                        Item.ZIndex = 6
                        Item.Parent = ItemsFrame

                        Item.MouseButton1Click:Connect(function()
                            currentOption = opt
                            DropButton.Text = " " .. opt
                            ItemsFrame.Visible = false
                            DropStroke.Color = Color3.fromRGB(35, 42, 50)
                            callback(opt)
                        end)

                        Item.MouseEnter:Connect(function()
                            Item.TextColor3 = Color3.fromRGB(44, 102, 138)
                        end)

                        Item.MouseLeave:Connect(function()
                            Item.TextColor3 = Color3.fromRGB(130, 140, 150)
                        end)
                    end
                    ItemsFrame.Size = UDim2.new(1, 0, 0, #options * 20)
                end

                populateItems()

                DropButton.MouseButton1Click:Connect(function()
                    local toggled = not ItemsFrame.Visible
                    ItemsFrame.Visible = toggled
                    DropStroke.Color = toggled and Color3.fromRGB(44, 102, 138) or Color3.fromRGB(35, 42, 50)
                end)

                local Dropdown = {}
                function Dropdown:Refresh(newOptions, defaultOpt)
                    options = newOptions or {}
                    currentOption = defaultOpt or options[1] or ""
                    DropButton.Text = " " .. currentOption
                    populateItems()
                end
                return Dropdown
            end

            return Groupbox
        end

        return Tab
    end

    return Window
end

return Library
