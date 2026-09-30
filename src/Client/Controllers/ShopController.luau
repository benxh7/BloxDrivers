-- Ubicación en Studio: StarterPlayer > StarterPlayerScripts > Controllers > ShopController (ModuleScript)
--
-- Ventana de la tienda (StarterGui > ShopGui). Se registra en UIManager como "Shop"
-- (la abre HUD.ShopButton vía HUDController) y arma una tarjeta por item de
-- ShopConfig.Rows clonando UITemplates.ShopCard.
--
-- Plantilla ShopCard (armada en Studio, orden de dibujo de atrás hacia adelante):
--   Glow (brillo 9-slice) > Ring (anillo de color) > Background (CanvasGroup: Art, Rays,
--   Pattern, TitleBar) > Outline (borde negro) > Icon > Title/Subtitle/Description >
--   GemButton + Actions (GiftButton, BuyButton).
--
-- El cliente nunca compra por su cuenta: manda el Id del item por "RequestShopPurchase"
-- y ShopService valida y abre el prompt de Roblox. Los items "View" abren otra ventana
-- con UIManager.Open(item.ViewTarget).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local Lighting = game:GetService("Lighting")
local TweenService = game:GetService("TweenService")

local UIManager = require(script.Parent:WaitForChild("UIManager"))
local Utils = script.Parent.Parent:WaitForChild("Utils")
local UIEffects = require(Utils:WaitForChild("UIEffects"))
local UITemplates = require(Utils:WaitForChild("UITemplates"))
local Remotes = require(ReplicatedStorage:WaitForChild("Remotes"))
local ShopConfig = require(ReplicatedStorage:WaitForChild("ShopConfig"))
local DebugConfig = require(ReplicatedStorage:WaitForChild("DebugConfig"))

local ShopController = {}

local WINDOW_NAME = "Shop"
local GUI_NAME = "ShopGui"
local CARD_TEMPLATE = "ShopCard"

-- Separación entre tarjetas de una misma fila (Scale del ancho de la fila).
local CARD_GAP = 0.035
-- Separación vertical entre filas, como fracción del ancho de la lista.
local ROW_GAP = 0.04
-- Márgenes de la lista (costados y arriba/abajo), también como fracción de su ancho.
local SIDE_PADDING = 0.045
local EDGE_PADDING = 0.045
-- Tamaño máximo del texto de la descripción, como fracción del alto de la tarjeta.
local DESCRIPTION_TEXT = 0.115
-- Los UIStroke usan su grosor de Studio a 1080 px de alto; en pantallas más chicas
-- (celular) se afinan en proporción, hasta la mitad, para no tapar el texto.
local REFERENCE_HEIGHT = 1080
local MIN_STROKE_FACTOR = 0.5
-- Brillo de las tarjetas: cuánto sobresale (px a 1080). La textura cae en 64 px, así que
-- SliceScale = extent / 64 hace que el brillo arranque justo en el borde de la tarjeta.
local GLOW_EXTENT = 22
local GLOW_SLICE_SCALE = GLOW_EXTENT / 64
-- Cuánto se aclara el color del brillo para la línea interior del borde.
local INNER_LINE_LIGHTEN = 0.45

-- Hover: tarjetas comunes (no las destacadas ni el pase) y botones de cada tarjeta.
local CARD_HOVER = { Scale = 1.03 }
local BUTTON_HOVER = { Scale = 1.08, Rotation = 5 }

-- Desenfoque del mundo mientras la tienda está abierta.
local BLUR_NAME = "ShopBlur"
local BLUR_SIZE = 16
local BLUR_TWEEN = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

-- PriceLabel con el ícono de Robux a la izquierda (igual que la plantilla) o solo.
local PRICE_WITH_ICON = { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.fromScale(0.95, 0.5), Size = UDim2.fromScale(0.62, 0.82) }
local PRICE_ALONE = { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(0.86, 0.8) }

-- Ubicación de los botones (Actions) según el tipo de tarjeta.
local ACTIONS_DEFAULT = { Position = UDim2.fromScale(0.97, 0.95), Size = UDim2.fromScale(0.62, 0.22) }
local ACTIONS_FEATURED = { Position = UDim2.fromScale(0.965, 0.95), Size = UDim2.fromScale(0.72, 0.25) }
local ACTIONS_BANNER = { Position = UDim2.fromScale(0.975, 0.93), Size = UDim2.fromScale(0.37, 0.3) }
local BUY_ASPECT = 2.5
local VIEW_ASPECT = 2.4

local main: GuiObject
local content: ScrollingFrame
local blur: BlurEffect
local owned: { [string]: boolean } = {}
local cards: { [string]: GuiObject } = {}

-- ─── Tamaños responsivos (bordes y brillo) ──────────────────────────────────────

local function strokeFactor(): number
	local camera = Workspace.CurrentCamera
	local height = if camera then camera.ViewportSize.Y else REFERENCE_HEIGHT
	return math.clamp(height / REFERENCE_HEIGHT, MIN_STROKE_FACTOR, 1)
end

local function scaleStrokes(root: Instance)
	local factor = strokeFactor()
	for _, object in root:GetDescendants() do
		if object:IsA("UIStroke") then
			local base = object:GetAttribute("BaseThickness")
			if typeof(base) ~= "number" then
				base = object.Thickness
				object:SetAttribute("BaseThickness", base)
			end
			object.Thickness = math.max(1, base * factor)
		elseif object:IsA("ImageLabel") and object.Name == "Glow" then
			local extent = GLOW_EXTENT * factor
			object.Size = UDim2.new(1, extent * 2, 1, extent * 2)
			object.SliceScale = GLOW_SLICE_SCALE * factor
		end
	end
end

-- ─── Tarjetas ───────────────────────────────────────────────────────────────────

local function setGradient(object: Instance, colors: { Color3 })
	local gradient = object:FindFirstChildOfClass("UIGradient")
	if not gradient then
		gradient = Instance.new("UIGradient")
		gradient.Rotation = 90
		gradient.Parent = object
	end
	gradient.Color = ColorSequence.new(colors[1], colors[2])
end

local function applyProps(object: Instance, props: { [string]: any })
	for key, value in props do
		(object :: any)[key] = value
	end
end

local function hasImage(image: string?): boolean
	return image ~= nil and image ~= "" and image ~= "rbxassetid://0"
end

local function setAspect(object: Instance, ratio: number)
	local aspect = object:FindFirstChildOfClass("UIAspectRatioConstraint")
	if aspect then
		aspect.AspectRatio = ratio
	end
end

-- Estado del botón: VIEW, OWNED o precio en Robux.
local function styleBuyButton(card: GuiObject, itemId: string, item: ShopConfig.Item)
	local buy = card:FindFirstChild("BuyButton", true)
	if not buy then
		return
	end
	local robux = buy:FindFirstChild("RobuxIcon") :: ImageLabel?
	local price = buy:FindFirstChild("PriceLabel") :: TextLabel?
	local inner = buy:FindFirstChild("Inner") :: Frame?

	local isView = item.Kind == "View"
	local text, colors, showRobux
	if isView then
		text, colors, showRobux = "VIEW", ShopConfig.ButtonColors.View, false
	elseif owned[itemId] then
		text, colors, showRobux = "OWNED", ShopConfig.ButtonColors.Owned, false
	else
		text, colors, showRobux = tostring(item.Price or "?"), ShopConfig.ButtonColors.Buy, true
	end

	setGradient(buy, colors)
	setAspect(buy, if isView then VIEW_ASPECT else BUY_ASPECT)
	if inner then
		-- Borde blanco interior: solo el botón VIEW lo lleva.
		inner.Visible = isView
	end
	if robux then
		robux.Visible = showRobux
		robux.Image = ShopConfig.Icons.Robux
	end
	if price then
		price.Text = text
		applyProps(price, if showRobux then PRICE_WITH_ICON else PRICE_ALONE)
	end
end

local function onBuy(itemId: string, item: ShopConfig.Item)
	if item.Kind == "View" then
		if item.ViewTarget then
			UIManager.Open(item.ViewTarget)
		end
		return
	end
	if owned[itemId] then
		return
	end
	if not item.ProductId or item.ProductId == 0 then
		DebugConfig.warn(("[ShopController] '%s' no tiene ProductId en ShopConfig todavía"):format(itemId))
		return
	end
	-- Solo el Id: el servidor busca el producto y abre el prompt.
	Remotes.event("RequestShopPurchase"):FireServer(itemId)
end

-- Brillo, anillo de color y borde interior.
local function styleFrame(card: GuiObject, item: ShopConfig.Item)
	local glow = card:FindFirstChild("Glow") :: ImageLabel?
	local ring = card:FindFirstChild("Ring") :: Frame?
	if glow then
		glow.Visible = item.Glow ~= nil
		if item.Glow then
			glow.ImageColor3 = item.Glow
		end
	end
	if ring then
		-- Anillo sólido solo si el item pide grosor (bundle, pase); el resto va con brillo solo.
		local thickness = item.GlowThickness or ShopConfig.GlowThickness
		ring.Visible = item.Glow ~= nil and thickness > 0
		local ringStroke = ring:FindFirstChildOfClass("UIStroke")
		if ringStroke and item.Glow and thickness > 0 then
			ringStroke.Color = item.Glow
			ringStroke.Thickness = thickness
		end
	end
	local background = card:FindFirstChild("Background")
	local innerLine = background and background:FindFirstChild("InnerLine") :: Frame?
	if innerLine then
		innerLine.Visible = item.Glow ~= nil
		local innerStroke = innerLine:FindFirstChildOfClass("UIStroke")
		if innerStroke and item.Glow then
			innerStroke.Color = item.Glow:Lerp(Color3.new(1, 1, 1), INNER_LINE_LIGHTEN)
		end
	end
	local outline = card:FindFirstChild("Outline")
	local outlineStroke = outline and outline:FindFirstChildOfClass("UIStroke")
	if outlineStroke and item.Outline then
		outlineStroke.Color = item.Outline
	end
end

-- Fondo: imagen o degradé, más los adornos (rayos, puntos) y el ícono del item.
local function styleBackground(card: GuiObject, item: ShopConfig.Item)
	local background = card:FindFirstChild("Background")
	if background then
		-- El UIGradient de un CanvasGroup tiñe TODO su contenido: con imagen va en blanco
		-- para no oscurecerla.
		setGradient(background, if hasImage(item.Image) then { Color3.new(1, 1, 1), Color3.new(1, 1, 1) } else item.Color)
		local art = background:FindFirstChild("Art") :: ImageLabel?
		if art then
			art.Visible = hasImage(item.Image)
			art.Image = if hasImage(item.Image) then item.Image else ""
		end
		local rays = background:FindFirstChild("Rays") :: ImageLabel?
		if rays then
			rays.Visible = item.Rays == true
		end
		local pattern = background:FindFirstChild("Pattern") :: ImageLabel?
		if pattern then
			pattern.Visible = item.Pattern ~= false
			if item.PatternColor then
				pattern.ImageColor3 = item.PatternColor
			end
			if item.PatternTransparency then
				pattern.ImageTransparency = item.PatternTransparency
			end
		end
		local titleBar = background:FindFirstChild("TitleBar") :: Frame?
		if titleBar then
			titleBar.Visible = not item.Banner
		end
	end

	local icon = card:FindFirstChild("Icon") :: ImageLabel?
	if icon then
		icon.Visible = hasImage(item.Icon)
		icon.Image = item.Icon or ""
		if item.IconLayout then
			icon.Position = item.IconLayout.Position
			icon.Size = item.IconLayout.Size
		end
	end
end

local function styleTexts(card: GuiObject, item: ShopConfig.Item)
	local title = card:FindFirstChild("Title") :: TextLabel?
	if title then
		title.Text = item.Title
		if item.TitleColor then
			title.TextColor3 = item.TitleColor
		end
		local titleStroke = title:FindFirstChildOfClass("UIStroke")
		if titleStroke and item.TitleStroke then
			titleStroke.Color = item.TitleStroke
		end
		if item.Banner then
			-- Estilo pase: título grande alineado a la izquierda, sin barra.
			title.Position = UDim2.fromScale(0.03, 0.04)
			title.Size = UDim2.fromScale(0.62, 0.27)
			title.TextXAlignment = Enum.TextXAlignment.Left
			if titleStroke then
				titleStroke.Thickness = 4
			end
			local padding = title:FindFirstChildOfClass("UIPadding")
			if padding then
				padding.PaddingLeft = UDim.new(0, 0)
			end
		end
	end

	local subtitle = card:FindFirstChild("Subtitle") :: TextLabel?
	if subtitle then
		subtitle.Visible = item.Subtitle ~= nil
		subtitle.Text = item.Subtitle or ""
	end

	local description = card:FindFirstChild("Description") :: TextLabel?
	if description then
		description.Text = item.Description or ""
		if item.DescriptionColor then
			description.TextColor3 = item.DescriptionColor
		end
		if item.Banner then
			description.Position = UDim2.fromScale(0.03, 0.31)
			description.Size = UDim2.fromScale(0.62, 0.12)
		elseif item.DescriptionAlign == "Right" then
			description.Position = UDim2.fromScale(0.42, 0.2)
			description.Size = UDim2.fromScale(0.56, 0.42)
			description.TextXAlignment = Enum.TextXAlignment.Center
		elseif item.Subtitle then
			description.Position = UDim2.fromScale(0.015, 0.46)
		end
		local limit = description:FindFirstChildOfClass("UITextSizeConstraint")
		if limit then
			-- TextScaled llenaría la caja con textos cortos: se topa según el alto de la tarjeta.
			local function fit()
				limit.MaxTextSize = math.max(8, math.floor(card.AbsoluteSize.Y * DESCRIPTION_TEXT))
			end
			card:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)
			fit()
		end
	end
end

local function bindButtons(card: GuiObject, itemId: string, item: ShopConfig.Item)
	local actions = card:FindFirstChild("Actions") :: Frame?
	if actions then
		applyProps(actions, if item.Banner then ACTIONS_BANNER elseif item.Featured then ACTIONS_FEATURED else ACTIONS_DEFAULT)
	end

	local gift = card:FindFirstChild("GiftButton", true) :: GuiButton?
	if gift then
		gift.Visible = ShopConfig.GiftEnabled
		local giftIcon = gift:FindFirstChild("Icon") :: ImageLabel?
		if giftIcon then
			giftIcon.Image = ShopConfig.Icons.Gift
		end
		UIEffects.bindButton(gift, function()
			DebugConfig.warn(("[ShopController] Regalar '%s': flujo de regalos sin implementar"):format(itemId))
		end)
		UIEffects.bindHover(gift, BUTTON_HOVER)
	end

	local gem = card:FindFirstChild("GemButton") :: GuiButton?
	if gem then
		gem.Visible = item.Gem == true
		local gemIcon = gem:FindFirstChild("Icon") :: ImageLabel?
		if gemIcon then
			gemIcon.Image = ShopConfig.Icons.Gem
		end
		if item.Gem then
			UIEffects.bindButton(gem, function()
				DebugConfig.warn(("[ShopController] Comprar '%s' con gemas: sin implementar"):format(itemId))
			end)
			UIEffects.bindHover(gem, BUTTON_HOVER)
		end
	end

	local buy = card:FindFirstChild("BuyButton", true) :: GuiButton?
	if buy then
		UIEffects.bindButton(buy, function()
			onBuy(itemId, item)
		end)
		UIEffects.bindHover(buy, BUTTON_HOVER)
	end
	styleBuyButton(card, itemId, item)
end

local function buildCard(itemId: string, item: ShopConfig.Item, width: number): GuiObject?
	local card = UITemplates.clone(CARD_TEMPLATE)
	if not card then
		return nil
	end
	card.Name = itemId
	card.Size = UDim2.fromScale(width, 1)

	styleFrame(card, item)
	styleBackground(card, item)
	styleTexts(card, item)
	bindButtons(card, itemId, item)

	if not (item.Featured or item.Banner) then
		UIEffects.bindHover(card, CARD_HOVER)
	end

	cards[itemId] = card
	return card
end

-- Cada fila es un Frame horizontal cuyo alto sale de su ancho (UIAspectRatioConstraint):
-- las tarjetas conservan su proporción en cualquier pantalla y el canvas crece solo.
local function buildRow(index: number, row: ShopConfig.Row)
	local count = #row.Items
	local width = row.Width or 1
	local cardWidth = (width - CARD_GAP * (count - 1)) / count

	local frame = Instance.new("Frame")
	frame.Name = "Row" .. index
	frame.LayoutOrder = index
	frame.BackgroundTransparency = 1
	frame.Size = UDim2.fromScale(1, 1)

	local aspect = Instance.new("UIAspectRatioConstraint")
	aspect.AspectRatio = row.CardAspect / cardWidth
	aspect.AspectType = Enum.AspectType.ScaleWithParentSize
	aspect.DominantAxis = Enum.DominantAxis.Width
	aspect.Parent = frame

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(CARD_GAP, 0)
	layout.Parent = frame

	for order, itemId in row.Items do
		local item = ShopConfig.get(itemId)
		if not item then
			DebugConfig.warn(("[ShopController] Rows[%d] nombra '%s', que no está en ShopConfig.Items"):format(index, itemId))
			continue
		end
		local card = buildCard(itemId, item, cardWidth)
		if card then
			card.LayoutOrder = order
			card.Parent = frame
		end
	end

	frame.Parent = content
end

local function buildShop()
	for _, child in content:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	table.clear(cards)
	for index, row in ShopConfig.Rows do
		buildRow(index, row)
	end
	scaleStrokes(main)
end

local function setOwned(itemId: string)
	owned[itemId] = true
	local card = cards[itemId]
	local item = ShopConfig.get(itemId)
	if card and item then
		styleBuyButton(card, itemId, item)
	end
end

-- Separaciones y alto del canvas calculados a mano, proporcionales al ancho de la lista.
-- Dentro de un ScrollingFrame, el Padding/UIPadding en Scale se mide contra el canvas y
-- AutomaticCanvasSize dejaba afuera las últimas filas.
local function bindCanvas()
	local layout = content:FindFirstChildOfClass("UIListLayout")
	local padding = content:FindFirstChildOfClass("UIPadding")
	if not layout then
		return
	end
	content.AutomaticCanvasSize = Enum.AutomaticSize.None
	local function fit()
		local width = content.AbsoluteSize.X
		local gap = math.floor(width * ROW_GAP)
		local side = math.floor(width * SIDE_PADDING)
		local edge = math.floor(width * EDGE_PADDING)
		layout.Padding = UDim.new(0, gap)
		if padding then
			padding.PaddingLeft = UDim.new(0, side)
			padding.PaddingRight = UDim.new(0, side)
			padding.PaddingTop = UDim.new(0, edge)
			padding.PaddingBottom = UDim.new(0, edge)
		end
		content.CanvasSize = UDim2.fromOffset(0, layout.AbsoluteContentSize.Y + edge * 2)
	end
	content:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)
	layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(fit)
	fit()
end

local function setBlur(enabled: boolean)
	TweenService:Create(blur, BLUR_TWEEN, { Size = if enabled then BLUR_SIZE else 0 }):Play()
end

-- ─── Init ───────────────────────────────────────────────────────────────────────

function ShopController.Init()
	local gui = UIManager.WaitForGui(GUI_NAME)
	if not gui then
		return
	end
	local found = UIEffects.findChild(gui, "Main", GUI_NAME)
	if not (found and found:IsA("GuiObject")) then
		return
	end
	main = found
	local list = UIEffects.findChild(main, "Content", GUI_NAME)
	if not (list and list:IsA("ScrollingFrame")) then
		return
	end
	content = list

	blur = Instance.new("BlurEffect")
	blur.Name = BLUR_NAME
	blur.Size = 0
	blur.Parent = Lighting

	-- El CloseButton del Header lo conecta UIManager solo.
	UIManager.Register(WINDOW_NAME, main)
	UIManager.OnOpened(WINDOW_NAME, function()
		content.CanvasPosition = Vector2.zero
		setBlur(true)
	end)
	UIManager.OnClosed(WINDOW_NAME, function()
		setBlur(false)
	end)

	buildShop()
	bindCanvas()

	local camera = Workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
			scaleStrokes(main)
		end)
	end

	-- Game Passes que ya tiene el jugador (y los que compre durante la partida).
	Remotes.onUpdate("shopOwned", setOwned)
	local ok, result = pcall(function()
		return Remotes.func("GetShopOwned"):InvokeServer()
	end)
	if ok and typeof(result) == "table" then
		for _, itemId in result do
			if typeof(itemId) == "string" then
				setOwned(itemId)
			end
		end
	elseif not ok then
		DebugConfig.warn("[ShopController] GetShopOwned falló: " .. tostring(result))
	end
end

return ShopController
