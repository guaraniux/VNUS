--[[
    VNUS v1.0 · Librería de interfaz para scripts de Roblox.
    Autor: Guaraniux.

    Los comentarios y textos visibles están en español; los identificadores,
    tokens internos y claves de configuración están en inglés.
    API principal: VNUS:CreateWindow, VNUS:Notify y VNUS:SetAccent.
]]

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local TextService = game:GetService("TextService")
local HttpService = game:GetService("HttpService")

local LocalPlayer = Players.LocalPlayer

local VNUS = {
    Version = "1.0",
    Flags = {},
    Window = nil,
}

local Theme = {
    -- Color de acento configurable mediante Theme.Accent o VNUS:SetAccent.
    Main = Color3.fromRGB(12, 12, 12),
    Top = Color3.fromRGB(12, 12, 12),
    Tab = Color3.fromRGB(12, 12, 12),
    Section = Color3.fromRGB(18, 18, 18),
    SectionInner = Color3.fromRGB(18, 18, 18),
    Element = Color3.fromRGB(24, 24, 24),
    ElementHover = Color3.fromRGB(32, 32, 32),
    Border = Color3.fromRGB(45, 45, 45),
    BorderDark = Color3.fromRGB(5, 5, 5),
    Text = Color3.fromRGB(170, 170, 170),
    DimText = Color3.fromRGB(100, 100, 100),
    BrightText = Color3.fromRGB(230, 230, 230),
    Accent = Color3.fromRGB(255, 45, 130),

    -- Colores semánticos usados por los estados de peligro y éxito.
    Danger = Color3.fromRGB(180, 58, 64),
    Success = Color3.fromRGB(48, 145, 78),
}

VNUS.Theme = Theme

-- Estado compartido por las ventanas: atajo, registro, captura y preferencias.
local function getSharedEnvironment()
    if type(getgenv) == "function" then
        local ok, env = pcall(getgenv)
        if ok and type(env) == "table" then
            return env
        end
    end

    return _G
end

local SharedEnvironment = getSharedEnvironment()
SharedEnvironment.__VNUS_UI_SHARED_STATE =
    SharedEnvironment.__VNUS_UI_SHARED_STATE
    or {
        ToggleKeyName = "K",
        Windows = setmetatable({}, {__mode = "k"}),
        CapturingWindow = nil,
        CapturingControl = nil,
        SuppressToggleUntil = 0,
        LayoutMode = "Auto",
        UIScalePercent = 100,
    }

local SharedUIState = SharedEnvironment.__VNUS_UI_SHARED_STATE
SharedUIState.ToggleKeyName = SharedUIState.ToggleKeyName or "K"
SharedUIState.Windows = SharedUIState.Windows or setmetatable({}, {__mode = "k"})
SharedUIState.SuppressToggleUntil = SharedUIState.SuppressToggleUntil or 0
SharedUIState.LayoutMode = tostring(SharedUIState.LayoutMode or "Auto")
SharedUIState.UIScalePercent = math.clamp(tonumber(SharedUIState.UIScalePercent) or 100, 75, 125)

-- Valores predeterminados compartidos para la ruta y las opciones de configuración.
SharedEnvironment.__VNUS_CONFIG_SHARED_STATE =
    SharedEnvironment.__VNUS_CONFIG_SHARED_STATE
    or {
        Root = "VNUS/Configs",
        AutoSaveDefault = true,
        AutoLoadDefault = true,
    }

local SharedConfigState = SharedEnvironment.__VNUS_CONFIG_SHARED_STATE
SharedConfigState.Root = tostring(SharedConfigState.Root or "VNUS/Configs")
if SharedConfigState.AutoSaveDefault == nil then
    SharedConfigState.AutoSaveDefault = true
end
if SharedConfigState.AutoLoadDefault == nil then
    SharedConfigState.AutoLoadDefault = true
end

local FileAPI = {
    Write = type(writefile) == "function" and writefile or nil,
    Read = type(readfile) == "function" and readfile or nil,
    IsFile = type(isfile) == "function" and isfile or nil,
    MakeFolder = type(makefolder) == "function" and makefolder or nil,
    ListFiles = type(listfiles) == "function" and listfiles or nil,
    DeleteFile = type(delfile) == "function" and delfile or nil,
}

local function sanitizeFileComponent(value, fallback)
    local text = tostring(value or "")
    text = text:gsub("[^%w%-%._ ]", "_")
    text = text:gsub("^%s+", ""):gsub("%s+$", "")
    text = text:gsub("%s+", "_")
    text = text:gsub("_+", "_")

    if text == "" then
        text = tostring(fallback or "default")
    end

    return text:sub(1, 80)
end

local function ensureFolderPath(path)
    if not FileAPI.MakeFolder then
        return false
    end

    local current = ""
    for part in tostring(path):gmatch("[^/\\]+") do
        current = current == "" and part or (current .. "/" .. part)
        pcall(FileAPI.MakeFolder, current)
    end

    return true
end

local function jsonDecode(text)
    if type(text) ~= "string" or text == "" then
        return nil
    end

    local ok, value = pcall(function()
        return HttpService:JSONDecode(text)
    end)

    return ok and value or nil
end

local function jsonEncode(value)
    local ok, text = pcall(function()
        return HttpService:JSONEncode(value)
    end)

    return ok and text or nil
end

-- Etiquetas visibles de los tokens de diseño guardados en las preferencias.
local LAYOUT_MODE_LABELS = {
    Auto = "Automático",
    Desktop = "Escritorio",
    Phone = "Móvil",
}

local function getLayoutModeLabel(mode)
    return LAYOUT_MODE_LABELS[mode] or tostring(mode or "Auto")
end

-- Nombres reconocidos para inyectar los controles integrados.
local SETTINGS_TAB_NAMES = {
    settings = true,
    ajustes = true,
}

local function isSettingsTabName(name)
    return SETTINGS_TAB_NAMES[string.lower(tostring(name or ""))] == true
end

local function normalizeLayoutMode(value)
    local text = tostring(value or "Auto")
    local lowered = string.lower(text)
    if lowered == "phone" or lowered == "mobile" or lowered == "móvil" or lowered == "movil" then
        return "Phone"
    elseif lowered == "desktop" or lowered == "pc" or lowered == "escritorio" then
        return "Desktop"
    end
    return "Auto"
end

local function getViewportSize()
    local camera = workspace.CurrentCamera
    local viewport = camera and camera.ViewportSize or Vector2.new(1280, 720)
    if viewport.X < 1 or viewport.Y < 1 then
        return Vector2.new(1280, 720)
    end
    return viewport
end

local function resolveLayoutMode(mode, viewport)
    mode = normalizeLayoutMode(mode)
    if mode ~= "Auto" then
        return mode
    end

    viewport = viewport or getViewportSize()
    local smallViewport = viewport.X < 760 or viewport.Y < 500
    local touchPhone = UserInputService.TouchEnabled
        and math.min(viewport.X, viewport.Y) <= 720

    return (smallViewport or touchPhone) and "Phone" or "Desktop"
end

local UI_PREFS_PATH = SharedConfigState.Root .. "/_ui_layout.json"

local function loadSharedUIPreferences()
    if not FileAPI.Read or not FileAPI.IsFile then
        return
    end

    local okExists, exists = pcall(FileAPI.IsFile, UI_PREFS_PATH)
    if not okExists or not exists then
        return
    end

    local okRead, text = pcall(FileAPI.Read, UI_PREFS_PATH)
    if not okRead then
        return
    end

    local data = jsonDecode(text)
    if type(data) ~= "table" then
        return
    end

    SharedUIState.LayoutMode = normalizeLayoutMode(data.LayoutMode or SharedUIState.LayoutMode)
    SharedUIState.UIScalePercent = math.clamp(
        tonumber(data.UIScalePercent) or SharedUIState.UIScalePercent or 100,
        75,
        125
    )
end

local function saveSharedUIPreferences()
    if not FileAPI.Write or not FileAPI.MakeFolder then
        return false
    end

    ensureFolderPath(SharedConfigState.Root)
    local encoded = jsonEncode({
        Version = 1,
        LayoutMode = normalizeLayoutMode(SharedUIState.LayoutMode),
        UIScalePercent = math.clamp(tonumber(SharedUIState.UIScalePercent) or 100, 75, 125),
    })

    return encoded ~= nil and pcall(FileAPI.Write, UI_PREFS_PATH, encoded)
end

loadSharedUIPreferences()

local function create(className, properties)
    local object = Instance.new(className)
    for key, value in pairs(properties or {}) do
        object[key] = value
    end
    return object
end

local function tween(object, duration, properties)
    local animation = TweenService:Create(
        object,
        TweenInfo.new(duration or 0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
        properties
    )
    animation:Play()
    return animation
end

-- Duraciones, en segundos, de las animaciones de interacción y de la ventana.
local Motion = {
    Hover = 0.08,
    Press = 0.07,
    Toggle = 0.11,
    Popup = 0.12,
    Tab = 0.16,
    Window = 0.19,
    Visibility = 0.14,
}

local function motionTween(object, duration, style, direction, properties)
    if not object or not object.Parent then
        return nil
    end

    local animation = TweenService:Create(
        object,
        TweenInfo.new(
            duration or Motion.Tab,
            style or Enum.EasingStyle.Quart,
            direction or Enum.EasingDirection.Out
        ),
        properties
    )
    animation:Play()
    return animation
end

local function codeLabel(parent, text, size, color, zIndex)
    return create("TextLabel", {
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Text = tostring(text or ""),
        TextColor3 = color or Theme.Text,
        TextSize = size or 12,
        Font = Enum.Font.Code,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextYAlignment = Enum.TextYAlignment.Center,
        ZIndex = zIndex or 4,
        Parent = parent,
    })
end

local function getGuiParent(screenGui)
    -- Primero intenta colocar el ScreenGui en PlayerGui; gethui() es el respaldo.
    local playerGui = LocalPlayer and LocalPlayer:FindFirstChildOfClass("PlayerGui")
    if not playerGui and LocalPlayer then
        playerGui = LocalPlayer:WaitForChild("PlayerGui", 10)
    end

    if playerGui then
        local ok = pcall(function()
            screenGui.Parent = playerGui
        end)
        if ok and screenGui.Parent == playerGui then
            return playerGui
        end
    end

    -- Respaldo para los entornos que no exponen PlayerGui.
    if type(gethui) == "function" then
        local ok, target = pcall(gethui)
        if ok and target then
            local parented = pcall(function()
                screenGui.Parent = target
            end)
            if parented then
                return target
            end
        end
    end

    return nil
end

local function normalizeDropdownValue(value)
    if type(value) == "table" then
        return value[1]
    end
    return value
end

local function safeCallback(callback, ...)
    if type(callback) == "function" then
        task.spawn(callback, ...)
    end
end

-- Asigna una propiedad dentro de pcall y devuelve si la operación tuvo éxito.
local function safeSet(instance, property, value)
    if not instance then
        return false
    end

    local ok = pcall(function()
        instance[property] = value
    end)
    return ok
end

local function setHover(button, normal, hover)
    local hovering = false

    button.MouseEnter:Connect(function()
        hovering = true
        if button.Parent then
            tween(button, Motion.Hover, {BackgroundColor3 = hover})
        end
    end)

    button.MouseLeave:Connect(function()
        hovering = false
        if button.Parent then
            tween(button, Motion.Hover, {BackgroundColor3 = normal})
        end
    end)

    button.MouseButton1Down:Connect(function()
        if button.Parent then
            motionTween(
                button,
                Motion.Press,
                Enum.EasingStyle.Quad,
                Enum.EasingDirection.Out,
                {BackgroundTransparency = math.min(0.12, button.BackgroundTransparency + 0.08)}
            )
        end
    end)

    button.MouseButton1Up:Connect(function()
        if button.Parent then
            motionTween(
                button,
                Motion.Press,
                Enum.EasingStyle.Quad,
                Enum.EasingDirection.Out,
                {BackgroundTransparency = 0}
            )
            tween(button, Motion.Hover, {BackgroundColor3 = hovering and hover or normal})
        end
    end)
end

local function getCurrentSection(tab)
    if tab._currentSection then
        return tab._currentSection
    end
    return tab:CreateSection("Principal")
end

function VNUS:SetAccent(color)
    if typeof(color) ~= "Color3" then
        return
    end

    Theme.Accent = color

    local window = self.Window
    if not window then
        return
    end

    for _, object in ipairs(window.AccentObjects or {}) do
        if object and object.Parent then
            if object:IsA("TextLabel") or object:IsA("TextButton") then
                object.TextColor3 = color
            elseif object:IsA("ImageLabel") or object:IsA("ImageButton") then
                object.ImageColor3 = color
            elseif object:IsA("GuiObject") then
                object.BackgroundColor3 = color
            end
        end
    end

    if window.CurrentTab and window.CurrentTab.Highlight then
        window.CurrentTab.Highlight.BackgroundColor3 = color
    end
end

-- Crea un aviso según data.Duration, con tres segundos por defecto, y lo elimina.
function VNUS:Notify(data)
    local window = self.Window
    if not window or not window.ScreenGui or not window.ScreenGui.Parent then
        return
    end

    data = data or {}

    local viewport = getViewportSize()
    local phoneLayout = resolveLayoutMode(SharedUIState.LayoutMode, viewport) == "Phone"
    local toastWidth = math.min(phoneLayout and 330 or 280, math.max(220, viewport.X - 24))
    local toastHeight = phoneLayout and 64 or 56

    local toast = create("Frame", {
        Size = UDim2.fromOffset(toastWidth, toastHeight),
        BackgroundColor3 = Theme.Section,
        BorderColor3 = Theme.Border,
        BorderSizePixel = 1,
        ZIndex = 700,
        Parent = window.NotificationHolder,
    })

    create("Frame", {
        Position = UDim2.fromOffset(1, 1),
        Size = UDim2.new(1, -2, 1, -2),
        BackgroundTransparency = 1,
        BorderColor3 = Theme.BorderDark,
        BorderSizePixel = 1,
        ZIndex = 701,
        Parent = toast,
    })

    local accent = create("Frame", {
        Position = UDim2.fromOffset(4, 4),
        Size = UDim2.new(0, 2, 1, -8),
        BackgroundColor3 = Theme.Accent,
        BorderSizePixel = 0,
        ZIndex = 702,
        Parent = toast,
    })
    table.insert(window.AccentObjects, accent)

    local title = codeLabel(toast, data.Title or "VNUS", phoneLayout and 14 or 12, Theme.BrightText, 703)
    title.Position = UDim2.fromOffset(12, 5)
    title.Size = UDim2.new(1, -18, 0, phoneLayout and 21 or 18)

    local content = codeLabel(toast, data.Content or "", phoneLayout and 12 or 11, Theme.DimText, 703)
    content.Position = UDim2.fromOffset(12, phoneLayout and 27 or 22)
    content.Size = UDim2.new(1, -18, 0, phoneLayout and 31 or 28)
    content.TextWrapped = true
    content.TextYAlignment = Enum.TextYAlignment.Top

    toast.BackgroundTransparency = 1
    title.TextTransparency = 1
    content.TextTransparency = 1
    accent.BackgroundTransparency = 1

    tween(toast, 0.12, {BackgroundTransparency = 0})
    tween(title, 0.12, {TextTransparency = 0})
    tween(content, 0.12, {TextTransparency = 0})
    tween(accent, 0.12, {BackgroundTransparency = 0})

    task.delay(tonumber(data.Duration) or 3, function()
        if not toast.Parent then return end
        tween(toast, 0.12, {BackgroundTransparency = 1})
        tween(title, 0.12, {TextTransparency = 1})
        tween(content, 0.12, {TextTransparency = 1})
        tween(accent, 0.12, {BackgroundTransparency = 1})
        task.wait(0.14)
        if toast.Parent then
            toast:Destroy()
        end
    end)
end

function VNUS:CreateWindow(settings)
    settings = settings or {}

    if self.Window and self.Window.ScreenGui then
        pcall(function()
            self.Window.ScreenGui:Destroy()
        end)
    end

    local width = tonumber(settings.Width) or 480
    local height = tonumber(settings.Height) or 540
    width = math.max(320, width)
    height = math.max(320, height)

    local screen = create("ScreenGui", {
        Name = settings.GuiName or "VNUS_UI",
        ResetOnSpawn = false,
        IgnoreGuiInset = true,
        ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
        DisplayOrder = 10000,
    })
    getGuiParent(screen)

    -- WindowMover no usa escala; durante el arrastre solo cambia su Position.
    local mover = create("Frame", {
        Name = "WindowMover",
        AnchorPoint = Vector2.new(0, 0),
        Position = UDim2.fromOffset(0, 0),
        Size = UDim2.fromOffset(0, 0),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Active = false,
        ClipsDescendants = false,
        ZIndex = 1,
        Parent = screen,
    })

    local shadow = create("Frame", {
        Name = "Shadow",
        AnchorPoint = Vector2.new(0, 0),
        Position = UDim2.fromOffset(4, 4),
        Size = UDim2.fromOffset(width, height),
        BackgroundColor3 = Color3.fromRGB(0, 0, 0),
        BackgroundTransparency = 0.5,
        BorderSizePixel = 0,
        ZIndex = 1,
        Parent = mover,
    })

    local main = create("CanvasGroup", {
        Name = "Main",
        AnchorPoint = Vector2.new(0, 0),
        Position = UDim2.fromOffset(0, 0),
        Size = UDim2.fromOffset(width, height),
        BackgroundColor3 = Theme.Main,
        BorderColor3 = Theme.BorderDark,
        BorderSizePixel = 1,
        GroupTransparency = 0,
        Active = true,
        ClipsDescendants = true,
        ZIndex = 2,
        Parent = mover,
    })

    local mainScale = create("UIScale", {Scale = 1, Parent = main})
    local shadowScale = create("UIScale", {Scale = 1, Parent = shadow})

    -- Patrón de rosas de fondo agrupado para controlar su transparencia.
    local roseBackground = create("CanvasGroup", {
        Name = "RoseBackground",
        Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ClipsDescendants = true,
        GroupTransparency = 0.68,
        ZIndex = 3,
        Parent = main,
    })

    local themeColor = Color3.fromRGB(255, 255, 255)

    local function softPart(parent, position, anchor, size, rotation, transparency, corner)
        local part = create("Frame", {
            AnchorPoint = anchor or Vector2.new(0.5, 0.5),
            Position = position,
            Size = size,
            Rotation = rotation or 0,
            BackgroundColor3 = themeColor,
            BackgroundTransparency = transparency or 0.82,
            BorderSizePixel = 0,
            ZIndex = 3,
            Parent = parent,
        })

        create("UICorner", {
            CornerRadius = UDim.new(corner or 1, 0),
            Parent = part,
        })

        return part
    end

    local function createPetal(parent, center, width, height, rotation, transparency)
        local petal = softPart(
            parent,
            center,
            Vector2.new(0.5, 1),
            UDim2.fromOffset(width, height),
            rotation,
            transparency,
            0.5
        )

        create("UIGradient", {
            Rotation = 90,
            Transparency = NumberSequence.new({
                NumberSequenceKeypoint.new(0, 0.18),
                NumberSequenceKeypoint.new(0.55, 0.42),
                NumberSequenceKeypoint.new(1, 0.78),
            }),
            Parent = petal,
        })

        return petal
    end

    local function createRose(centerX, centerY, scale, rotationOffset)
        local size = math.floor(82 * scale)
        local motif = create("Frame", {
            Name = "RoseMotif",
            AnchorPoint = Vector2.new(0.5, 0.5),
            Position = UDim2.fromOffset(centerX, centerY),
            Size = UDim2.fromOffset(size, size),
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            ZIndex = 3,
            Parent = roseBackground,
        })

        local center = UDim2.fromScale(0.5, 0.42)

        -- Seis pétalos exteriores con una separación angular de 60 grados.
        for i = 0, 5 do
            createPetal(
                motif,
                center,
                math.max(5, math.floor(14 * scale)),
                math.max(10, math.floor(22 * scale)),
                (i * 60) + rotationOffset,
                0.76
            )
        end

        -- Pétalos interiores desplazados 36 grados respecto a los exteriores.
        for i = 0, 4 do
            createPetal(
                motif,
                center,
                math.max(4, math.floor(10 * scale)),
                math.max(7, math.floor(15 * scale)),
                (i * 72) + 36 + rotationOffset,
                0.70
            )
        end

        -- Centro difuso de la rosa.
        softPart(
            motif,
            center,
            Vector2.new(0.5, 0.5),
            UDim2.fromOffset(math.max(3, math.floor(5 * scale)), math.max(3, math.floor(5 * scale))),
            0,
            0.58,
            1
        )

        -- Dos hojas formadas por elementos finos rotados.
        local leafY = 0.60
        softPart(
            motif,
            UDim2.new(0.5, -5 * scale, leafY, 0),
            Vector2.new(1, 0.5),
            UDim2.fromOffset(math.max(8, math.floor(17 * scale)), math.max(2, math.floor(4 * scale))),
            -32 + rotationOffset * 0.15,
            0.78,
            1
        )
        softPart(
            motif,
            UDim2.new(0.5, 5 * scale, leafY + 0.035, 0),
            Vector2.new(0, 0.5),
            UDim2.fromOffset(math.max(8, math.floor(17 * scale)), math.max(2, math.floor(4 * scale))),
            32 + rotationOffset * 0.15,
            0.78,
            1
        )

        -- Tallo con degradado de transparencia.
        local stem = create("Frame", {
            AnchorPoint = Vector2.new(0.5, 0),
            Position = UDim2.new(0.5, 0, 0.56, 0),
            Size = UDim2.fromOffset(1, math.max(10, math.floor(24 * scale))),
            BackgroundColor3 = themeColor,
            BackgroundTransparency = 0.74,
            BorderSizePixel = 0,
            ZIndex = 2,
            Parent = motif,
        })

        create("UIGradient", {
            Rotation = 90,
            Transparency = NumberSequence.new({
                NumberSequenceKeypoint.new(0, 0.10),
                NumberSequenceKeypoint.new(1, 1),
            }),
            Parent = stem,
        })
    end

    -- Distribución escalonada de las rosas dentro del área útil de la ventana.
    local tileX = 138
    local tileY = 132
    local firstY = 88 -- comienza debajo de la cabecera y las pestañas
    local row = 0

    for y = firstY, height - 34, tileY do
        local offset = (row % 2 == 0) and 0 or math.floor(tileX / 2)
        local column = 0

        for x = 50 + offset, width - 38, tileX do
            local scale = ((row + column) % 3 == 0) and 0.70 or 0.60
            local tilt = ((row + column) % 2 == 0) and -7 or 7
            createRose(x, y, scale, tilt)
            column += 1
        end

        row += 1
    end

    create("Frame", {
        Name = "InnerBorder",
        Position = UDim2.fromOffset(1, 1),
        Size = UDim2.new(1, -2, 1, -2),
        BackgroundTransparency = 1,
        BorderColor3 = Theme.Border,
        BorderSizePixel = 1,
        ZIndex = 4,
        Parent = main,
    })

    local titleBar = create("Frame", {
        Name = "TitleBar",
        Position = UDim2.fromOffset(2, 2),
        Size = UDim2.new(1, -4, 0, 24),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ZIndex = 8,
        Parent = main,
    })

    local titleLabel = codeLabel(titleBar, settings.Name or settings.Title or "VNUS", 13, Theme.BrightText, 11)
    titleLabel.Position = UDim2.fromOffset(6, 3)
    titleLabel.Size = UDim2.new(1, -52, 0, 18)
    titleLabel.TextWrapped = false
    titleLabel.TextYAlignment = Enum.TextYAlignment.Top
    titleLabel.TextTruncate = Enum.TextTruncate.AtEnd

    -- Mantiene el título visible fuera de Main cuando la ventana está minimizada.
    local minimizedTitleLabel = codeLabel(mover, settings.Name or settings.Title or "VNUS", 13, Theme.BrightText, 20)
    minimizedTitleLabel.Name = "MinimizedTitle"
    minimizedTitleLabel.Position = UDim2.fromOffset(6, 3)
    minimizedTitleLabel.Size = UDim2.fromOffset(math.max(1, width - 52), 18)
    minimizedTitleLabel.TextWrapped = false
    minimizedTitleLabel.TextYAlignment = Enum.TextYAlignment.Top
    minimizedTitleLabel.TextTruncate = Enum.TextTruncate.AtEnd
    minimizedTitleLabel.Visible = false

    local close = create("TextButton", {
        Name = "Close",
        AnchorPoint = Vector2.new(1, 0),
        Position = UDim2.new(1, -2, 0, 2),
        Size = UDim2.fromOffset(18, 19),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        AutoButtonColor = false,
        Font = Enum.Font.Code,
        Text = "x",
        TextSize = 12,
        TextColor3 = Theme.DimText,
        ZIndex = 15,
        Parent = titleBar,
    })

    local minimize = create("TextButton", {
        Name = "Minimize",
        AnchorPoint = Vector2.new(1, 0),
        Position = UDim2.new(1, -20, 0, 2),
        Size = UDim2.fromOffset(18, 18),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        AutoButtonColor = false,
        Font = Enum.Font.Code,
        Text = "-",
        TextSize = 12,
        TextColor3 = Theme.DimText,
        ZIndex = 15,
        Parent = titleBar,
    })

    local dragHandle = create("TextButton", {
        Name = "DragHandle",
        Position = UDim2.fromOffset(0, 0),
        Size = UDim2.new(1, -42, 1, 0),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        AutoButtonColor = false,
        Text = "",
        Active = true,
        ZIndex = 14,
        Parent = titleBar,
    })

    local accentTop = create("Frame", {
        Name = "AccentTop",
        Position = UDim2.fromOffset(2, 26),
        Size = UDim2.new(1, -4, 0, 1),
        BackgroundColor3 = Theme.Accent,
        BorderSizePixel = 0,
        ZIndex = 9,
        Parent = main,
    })

    local tabBar = create("ScrollingFrame", {
        Name = "TabBar",
        Position = UDim2.fromOffset(2, 27),
        Size = UDim2.new(1, -4, 0, 22),
        BackgroundColor3 = Theme.Tab,
        -- La barra permanece opaca para separar el acento superior de sus etiquetas.
        BackgroundTransparency = 0,
        BorderSizePixel = 0,
        CanvasSize = UDim2.new(),
        AutomaticCanvasSize = Enum.AutomaticSize.X,
        ScrollingDirection = Enum.ScrollingDirection.X,
        ScrollBarThickness = 0,
        ElasticBehavior = Enum.ElasticBehavior.Never,
        ZIndex = 8,
        Parent = main,
    })

    local tabLayout = create("UIListLayout", {
        FillDirection = Enum.FillDirection.Horizontal,
        HorizontalAlignment = Enum.HorizontalAlignment.Left,
        VerticalAlignment = Enum.VerticalAlignment.Center,
        SortOrder = Enum.SortOrder.LayoutOrder,
        Padding = UDim.new(0, 12),
        Parent = tabBar,
    })

    -- El separador se coloca debajo de la barra de pestañas.
    local tabSeparatorDark = create("Frame", {
        Name = "TabSeparatorDark",
        Position = UDim2.fromOffset(2, 49),
        Size = UDim2.new(1, -4, 0, 1),
        BackgroundColor3 = Theme.BorderDark,
        BorderSizePixel = 0,
        ZIndex = 8,
        Parent = main,
    })

    local tabSeparator = create("Frame", {
        Name = "TabSeparator",
        Position = UDim2.fromOffset(2, 50),
        Size = UDim2.new(1, -4, 0, 1),
        BackgroundColor3 = Theme.Border,
        BackgroundTransparency = 0.45,
        BorderSizePixel = 0,
        ZIndex = 8,
        Parent = main,
    })

    local columnsHost = create("Frame", {
        Name = "ColumnsHost",
        Position = UDim2.fromOffset(8, 57),
        Size = UDim2.new(1, -16, 1, -65),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ClipsDescendants = true,
        ZIndex = 4,
        Parent = main,
    })

    local popupLayer = create("Frame", {
        Name = "PopupLayer",
        Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Active = false,
        ZIndex = 500,
        Parent = screen,
    })

    local notificationHolder = create("Frame", {
        Name = "Notifications",
        AnchorPoint = Vector2.new(1, 0),
        Position = UDim2.new(1, -10, 0, 10),
        Size = UDim2.fromOffset(290, 450),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ZIndex = 690,
        Parent = screen,
    })
    create("UIListLayout", {
        FillDirection = Enum.FillDirection.Vertical,
        HorizontalAlignment = Enum.HorizontalAlignment.Right,
        VerticalAlignment = Enum.VerticalAlignment.Top,
        SortOrder = Enum.SortOrder.LayoutOrder,
        Padding = UDim.new(0, 4),
        Parent = notificationHolder,
    })

    local window = {
        ScreenGui = screen,
        Mover = mover,
        Main = main,
        TitleBar = titleBar,
        TitleLabel = titleLabel,
        MinimizedTitleLabel = minimizedTitleLabel,
        TabBar = tabBar,
        ColumnsHost = columnsHost,
        PopupLayer = popupLayer,
        NotificationHolder = notificationHolder,
        AccentObjects = {accentTop},
        Tabs = {},
        CurrentTab = nil,
        OpenPopup = nil,
        CloseCallback = nil,
        Minimized = false,
        Visible = true,
        UserPositioned = false,
        FullSize = UDim2.fromOffset(width, height),
        BaseWidth = width,
        BaseHeight = height,
        MainScale = mainScale,
        ShadowScale = shadowScale,
        LayoutMode = normalizeLayoutMode(SharedUIState.LayoutMode),
        ResolvedLayout = "Desktop",
        UIScalePercent = math.clamp(tonumber(SharedUIState.UIScalePercent) or 100, 75, 125),
        ToggleKeyName = tostring(SharedUIState.ToggleKeyName or "K"),
        ToggleKeyCode = Enum.KeyCode.K,
        KeybindDisplays = {},
        ResponsiveConnections = {},
        TabAnimationGeneration = 0,
        WindowAnimationGeneration = 0,
        VisibilityAnimationGeneration = 0,
        WindowAnimating = false,
    }

    local function updateResponsiveTextSizes(phoneLayout)
        local factor = phoneLayout and 1.12 or 1
        for _, object in ipairs(screen:GetDescendants()) do
            if object:IsA("TextLabel") or object:IsA("TextButton") or object:IsA("TextBox") then
                local base = object:GetAttribute("VNUSBaseTextSize")
                if not base then
                    base = object.TextSize
                    object:SetAttribute("VNUSBaseTextSize", base)
                end
                object.TextSize = math.max(9, math.floor(base * factor + 0.5))
            end
        end
    end

    local function updateResponsiveRows(phoneLayout)
        local factor = phoneLayout and 1.10 or 1
        for _, object in ipairs(screen:GetDescendants()) do
            if object:IsA("GuiObject") then
                local baseHeight = object:GetAttribute("VNUSControlBaseHeight")
                if baseHeight then
                    object.Size = UDim2.new(1, 0, 0, math.floor(baseHeight * factor + 0.5))
                end
            end
        end
    end

    function window:_RenderedWindowSize(boundsMode)
        local scale = 1
        if self.MainScale then
            scale = math.max(0.01, tonumber(self.MainScale.Scale) or 1)
        end

        local baseWidth = math.max(1, tonumber(self.Main.Size.X.Offset) or self.BaseWidth or 1)
        local baseHeight = math.max(1, tonumber(self.Main.Size.Y.Offset) or self.BaseHeight or 1)
        if boundsMode == "Expanded" then
            baseWidth = math.max(1, tonumber(self.FullSize.X.Offset) or baseWidth)
            baseHeight = math.max(1, tonumber(self.FullSize.Y.Offset) or baseHeight)
        end

        return Vector2.new(baseWidth * scale, baseHeight * scale)
    end

    function window:Center()
        if not self.Mover or not self.Mover.Parent then
            return
        end

        self.UserPositioned = false
        local viewport = getViewportSize()
        local size = self:_RenderedWindowSize(self.Minimized and "Current" or "Expanded")
        self.Mover.AnchorPoint = Vector2.new(0, 0)
        self.Mover.Position = UDim2.fromOffset(
            math.floor((viewport.X - size.X) * 0.5 + 0.5),
            math.floor((viewport.Y - size.Y) * 0.5 + 0.5)
        )
    end

    function window:ClampToViewport(padding, boundsMode)
        if not self.Mover or not self.Mover.Parent then
            return
        end
        if not self.UserPositioned then
            self:Center()
            return
        end

        -- Ajusta solo WindowMover; Main y Shadow conservan su posición local.
        local viewport = getViewportSize()
        local margin = math.max(4, tonumber(padding) or 6)
        local size = self:_RenderedWindowSize(boundsMode)
        local pos = self.Mover.Position
        local x = viewport.X * pos.X.Scale + pos.X.Offset
        local y = viewport.Y * pos.Y.Scale + pos.Y.Offset
        local maxX = math.max(margin, viewport.X - size.X - margin)
        local maxY = math.max(margin, viewport.Y - size.Y - margin)
        local nx = math.clamp(x, margin, maxX)
        local ny = math.clamp(y, margin, maxY)

        if math.abs(nx - x) < 0.01 and math.abs(ny - y) < 0.01 then
            return
        end

        self.Mover.Position = UDim2.fromOffset(nx, ny)
    end

    -- Ajusta WindowMover usando el rectángulo que Roblox dibujó para Main.
    function window:ClampRenderedToViewport(padding)
        if not self.Mover or not self.Mover.Parent or not self.Main or not self.Main.Parent then
            return
        end
        if not self.UserPositioned then
            self:Center()
            return
        end

        local viewport = getViewportSize()
        local margin = math.max(4, tonumber(padding) or 6)
        local topLeft = self.Main.AbsolutePosition
        local size = self.Main.AbsoluteSize
        local right = topLeft.X + size.X
        local bottom = topLeft.Y + size.Y
        local dx, dy = 0, 0

        if size.X + (margin * 2) <= viewport.X then
            if topLeft.X < margin then
                dx = margin - topLeft.X
            elseif right > viewport.X - margin then
                dx = (viewport.X - margin) - right
            end
        else
            -- Si Main aún excede el viewport, conserva su borde izquierdo dentro
            -- del margen hasta que el siguiente ajuste reduzca su tamaño.
            dx = margin - topLeft.X
        end

        if size.Y + (margin * 2) <= viewport.Y then
            if topLeft.Y < margin then
                dy = margin - topLeft.Y
            elseif bottom > viewport.Y - margin then
                dy = (viewport.Y - margin) - bottom
            end
        else
            dy = margin - topLeft.Y
        end

        if math.abs(dx) < 0.01 and math.abs(dy) < 0.01 then
            return
        end

        local pos = self.Mover.Position
        self.Mover.Position = UDim2.new(
            pos.X.Scale,
            pos.X.Offset + dx,
            pos.Y.Scale,
            pos.Y.Offset + dy
        )
    end

    function window:ApplyResponsiveLayout()
        if not self.ScreenGui or not self.ScreenGui.Parent then
            return
        end

        local viewport = getViewportSize()
        local requestedMode = normalizeLayoutMode(SharedUIState.LayoutMode)
        local resolved = resolveLayoutMode(requestedMode, viewport)
        local phoneLayout = resolved == "Phone"
        local scalePercent = math.clamp(tonumber(SharedUIState.UIScalePercent) or 100, 75, 125)
        local requestedScale = scalePercent / 100
        local landscape = viewport.X > viewport.Y

        local baseWidth = self.BaseWidth
        local baseHeight = self.BaseHeight
        if phoneLayout then
            if landscape then
                baseWidth = math.min(560, math.max(420, math.floor((viewport.X - 18) / math.max(requestedScale, 0.75))))
                baseHeight = math.min(370, math.max(300, math.floor((viewport.Y - 18) / math.max(requestedScale, 0.75))))
            else
                baseWidth = math.min(380, math.max(320, math.floor((viewport.X - 18) / math.max(requestedScale, 0.75))))
                baseHeight = math.min(620, math.max(430, math.floor((viewport.Y - 18) / math.max(requestedScale, 0.75))))
            end
        end

        local fitScale = math.min(
            (viewport.X - 12) / math.max(baseWidth, 1),
            (viewport.Y - 12) / math.max(baseHeight, 1)
        )
        local effectiveScale = math.max(0.60, math.min(requestedScale, fitScale))

        self.LayoutMode = requestedMode
        self.ResolvedLayout = resolved
        self.UIScalePercent = scalePercent
        self.FullSize = UDim2.fromOffset(baseWidth, baseHeight)
        self.MainScale.Scale = effectiveScale
        self.ShadowScale.Scale = effectiveScale

        local headerHeight = phoneLayout and 31 or 24
        local tabHeight = phoneLayout and 29 or 22
        local tabY = phoneLayout and 35 or 27
        local contentY = phoneLayout and 70 or 57
        local bottomPad = phoneLayout and 79 or 65

        titleBar.Size = UDim2.new(1, -4, 0, headerHeight)
        close.Size = UDim2.fromOffset(phoneLayout and 27 or 18, phoneLayout and 27 or 19)
        minimize.Position = UDim2.new(1, phoneLayout and -30 or -20, 0, 2)
        minimize.Size = UDim2.fromOffset(phoneLayout and 27 or 18, phoneLayout and 27 or 18)
        dragHandle.Size = UDim2.new(1, phoneLayout and -62 or -42, 1, 0)
        accentTop.Position = UDim2.fromOffset(2, phoneLayout and 33 or 26)
        tabBar.Position = UDim2.fromOffset(2, tabY)
        tabBar.Size = UDim2.new(1, -4, 0, tabHeight)

        -- El separador sigue la posición y la altura de la barra de pestañas.
        local separatorY = tabY + tabHeight
        tabSeparatorDark.Position = UDim2.fromOffset(2, separatorY)
        tabSeparator.Position = UDim2.fromOffset(2, separatorY + 1)

        columnsHost.Position = UDim2.fromOffset(phoneLayout and 5 or 8, contentY)
        columnsHost.Size = UDim2.new(1, phoneLayout and -10 or -16, 1, -bottomPad)

        for _, tab in ipairs(self.Tabs or {}) do
            if tab.Button then
                local baseTabWidth = tab.Button:GetAttribute("VNUSBaseTabWidth") or tab.Button.Size.X.Offset
                tab.Button.Size = UDim2.fromOffset(baseTabWidth + (phoneLayout and 10 or 0), tabHeight)
            end
            if tab._ReflowSections then
                tab:_ReflowSections()
            end
        end

        updateResponsiveRows(phoneLayout)
        updateResponsiveTextSizes(phoneLayout)

        local minimizedTitleInset = phoneLayout and 8 or 6
        local minimizedTitleTop = phoneLayout and 5 or 3
        local minimizedTitleHeight = phoneLayout and 21 or 18
        local minimizedTitleWidth = phoneLayout and 70 or 52
        minimizedTitleLabel.Position = UDim2.fromOffset(
            math.floor(minimizedTitleInset * effectiveScale + 0.5),
            math.floor(minimizedTitleTop * effectiveScale + 0.5)
        )
        minimizedTitleLabel.Size = UDim2.fromOffset(
            math.max(1, math.floor((baseWidth - minimizedTitleWidth) * effectiveScale + 0.5)),
            math.floor(minimizedTitleHeight * effectiveScale + 0.5)
        )
        minimizedTitleLabel.TextSize = math.max(
            9,
            math.floor((phoneLayout and 14 or 13) * effectiveScale + 0.5)
        )
        minimizedTitleLabel.Visible = self.Minimized and self.Visible ~= false

        if self.Minimized then
            main.Size = UDim2.fromOffset(baseWidth, phoneLayout and 34 or 27)
            shadow.Size = main.Size
            -- La sombra no se muestra mientras la ventana está minimizada.
            shadow.Visible = false
        else
            main.Size = self.FullSize
            shadow.Size = self.FullSize
            shadow.Visible = self.Visible ~= false
        end

        notificationHolder.Size = UDim2.fromOffset(
            math.min(phoneLayout and 340 or 290, math.max(220, viewport.X - 18)),
            math.max(220, viewport.Y - 20)
        )

        if self.DeviceStatusLabel and self.DeviceStatusLabel.Set then
            local inputName = UserInputService.TouchEnabled and "Táctil" or "Teclado/Ratón"
            self.DeviceStatusLabel:Set(string.format(
                "%s • %s • %dx%d • %d%%",
                inputName,
                getLayoutModeLabel(resolved),
                math.floor(viewport.X),
                math.floor(viewport.Y),
                scalePercent
            ))
        end

        -- El reflujo cambia el contenido; solo las ventanas no arrastradas vuelven
        -- a centrarse.
        if not self.UserPositioned then
            self:Center()
        end
    end

    function window:SetLayoutMode(mode)
        SharedUIState.LayoutMode = normalizeLayoutMode(mode)
        for otherWindow in pairs(SharedUIState.Windows) do
            if otherWindow and otherWindow.ApplyResponsiveLayout then
                otherWindow:ApplyResponsiveLayout()
            end
        end
        saveSharedUIPreferences()
        return SharedUIState.LayoutMode
    end

    function window:SetUIScalePercent(value)
        SharedUIState.UIScalePercent = math.clamp(tonumber(value) or 100, 75, 125)
        for otherWindow in pairs(SharedUIState.Windows) do
            if otherWindow and otherWindow.ApplyResponsiveLayout then
                otherWindow:ApplyResponsiveLayout()
            end
        end
        saveSharedUIPreferences()
        return SharedUIState.UIScalePercent
    end

    ------------------------------------------------------------------------
    -- Persistencia compartida de perfiles de configuración.
    ------------------------------------------------------------------------
    local configSettings = type(settings.Configs) == "table" and settings.Configs or {}
    local configId = sanitizeFileComponent(
        settings.ConfigId or settings.GuiName or settings.Name or settings.Title,
        "VNUS"
    )

    local config = {
        Enabled = settings.DisableConfigs ~= true,
        Available = false,
        Root = tostring(configSettings.Root or SharedConfigState.Root),
        Id = configId,
        Folder = "",
        MetaPath = "",
        Selected = sanitizeFileComponent(configSettings.DefaultProfile or "default", "default"),
        AutoSave = SharedConfigState.AutoSaveDefault == true,
        AutoLoad = SharedConfigState.AutoLoadDefault == true,
        Controls = {},
        LoadedValues = {},
        Applying = false,
        Ready = false,
        LastFingerprint = nil,
        StatusLabel = nil,
        ProfilesDropdown = nil,
        ProfileInput = nil,
    }

    config.Folder = config.Root .. "/" .. config.Id
    config.MetaPath = config.Folder .. "/_meta.json"
    config.Available =
        config.Enabled
        and FileAPI.Write ~= nil
        and FileAPI.Read ~= nil
        and FileAPI.IsFile ~= nil
        and FileAPI.MakeFolder ~= nil

    if configSettings.AutoSave ~= nil then
        config.AutoSave = configSettings.AutoSave == true
    end
    if configSettings.AutoLoad ~= nil then
        config.AutoLoad = configSettings.AutoLoad == true
    end

    window.Config = config

    local function configFilePath(profile)
        return config.Folder
            .. "/"
            .. sanitizeFileComponent(profile, "default")
            .. ".json"
    end

    local function setConfigStatus(text)
        local value = tostring(text or "")
        if config.StatusLabel and config.StatusLabel.Set then
            config.StatusLabel:Set(value)
        end
    end

    function window:_SaveConfigMeta()
        if not config.Available then
            return false
        end

        local encoded = jsonEncode({
            Version = 1,
            Selected = config.Selected,
            AutoSave = config.AutoSave,
            AutoLoad = config.AutoLoad,
        })

        if not encoded then
            return false
        end

        local ok = pcall(FileAPI.Write, config.MetaPath, encoded)
        return ok == true
    end

    local function loadConfigMeta()
        if not config.Available or not FileAPI.IsFile(config.MetaPath) then
            return
        end

        local ok, text = pcall(FileAPI.Read, config.MetaPath)
        if not ok then
            return
        end

        local data = jsonDecode(text)
        if type(data) ~= "table" then
            return
        end

        if data.Selected ~= nil then
            config.Selected = sanitizeFileComponent(data.Selected, "default")
        end
        if data.AutoSave ~= nil then
            config.AutoSave = data.AutoSave == true
        end
        if data.AutoLoad ~= nil then
            config.AutoLoad = data.AutoLoad == true
        end
    end

    function window:_SnapshotConfigValues()
        local values = {}

        for key, control in pairs(config.Controls) do
            if control and control.Get then
                local ok, value = pcall(function()
                    return control:Get()
                end)

                if ok then
                    local valueType = typeof(value)
                    if valueType == "boolean"
                        or valueType == "number"
                        or valueType == "string" then
                        values[key] = value
                    end
                end
            end
        end

        return values
    end

    function window:_ConfigFingerprint()
        return jsonEncode(self:_SnapshotConfigValues()) or ""
    end

    function window:_WriteConfig(profile, showNotification)
        if not config.Available then
            setConfigStatus("Configuración no disponible • faltan las APIs de archivo del ejecutor")
            if showNotification then
                VNUS:Notify({
                    Title = "Configuración",
                    Content = "Este ejecutor no expone writefile/readfile/makefolder.",
                    Duration = 3,
                })
            end
            return false
        end

        local cleanProfile = sanitizeFileComponent(profile or config.Selected, "default")
        config.Selected = cleanProfile
        ensureFolderPath(config.Folder)

        local payload = {
            Version = 1,
            VNUSVersion = VNUS.Version,
            ConfigId = config.Id,
            Profile = cleanProfile,
            Values = self:_SnapshotConfigValues(),
        }

        local encoded = jsonEncode(payload)
        if not encoded then
            setConfigStatus("Error al guardar • fallo al codificar el JSON")
            return false
        end

        local ok, err = pcall(FileAPI.Write, configFilePath(cleanProfile), encoded)
        if not ok then
            setConfigStatus("Error al guardar • " .. tostring(err))
            return false
        end

        self:_SaveConfigMeta()
        config.LastFingerprint = self:_ConfigFingerprint()
        setConfigStatus("Guardado • " .. cleanProfile)

        if showNotification then
            VNUS:Notify({
                Title = "Configuración",
                Content = "Guardado " .. cleanProfile,
                Duration = 2,
            })
        end

        return true
    end

    function window:_ApplyConfigValues(values)
        if type(values) ~= "table" then
            return false
        end

        config.Applying = true

        for key, value in pairs(values) do
            local control = config.Controls[key]
            if control and control.Set then
                pcall(function()
                    control:Set(value)
                end)
            else
                -- Guarda el valor hasta que se registre el control correspondiente.
                config.LoadedValues[key] = value
            end
        end

        config.Applying = false
        config.LastFingerprint = self:_ConfigFingerprint()
        return true
    end

    function window:_ReadConfig(profile, showNotification)
        if not config.Available then
            setConfigStatus("Configuración no disponible • faltan las APIs de archivo del ejecutor")
            return false
        end

        local cleanProfile = sanitizeFileComponent(profile or config.Selected, "default")
        local path = configFilePath(cleanProfile)

        if not FileAPI.IsFile(path) then
            setConfigStatus("No encontrado • " .. cleanProfile)
            if showNotification then
                VNUS:Notify({
                    Title = "Configuración",
                    Content = "Configuración no encontrada: " .. cleanProfile,
                    Duration = 2.5,
                })
            end
            return false
        end

        local ok, text = pcall(FileAPI.Read, path)
        if not ok then
            setConfigStatus("Error al cargar • no se pudo leer el archivo")
            return false
        end

        local data = jsonDecode(text)
        if type(data) ~= "table" or type(data.Values) ~= "table" then
            setConfigStatus("Error al cargar • archivo de configuración no válido")
            return false
        end

        config.Selected = cleanProfile
        config.LoadedValues = data.Values
        self:_ApplyConfigValues(data.Values)
        self:_SaveConfigMeta()
        setConfigStatus("Cargado • " .. cleanProfile)

        if showNotification then
            VNUS:Notify({
                Title = "Configuración",
                Content = "Cargado " .. cleanProfile,
                Duration = 2,
            })
        end

        return true
    end

    function window:_DeleteConfig(profile)
        if not config.Available or not FileAPI.DeleteFile then
            setConfigStatus("No se puede eliminar en este ejecutor")
            return false
        end

        local cleanProfile = sanitizeFileComponent(profile or config.Selected, "default")
        local path = configFilePath(cleanProfile)

        if not FileAPI.IsFile(path) then
            setConfigStatus("No encontrado • " .. cleanProfile)
            return false
        end

        local ok = pcall(FileAPI.DeleteFile, path)
        if not ok then
            setConfigStatus("Error al eliminar • " .. cleanProfile)
            return false
        end

        if config.Selected == cleanProfile then
            config.Selected = "default"
        end

        self:_SaveConfigMeta()
        setConfigStatus("Eliminado • " .. cleanProfile)
        return true
    end

    function window:_ListConfigProfiles()
        local found = {}
        local seen = {}

        local function add(name)
            local clean = sanitizeFileComponent(name, "default")
            if not seen[clean] then
                seen[clean] = true
                table.insert(found, clean)
            end
        end

        add(config.Selected)
        add("default")

        if config.Available and FileAPI.ListFiles then
            local ok, files = pcall(FileAPI.ListFiles, config.Folder)
            if ok and type(files) == "table" then
                for _, path in ipairs(files) do
                    local normalized = tostring(path):gsub("\\", "/")
                    local name = normalized:match("([^/]+)%.json$")
                    if name and name ~= "_meta" then
                        add(name)
                    end
                end
            end
        end

        table.sort(found)
        return found
    end

    function window:_RegisterConfigControl(tab, data, control)
        if not config.Enabled
            or not control
            or type(data) ~= "table"
            or data.NoConfig == true then
            return
        end

        local baseName = data.ConfigKey or data.Flag or data.Name or data.Text
        if baseName == nil then
            return
        end

        local key = tostring(tab.Name) .. "." .. tostring(baseName)
        if config.Controls[key] and config.Controls[key] ~= control then
            local suffix = 2
            local original = key
            while config.Controls[key] do
                key = original .. "#" .. tostring(suffix)
                suffix += 1
            end
        end

        config.Controls[key] = control

        local loaded = config.LoadedValues[key]
        if loaded ~= nil and control.Set then
            task.defer(function()
                if not control.Set then
                    return
                end

                config.Applying = true
                pcall(function()
                    control:Set(loaded)
                end)
                config.Applying = false
            end)
        end
    end

    if config.Available then
        ensureFolderPath(config.Folder)
        loadConfigMeta()

        if config.AutoLoad then
            local path = configFilePath(config.Selected)
            if FileAPI.IsFile(path) then
                local ok, text = pcall(FileAPI.Read, path)
                if ok then
                    local data = jsonDecode(text)
                    if type(data) == "table" and type(data.Values) == "table" then
                        config.LoadedValues = data.Values
                    end
                end
            end
        end
    end

    self.Window = window
    SharedUIState.Windows[window] = true

    -- Un redimensionado puede generar varios ViewportSize intermedios; las pasadas
    -- posteriores esperan a que el diseño y AbsoluteSize se actualicen.
    local viewportSettleGeneration = 0

    local function settleViewportResize()
        viewportSettleGeneration += 1
        local generation = viewportSettleGeneration

        task.spawn(function()
            if not (window.ScreenGui and window.ScreenGui.Parent) then
                return
            end

            -- Aplica de inmediato el diseño y la escala solicitados.
            window:ApplyResponsiveLayout()

            -- Espera seis RenderStepped para absorber cambios de cámara, UIScale y
            -- AbsoluteSize.
            for pass = 1, 6 do
                RunService.RenderStepped:Wait()
                if generation ~= viewportSettleGeneration then
                    return
                end
                if not (window.ScreenGui and window.ScreenGui.Parent) then
                    return
                end

                -- Reaplica el diseño y corrige la posición con el rectángulo de Main.
                if pass == 2 or pass == 4 then
                    window:ApplyResponsiveLayout()
                end

                local margin = window.Minimized and 6
                    or (window.ResolvedLayout == "Phone" and 6 or 8)
                window:ClampRenderedToViewport(margin)
            end
        end)
    end

    local function connectViewportCamera(camera)
        if not camera then
            return
        end
        table.insert(window.ResponsiveConnections, camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
            settleViewportResize()
        end))
    end

    connectViewportCamera(workspace.CurrentCamera)
    table.insert(window.ResponsiveConnections, workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
        connectViewportCamera(workspace.CurrentCamera)
        settleViewportResize()
    end))

    ------------------------------------------------------------------------
    -- Arrastre de WindowMover.
    ------------------------------------------------------------------------
    local dragging = false
    local dragInput = nil
    local dragStart = nil
    local startPosition = nil
    local activeTouch = nil
    local closeOpenPopup = function() end

    local function mousePosition(input)
        if input and input.UserInputType == Enum.UserInputType.Touch then
            return Vector2.new(input.Position.X, input.Position.Y)
        end
        local p = UserInputService:GetMouseLocation()
        return Vector2.new(p.X, p.Y)
    end

    local DRAG_EDGE_MARGIN = 6

    local function updateDrag(input)
        if not dragging or not dragStart or not startPosition then
            return
        end

        local current = mousePosition(input)
        local delta = current - dragStart

        -- Posición calculada antes de aplicar los límites del viewport.
        local targetX = startPosition.X.Offset + delta.X
        local targetY = startPosition.Y.Offset + delta.Y

        -- Ajusta la posición con el tamaño actualmente renderizado de la ventana.
        local viewport = getViewportSize()
        local size = window:_RenderedWindowSize(window.Minimized and "Current" or "Expanded")
        local margin = DRAG_EDGE_MARGIN
        local maxX = math.max(margin, viewport.X - size.X - margin)
        local maxY = math.max(margin, viewport.Y - size.Y - margin)
        local clampedX = math.clamp(targetX, margin, maxX)
        local clampedY = math.clamp(targetY, margin, maxY)

        mover.Position = UDim2.new(
            startPosition.X.Scale,
            clampedX,
            startPosition.Y.Scale,
            clampedY
        )
    end

    dragHandle.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then

            closeOpenPopup()
            dragging = true
            window.UserPositioned = true
            dragStart = mousePosition(input)
            startPosition = mover.Position
            activeTouch = input.UserInputType == Enum.UserInputType.Touch and input or nil

            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then
                    dragging = false
                    dragInput = nil
                    dragStart = nil
                    startPosition = nil
                    activeTouch = nil
                end
            end)
        end
    end)

    dragHandle.InputChanged:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseMovement
            or input.UserInputType == Enum.UserInputType.Touch then
            dragInput = input
        end
    end)

    UserInputService.InputChanged:Connect(function(input)
        if not dragging then return end

        if activeTouch then
            if input == activeTouch then
                updateDrag(input)
            end
        elseif input.UserInputType == Enum.UserInputType.MouseMovement then
            -- Usa la posición global del ratón para continuar el arrastre fuera de
            -- la barra de título.
            updateDrag(input)
        end
    end)

    UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or (activeTouch ~= nil and input == activeTouch) then
            dragging = false
            dragInput = nil
            dragStart = nil
            startPosition = nil
            activeTouch = nil
            -- Al soltar, conserva la posición calculada sin aplicar otro ajuste.
        end
    end)

    ------------------------------------------------------------------------
    -- Gestión de menús emergentes.
    ------------------------------------------------------------------------
    function window:ClosePopup()
        local popup = self.OpenPopup
        self.OpenPopup = nil
        if popup and popup.Close then
            popup:Close()
        end
    end

    closeOpenPopup = function()
        window:ClosePopup()
    end

    function window:SetCloseCallback(callback)
        self.CloseCallback = callback
    end

    function window:SetTitle(text)
        local title = tostring(text or "")
        self.TitleLabel.Text = title
        self.MinimizedTitleLabel.Text = title
    end

    function window:SetVisible(state)
        local visible = state == true
        if self.Visible == visible and self.Main and self.Main.Visible == visible then
            return
        end

        self.VisibilityAnimationGeneration += 1
        local generation = self.VisibilityAnimationGeneration
        self.Visible = visible

        if visible then
            self.MinimizedTitleLabel.Visible = self.Minimized
            safeSet(self.Main, "Visible", true)
            safeSet(self.Main, "GroupTransparency", 1)

            if shadow and not self.Minimized then
                safeSet(shadow, "Visible", true)
                safeSet(shadow, "BackgroundTransparency", 1)
                motionTween(
                    shadow,
                    Motion.Visibility,
                    Enum.EasingStyle.Quad,
                    Enum.EasingDirection.Out,
                    {BackgroundTransparency = 0.5}
                )
            end

            motionTween(
                self.Main,
                Motion.Visibility,
                Enum.EasingStyle.Quad,
                Enum.EasingDirection.Out,
                {GroupTransparency = 0}
            )
        else
            self.MinimizedTitleLabel.Visible = false
            self:ClosePopup()

            motionTween(
                self.Main,
                Motion.Visibility,
                Enum.EasingStyle.Quad,
                Enum.EasingDirection.In,
                {GroupTransparency = 1}
            )

            if shadow and shadow.Visible then
                motionTween(
                    shadow,
                    Motion.Visibility,
                    Enum.EasingStyle.Quad,
                    Enum.EasingDirection.In,
                    {BackgroundTransparency = 1}
                )
            end

            task.delay(Motion.Visibility + 0.02, function()
                if generation ~= self.VisibilityAnimationGeneration or self.Visible then
                    return
                end
                safeSet(self.Main, "Visible", false)
                if shadow then
                    safeSet(shadow, "Visible", false)
                end
            end)
        end
    end

    function window:Toggle()
        self:SetVisible(not self.Visible)
    end

    function window:_ApplyToggleKey(key)
        local keyCode

        if typeof(key) == "EnumItem" and key.EnumType == Enum.KeyCode then
            keyCode = key
        else
            keyCode = Enum.KeyCode[tostring(key or "")]
        end

        if not keyCode or keyCode == Enum.KeyCode.Unknown then
            return false
        end

        self.ToggleKeyCode = keyCode
        self.ToggleKeyName = keyCode.Name

        for _, control in ipairs(self.KeybindDisplays or {}) do
            if control and control._SetKeyName then
                control:_SetKeyName(self.ToggleKeyName)
            end
        end

        return true
    end

    function window:SetToggleKey(key)
        local keyCode

        if typeof(key) == "EnumItem" and key.EnumType == Enum.KeyCode then
            keyCode = key
        else
            keyCode = Enum.KeyCode[tostring(key or "")]
        end

        if not keyCode or keyCode == Enum.KeyCode.Unknown then
            return false
        end

        SharedUIState.ToggleKeyName = keyCode.Name

        -- Aplica la nueva tecla a todas las ventanas registradas.
        for otherWindow in pairs(SharedUIState.Windows) do
            if otherWindow and otherWindow._ApplyToggleKey then
                otherWindow:_ApplyToggleKey(keyCode)
            end
        end

        return true
    end

    function window:GetToggleKey()
        return self.ToggleKeyName
    end

    function window:Destroy()
        self:ClosePopup()
        SharedUIState.Windows[self] = nil

        for _, connection in ipairs(self.ResponsiveConnections or {}) do
            pcall(function() connection:Disconnect() end)
        end
        self.ResponsiveConnections = {}

        if SharedUIState.CapturingWindow == self then
            SharedUIState.CapturingWindow = nil
            SharedUIState.CapturingControl = nil
        end

        if self.ScreenGui then
            self.ScreenGui:Destroy()
        end
    end

    function window:SelectTab(tab)
        if not tab or self.CurrentTab == tab then
            return
        end

        self:ClosePopup()
        self.TabAnimationGeneration += 1
        local generation = self.TabAnimationGeneration
        local previous = self.CurrentTab
        local previousIndex = previous and tonumber(previous.Index) or tonumber(tab.Index) or 1
        local nextIndex = tonumber(tab.Index) or previousIndex
        local direction = nextIndex >= previousIndex and 1 or -1
        local travel = window.ResolvedLayout == "Phone" and 10 or 14

        -- Solo la pestaña anterior y la nueva participan en la transición.
        for _, otherTab in ipairs(self.Tabs or {}) do
            if otherTab ~= previous and otherTab ~= tab and otherTab.Container then
                otherTab.Container.Visible = false
                otherTab.Container.GroupTransparency = 0
                otherTab.Container.Position = UDim2.fromOffset(0, 0)
                if otherTab.Highlight then
                    otherTab.Highlight.Visible = false
                    otherTab.Highlight.BackgroundTransparency = 0
                    otherTab.Highlight.Size = UDim2.new(1, 0, 0, 1)
                end
            end
        end

        self.CurrentTab = tab

        if previous then
            motionTween(
                previous.Button,
                Motion.Tab,
                Enum.EasingStyle.Quad,
                Enum.EasingDirection.Out,
                {TextColor3 = Theme.Text}
            )
            motionTween(
                previous.Highlight,
                Motion.Tab * 0.75,
                Enum.EasingStyle.Quad,
                Enum.EasingDirection.In,
                {
                    BackgroundTransparency = 1,
                    Size = UDim2.new(0.18, 0, 0, 1),
                }
            )
            motionTween(
                previous.Container,
                Motion.Tab,
                Enum.EasingStyle.Quart,
                Enum.EasingDirection.Out,
                {
                    GroupTransparency = 1,
                    Position = UDim2.fromOffset(-direction * travel, 0),
                }
            )
        end

        tab.Container.Visible = true
        tab.Container.GroupTransparency = 1
        tab.Container.Position = UDim2.fromOffset(direction * travel, 0)
        tab.Highlight.BackgroundColor3 = Theme.Accent
        tab.Highlight.BackgroundTransparency = 1
        tab.Highlight.Size = UDim2.new(0.18, 0, 0, 1)
        tab.Highlight.Visible = true

        motionTween(
            tab.Button,
            Motion.Tab,
            Enum.EasingStyle.Quad,
            Enum.EasingDirection.Out,
            {TextColor3 = Theme.Accent}
        )
        motionTween(
            tab.Highlight,
            Motion.Tab,
            Enum.EasingStyle.Quart,
            Enum.EasingDirection.Out,
            {
                BackgroundTransparency = 0,
                Size = UDim2.new(1, 0, 0, 1),
            }
        )
        motionTween(
            tab.Container,
            Motion.Tab,
            Enum.EasingStyle.Quart,
            Enum.EasingDirection.Out,
            {
                GroupTransparency = 0,
                Position = UDim2.fromOffset(0, 0),
            }
        )

        if previous then
            task.delay(Motion.Tab + 0.025, function()
                if previous ~= self.CurrentTab and previous.Container and previous.Container.Parent then
                    previous.Container.Visible = false
                    previous.Container.GroupTransparency = 0
                    previous.Container.Position = UDim2.fromOffset(0, 0)
                    previous.Highlight.Visible = false
                    previous.Highlight.BackgroundTransparency = 0
                    previous.Highlight.Size = UDim2.new(1, 0, 0, 1)
                end
            end)
        end

        task.defer(function()
            if not tab.Button.Parent then return end
            local buttonLeft = tab.Button.AbsolutePosition.X - tabBar.AbsolutePosition.X + tabBar.CanvasPosition.X
            local buttonRight = buttonLeft + tab.Button.AbsoluteSize.X
            local visibleLeft = tabBar.CanvasPosition.X
            local visibleRight = visibleLeft + tabBar.AbsoluteSize.X
            local targetX = nil

            if buttonLeft < visibleLeft then
                targetX = math.max(0, buttonLeft - 4)
            elseif buttonRight > visibleRight then
                targetX = math.max(0, buttonRight - tabBar.AbsoluteSize.X + 4)
            end

            if targetX then
                -- Anima CanvasPosition en pasos de RenderStepped.
                local startX = tabBar.CanvasPosition.X
                local started = os.clock()
                local duration = Motion.Tab
                while tabBar.Parent and os.clock() - started < duration do
                    local alpha = math.clamp((os.clock() - started) / duration, 0, 1)
                    local eased = 1 - ((1 - alpha) ^ 3)
                    tabBar.CanvasPosition = Vector2.new(startX + (targetX - startX) * eased, 0)
                    RunService.RenderStepped:Wait()
                end
                if tabBar.Parent then
                    tabBar.CanvasPosition = Vector2.new(targetX, 0)
                end
            end
        end)
    end

    -- Actualiza esta ventana con el atajo compartido vigente.
    if not window:_ApplyToggleKey(SharedUIState.ToggleKeyName) then
        window:_ApplyToggleKey("K")
    end

    ------------------------------------------------------------------------
    -- Pestañas y controles.
    ------------------------------------------------------------------------
    function window:CreateTab(tabName, _icon)
        local tab = {
            Name = tostring(tabName),
            Window = self,
            Sections = {},
            _nextColumn = 1,
            _currentSection = nil,
            Index = #self.Tabs + 1,
        }

        local textSize = TextService:GetTextSize(tab.Name, 13, Enum.Font.Code, Vector2.new(1000, 18))
        local buttonWidth = math.max(38, textSize.X + 10)

        -- Restablece el desplazamiento de la barra al crear una pestaña.
        if #self.Tabs == 0 then
            tabBar.CanvasPosition = Vector2.new(0, 0)
        end

        local button = create("TextButton", {
            Name = "Tab_" .. tab.Name,
            LayoutOrder = #self.Tabs + 1,
            Size = UDim2.fromOffset(buttonWidth, 22),
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            AutoButtonColor = false,
            Font = Enum.Font.Code,
            Text = tab.Name,
            TextSize = 13,
            TextColor3 = Theme.Text,
            ZIndex = 10,
            Parent = tabBar,
        })
        button:SetAttribute("VNUSBaseTabWidth", buttonWidth)

        -- Resaltado de la pestaña activa.
        local highlight = create("Frame", {
            AnchorPoint = Vector2.new(0.5, 0),
            Position = UDim2.new(0.5, 0, 1, -1),
            Size = UDim2.new(1, 0, 0, 1),
            BackgroundColor3 = Theme.Accent,
            BorderSizePixel = 0,
            Visible = false,
            ZIndex = 11,
            Parent = button,
        })
        table.insert(window.AccentObjects, highlight)

        local container = create("CanvasGroup", {
            Name = "Content_" .. tab.Name,
            Size = UDim2.fromScale(1, 1),
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            ClipsDescendants = false,
            GroupTransparency = 0,
            Visible = false,
            ZIndex = 4,
            Parent = columnsHost,
        })

        local columns = {}
        local columnLayouts = {}

        local function updateColumnCanvas(index)
            local scroll = columns[index]
            local layout = columnLayouts[index]
            if not scroll or not layout then
                return
            end

            -- CanvasSize manual evita depender de AutomaticCanvasSize anidado.
            local contentHeight = math.max(0, layout.AbsoluteContentSize.Y + 14)
            scroll.CanvasSize = UDim2.fromOffset(0, contentHeight)
        end

        for index = 1, 2 do
            local leftSide = index == 1
            local scroll = create("ScrollingFrame", {
                Name = "Column" .. tostring(index),
                Position = UDim2.new(leftSide and 0 or 0.5, leftSide and 0 or 4, 0, 0),
                Size = UDim2.new(0.5, -4, 1, 0),
                BackgroundTransparency = 1,
                BorderSizePixel = 0,
                CanvasSize = UDim2.new(),
                AutomaticCanvasSize = Enum.AutomaticSize.None,
                ScrollBarThickness = 2,
                ScrollBarImageColor3 = Color3.fromRGB(60, 60, 60),
                ScrollingDirection = Enum.ScrollingDirection.Y,
                ElasticBehavior = Enum.ElasticBehavior.Never,
                ClipsDescendants = true,
                ZIndex = 4,
                Parent = container,
            })

            local layout = create("UIListLayout", {
                SortOrder = Enum.SortOrder.LayoutOrder,
                Padding = UDim.new(0, 8),
                Parent = scroll,
            })

            create("UIPadding", {
                PaddingTop = UDim.new(0, 8),
                PaddingRight = UDim.new(0, leftSide and 3 or 0),
                PaddingBottom = UDim.new(0, 6),
                Parent = scroll,
            })

            layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
                updateColumnCanvas(index)
            end)

            scroll:GetPropertyChangedSignal("CanvasPosition"):Connect(function()
                if window.OpenPopup then
                    window:ClosePopup()
                end
            end)

            columns[index] = scroll
            columnLayouts[index] = layout
        end

        tab.Button = button
        tab.Highlight = highlight
        tab.Container = container
        tab.Columns = columns

        -- Distribución de secciones:
        --   una sección -> una columna a todo el ancho;
        --   dos o más   -> dos columnas alternas.
        -- La columna se asigna al crear la sección, sin depender de
        -- AbsoluteContentSize.
        local function reflowSections()
            local count = #tab.Sections
            local phoneLayout = window.ResolvedLayout == "Phone"

            if phoneLayout or count <= 1 then
                columns[1].Visible = true
                columns[1].Position = UDim2.new(0, 0, 0, 0)
                columns[1].Size = UDim2.new(1, 0, 1, 0)
                columns[2].Visible = false
                columns[2].CanvasPosition = Vector2.new(0, 0)

                for _, existingSection in ipairs(tab.Sections) do
                    if existingSection.Frame.Parent ~= columns[1] then
                        existingSection.Frame.Parent = columns[1]
                    end
                end
            else
                columns[1].Visible = true
                columns[2].Visible = true
                columns[1].Position = UDim2.new(0, 0, 0, 0)
                columns[1].Size = UDim2.new(0.5, -4, 1, 0)
                columns[2].Position = UDim2.new(0.5, 4, 0, 0)
                columns[2].Size = UDim2.new(0.5, -4, 1, 0)

                for sectionIndex, existingSection in ipairs(tab.Sections) do
                    local targetColumn = ((sectionIndex - 1) % 2) + 1
                    if existingSection.Frame.Parent ~= columns[targetColumn] then
                        existingSection.Frame.Parent = columns[targetColumn]
                    end
                end
            end

            task.defer(function()
                updateColumnCanvas(1)
                updateColumnCanvas(2)
            end)
        end

        tab._ReflowSections = reflowSections

        function tab:CreateSection(sectionName)
            local section = {
                Name = tostring(sectionName or "Sección"),
                Tab = self,
            }

            local frame = create("Frame", {
                Name = "Section_" .. section.Name,
                Size = UDim2.new(1, -2, 0, 24),
                BackgroundColor3 = Theme.SectionInner,
                BackgroundTransparency = 0.5,
                BorderColor3 = Theme.BorderDark,
                BorderSizePixel = 1,
                ClipsDescendants = false,
                ZIndex = 5,
                Parent = columns[1],
            })

            create("UIStroke", {
                Color = Theme.Border,
                Thickness = 1,
                Parent = frame,
            })

            -- El acento es un borde superior y el título se coloca debajo.
            local topAccentLine = create("Frame", {
                Position = UDim2.fromOffset(0, 0),
                Size = UDim2.new(1, 0, 0, 1),
                BackgroundColor3 = Theme.Accent,
                BorderSizePixel = 0,
                ZIndex = 7,
                Parent = frame,
            })
            table.insert(window.AccentObjects, topAccentLine)

            local titleWidth = TextService:GetTextSize(section.Name, 12, Enum.Font.Code, Vector2.new(1000, 16)).X + 6

            local headerPatch = create("Frame", {
                Position = UDim2.fromOffset(8, 3),
                Size = UDim2.fromOffset(titleWidth, 16),
                BackgroundTransparency = 1,
                BorderSizePixel = 0,
                ZIndex = 7,
                Parent = frame,
            })

            local header = codeLabel(headerPatch, section.Name, 12, Theme.Text, 8)
            header.Position = UDim2.fromOffset(0, 0)
            header.Size = UDim2.new(1, 0, 1, 0)
            header.TextXAlignment = Enum.TextXAlignment.Left

            local body = create("Frame", {
                Name = "Body",
                Position = UDim2.fromOffset(8, 22),
                Size = UDim2.new(1, -16, 0, 0),
                BackgroundTransparency = 1,
                BorderSizePixel = 0,
                ClipsDescendants = false,
                ZIndex = 6,
                Parent = frame,
            })

            local bodyLayout = create("UIListLayout", {
                SortOrder = Enum.SortOrder.LayoutOrder,
                Padding = UDim.new(0, 4),
                Parent = body,
            })

            create("UIPadding", {
                PaddingBottom = UDim.new(0, 8),
                Parent = body,
            })

            local function updateSectionSize()
                local bodyHeight = math.max(0, bodyLayout.AbsoluteContentSize.Y + 8)
                body.Size = UDim2.new(1, -16, 0, bodyHeight)
                frame.Size = UDim2.new(1, -2, 0, math.max(36, 22 + bodyHeight))
            end

            bodyLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
                updateSectionSize()
                task.defer(function()
                    updateColumnCanvas(1)
                    updateColumnCanvas(2)
                end)
            end)

            section.Frame = frame
            section.Body = body

            function section:Set(newName)
                self.Name = tostring(newName or "")
                header.Text = self.Name
                local newWidth = TextService:GetTextSize(self.Name, 12, Enum.Font.Code, Vector2.new(1000, 16)).X + 6
                headerPatch.Size = UDim2.fromOffset(newWidth, 14)
            end

            table.insert(self.Sections, section)
            self._currentSection = section
            reflowSections()

            task.defer(updateSectionSize)
            return section
        end

        local function addControlFrame(height)
            local section = getCurrentSection(tab)
            local phoneFactor = window.ResolvedLayout == "Phone" and 1.10 or 1
            local row = create("Frame", {
                Size = UDim2.new(1, 0, 0, math.floor(height * phoneFactor + 0.5)),
                BackgroundTransparency = 1,
                BorderSizePixel = 0,
                ClipsDescendants = false,
                ZIndex = 6,
                Parent = section.Body,
            })
            row:SetAttribute("VNUSControlBaseHeight", height)
            return row
        end

        function tab:CreateDivider()
            local row = addControlFrame(9)
            local divider = create("Frame", {
                Position = UDim2.fromOffset(0, 4),
                Size = UDim2.new(1, 0, 0, 1),
                BackgroundColor3 = Theme.Border,
                BorderSizePixel = 0,
                ZIndex = 7,
                Parent = row,
            })

            local object = {}
            function object:Set(visible)
                divider.Visible = visible ~= false
            end
            return object
        end

        -- Mide el texto envuelto y guarda la altura base para recalcularla al
        -- cambiar el diseño.
        local function measureRowBase(row, text, minimumHeight, reserveTop)
            local width = row.AbsoluteSize.X
            if width < 8 then return end
            local measured = TextService:GetTextSize(
                tostring(text or ""), 11, Enum.Font.Code, Vector2.new(width, 4096)
            ).Y
            local base = math.max(minimumHeight or 17, math.ceil(measured) + 2 + (reserveTop or 0))
            local current = row:GetAttribute("VNUSControlBaseHeight") or 0
            if math.abs(current - base) < 0.5 then return end
            row:SetAttribute("VNUSControlBaseHeight", base)
            local factor = window.ResolvedLayout == "Phone" and 1.10 or 1
            row.Size = UDim2.new(1, 0, 0, math.floor(base * factor + 0.5))
        end

        local function bindRowHeight(row, getText, minimumHeight, reserveTop)
            local function refresh()
                measureRowBase(row, getText(), minimumHeight, reserveTop)
            end
            row:GetPropertyChangedSignal("AbsoluteSize"):Connect(refresh)
            task.defer(refresh)
            return refresh
        end

        function tab:CreateLabel(text, _icon, color)
            local row = addControlFrame(17)
            local label = codeLabel(row, text, 11, color or Theme.DimText, 7)
            label.Size = UDim2.fromScale(1, 1)
            label.TextWrapped = true
            label.TextTruncate = Enum.TextTruncate.None
            local refreshHeight = bindRowHeight(row, function() return label.Text end, 17)

            local object = {
                Label = label,
            }

            function object:Set(value, _newIcon, newColor)
                safeSet(label, "Text", tostring(value or ""))
                if typeof(newColor) == "Color3" then
                    safeSet(label, "TextColor3", newColor)
                end
                task.defer(refreshHeight)
            end

            return object
        end

        function tab:CreateParagraph(data)
            data = data or {}

            local contentText = tostring(data.Content or "")
            local rowHeight = tonumber(data.Height) or 50
            if #contentText > 140 then
                rowHeight = 68
            elseif #contentText > 75 then
                rowHeight = 58
            end

            local row = addControlFrame(rowHeight)

            local title = codeLabel(row, data.Title or "", 12, Theme.BrightText, 7)
            title.Position = UDim2.fromOffset(0, 0)
            title.Size = UDim2.new(1, 0, 0, 16)

            local body = codeLabel(row, contentText, 11, Theme.DimText, 7)
            body.Position = UDim2.fromOffset(0, 16)
            body.Size = UDim2.new(1, 0, 1, -16)
            body.TextWrapped = true
            body.TextYAlignment = Enum.TextYAlignment.Top
            local refreshHeight = bindRowHeight(row, function() return body.Text end, rowHeight, 16)

            local object = {}
            function object:Set(nextData)
                if type(nextData) == "table" then
                    if nextData.Title ~= nil then
                        safeSet(title, "Text", tostring(nextData.Title))
                    end
                    if nextData.Content ~= nil then
                        safeSet(body, "Text", tostring(nextData.Content))
                    end
                else
                    safeSet(body, "Text", tostring(nextData or ""))
                end
                task.defer(refreshHeight)
            end

            return object
        end

        function tab:CreateButton(data)
            data = data or {}

            -- Los nombres heredados para ocultar la interfaz no crean un botón
            -- visible; devuelven un control inerte.
            local requestedName = tostring(data.Name or data.Text or "Botón")
            local normalizedName = string.lower(requestedName)
            normalizedName = normalizedName:gsub("%s+", " ")

            local legacyUIButtons = {
                ["hide ui"] = true,
                ["toggle ui"] = true,
                ["hide/show ui"] = true,
                ["show/hide ui"] = true,
                ["hide / show ui"] = true,
                ["show / hide ui"] = true,
            }

            if legacyUIButtons[normalizedName] then
                local hiddenObject = {}
                function hiddenObject:Set(_value) end
                function hiddenObject:SetText(_value) end
                function hiddenObject:Get() return false end
                return hiddenObject
            end

            local row = addControlFrame(24)

            local buttonControl = create("TextButton", {
                Position = UDim2.fromOffset(0, 1),
                Size = UDim2.new(1, 0, 1, -2),
                BackgroundColor3 = Theme.Element,
                BorderColor3 = Theme.BorderDark,
                BorderSizePixel = 1,
                AutoButtonColor = false,
                Font = Enum.Font.Code,
                Text = tostring(data.Name or data.Text or "Botón"),
                TextColor3 = Theme.Text,
                TextSize = 11,
                ZIndex = 7,
                Parent = row,
            })
            setHover(buttonControl, Theme.Element, Theme.ElementHover)

            buttonControl.MouseButton1Click:Connect(function()
                safeCallback(data.Callback)
            end)

            local object = {
                Button = buttonControl,
            }

            function object:Set(value)
                buttonControl.Text = tostring(value or "")
            end

            function object:SetText(value)
                buttonControl.Text = tostring(value or "")
            end

            return object
        end

        function tab:CreateToggle(data)
            data = data or {}

            local row = addControlFrame(18)
            local state = data.CurrentValue == true
            local flag = data.Flag

            local hit = create("TextButton", {
                Size = UDim2.fromScale(1, 1),
                BackgroundTransparency = 1,
                BorderSizePixel = 0,
                AutoButtonColor = false,
                Text = "",
                ZIndex = 9,
                Parent = row,
            })

            local box = create("Frame", {
                Position = UDim2.fromOffset(2, 3),
                Size = UDim2.fromOffset(12, 12),
                BackgroundColor3 = Color3.fromRGB(15, 15, 15),
                BorderColor3 = Theme.BorderDark,
                BorderSizePixel = 1,
                ZIndex = 7,
                Parent = row,
            })
            create("UIStroke", { Color = Theme.Border, Thickness = 1, Parent = box })

            local fill = create("Frame", {
                AnchorPoint = Vector2.new(0.5, 0.5),
                Position = UDim2.fromScale(0.5, 0.5),
                Size = state and UDim2.new(1, -4, 1, -4) or UDim2.fromOffset(0, 0),
                BackgroundColor3 = Theme.Accent,
                BackgroundTransparency = state and 0 or 1,
                BorderSizePixel = 0,
                Visible = true,
                ZIndex = 9,
                Parent = box,
            })
            table.insert(window.AccentObjects, fill)

            local label = codeLabel(row, data.Name or data.Text or "Activar/Desactivar", 12, state and Theme.BrightText or Theme.DimText, 7)
            label.Position = UDim2.fromOffset(22, 0)
            label.Size = UDim2.new(1, -22, 1, 0)
            label.TextTruncate = Enum.TextTruncate.AtEnd

            local object = {}
            local toggleGeneration = 0

            local function apply(value, invokeCallback)
                state = value == true
                toggleGeneration += 1
                local generation = toggleGeneration

                motionTween(
                    fill,
                    Motion.Toggle,
                    Enum.EasingStyle.Back,
                    Enum.EasingDirection.Out,
                    {
                        Size = state and UDim2.new(1, -4, 1, -4) or UDim2.fromOffset(0, 0),
                        BackgroundTransparency = state and 0 or 1,
                    }
                )
                motionTween(
                    label,
                    Motion.Toggle,
                    Enum.EasingStyle.Quad,
                    Enum.EasingDirection.Out,
                    {TextColor3 = state and Theme.BrightText or Theme.DimText}
                )

                if not state then
                    task.delay(Motion.Toggle + 0.02, function()
                        if generation == toggleGeneration and not state and fill.Parent then
                            fill.Size = UDim2.fromOffset(0, 0)
                            fill.BackgroundTransparency = 1
                        end
                    end)
                end

                if flag then
                    VNUS.Flags[flag] = state
                end

                if invokeCallback then
                    safeCallback(data.Callback, state)
                end
            end

            function object:Set(value)
                apply(value, true)
            end

            function object:Get()
                return state
            end

            hit.MouseButton1Click:Connect(function()
                apply(not state, true)
            end)

            if flag then
                VNUS.Flags[flag] = state
            end

            window:_RegisterConfigControl(tab, data, object)
            return object
        end

        function tab:CreateDropdown(data)
            data = data or {}

            local row = addControlFrame(40)
            local label = codeLabel(row, data.Name or "Desplegable", 12, Theme.Text, 7)
            label.Size = UDim2.new(1, 0, 0, 16)

            local options = {}
            for _, option in ipairs(data.Options or {}) do
                table.insert(options, option)
            end

            local current = normalizeDropdownValue(data.CurrentOption)
            if current == nil then
                current = options[1]
            end

            local selector = create("TextButton", {
                Position = UDim2.fromOffset(0, 18),
                Size = UDim2.new(1, 0, 0, 20),
                BackgroundColor3 = Theme.Element,
                BorderColor3 = Theme.BorderDark,
                BorderSizePixel = 1,
                AutoButtonColor = false,
                Font = Enum.Font.Code,
                Text = "  " .. tostring(current or "Seleccionar..."),
                TextColor3 = Theme.Text,
                TextSize = 11,
                TextXAlignment = Enum.TextXAlignment.Left,
                ZIndex = 8,
                Parent = row,
            })
            setHover(selector, Theme.Element, Theme.ElementHover)

            local arrow = codeLabel(selector, "v", 10, Theme.DimText, 9)
            arrow.AnchorPoint = Vector2.new(1, 0)
            arrow.Position = UDim2.new(1, -3, 0, 0)
            arrow.Size = UDim2.fromOffset(12, 20)
            arrow.TextXAlignment = Enum.TextXAlignment.Center

            local object = {}
            local flag = data.Flag
            local popup = nil
            local blocker = nil
            local popupGeneration = 0
            local popupOpensUpward = false
            local popupTargetPosition = nil
            local popupTargetHeight = 0

            local function apply(value, invokeCallback)
                if value == nil then
                    return
                end

                current = value
                selector.Text = "  " .. tostring(current)

                if flag then
                    VNUS.Flags[flag] = current
                end

                if invokeCallback then
                    safeCallback(data.Callback, {current})
                end
            end

            local function closePopup()
                popupGeneration += 1
                local generation = popupGeneration
                local oldPopup = popup
                popup = nil

                if blocker then
                    blocker:Destroy()
                    blocker = nil
                end

                motionTween(
                    arrow,
                    Motion.Popup,
                    Enum.EasingStyle.Quad,
                    Enum.EasingDirection.Out,
                    {Rotation = 0, TextColor3 = Theme.DimText}
                )

                if oldPopup and oldPopup.Parent then
                    local targetPosition = oldPopup.Position
                    if popupOpensUpward then
                        targetPosition = UDim2.fromOffset(
                            oldPopup.Position.X.Offset,
                            oldPopup.Position.Y.Offset + oldPopup.AbsoluteSize.Y
                        )
                    end

                    motionTween(
                        oldPopup,
                        Motion.Popup,
                        Enum.EasingStyle.Quad,
                        Enum.EasingDirection.In,
                        {
                            Size = UDim2.fromOffset(oldPopup.Size.X.Offset, 1),
                            Position = targetPosition,
                            BackgroundTransparency = 1,
                        }
                    )

                    task.delay(Motion.Popup + 0.02, function()
                        if oldPopup and oldPopup.Parent then
                            oldPopup:Destroy()
                        end
                    end)
                end

                if window.OpenPopup == object then
                    window.OpenPopup = nil
                end
            end

            function object:Close()
                closePopup()
            end

            -- El menú se crea en popupLayer y se abre arriba si no cabe debajo del selector.
            local function openPopup()
                if window.OpenPopup and window.OpenPopup ~= object then
                    window.OpenPopup:Close()
                end

                closePopup()

                local selectorPosition = selector.AbsolutePosition
                local selectorSize = selector.AbsoluteSize
                local itemHeight = window.ResolvedLayout == "Phone" and 28 or 20
                local maxVisible = tonumber(data.MaxVisible) or (window.ResolvedLayout == "Phone" and 6 or 8)
                local visibleCount = math.min(#options, maxVisible)
                local menuHeight = math.max(itemHeight + 2, visibleCount * itemHeight + 2)

                local viewport = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or Vector2.new(1920, 1080)
                local menuY = selectorPosition.Y + selectorSize.Y + 1
                popupOpensUpward = false

                if menuY + menuHeight > viewport.Y - 6 then
                    menuY = selectorPosition.Y - menuHeight - 1
                    popupOpensUpward = true
                end

                popupTargetPosition = UDim2.fromOffset(selectorPosition.X, menuY)
                popupTargetHeight = menuHeight

                blocker = create("TextButton", {
                    Size = UDim2.fromScale(1, 1),
                    BackgroundTransparency = 1,
                    BorderSizePixel = 0,
                    AutoButtonColor = false,
                    Text = "",
                    ZIndex = 501,
                    Parent = popupLayer,
                })

                blocker.MouseButton1Click:Connect(closePopup)

                local popupWidth = math.max(80, selectorSize.X)
                local startY = popupOpensUpward and (menuY + menuHeight) or menuY

                popup = create("ScrollingFrame", {
                    Position = UDim2.fromOffset(selectorPosition.X, startY),
                    Size = UDim2.fromOffset(popupWidth, 1),
                    BackgroundColor3 = Color3.fromRGB(20, 20, 20),
                    BackgroundTransparency = 1,
                    BorderColor3 = Theme.Border,
                    BorderSizePixel = 1,
                    CanvasSize = UDim2.new(),
                    AutomaticCanvasSize = Enum.AutomaticSize.Y,
                    ScrollBarThickness = #options > maxVisible and 3 or 0,
                    ScrollBarImageColor3 = Color3.fromRGB(90, 90, 90),
                    ScrollingDirection = Enum.ScrollingDirection.Y,
                    ElasticBehavior = Enum.ElasticBehavior.Never,
                    ClipsDescendants = true,
                    ZIndex = 510,
                    Parent = popupLayer,
                })

                create("UIListLayout", {
                    SortOrder = Enum.SortOrder.LayoutOrder,
                    Padding = UDim.new(0, 0),
                    Parent = popup,
                })

                for index, value in ipairs(options) do
                    local optionButton = create("TextButton", {
                        LayoutOrder = index,
                        Size = UDim2.new(1, 0, 0, itemHeight),
                        BackgroundColor3 = value == current and Color3.fromRGB(38, 38, 38) or Color3.fromRGB(25, 25, 25),
                        BorderSizePixel = 0,
                        AutoButtonColor = false,
                        Font = Enum.Font.Code,
                        Text = "  " .. tostring(value),
                        TextColor3 = value == current and Theme.BrightText or Theme.Text,
                        TextSize = window.ResolvedLayout == "Phone" and 12 or 11,
                        TextXAlignment = Enum.TextXAlignment.Left,
                        ZIndex = 512,
                        Parent = popup,
                    })

                    setHover(
                        optionButton,
                        value == current and Color3.fromRGB(38, 38, 38) or Color3.fromRGB(25, 25, 25),
                        Theme.Element
                    )

                    optionButton.MouseButton1Click:Connect(function()
                        apply(value, true)
                        closePopup()
                    end)
                end

                popupGeneration += 1
                local generation = popupGeneration

                motionTween(
                    popup,
                    Motion.Popup,
                    Enum.EasingStyle.Quart,
                    Enum.EasingDirection.Out,
                    {
                        Position = popupTargetPosition,
                        Size = UDim2.fromOffset(popupWidth, popupTargetHeight),
                        BackgroundTransparency = 0,
                    }
                )
                motionTween(
                    arrow,
                    Motion.Popup,
                    Enum.EasingStyle.Quart,
                    Enum.EasingDirection.Out,
                    {Rotation = 180, TextColor3 = Theme.BrightText}
                )

                window.OpenPopup = object
            end

            selector.MouseButton1Click:Connect(function()
                if window.OpenPopup == object then
                    closePopup()
                else
                    openPopup()
                end
            end)

            function object:Set(value)
                apply(normalizeDropdownValue(value), true)
            end

            function object:Get()
                return current
            end

            function object:Refresh(newOptions)
                closePopup()

                options = {}
                for _, option in ipairs(newOptions or {}) do
                    table.insert(options, option)
                end

                if current == nil or not table.find(options, current) then
                    current = options[1]
                    selector.Text = "  " .. tostring(current or "Seleccionar...")
                    if flag then
                        VNUS.Flags[flag] = current
                    end
                end
            end

            if flag and current ~= nil then
                VNUS.Flags[flag] = current
            end

            window:_RegisterConfigControl(tab, data, object)
            return object
        end

        function tab:CreateSlider(data)
            data = data or {}

            -- El control deslizante muestra el valor dentro de una barra de 14 px.
            local row = addControlFrame(34)
            local minimum = tonumber(data.Range and data.Range[1] or data.Min) or 0
            local maximum = tonumber(data.Range and data.Range[2] or data.Max) or 100
            local increment = tonumber(data.Increment) or 1
            local suffix = tostring(data.Suffix or "")

            local value = tonumber(data.CurrentValue or data.Value) or minimum
            value = math.clamp(value, minimum, maximum)

            local label = codeLabel(row, data.Name or "Control deslizante", 11, Theme.DimText, 7)
            label.Size = UDim2.new(1, 0, 0, 14)

            local rail = create("Frame", {
                Position = UDim2.fromOffset(0, 18),
                Size = UDim2.new(1, 0, 0, 14),
                BackgroundColor3 = Theme.Element,
                BorderColor3 = Theme.BorderDark,
                BorderSizePixel = 1,
                Active = true,
                ZIndex = 7,
                Parent = row,
            })

            local fill = create("Frame", {
                Size = UDim2.new((value - minimum) / math.max(maximum - minimum, 1), 0, 1, 0),
                BackgroundColor3 = Theme.Accent,
                BorderSizePixel = 0,
                ZIndex = 8,
                Parent = rail,
            })
            table.insert(window.AccentObjects, fill)

            -- El texto del valor se centra dentro de rail.
            local valueLabel = codeLabel(rail, tostring(value) .. suffix, 11, Theme.BrightText, 9)
            valueLabel.Size = UDim2.fromScale(1, 1)
            valueLabel.TextXAlignment = Enum.TextXAlignment.Center

            local draggingSlider = false
            local flag = data.Flag
            local object = {}

            local function apply(nextValue, invokeCallback)
                nextValue = tonumber(nextValue)
                if not nextValue then
                    return
                end

                nextValue = math.clamp(nextValue, minimum, maximum)
                nextValue = math.floor(nextValue / increment + 0.5) * increment

                if increment < 1 then
                    local decimals = math.max(0, math.ceil(-math.log10(increment)))
                    local factor = 10 ^ decimals
                    nextValue = math.floor(nextValue * factor + 0.5) / factor
                end

                value = nextValue
                valueLabel.Text = tostring(value) .. suffix
                local targetFill = UDim2.new(
                    (value - minimum) / math.max(maximum - minimum, 1),
                    0,
                    1,
                    0
                )
                if draggingSlider then
                    fill.Size = targetFill
                else
                    motionTween(
                        fill,
                        Motion.Toggle,
                        Enum.EasingStyle.Quad,
                        Enum.EasingDirection.Out,
                        {Size = targetFill}
                    )
                end

                if flag then
                    VNUS.Flags[flag] = value
                end

                if invokeCallback then
                    safeCallback(data.Callback, value)
                end
            end

            local function fromPosition(x)
                local alpha = math.clamp(
                    (x - rail.AbsolutePosition.X) / math.max(rail.AbsoluteSize.X, 1),
                    0,
                    1
                )
                apply(minimum + (maximum - minimum) * alpha, true)
            end

            rail.InputBegan:Connect(function(input)
                if input.UserInputType == Enum.UserInputType.MouseButton1
                    or input.UserInputType == Enum.UserInputType.Touch then
                    draggingSlider = true
                    fromPosition(input.Position.X)
                end
            end)

            UserInputService.InputChanged:Connect(function(input)
                if draggingSlider and (
                    input.UserInputType == Enum.UserInputType.MouseMovement
                    or input.UserInputType == Enum.UserInputType.Touch
                ) then
                    fromPosition(input.Position.X)
                end
            end)

            UserInputService.InputEnded:Connect(function(input)
                if input.UserInputType == Enum.UserInputType.MouseButton1
                    or input.UserInputType == Enum.UserInputType.Touch then
                    draggingSlider = false
                end
            end)

            function object:Set(nextValue)
                apply(nextValue, true)
            end

            function object:Get()
                return value
            end

            if flag then
                VNUS.Flags[flag] = value
            end

            window:_RegisterConfigControl(tab, data, object)
            return object
        end

        function tab:CreateInput(data)
            data = data or {}

            local row = addControlFrame(40)

            local label = codeLabel(row, data.Name or "Campo de texto", 11, Theme.Text, 7)
            label.Size = UDim2.new(1, 0, 0, 16)

            local box = create("TextBox", {
                Position = UDim2.fromOffset(0, 18),
                Size = UDim2.new(1, 0, 0, 20),
                BackgroundColor3 = Theme.Element,
                BorderColor3 = Theme.BorderDark,
                BorderSizePixel = 1,
                ClearTextOnFocus = false,
                Font = Enum.Font.Code,
                Text = tostring(data.CurrentValue or ""),
                PlaceholderText = tostring(data.PlaceholderText or ""),
                TextColor3 = Theme.Text,
                PlaceholderColor3 = Theme.DimText,
                TextSize = 11,
                TextXAlignment = Enum.TextXAlignment.Left,
                ZIndex = 8,
                Parent = row,
            })

            create("UIPadding", {
                PaddingLeft = UDim.new(0, 6),
                PaddingRight = UDim.new(0, 6),
                Parent = box,
            })

            local current = box.Text
            local flag = data.Flag
            local object = {}

            local function apply(value, invokeCallback)
                current = tostring(value or "")
                box.Text = current

                if flag then
                    VNUS.Flags[flag] = current
                end

                if invokeCallback then
                    safeCallback(data.Callback, current)
                end
            end

            box.FocusLost:Connect(function()
                current = box.Text

                if flag then
                    VNUS.Flags[flag] = current
                end

                safeCallback(data.Callback, current)

                if data.RemoveTextAfterFocusLost then
                    box.Text = ""
                end
            end)

            function object:Set(value)
                apply(value, true)
            end

            function object:Get()
                return current
            end

            if flag then
                VNUS.Flags[flag] = current
            end

            window:_RegisterConfigControl(tab, data, object)
            return object
        end

        function tab:CreateKeybind(data)
            data = data or {}

            local row = addControlFrame(40)

            local label = codeLabel(row, data.Name or "Tecla para mostrar/ocultar la interfaz", 11, Theme.Text, 7)
            label.Size = UDim2.new(1, 0, 0, 16)

            local bindButton = create("TextButton", {
                Position = UDim2.fromOffset(0, 18),
                Size = UDim2.new(1, 0, 0, 20),
                BackgroundColor3 = Theme.Element,
                BorderColor3 = Theme.BorderDark,
                BorderSizePixel = 1,
                AutoButtonColor = false,
                Font = Enum.Font.Code,
                Text = "",
                TextColor3 = Theme.Text,
                TextSize = 11,
                ZIndex = 8,
                Parent = row,
            })
            create("UIStroke", {Color = Theme.Border, Thickness = 1, Parent = bindButton})
            setHover(bindButton, Theme.Element, Theme.ElementHover)

            local object = {
                Button = bindButton,
                Callback = data.Callback,
                CurrentKey = window.ToggleKeyName,
                Capturing = false,
            }

            function object:_SetKeyName(keyName)
                self.CurrentKey = tostring(keyName or "K")
                self.Capturing = false
                bindButton.Text = "[ " .. self.CurrentKey .. " ]"
                bindButton.TextColor3 = Theme.Text
            end

            function object:Set(value)
                local previous = window.ToggleKeyName
                if window:SetToggleKey(value) then
                    self:_SetKeyName(window.ToggleKeyName)
                    if previous ~= window.ToggleKeyName then
                        safeCallback(self.Callback, window.ToggleKeyName)
                    end
                    return true
                end
                return false
            end

            function object:Get()
                return window.ToggleKeyName
            end

            function object:CancelCapture()
                if SharedUIState.CapturingControl == self then
                    SharedUIState.CapturingControl = nil
                    SharedUIState.CapturingWindow = nil
                end
                self:_SetKeyName(window.ToggleKeyName)
            end

            -- Al pulsar el botón, SharedUIState registra quién capturará la próxima tecla.
            bindButton.MouseButton1Click:Connect(function()
                local previousControl = SharedUIState.CapturingControl
                if previousControl and previousControl ~= object and previousControl.CancelCapture then
                    previousControl:CancelCapture()
                end

                window:ClosePopup()
                SharedUIState.CapturingWindow = window
                SharedUIState.CapturingControl = object
                object.Capturing = true
                bindButton.Text = "[ pulsa una tecla... ]"
                bindButton.TextColor3 = Theme.Accent
            end)

            object:_SetKeyName(window.ToggleKeyName)
            table.insert(window.KeybindDisplays, object)

            return object
        end

        button.MouseEnter:Connect(function()
            if window.CurrentTab ~= tab and button.Parent then
                motionTween(
                    button,
                    Motion.Hover,
                    Enum.EasingStyle.Quad,
                    Enum.EasingDirection.Out,
                    {TextColor3 = Theme.BrightText}
                )
            end
        end)

        button.MouseLeave:Connect(function()
            if window.CurrentTab ~= tab and button.Parent then
                motionTween(
                    button,
                    Motion.Hover,
                    Enum.EasingStyle.Quad,
                    Enum.EasingDirection.Out,
                    {TextColor3 = Theme.Text}
                )
            end
        end)

        button.MouseButton1Click:Connect(function()
            window:SelectTab(tab)
        end)

        table.insert(self.Tabs, tab)

        -- Al crear una pestaña Ajustes o Settings, se inyectan los controles integrados.
        if isSettingsTabName(tab.Name)
            and settings.DisableBuiltInResponsiveUI ~= true then

            tab:CreateSection("Interfaz")

            if settings.DisableBuiltInUIKeybind ~= true then
                tab:CreateKeybind({
                    Name = "Tecla para mostrar/ocultar la interfaz",
                    Callback = function(keyName)
                        VNUS:Notify({
                            Title = "Tecla de la interfaz",
                            Content = "Todas las interfaces de VNUS usan ahora " .. tostring(keyName),
                            Duration = 2.5,
                        })
                    end,
                })
            end

            tab:CreateDropdown({
                Name = "Diseño de la interfaz",
                Options = {LAYOUT_MODE_LABELS.Auto, LAYOUT_MODE_LABELS.Desktop, LAYOUT_MODE_LABELS.Phone},
                CurrentOption = {getLayoutModeLabel(normalizeLayoutMode(SharedUIState.LayoutMode))},
                NoConfig = true,
                Callback = function(option)
                    local selected = normalizeDropdownValue(option)
                    window:SetLayoutMode(selected)
                end,
            })

            tab:CreateSlider({
                Name = "Tamaño de la interfaz",
                Range = {75, 125},
                Increment = 5,
                CurrentValue = math.clamp(tonumber(SharedUIState.UIScalePercent) or 100, 75, 125),
                Suffix = "%",
                NoConfig = true,
                Callback = function(value)
                    window:SetUIScalePercent(value)
                end,
            })

            window.DeviceStatusLabel = tab:CreateLabel("Detectando la pantalla...")
            if settings.DisableBuiltInUIKeybind ~= true then
                tab:CreateLabel("Haz clic en la caja de la tecla y luego pulsa una tecla. Escape cancela.")
            end
        end

        if isSettingsTabName(tab.Name)
            and settings.DisableBuiltInConfigs ~= true
            and not self._CreatingConfigTab then
            task.defer(function()
                if self.ScreenGui and self.ScreenGui.Parent then
                    self:_EnsureConfigTab()
                end
            end)
        end

        if #self.Tabs == 1 then
            task.defer(function()
                if button.Parent then
                    tabBar.CanvasPosition = Vector2.new(0, 0)
                    self:SelectTab(tab)
                end
            end)
        end

        task.defer(function()
            if window.ScreenGui and window.ScreenGui.Parent then
                window:ApplyResponsiveLayout()
            end
        end)

        return tab
    end

    function window:_EnsureConfigTab()
        if self._ConfigTab or self._CreatingConfigTab or not config.Enabled then
            return self._ConfigTab
        end

        self._CreatingConfigTab = true
        local tab = self:CreateTab("Configuración")
        self._CreatingConfigTab = false
        self._ConfigTab = tab

        tab:CreateSection("Perfiles")

        config.StatusLabel = tab:CreateLabel(
            config.Available
                and ("Listo • " .. config.Selected)
                or "No disponible • faltan las APIs de archivo del ejecutor"
        )

        if not config.Available then
            tab:CreateParagraph({
                Title = "Configuración persistente no disponible",
                Content = "Este ejecutor necesita writefile, readfile, isfile y makefolder para guardar la configuración. El resto de VNUS funciona con normalidad.",
                Height = 64,
            })
            return tab
        end

        config.ProfilesDropdown = tab:CreateDropdown({
            Name = "Perfil de configuración",
            Options = self:_ListConfigProfiles(),
            CurrentOption = {config.Selected},
            NoConfig = true,
            Callback = function(option)
                local value = normalizeDropdownValue(option)
                if value ~= nil then
                    config.Selected = sanitizeFileComponent(value, "default")
                    if config.ProfileInput and config.ProfileInput.Set then
                        config.ProfileInput:Set(config.Selected)
                    end
                    self:_SaveConfigMeta()
                    setConfigStatus("Seleccionado • " .. config.Selected)
                end
            end,
        })

        config.ProfileInput = tab:CreateInput({
            Name = "Nombre del perfil",
            CurrentValue = config.Selected,
            PlaceholderText = "default",
            NoConfig = true,
            Callback = function(value)
                config.PendingProfile = sanitizeFileComponent(value, config.Selected)
            end,
        })

        tab:CreateButton({
            Name = "Guardar / Crear perfil",
            Callback = function()
                local profile = config.PendingProfile or config.Selected
                config.Selected = sanitizeFileComponent(profile, "default")
                self:_WriteConfig(config.Selected, true)

                if config.ProfilesDropdown and config.ProfilesDropdown.Refresh then
                    config.ProfilesDropdown:Refresh(self:_ListConfigProfiles())
                    config.ProfilesDropdown:Set(config.Selected)
                end
            end,
        })

        tab:CreateButton({
            Name = "Cargar perfil seleccionado",
            Callback = function()
                self:_ReadConfig(config.Selected, true)
            end,
        })

        tab:CreateButton({
            Name = "Actualizar perfiles",
            Callback = function()
                if config.ProfilesDropdown and config.ProfilesDropdown.Refresh then
                    config.ProfilesDropdown:Refresh(self:_ListConfigProfiles())
                    config.ProfilesDropdown:Set(config.Selected)
                end
                setConfigStatus("Perfiles actualizados")
            end,
        })

        tab:CreateButton({
            Name = "Eliminar perfil seleccionado",
            Callback = function()
                local deleted = config.Selected
                if self:_DeleteConfig(deleted) then
                    if config.ProfilesDropdown and config.ProfilesDropdown.Refresh then
                        config.ProfilesDropdown:Refresh(self:_ListConfigProfiles())
                        config.ProfilesDropdown:Set(config.Selected)
                    end
                    if config.ProfileInput and config.ProfileInput.Set then
                        config.ProfileInput:Set(config.Selected)
                    end
                    VNUS:Notify({
                        Title = "Configuración",
                        Content = "Eliminado " .. tostring(deleted),
                        Duration = 2,
                    })
                end
            end,
        })

        tab:CreateSection("Automatización")

        tab:CreateToggle({
            Name = "Guardado automático",
            CurrentValue = config.AutoSave,
            NoConfig = true,
            Callback = function(value)
                config.AutoSave = value == true
                self:_SaveConfigMeta()
                if config.AutoSave then
                    self:_WriteConfig(config.Selected, false)
                end
                setConfigStatus(
                    config.AutoSave
                        and ("Guardado automático ACTIVADO • " .. config.Selected)
                        or "Guardado automático DESACTIVADO"
                )
            end,
        })

        tab:CreateToggle({
            Name = "Carga automática",
            CurrentValue = config.AutoLoad,
            NoConfig = true,
            Callback = function(value)
                config.AutoLoad = value == true
                self:_SaveConfigMeta()
                setConfigStatus(
                    config.AutoLoad
                        and ("Carga automática ACTIVADA • " .. config.Selected)
                        or "Carga automática DESACTIVADA"
                )
            end,
        })

        tab:CreateLabel("La carga automática restaura el perfil seleccionado en la próxima ejecución.")
        tab:CreateLabel("El guardado automático escribe los cambios al ajustar cualquier control guardado.")

        if next(config.LoadedValues) ~= nil and config.AutoLoad then
            task.defer(function()
                VNUS:Notify({
                    Title = "Configuración",
                    Content = "Cargado automáticamente " .. config.Selected,
                    Duration = 2.5,
                })
            end)
        end

        return tab
    end

    close.MouseEnter:Connect(function()
        if close.Parent then
            motionTween(close, Motion.Hover, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, {
                TextColor3 = Theme.Danger,
            })
        end
    end)

    close.MouseLeave:Connect(function()
        if close.Parent then
            motionTween(close, Motion.Hover, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, {
                TextColor3 = Theme.DimText,
            })
        end
    end)

    minimize.MouseEnter:Connect(function()
        if minimize.Parent then
            motionTween(minimize, Motion.Hover, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, {
                TextColor3 = Theme.BrightText,
            })
        end
    end)

    minimize.MouseLeave:Connect(function()
        if minimize.Parent and not window.WindowAnimating then
            motionTween(minimize, Motion.Hover, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, {
                TextColor3 = Theme.DimText,
            })
        end
    end)

    close.MouseButton1Click:Connect(function()
        window:ClosePopup()
        minimizedTitleLabel.Visible = false
        window.VisibilityAnimationGeneration += 1
        motionTween(
            main,
            Motion.Visibility,
            Enum.EasingStyle.Quad,
            Enum.EasingDirection.In,
            {GroupTransparency = 1}
        )
        if shadow.Visible then
            motionTween(
                shadow,
                Motion.Visibility,
                Enum.EasingStyle.Quad,
                Enum.EasingDirection.In,
                {BackgroundTransparency = 1}
            )
        end

        task.delay(Motion.Visibility, function()
            if window.CloseCallback then
                window.CloseCallback()
            else
                window:Destroy()
            end
        end)
    end)

    minimize.MouseButton1Click:Connect(function()
        if window.WindowAnimating then
            return
        end

        window:ClosePopup()
        window.WindowAnimationGeneration += 1
        local generation = window.WindowAnimationGeneration
        window.WindowAnimating = true
        window.Minimized = not window.Minimized

        local miniHeight = window.ResolvedLayout == "Phone" and 34 or 27

        if window.Minimized then
            titleLabel.Visible = false
            minimizedTitleLabel.Visible = window.Visible ~= false
            minimize.Text = "+"
            motionTween(
                minimize,
                Motion.Window,
                Enum.EasingStyle.Quart,
                Enum.EasingDirection.Out,
                {TextColor3 = Theme.BrightText, Rotation = 180}
            )

            shadow.Visible = window.Visible ~= false
            motionTween(
                shadow,
                Motion.Window * 0.8,
                Enum.EasingStyle.Quad,
                Enum.EasingDirection.In,
                {
                    Size = UDim2.fromOffset(window.FullSize.X.Offset, miniHeight),
                    BackgroundTransparency = 1,
                }
            )
            motionTween(
                main,
                Motion.Window,
                Enum.EasingStyle.Quart,
                Enum.EasingDirection.Out,
                {Size = UDim2.fromOffset(window.FullSize.X.Offset, miniHeight)}
            )

            task.delay(Motion.Window * 0.82, function()
                if generation ~= window.WindowAnimationGeneration or not window.Minimized then
                    return
                end

                tabBar.Visible = false
                accentTop.Visible = false
                tabSeparatorDark.Visible = false
                tabSeparator.Visible = false
                columnsHost.Visible = false
            end)

            task.delay(Motion.Window + 0.025, function()
                if generation ~= window.WindowAnimationGeneration or not window.Minimized then
                    return
                end
                shadow.Visible = false
                window.WindowAnimating = false
                window:ClampToViewport(6, "Current")
            end)
        else
            minimizedTitleLabel.Visible = false
            titleLabel.Visible = true
            -- Ajusta los límites con el tamaño expandido antes de iniciar la animación.
            window:ClampToViewport(
                window.ResolvedLayout == "Phone" and 6 or 8,
                "Expanded"
            )

            tabBar.Visible = true
            accentTop.Visible = true
            tabSeparatorDark.Visible = true
            tabSeparator.Visible = true
            columnsHost.Visible = true

            if window.CurrentTab and window.CurrentTab.Container then
                window.CurrentTab.Container.Visible = true
            end

            shadow.Visible = window.Visible ~= false
            shadow.BackgroundTransparency = 1
            shadow.Size = UDim2.fromOffset(window.FullSize.X.Offset, miniHeight)

            minimize.Text = "-"
            minimize.Rotation = 180

            motionTween(
                minimize,
                Motion.Window,
                Enum.EasingStyle.Quart,
                Enum.EasingDirection.Out,
                {TextColor3 = Theme.DimText, Rotation = 0}
            )
            motionTween(
                shadow,
                Motion.Window,
                Enum.EasingStyle.Quart,
                Enum.EasingDirection.Out,
                {
                    Size = window.FullSize,
                    BackgroundTransparency = 0.5,
                }
            )
            motionTween(
                main,
                Motion.Window,
                Enum.EasingStyle.Quart,
                Enum.EasingDirection.Out,
                {Size = window.FullSize}
            )

            task.delay(Motion.Window + 0.03, function()
                if generation ~= window.WindowAnimationGeneration or window.Minimized then
                    return
                end

                window.WindowAnimating = false
                window:ClampToViewport(
                    window.ResolvedLayout == "Phone" and 6 or 8,
                    "Expanded"
                )
            end)
        end
    end)

    -- Captura de teclas para cambiar el atajo y mostrar u ocultar la ventana.
    UserInputService.InputBegan:Connect(function(input, processed)
        local capturingWindow = SharedUIState.CapturingWindow

        if capturingWindow then
            -- Solo la ventana que inició la captura procesa esa tecla.
            if capturingWindow ~= window then
                return
            end

            if input.UserInputType ~= Enum.UserInputType.Keyboard then
                return
            end

            local control = SharedUIState.CapturingControl

            if input.KeyCode == Enum.KeyCode.Escape then
                SharedUIState.SuppressToggleUntil = os.clock() + 0.25
                SharedUIState.CapturingWindow = nil
                SharedUIState.CapturingControl = nil

                if control and control.CancelCapture then
                    control:CancelCapture()
                end
                return
            end

            if input.KeyCode ~= Enum.KeyCode.Unknown then
                local keyName = input.KeyCode.Name

                -- Evita que la tecla recién asignada active también el atajo de la interfaz.
                SharedUIState.SuppressToggleUntil = os.clock() + 0.30
                SharedUIState.CapturingWindow = nil
                SharedUIState.CapturingControl = nil

                window:SetToggleKey(input.KeyCode)

                if control then
                    control:_SetKeyName(keyName)
                    safeCallback(control.Callback, keyName)
                end
            end

            return
        end

        if os.clock() < (SharedUIState.SuppressToggleUntil or 0) then
            return
        end

        if processed then
            return
        end

        if input.UserInputType == Enum.UserInputType.Keyboard
            and input.KeyCode == window.ToggleKeyCode then
            window:Toggle()
        end
    end)

    window:ApplyResponsiveLayout()

    -- Comprueba periódicamente si cambió algún valor guardado.
    task.spawn(function()
        task.wait(1.0)

        if not config.Available or not config.Enabled then
            return
        end

        config.Ready = true
        config.LastFingerprint = window:_ConfigFingerprint()

        -- Crea el archivo del perfil si el guardado automático está activo y aún no existe.
        if config.AutoSave and not FileAPI.IsFile(configFilePath(config.Selected)) then
            window:_WriteConfig(config.Selected, false)
        end

        while window.ScreenGui and window.ScreenGui.Parent do
            if config.AutoSave and not config.Applying then
                local fingerprint = window:_ConfigFingerprint()

                if fingerprint ~= ""
                    and fingerprint ~= config.LastFingerprint then
                    window:_WriteConfig(config.Selected, false)
                end
            end

            task.wait(0.5)
        end
    end)

    return window
end

return VNUS
