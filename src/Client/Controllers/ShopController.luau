-- Ubicación en Studio: StarterPlayer > StarterPlayerScripts > Controllers > ShopController (ModuleScript)
--
-- Ventana de la tienda (StarterGui > ShopGui). Se registra en UIManager como "Shop"
-- (la abre HUD.ShopButton vía HUDController) y arma una tarjeta por item de
-- ShopConfig.Rows clonando UITemplates.ShopCard.
--
-- DÓNDE SE EDITA CADA COSA
--   · Items, precios, colores e íconos de cada tarjeta ....... ShopConfig.Items / Rows
--   · Esquinas, borde, brillo, hover, espaciados, blur, apertura ShopConfig.Style
--   · Sonidos al abrir la tienda ............................. ShopConfig.Sounds
--   · Colores de los botones (comprar / VIEW / OWNED / regalo / gema)
--       ShopConfig.ButtonColors y ButtonStyle
--   · Forma de las capas (fuentes, posiciones base) .......... plantilla en Studio
--   · Posiciones que cambian según el tipo de tarjeta ........ "Layout por tipo" (abajo)
--
-- Plantilla ShopCard (Studio), de atrás hacia adelante:
--   Glow (vacío: acá se crean las capas del brillo) > Ring (anillo sólido) >
--   Background (CanvasGroup: Art, Rays, Pattern, InnerLine, TitleBar) > Outline (borde) >
--   Icon > Title / Subtitle / Description > GemSlot + Actions (GiftSlot, BuySlot).
--   Cada botón va centrado dentro de su *Slot: el hover lo escala desde el centro sin
--   empujar a los demás.
--
-- El cliente nunca compra por su cuenta: manda el Id del item por "RequestShopPurchase"
-- y ShopService valida y abre el prompt de Roblox. Los items "View" abren otra ventana
-- con UIManager.Open(item.ViewTarget).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local Lighting = game:GetService("Lighting")
local TweenService = game:GetService("TweenService")
local ContentProvider = game:GetService("ContentProvider")

local UIManager = require(script.Parent:WaitForChild("UIManager"))
local Utils = script.Parent.Parent:WaitForChild("Utils")
local UIEffects = require(Utils:WaitForChild("UIEffects"))
local UITemplates = require(Utils:WaitForChild("UITemplates"))
local Remotes = require(ReplicatedStorage:WaitForChild("Remotes"))
local ShopConfig = require(ReplicatedStorage:WaitForChild("ShopConfig"))
local DebugConfig = require(ReplicatedStorage:WaitForChild("DebugConfig"))

local ShopController = {}

local Style = ShopConfig.Style

local WINDOW_NAME = "Shop"
local GUI_NAME = "ShopGui"
local CARD_TEMPLATE = "ShopCard"
local BLUR_NAME = "ShopBlur"

-- Los UIStroke usan su grosor a 1080 px de alto; en pantallas más chicas (celular) se
-- afinan en proporción, hasta la mitad, para no tapar el texto.
local REFERENCE_HEIGHT = 1080
local MIN_STROKE_FACTOR = 0.5

-- Capas de la tarjeta cuyo UICorner se iguala a Style.CornerRadius.
local CORNER_LAYERS = { Ring = true, Background = true, Outline = true, InnerLine = true }

-- ─── Layout por tipo de tarjeta ─────────────────────────────────────────────────

-- Botones (Actions): tarjeta común, destacada (bundle) y pase.
local ACTIONS_DEFAULT = { Position = UDim2.fromScale(0.97, 0.95), Size = UDim2.fromScale(0.62, 0.22) }
local ACTIONS_FEATURED = { Position = UDim2.fromScale(0.965, 0.95), Size = UDim2.fromScale(0.72, 0.25) }
local ACTIONS_BANNER = { Position = UDim2.fromScale(0.975, 0.93), Size = UDim2.fromScale(0.37, 0.3) }
-- Proporción ancho/alto del botón de compra y del botón VIEW.
local BUY_ASPECT = 2.5
local VIEW_ASPECT = 2.4
-- PriceLabel centrado: el símbolo de Robux va dentro del mismo texto.
local PRICE_LAYOUT = { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(0.9, 0.86) }
-- Ícono de Robux de las fuentes de Roblox (se dibuja como texto, con el mismo borde).
local ROBUX_GLYPH = utf8.char(0xE002)
-- Pase (Banner): título grande a la izquierda y descripción debajo.
local BANNER_TITLE = { Position = UDim2.fromScale(0.03, 0.04), Size = UDim2.fromScale(0.62, 0.27) }
local BANNER_DESCRIPTION = { Position = UDim2.fromScale(0.03, 0.31), Size = UDim2.fromScale(0.62, 0.12) }
-- Descripción centrada en la mitad derecha (DescriptionAlign = "Right", bundle).
local RIGHT_DESCRIPTION = { Position = UDim2.fromScale(0.42, 0.2), Size = UDim2.fromScale(0.56, 0.42) }
-- Descripción corrida hacia abajo cuando hay subtítulo.
local SUBTITLE_DESCRIPTION_Y = 0.46

local main: GuiObject
local content: ScrollingFrame
local blur: BlurEffect
local openSounds: { Sound } = {}
local owned: { [string]: boolean } = {}
local cards: { [string]: GuiObject } = {}

-- ─── Helpers ────────────────────────────────────────────────────────────────────

local function strokeFactor(): number
	local camera = Workspace.CurrentCamera
	local height = if camera then camera.ViewportSize.Y else REFERENCE_HEIGHT
	return math.clamp(height / REFERENCE_HEIGHT, MIN_STROKE_FACTOR, 1)
end

-- Todos los UIStroke (bordes, anillo, capas del brillo) se escalan con la pantalla. El
-- grosor "de diseño" queda guardado en el atributo BaseThickness.
local function scaleStrokes(root: Instance)
	local factor = strokeFactor()
	for _, stroke in root:GetDescendants() do
		if stroke:IsA("UIStroke") then
			local base = stroke:GetAttribute("BaseThickness")
			if typeof(base) ~= "number" then
				base = stroke.Thickness
				stroke:SetAttribute("BaseThickness", base)
			end
			stroke.Thickness = math.max(1, base * factor)
			-- Aro interior de un botón: su Frame se achica lo mismo que engorda el trazo,
			-- así el aro queda siempre pegado al borde negro, sin hueco ni encimado.
			if stroke:GetAttribute("Rim") and stroke.Parent and stroke.Parent:IsA("GuiObject") then
				-- Entero: el Offset de Size no admite decimales y el aro se metería en el borde.
				stroke.Thickness = math.max(1, math.round(stroke.Thickness))
				local rim = stroke.Thickness
				stroke.Parent.Size = UDim2.new(1, -2 * rim, 1, -2 * rim)
			end
		end
	end
end

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

-- El Slot que contiene al botón (para mostrarlo/ocultarlo sin romper el layout).
local function slotOf(button: Instance): GuiObject?
	local parent = button.Parent
	return if parent and parent:IsA("GuiObject") and parent.Name:match("Slot$") then parent else nil
end

-- ─── Marco: esquinas, borde, anillo y brillo ────────────────────────────────────

local function applyCorners(card: GuiObject)
	for _, corner in card:GetDescendants() do
		if corner:IsA("UICorner") and corner.Parent and CORNER_LAYERS[corner.Parent.Name] then
			corner.CornerRadius = UDim.new(Style.CornerRadius, 0)
		end
	end
end

-- Brillo difuminado con la MISMA forma que la tarjeta: anillos de UIStroke de un
-- grosor cada vez mayor (un paso por capa) sobre Frames con el UICorner de la tarjeta,
-- así que las esquinas quedan redondas como ella. Las capas se suman: en una distancia
-- `d` del borde se ven todas las que llegan hasta ahí. La transparencia de cada una se
-- calcula para que la suma siga una curva suave, Opacity pegado al borde y 0 al final
-- de Spread (curva ^ Curve): un desenfoque parejo, sin bandas ni borde duro.
local function buildGlow(card: GuiObject, color: Color3?, startAt: number)
	local container = card:FindFirstChild("Glow")
	if not container then
		return
	end
	container:ClearAllChildren()
	if not color then
		return
	end
	local glow = Style.Glow
	local layers = math.max(1, glow.Layers)

	-- Opacidad buscada en la franja de cada capa (1 = pegada al borde).
	local function target(index: number): number
		if index > layers then
			return 0
		end
		return glow.Opacity * (1 - (index - 1) / layers) ^ glow.Curve
	end

	for index = 1, layers do
		-- La franja `index` la cubren las capas index..layers: esta capa aporta lo que
		-- falta para pasar de la opacidad de la franja siguiente a la de la suya.
		local alpha = 1 - (1 - target(index)) / (1 - target(index + 1))

		local layer = Instance.new("Frame")
		layer.Name = "Layer" .. index
		layer.BackgroundTransparency = 1
		layer.Size = UDim2.fromScale(1, 1)
		layer.ZIndex = 0

		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(Style.CornerRadius, 0)
		corner.Parent = layer

		local stroke = Instance.new("UIStroke")
		stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		stroke.LineJoinMode = Enum.LineJoinMode.Round
		stroke.Color = color
		stroke.Transparency = 1 - alpha
		stroke.Thickness = startAt + glow.Spread * index / layers
		stroke.Parent = layer

		layer.Parent = container
	end
end

local function styleFrame(card: GuiObject, item: ShopConfig.Item)
	applyCorners(card)

	local outline = card:FindFirstChild("Outline")
	local outlineStroke = outline and outline:FindFirstChildOfClass("UIStroke")
	if outlineStroke then
		outlineStroke.Thickness = Style.OutlineThickness
		if item.Outline then
			outlineStroke.Color = item.Outline
		end
	end

	-- Anillo sólido (bundle, pase): va por fuera del borde negro.
	local ringThickness = if item.Glow then item.RingThickness or Style.RingThickness else 0
	local ring = card:FindFirstChild("Ring") :: Frame?
	if ring then
		ring.Visible = ringThickness > 0
		local ringStroke = ring:FindFirstChildOfClass("UIStroke")
		if ringStroke and item.Glow and ringThickness > 0 then
			ringStroke.Color = item.Glow
			ringStroke.Thickness = Style.OutlineThickness + ringThickness
		end
	end

	-- El brillo arranca donde termina el borde (y el anillo, si hay).
	buildGlow(card, item.Glow, Style.OutlineThickness + ringThickness)

	-- Línea clara por dentro del borde, del color del brillo aclarado.
	local background = card:FindFirstChild("Background")
	local innerLine = background and background:FindFirstChild("InnerLine") :: Frame?
	if innerLine then
		innerLine.Visible = item.Glow ~= nil
		local innerStroke = innerLine:FindFirstChildOfClass("UIStroke")
		if innerStroke and item.Glow then
			innerStroke.Color = item.Glow:Lerp(Color3.new(1, 1, 1), Style.InnerLineLighten)
		end
	end
end

-- ─── Fondo e ícono ──────────────────────────────────────────────────────────────

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
			applyProps(icon, item.IconLayout)
		end
	end
end

-- ─── Textos ─────────────────────────────────────────────────────────────────────

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
			applyProps(title, BANNER_TITLE)
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
			applyProps(description, BANNER_DESCRIPTION)
		elseif item.DescriptionAlign == "Right" then
			applyProps(description, RIGHT_DESCRIPTION)
			description.TextXAlignment = Enum.TextXAlignment.Center
		elseif item.Subtitle then
			description.Position = UDim2.fromScale(description.Position.X.Scale, SUBTITLE_DESCRIPTION_Y)
		end
		local limit = description:FindFirstChildOfClass("UITextSizeConstraint")
		if limit then
			-- TextScaled llenaría la caja con textos cortos: se topa según el alto de la tarjeta.
			local function fit()
				limit.MaxTextSize = math.max(8, math.floor(card.AbsoluteSize.Y * Style.DescriptionTextSize))
			end
			card:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)
			fit()
		end
	end
end

-- ─── Botones ────────────────────────────────────────────────────────────────────

-- Grosor de diseño (px a 1080) guardado para scaleStrokes + grosor real ya escalado:
-- así un botón re-estilado después (ej. al pasar a OWNED) no vuelve al grosor crudo.
local function setStrokeThickness(stroke: UIStroke, base: number)
	stroke:SetAttribute("BaseThickness", base)
	stroke.Thickness = math.max(1, base * strokeFactor())
end

-- Look común de los botones de la tarjeta: degradé, borde oscuro grueso y un aro claro
-- pegado por dentro del borde (el degradé del botón aclarado). `key` es la clave en
-- ShopConfig.ButtonColors.
local function styleButtonSkin(button: Instance, key: string)
	local buttonStyle = ShopConfig.ButtonStyle
	local colors = ShopConfig.ButtonColors[key]
	setGradient(button, colors)

	local corner = button:FindFirstChildOfClass("UICorner")
	if corner then
		corner.CornerRadius = UDim.new(buttonStyle.CornerRadius, 0)
	end
	local stroke = button:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Color = buttonStyle.OutlineColor
		setStrokeThickness(stroke, buttonStyle.OutlineThickness)
	end

	local inner = button:FindFirstChild("Inner")
	if not (inner and inner:IsA("GuiObject")) then
		return
	end
	inner.Visible = true
	inner.AnchorPoint = Vector2.new(0.5, 0.5)
	inner.Position = UDim2.fromScale(0.5, 0.5)
	inner.BackgroundTransparency = 1
	local innerCorner = inner:FindFirstChildOfClass("UICorner")
	if innerCorner then
		innerCorner.CornerRadius = UDim.new(buttonStyle.CornerRadius, 0)
	end
	local rimStroke = inner:FindFirstChildOfClass("UIStroke")
	if rimStroke then
		local white = Color3.new(1, 1, 1)
		rimStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		rimStroke.Color = white
		rimStroke.Transparency = 0
		-- El UIGradient hijo del UIStroke pinta el trazo con el mismo degradé, aclarado.
		setGradient(rimStroke, {
			colors[1]:Lerp(white, buttonStyle.RimLighten),
			colors[2]:Lerp(white, buttonStyle.RimLighten),
		})
		rimStroke:SetAttribute("Rim", true)
		setStrokeThickness(rimStroke, buttonStyle.RimThickness)
		rimStroke.Thickness = math.max(1, math.round(rimStroke.Thickness))
		local rim = rimStroke.Thickness
		inner.Size = UDim2.new(1, -2 * rim, 1, -2 * rim)
	end
end

-- Estado del botón de compra: VIEW, OWNED o precio en Robux.
local function styleBuyButton(card: GuiObject, itemId: string, item: ShopConfig.Item)
	local buy = card:FindFirstChild("BuyButton", true)
	if not buy then
		return
	end
	local price = buy:FindFirstChild("PriceLabel") :: TextLabel?

	local isView = item.Kind == "View"
	local text, key
	if isView then
		text, key = "VIEW", "View"
	elseif owned[itemId] then
		text, key = "OWNED", "Owned"
	else
		text, key = ROBUX_GLYPH .. tostring(item.Price or "?"), "Buy"
	end

	styleButtonSkin(buy, key)
	local slot = slotOf(buy)
	if slot then
		setAspect(slot, if isView then VIEW_ASPECT else BUY_ASPECT)
	end
	if price then
		local buttonStyle = ShopConfig.ButtonStyle
		price.Text = text
		price.FontFace = buttonStyle.PriceFont
		applyProps(price, PRICE_LAYOUT)
		local priceStroke = price:FindFirstChildOfClass("UIStroke")
		if priceStroke then
			priceStroke.Color = buttonStyle.PriceStrokeColor
			priceStroke.Thickness = buttonStyle.PriceStrokeThickness
		end
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

-- Botón de la tarjeta: click + hover (el mismo para regalo, gema y compra).
local function bindCardButton(button: GuiButton?, visible: boolean, onClick: () -> ())
	if not button then
		return
	end
	local slot = slotOf(button)
	if slot then
		slot.Visible = visible
	else
		button.Visible = visible
	end
	if not visible then
		return
	end
	UIEffects.bindButton(button, onClick)
	UIEffects.bindHover(button, Style.Hover.Button)
end

-- El botón de gema va justo arriba del de compra: mismo tamaño, alineado a su borde
-- derecho y separado por la MISMA distancia que hay entre regalo y compra. Ese hueco es
-- ButtonStyle.Gap del ancho de Actions (en px), así que se recalcula cuando cambia el
-- tamaño de la tarjeta.
local function placeAboveActions(card: GuiObject, actions: GuiObject, slot: GuiObject)
	local function fit()
		local cardHeight = card.AbsoluteSize.Y
		if cardHeight <= 0 then
			return
		end
		local gap = ShopConfig.ButtonStyle.Gap * actions.AbsoluteSize.X / cardHeight
		slot.AnchorPoint = Vector2.new(1, 1)
		slot.Size = UDim2.fromScale(slot.Size.X.Scale, actions.Size.Y.Scale)
		slot.Position = UDim2.fromScale(actions.Position.X.Scale, actions.Position.Y.Scale - actions.Size.Y.Scale - gap)
	end
	card:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)
	fit()
end

local function bindButtons(card: GuiObject, itemId: string, item: ShopConfig.Item)
	local actions = card:FindFirstChild("Actions") :: Frame?
	if actions then
		applyProps(actions, if item.Banner then ACTIONS_BANNER elseif item.Featured then ACTIONS_FEATURED else ACTIONS_DEFAULT)
		local layout = actions:FindFirstChildOfClass("UIListLayout")
		if layout then
			layout.Padding = UDim.new(ShopConfig.ButtonStyle.Gap, 0)
		end
	end

	local gift = card:FindFirstChild("GiftButton", true) :: GuiButton?
	local giftIcon = gift and gift:FindFirstChild("Icon") :: ImageLabel?
	if giftIcon then
		giftIcon.Image = ShopConfig.Icons.Gift
	end
	if gift then
		styleButtonSkin(gift, "Gift")
	end
	bindCardButton(gift, ShopConfig.GiftEnabled, function()
		DebugConfig.warn(("[ShopController] Regalar '%s': flujo de regalos sin implementar"):format(itemId))
	end)

	local gem = card:FindFirstChild("GemButton", true) :: GuiButton?
	local gemIcon = gem and gem:FindFirstChild("Icon") :: ImageLabel?
	if gemIcon then
		gemIcon.Image = ShopConfig.Icons.Gem
	end
	if gem then
		styleButtonSkin(gem, "Gem")
		local gemSlot = slotOf(gem)
		if gemSlot and actions then
			placeAboveActions(card, actions, gemSlot)
		end
	end
	bindCardButton(gem, item.Gem == true, function()
		DebugConfig.warn(("[ShopController] Comprar '%s' con gemas: sin implementar"):format(itemId))
	end)

	local buy = card:FindFirstChild("BuyButton", true) :: GuiButton?
	bindCardButton(buy, true, function()
		onBuy(itemId, item)
	end)
	styleBuyButton(card, itemId, item)
end

-- ─── Armado de la tienda ────────────────────────────────────────────────────────

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
		UIEffects.bindHover(card, Style.Hover.Card)
	end

	cards[itemId] = card
	return card
end

-- Cada fila es un Frame horizontal cuyo alto sale de su ancho (UIAspectRatioConstraint):
-- las tarjetas conservan su proporción en cualquier pantalla y el canvas crece solo.
local function buildRow(index: number, row: ShopConfig.Row)
	local gap = Style.Layout.CardGap
	local count = #row.Items
	local width = row.Width or 1
	local cardWidth = (width - gap * (count - 1)) / count

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
	layout.Padding = UDim.new(gap, 0)
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
		local gap = math.floor(width * Style.Layout.RowGap)
		local side = math.floor(width * Style.Layout.SidePadding)
		local edge = math.floor(width * Style.Layout.EdgePadding)
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
	local info = TweenInfo.new(Style.Blur.Duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(blur, info, { Size = if enabled then Style.Blur.Size else 0 }):Play()
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

	for index, soundId in ShopConfig.Sounds.Open do
		local sound = UIEffects.makeSound("ShopOpen" .. index, soundId, ShopConfig.Sounds.Volume)
		if sound then
			table.insert(openSounds, sound)
		end
	end
	task.spawn(function()
		local ok, err = pcall(ContentProvider.PreloadAsync, ContentProvider, openSounds)
		if not ok then
			DebugConfig.warn("[ShopController] No se pudieron precargar los sonidos: " .. tostring(err))
		end
	end)

	-- El CloseButton del Header lo conecta UIManager solo. Main tiene AnchorPoint
	-- 0.5, 0.5: la apertura crece desde el centro de la pantalla.
	UIManager.Register(WINDOW_NAME, main, {
		HiddenScale = Style.Open.FromScale,
		OpenDuration = Style.Open.Duration,
	})
	UIManager.OnOpened(WINDOW_NAME, function()
		content.CanvasPosition = Vector2.zero
		setBlur(true)
		for _, sound in openSounds do
			UIEffects.playOneShot(sound)
		end
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
