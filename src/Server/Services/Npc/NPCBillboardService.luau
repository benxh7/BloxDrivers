-- Ubicación en Studio: ServerScriptService > Services > Npc > NPCBillboardService (ModuleScript)
-- Cartel del NPC, armado una vez en el servidor: el NPC no respawnea y nada depende de
-- quién mira. En px a propósito: en Scale se achicaría con la distancia.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local NPCConfig = require(ReplicatedStorage:WaitForChild("NPCConfig"))
local DebugConfig = require(ReplicatedStorage:WaitForChild("DebugConfig"))

local NPCBillboardService = {}

local BILLBOARD_NAME = "NPCTag"

local function textLabel(name: string, text: string, size: number, color: Color3, order: number): TextLabel
	local style = NPCConfig.Billboard

	local label = Instance.new("TextLabel")
	label.Name = name
	label.Text = text
	label.Size = UDim2.new(1, 0, 0, size + 4)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.TextSize = size
	label.TextColor3 = color
	label.LayoutOrder = order
	-- El TextStroke viejo se suma al UIStroke y engorda el borde.
	label.TextStrokeTransparency = 1

	local stroke = Instance.new("UIStroke")
	stroke.Color = style.StrokeColor
	stroke.Thickness = style.StrokeThickness
	stroke.Parent = label

	return label
end

local function buildBillboard(model: Model, settings)
	local head = model:FindFirstChild("Head") or model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart")
	if not (head and head:IsA("BasePart")) then
		DebugConfig.warn(("[NPCBillboardService] %s no tiene de dónde colgar el cartel"):format(model.Name))
		return
	end

	local existing = head:FindFirstChild(BILLBOARD_NAME)
	if existing then
		existing:Destroy()
	end

	local style = NPCConfig.Billboard

	-- Entero antes de parentarlo: una sola replicación en vez de una por hijo.
	local billboard = Instance.new("BillboardGui")
	billboard.Name = BILLBOARD_NAME
	billboard.Size = UDim2.fromOffset(style.WidthPixels, style.HeightPixels)
	billboard.StudsOffset = Vector3.new(0, settings.BillboardHeight, 0)
	-- Apoyado por el borde de abajo: medido en px, de lejos el cartel ocupa más studs y,
	-- centrado, su mitad inferior se hundía en la cabeza del NPC.
	billboard.SizeOffset = Vector2.new(0, 0.5)
	billboard.MaxDistance = style.MaxDistance
	-- false = se tapa detrás de las paredes, como los nombres de los jugadores.
	billboard.AlwaysOnTop = false

	local root = Instance.new("Frame")
	root.Name = "Root"
	root.Size = UDim2.fromScale(1, 1)
	root.BackgroundTransparency = 1
	root.Parent = billboard

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Bottom
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = root

	textLabel("Title", settings.Title, style.TitleSize, style.TitleColor, 1).Parent = root

	local line = Instance.new("Frame")
	line.Name = "Line"
	line.Size = UDim2.new(style.LineWidthScale, 0, 0, style.LineThicknessPixels)
	line.BackgroundColor3 = style.LineColor
	line.BorderSizePixel = 0
	line.LayoutOrder = 2
	line.Parent = root

	-- Una label vacía igual ocuparía su alto en el UIListLayout y descentraría el cartel.
	if settings.Subtitle ~= "" then
		textLabel("Subtitle", settings.Subtitle, style.SubtitleSize, style.SubtitleColor, 3).Parent = root
	end

	billboard.Parent = head
	DebugConfig.print(('[NPCBillboard] %s -> "%s"'):format(model.Name, settings.Title))
end

-- Si no, quedan el cartel nativo y el nuestro encimados. `None` apaga nombre y barra de vida.
local function hideNativeName(npc: Model)
	local humanoid = npc:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	end
end

function NPCBillboardService.Init()
	NPCConfig.observe(function(npc: Model)
		hideNativeName(npc)
		buildBillboard(npc, NPCConfig.get(npc))
	end)
end

return NPCBillboardService
