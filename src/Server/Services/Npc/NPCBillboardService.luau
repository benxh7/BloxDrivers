-- Ubicación en Studio: ServerScriptService > Services > Npc > NPCBillboardService (ModuleScript)
--
-- Cartel sobre la cabeza del NPC: nombre, una rayita y el subtítulo. Lo arma el
-- SERVIDOR una sola vez porque el NPC no se respawnea — un cartel por cliente sería
-- el mismo trabajo repetido y nada acá depende de quién mira.
--
-- Nota: el BillboardGui usa píxeles a propósito (NPCConfig.Billboard). Un billboard
-- en Offset mantiene el mismo tamaño en pantalla a cualquier distancia; en Scale se
-- achicaría con la distancia como un objeto 3D.
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
	-- El TextStroke viejo se SUMA al UIStroke y engorda el borde: se apaga.
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

	-- Se arma entero ANTES de parentarlo: una sola replicación en vez de una por hijo.
	local billboard = Instance.new("BillboardGui")
	billboard.Name = BILLBOARD_NAME
	billboard.Size = UDim2.fromOffset(style.WidthPixels, style.HeightPixels)
	billboard.StudsOffset = Vector3.new(0, settings.BillboardHeight, 0)
	billboard.MaxDistance = style.MaxDistance
	-- false = se tapa detrás de las paredes, igual que los nombres de los jugadores.
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

	-- Sin subtítulo NO se crea la label: una label vacía igual ocuparía su alto en el
	-- UIListLayout y dejaría el cartel descentrado.
	if settings.Subtitle ~= "" then
		textLabel("Subtitle", settings.Subtitle, style.SubtitleSize, style.SubtitleColor, 3).Parent = root
	end

	billboard.Parent = head
end

-- El cartel nativo del Humanoid sobra: nuestro billboard lo reemplaza, y si no
-- quedan los dos encimados. `None` apaga el nombre Y la barra de vida de una.
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
