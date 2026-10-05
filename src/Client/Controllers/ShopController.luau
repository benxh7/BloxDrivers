-- Ubicación en Studio: StarterPlayer > StarterPlayerScripts > Controllers > ShopController (ModuleScript)
-- Ventana "Shop": una tarjeta UITemplates.ShopCard por item de ShopConfig.Rows. Todo lo
-- ajustable está en ShopConfig; la forma de las capas, en la plantilla de Studio.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local TweenService = game:GetService("TweenService")
local ContentProvider = game:GetService("ContentProvider")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")

local UIManager = require(script.Parent:WaitForChild("UIManager"))
local Utils = script.Parent.Parent:WaitForChild("Utils")
local UIEffects = require(Utils:WaitForChild("UIEffects"))
local UITemplates = require(Utils:WaitForChild("UITemplates"))
local PurchaseEffect = require(Utils:WaitForChild("ShopPurchaseEffect"))
local WindowLayout = require(Utils:WaitForChild("WindowLayout"))
local Remotes = require(ReplicatedStorage:WaitForChild("Remotes"))
local ShopConfig = require(ReplicatedStorage:WaitForChild("ShopConfig"))
local DebugConfig = require(ReplicatedStorage:WaitForChild("DebugConfig"))

local ShopController = {}
local spinTweens = {}

local Style = ShopConfig.Style

local WINDOW_NAME = "Shop"
local GUI_NAME = "ShopGui"
local CARD_TEMPLATE = "ShopCard"
local BLUR_NAME = "ShopBlur"

-- Los grosores son a 1080 px de alto; en pantallas chicas se afinan hasta la mitad.
local REFERENCE_HEIGHT = 1080
local MIN_STROKE_FACTOR = 0.5

local CORNER_LAYERS = { Ring = true, Background = true, Outline = true, InnerLine = true }

local ACTIONS_DEFAULT = { Position = UDim2.fromScale(0.96, 0.95), Size = UDim2.fromScale(0.56, 0.2) }
local ACTIONS_FEATURED = { Position = UDim2.fromScale(0.96, 0.95), Size = UDim2.fromScale(0.58, 0.23) }
local ACTIONS_BANNER = { Position = UDim2.fromScale(0.975, 0.93), Size = UDim2.fromScale(0.37, 0.3) }
local BUY_ASPECT = 2.5
local VIEW_ASPECT = 2.4
local PRICE_LAYOUT =
	{ AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(0.9, 0.86) }
-- Glifo de Robux de las fuentes de Roblox: se dibuja como texto, con el mismo borde.
local ROBUX_GLYPH = utf8.char(0xE002)
local BANNER_TITLE = { Position = UDim2.fromScale(0.03, 0.04), Size = UDim2.fromScale(0.62, 0.27) }
local BANNER_DESCRIPTION = { Position = UDim2.fromScale(0.03, 0.31), Size = UDim2.fromScale(0.62, 0.12) }
local RIGHT_DESCRIPTION = { Position = UDim2.fromScale(0.42, 0.2), Size = UDim2.fromScale(0.56, 0.42) }
local SUBTITLE_DESCRIPTION_Y = 0.46

local player = Players.LocalPlayer
local gui: ScreenGui
local main: GuiObject
local content: ScrollingFrame
local giftOverlay: Frame?
local giftList: ScrollingFrame?
local giftEmpty: TextLabel?
local giftItemId: string?
local setBlur: (enabled: boolean) -> ()
local openSounds: { Sound } = {}
local owned: { [string]: boolean } = {}
local cards: { [string]: GuiObject } = {}

local function strokeFactor(): number
	local camera = Workspace.CurrentCamera
	local height = if camera then camera.ViewportSize.Y else REFERENCE_HEIGHT
	return math.clamp(height / REFERENCE_HEIGHT, MIN_STROKE_FACTOR, 1)
end

-- El marco diseñado en Studio conserva sus grosores. Solo los elementos marcados
-- explícitamente como responsive se escalan con la altura de pantalla.
local function scaleStrokes(root: Instance)
	local factor = strokeFactor()
	for _, stroke in root:GetDescendants() do
		if stroke:IsA("UIStroke") and stroke:GetAttribute("ResponsiveThickness") == true then
			local base = stroke:GetAttribute("BaseThickness")
			if typeof(base) ~= "number" then
				base = stroke.Thickness
				stroke:SetAttribute("BaseThickness", base)
			end
			stroke.Thickness = math.max(1, base * factor)
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
	local points = {}
	for index, color in colors do
		table.insert(points, ColorSequenceKeypoint.new((index - 1) / math.max(1, #colors - 1), color))
	end
	gradient.Color = ColorSequence.new(points)
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

-- Se oculta el Slot y no el botón: así no se rompe el layout.
local function slotOf(button: Instance): GuiObject?
	local parent = button.Parent
	return if parent and parent:IsA("GuiObject") and parent.Name:match("Slot$") then parent else nil
end

local function applyCorners(card: GuiObject)
	for _, corner in card:GetDescendants() do
		if corner:IsA("UICorner") and corner.Parent and CORNER_LAYERS[corner.Parent.Name] then
			corner.CornerRadius = UDim.new(Style.CornerRadius, 0)
		end
	end
end

-- Capas de UIStroke con el UICorner de la tarjeta (esquinas redondas como ella). Las capas
-- se suman: el alfa de cada una hace que el total siga Opacity * (1 - d/Spread)^Curve.
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

	local function target(index: number): number
		if index > layers then
			return 0
		end
		return glow.Opacity * (1 - (index - 1) / layers) ^ glow.Curve
	end

	for index = 1, layers do
		-- La franja `index` la cubren las capas index..layers: esta aporta lo que falta.
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
	local outline = card.Outline:FindFirstChildOfClass("UIStroke")
	outline.Thickness = Style.OutlineThickness
	outline.Color = item.Outline or Color3.fromRGB(4, 4, 9)
	local ring = card.Ring
	local ringThickness = if item.Glow then item.RingThickness or Style.RingThickness else 0
	ring.Visible = ringThickness > 0
	ring.UIStroke.Color = item.Glow or Color3.new()
	ring.UIStroke.Thickness = Style.OutlineThickness + ringThickness
	buildGlow(card, item.Glow, Style.OutlineThickness + ringThickness)
	local inner = card.InnerBorder
	-- El rim está adosado a la cara interior del outline, con la transparencia de Settings.
	local rim = inner.Rim
	rim.Transparency = StarterGui.SettingsGui.Main.InnerBorder.Rim.Transparency
	rim.Color = Color3.new(1, 1, 1)
	rim.Thickness = 6
	inner.Size = UDim2.new(1, -6, 1, -6)
end

local function styleBackground(card: GuiObject, item: ShopConfig.Item)
	local background = card:FindFirstChild("Background")
	if background then
		-- El UIGradient de un CanvasGroup tiñe todo su contenido: con imagen va en blanco.
		setGradient(
			background,
			if hasImage(item.Image) then { Color3.new(1, 1, 1), Color3.new(1, 1, 1) } else item.Color
		)
		local art = background:FindFirstChild("Art") :: ImageLabel?
		if art then
			art.Visible = hasImage(item.Image)
			art.Image = if hasImage(item.Image) then item.Image else ""
		end
		local rays = background:FindFirstChild("Rays") :: ImageLabel?
		if rays then
			rays.Visible = item.Rays == true
		end
		local pattern = background:FindFirstChild("Pattern")
		if pattern and pattern:IsA("ImageLabel") then
			pattern.Visible = item.Pattern ~= false
			pattern.ImageColor3 = item.PatternColor or Color3.fromRGB(65, 65, 65)
			pattern.ImageTransparency = item.PatternTransparency or 0.05
		end
		local titleBar = background:FindFirstChild("TitleBar") :: Frame?
		if titleBar then
			titleBar.Visible = not item.Banner
		end
	end

	if item.SpinDecal and background then
		local decal = card:FindFirstChild("SpinDecal")
		if decal then
			decal.Visible = true
			decal.Image = ShopConfig.SpinDecal.Image
			decal.ImageTransparency = ShopConfig.SpinDecal.Transparency
			decal.Position = if item.IconLayout then item.IconLayout.Position else UDim2.fromScale(0.5, 0.55)
			local tween = TweenService:Create(
				decal,
				TweenInfo.new(
					ShopConfig.SpinDecal.SecondsPerTurn,
					Enum.EasingStyle.Linear,
					Enum.EasingDirection.InOut,
					-1
				),
				{ Rotation = 360 }
			)
			table.insert(spinTweens, tween)
			if UIManager.IsOpen(WINDOW_NAME) then
				tween:Play()
			end
		end
	end
	local icon = card:FindFirstChild("Icon") :: ImageLabel?
	if icon then
		icon.Visible = hasImage(item.Icon)
		icon.Image = item.Icon or ""
		if item.IconLayout then
			applyProps(icon, item.IconLayout)
		end
		-- Cada paquete usa su ilustración completa desde ShopConfig.
		local rewardType = item.Reward and item.Reward.Type
		if (rewardType == "Cash" or item.Title == "2x Cash") and not item.Featured and background then
			for index = 1, 12 do
				local bill = Instance.new("ImageLabel")
				bill.Name = "CashPattern" .. index
				bill.Image = ShopConfig.Icons.CashPattern
				bill.BackgroundTransparency = 1
				bill.ImageTransparency = 0.85
				bill.Size = UDim2.fromScale(0.21, 0.2)
				bill.Position =
					UDim2.fromScale(((index - 1) % 4) * 0.28 - 0.03, 0.2 + math.floor((index - 1) / 4) * 0.27)
				bill.Rotation = -25
				bill.ScaleType = Enum.ScaleType.Fit
				bill.ZIndex = 2
				bill.Parent = background
			end
		end
	end
end

local function styleTexts(card: GuiObject, item: ShopConfig.Item)
	local title = card:FindFirstChild("Title") :: TextLabel?
	if title then
		title.FontFace = ShopConfig.Font
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
		subtitle.FontFace = ShopConfig.Font
		subtitle.Visible = item.Subtitle ~= nil
		subtitle.Text = item.Subtitle or ""
	end

	local description = card:FindFirstChild("Description") :: TextLabel?
	if description then
		description.FontFace = ShopConfig.Font
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
			-- Sin tope, TextScaled llenaría la caja con textos cortos.
			local function fit()
				limit.MaxTextSize = math.max(8, math.floor(card.AbsoluteSize.Y * Style.DescriptionTextSize))
			end
			card:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)
			fit()
		end
	end
end

-- Guarda el grosor de diseño y pone el escalado: un re-estilo (ej. OWNED) no vuelve al crudo.
local function setStrokeThickness(stroke: UIStroke, base: number)
	stroke:SetAttribute("BaseThickness", base)
	stroke:SetAttribute("ResponsiveThickness", nil)
	stroke.Thickness = base
end

-- `key` es la clave en ShopConfig.ButtonColors.
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
		-- Un UIGradient hijo de un UIStroke pinta el trazo.
		setGradient(rimStroke, {
			colors[1]:Lerp(white, buttonStyle.RimLighten),
			colors[math.ceil(#colors / 2)]:Lerp(white, buttonStyle.RimLighten),
			colors[#colors]:Lerp(white, buttonStyle.RimLighten),
		})
		rimStroke:SetAttribute("Rim", true)
		setStrokeThickness(rimStroke, buttonStyle.RimThickness)
		rimStroke.Thickness = math.max(1, math.round(rimStroke.Thickness))
		local rim = rimStroke.Thickness
		inner.Size = UDim2.new(1, -2 * rim, 1, -2 * rim)
	end

	-- CanvasGroup y no ClipsDescendants: el hover rota el botón y la rotación apaga ese recorte.
	local dotsClip = button:FindFirstChild("DotsClip")
	if dotsClip and dotsClip:IsA("GuiObject") then
		dotsClip.Size = inner.Size
		local dotsCorner = dotsClip:FindFirstChildOfClass("UICorner")
		if dotsCorner then
			dotsCorner.CornerRadius = UDim.new(buttonStyle.CornerRadius, 0)
		end
	end
end

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
		local number = tostring(item.Price or "?")
		number = number:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
		text, key = ROBUX_GLYPH .. number, "Buy"
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
	PurchaseEffect.Start(itemId, item, function()
		Remotes.event("RequestShopPurchase"):FireServer(itemId)
	end)
end

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
	if slot then
		-- UIScale toma el centro del botón como origen del hover.
		button.AnchorPoint = Vector2.new(0.5, 0.5)
		button.Position = UDim2.fromScale(0.5, 0.5)
		button.Size = UDim2.fromScale(1, 1)
	end
	UIEffects.bindButton(button, onClick)
	UIEffects.bindHover(button, Style.Hover.Button)
end

-- Misma separación que regalo-compra: Gap es del ANCHO de Actions, por eso se recalcula en px
-- al cambiar el tamaño de la tarjeta.
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

local function closeGift()
	if main then
		main.Header.Visible = true
		content.Visible = true
		main.InnerBorder.Visible = true
		main.Outline.Enabled = true
		main.BackgroundTransparency = main:GetAttribute("ShopBackgroundTransparency") or 0.35
	end
	giftItemId = nil
	if giftOverlay then
		giftOverlay.Visible = false
	end
end

local function updateGiftCanvas()
	if not giftList then
		return
	end
	local layout = giftList:FindFirstChildOfClass("UIListLayout")
	local padding = giftList:FindFirstChildOfClass("UIPadding")
	if layout then
		local top = if padding then padding.PaddingTop.Offset else 0
		local bottom = if padding then padding.PaddingBottom.Offset else 0
		giftList.CanvasSize = UDim2.fromOffset(0, layout.AbsoluteContentSize.Y + top + bottom)
	end
end

local function selectGiftTarget(target: Player)
	local itemId = giftItemId
	if not itemId then
		return
	end
	local item = ShopConfig.get(itemId)
	if not item then
		return
	end
	-- El catálogo usa ProductId 0 por ahora. Guardamos la selección para que la UI y
	-- el flujo queden listos; el prompt real se conecta al asignar productos de regalo.
	player:SetAttribute("SelectedGiftItem", itemId)
	player:SetAttribute("SelectedGiftTargetUserId", target.UserId)
	if not item.ProductId or item.ProductId <= 0 then
		DebugConfig.warn(
			("[ShopController] Regalo '%s' para @%s seleccionado; falta configurar ProductId"):format(
				itemId,
				target.Name
			)
		)
	else
		DebugConfig.warn(
			("[ShopController] Regalo '%s' para @%s seleccionado; falta el producto de gifting persistente"):format(
				itemId,
				target.Name
			)
		)
	end
	closeGift()
end

local function clearGiftRows()
	if not giftList then
		return
	end
	for _, child in giftList:GetChildren() do
		if child:IsA("GuiObject") and child ~= giftEmpty then
			child:Destroy()
		end
	end
end

local function refreshGiftPlayers()
	if not (giftList and giftEmpty) then
		return
	end
	clearGiftRows()
	local count = 0
	for _, target in Players:GetPlayers() do
		if target == player then
			continue
		end
		local row = UITemplates.clone("ShopGiftPlayer")
		if not row then
			continue
		end
		count += 1
		row.Name = "Player_" .. target.UserId
		row.LayoutOrder = count
		row.DisplayName.Text = target.DisplayName
		row.Username.Text = "@" .. target.Name
		row.Parent = giftList
		local selectButton = row:FindFirstChild("SelectButton") :: GuiButton?
		if selectButton then
			UIEffects.bindButton(selectButton, function()
				selectGiftTarget(target)
			end)
			UIEffects.bindHover(selectButton, Style.Hover.Button)
		end
		task.spawn(function()
			local ok, image = pcall(
				Players.GetUserThumbnailAsync,
				Players,
				target.UserId,
				Enum.ThumbnailType.HeadShot,
				Enum.ThumbnailSize.Size150x150
			)
			if ok and row.Parent then
				row.Avatar.Image = image
			end
		end)
	end
	if count == 0 then
		local preview = UITemplates.clone("ShopGiftPlayer")
		if preview then
			preview.Name = "GiftPreview"
			preview.LayoutOrder = 1
			preview.DisplayName.Text = "Preview Player"
			preview.Username.Text = "@player_preview"
			local selectButton = preview:FindFirstChild("SelectButton") :: TextButton?
			if selectButton then
				selectButton.Label.Text = "Select"
				selectButton.Active = true
				selectButton.Interactable = true
				UIEffects.bindButton(selectButton, function()
					-- Vista previa: reproduce el feedback sin seleccionar un destinatario real.
				end)
				UIEffects.bindHover(selectButton, Style.Hover.Button)
			end
			preview.Parent = giftList
			task.spawn(function()
				local ok, image = pcall(
					Players.GetUserThumbnailAsync,
					Players,
					player.UserId,
					Enum.ThumbnailType.HeadShot,
					Enum.ThumbnailSize.Size150x150
				)
				if ok and preview.Parent then
					preview.Avatar.Image = image
				end
			end)
		end
	end
	giftEmpty.Visible = false
	updateGiftCanvas()
end

local function openGift(itemId: string)
	if not giftOverlay then
		return
	end
	giftItemId = itemId
	refreshGiftPlayers()
	giftOverlay.Visible = true
	main.Header.Visible = false
	content.Visible = false
	main.InnerBorder.Visible = false
	main.Outline.Enabled = false
	main.BackgroundTransparency = 1
	local h = math.clamp(giftOverlay.AbsoluteSize.X * 0.185, 76, 104)
	for _, row in giftList:GetChildren() do
		if row:IsA("Frame") then
			row.Size = UDim2.new(1, 0, 0, h)
		end
	end
	updateGiftCanvas()
end

local function bindButtons(card: GuiObject, itemId: string, item: ShopConfig.Item)
	local actions = card:FindFirstChild("Actions") :: Frame?
	if actions then
		applyProps(
			actions,
			if item.Banner then ACTIONS_BANNER elseif item.Featured then ACTIONS_FEATURED else ACTIONS_DEFAULT
		)
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
		openGift(itemId)
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

local function buildCard(itemId: string, item: ShopConfig.Item, width: number): GuiObject?
	local card = UITemplates.clone(CARD_TEMPLATE)
	if not card then
		return nil
	end
	card.Name = itemId
	card.Size = UDim2.fromScale(1, 1)
	card.AnchorPoint = Vector2.new(0.5, 0.5)
	card.Position = UDim2.fromScale(0.5, 0.5)

	styleFrame(card, item)
	styleBackground(card, item)
	styleTexts(card, item)
	bindButtons(card, itemId, item)

	UIEffects.bindHover(card, Style.Hover.Card)

	cards[itemId] = card
	return card
end

-- El alto de cada fila sale de su ancho: las tarjetas conservan su proporción en cualquier pantalla.
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
			DebugConfig.warn(
				("[ShopController] Rows[%d] nombra '%s', que no está en ShopConfig.Items"):format(index, itemId)
			)
			continue
		end
		local card = buildCard(itemId, item, cardWidth)
		if card then
			card.LayoutOrder = order
			local slot = Instance.new("Frame")
			slot.Name = itemId .. "Slot"
			slot.BackgroundTransparency = 1
			slot.Size = UDim2.fromScale(cardWidth, 1)
			slot.LayoutOrder = order
			slot.Parent = frame
			card.Parent = slot
		end
	end

	frame.Parent = content
end

local function buildShop()
	for _, t in spinTweens do
		t:Cancel()
	end
	table.clear(spinTweens)
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

-- Escala de la apertura (UIScale del Main) medida en Content: sale del mismo layout que las
-- posiciones absolutas, así que coincide con ellas aunque el UIScale ya haya avanzado.
local function openScale(): number
	local height = main.Size.Y.Offset + content.Size.Y.Offset
	return if height > 0 then content.AbsoluteSize.Y / height else 1
end

-- A mano: dentro de un ScrollingFrame el padding en Scale se mide contra el canvas, y
-- AutomaticCanvasSize dejaba afuera las últimas filas.
local function bindCanvas()
	local layout = content:FindFirstChildOfClass("UIListLayout")
	local padding = content:FindFirstChildOfClass("UIPadding")
	if not layout then
		return
	end
	content.AutomaticCanvasSize = Enum.AutomaticSize.None
	local function fit()
		-- Sin la escala de la apertura: si no, las filas se reacomodan mientras la ventana crece.
		local width = content.AbsoluteSize.X / openScale()
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
		content.CanvasSize = UDim2.fromOffset(0, layout.AbsoluteContentSize.Y / openScale() + edge * 2)
	end
	content:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)
	layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(fit)
	fit()
end

local function fitWindow()
	local size = gui.AbsoluteSize
	if size.X <= 0 or size.Y <= 0 then
		return
	end
	local width, height = WindowLayout.fitMain(size, main)
	local headerHeight, closeSize = WindowLayout.fitHeader(main.Header, height, 88, 52)
	content.Position = UDim2.fromOffset(0, headerHeight + 6)
	content.Size = UDim2.new(1, 0, 1, -headerHeight - 14)
	if giftOverlay then
		giftOverlay.Size = UDim2.fromScale(if width < 550 then 0.98 else 0.82, 1)
		giftOverlay.GiftCloseButton.Size = UDim2.fromOffset(closeSize, closeSize)
		giftOverlay.Title.TextLimit.MaxTextSize = math.clamp(height * 0.09, 26, 56)
		local rowHeight = math.clamp(giftOverlay.AbsoluteSize.X * 0.185, 76, 104)
		if giftList then
			for _, row in giftList:GetChildren() do
				if row:IsA("Frame") then
					row.Size = UDim2.new(1, 0, 0, rowHeight)
				end
			end
			updateGiftCanvas()
		end
	end
	scaleStrokes(main)
end

local sectionRequest = 0
local sectionScroll: RBXScriptConnection?
local function cancelSectionScroll()
	sectionRequest += 1
	if sectionScroll then
		sectionScroll:Disconnect()
		sectionScroll = nil
	end
end

-- CanvasPosition va en px escalados por la apertura. Absolute* es del frame anterior: se pasa
-- a escala 1 con su propia escala (`measured`) y se vuelve a escalar con la actual del UIScale.
local function sectionTarget(row: GuiObject, measured: number): number
	local windowScale = main:FindFirstChild("WindowScale") :: UIScale?
	local current = if windowScale then windowScale.Scale else 1
	local viewport = content.AbsoluteWindowSize.Y / measured
	local margin = math.clamp(viewport * 0.035, 12, 24)
	local rowTop = (row.AbsolutePosition.Y - content.AbsolutePosition.Y + content.CanvasPosition.Y) / measured
	local limit = math.max(0, content.AbsoluteCanvasSize.Y / measured - viewport)
	return math.clamp(rowTop - margin, 0, limit) * current
end

-- Scroll suave (Quint) que arranca junto con la apertura, sin esperar a que termine.
function ShopController.OpenSection(section: string)
	local targetName = ({ Cash = "Cash10K", Gems = "Gems100" })[section]
	if not targetName or not content then
		return false
	end
	cancelSectionScroll()
	local request = sectionRequest
	UIManager.Open(WINDOW_NAME)
	closeGift()
	local card = cards[targetName]
	if not card then
		return true
	end
	-- La fila, no la tarjeta: el hover de la tarjeta la agranda y la gira.
	local row = card.Parent.Parent
	local start = content.CanvasPosition.Y
	local startedAt = os.clock()
	local duration: number? = nil
	-- RenderStepped: el UIScale ya tiene el valor que se va a dibujar en este frame.
	sectionScroll = RunService.RenderStepped:Connect(function()
		if request ~= sectionRequest or not UIManager.IsOpen(WINDOW_NAME) then
			cancelSectionScroll()
			return
		end
		local scale = openScale()
		if scale < 0.05 then
			return
		end
		local target = sectionTarget(row, scale)
		duration = duration or math.clamp(math.abs(target - start) / 3500, 0.3, 0.65)
		local alpha = math.clamp((os.clock() - startedAt) / duration, 0, 1)
		local eased = 1 - (1 - alpha) ^ 5
		content.CanvasPosition = Vector2.new(0, start + (target - start) * eased)
		-- Sigue corrigiendo hasta que termine la apertura (UIScale "WindowScale" de UIEffects en 1);
		-- el tope evita quedar pegado si algo deja la escala distinta de 1.
		local windowScale = main:FindFirstChild("WindowScale") :: UIScale?
		local opened = not windowScale or windowScale.Scale == 1
		if alpha >= 1 and (opened or os.clock() - startedAt > duration + 1) then
			cancelSectionScroll()
		end
	end)
	return true
end

function ShopController.Init()
	gui = UIManager.WaitForGui(GUI_NAME)
	if not gui then
		return
	end
	local found = UIEffects.findChild(gui, "Main", GUI_NAME)
	if not (found and found:IsA("GuiObject")) then
		return
	end
	main = found
	main:SetAttribute("ShopBackgroundTransparency", main.BackgroundTransparency)
	local list = UIEffects.findChild(main, "Content", GUI_NAME)
	if not (list and list:IsA("ScrollingFrame")) then
		return
	end
	content = list
	content.InputBegan:Connect(function(input)
		if
			input.UserInputType == Enum.UserInputType.Touch
			or input.UserInputType == Enum.UserInputType.MouseButton1
		then
			cancelSectionScroll()
		end
	end)
	content.InputChanged:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseWheel then
			cancelSectionScroll()
		end
	end)
	giftOverlay = main:FindFirstChild("GiftOverlay") :: Frame?
	if giftOverlay then
		giftOverlay.Visible = false
		giftList = giftOverlay:FindFirstChild("PlayerList") :: ScrollingFrame?
		giftEmpty = giftList and giftList:FindFirstChild("EmptyLabel") :: TextLabel?
		local giftClose = giftOverlay:FindFirstChild("GiftCloseButton") :: GuiButton?
		if giftClose then
			UIEffects.bindButton(giftClose, closeGift)
			UIEffects.bindHover(giftClose, { Scale = 1.08, Rotation = 5, Duration = 0.14 })
		end
		if giftList then
			local layout = giftList:FindFirstChildOfClass("UIListLayout")
			if layout then
				layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(updateGiftCanvas)
			end
		end
	end
	local windowClose = main:FindFirstChild("CloseButton", true) :: GuiButton?
	if windowClose then
		UIEffects.bindHover(windowClose, { Scale = 1.08, Rotation = 5, Duration = 0.14 })
	end

	setBlur = UIEffects.makeBlur(BLUR_NAME, Style.Blur.Size, Style.Blur.Duration)

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

	-- Main tiene AnchorPoint 0.5: la apertura crece desde el centro.
	UIManager.Register(WINDOW_NAME, main, {
		HiddenScale = Style.Open.FromScale,
		OpenDuration = Style.Open.Duration,
	})
	UIManager.OnOpened(WINDOW_NAME, function()
		for _, t in spinTweens do
			t:Play()
		end
		content.CanvasPosition = Vector2.zero
		closeGift()
		task.defer(fitWindow)
		setBlur(true)
		for _, sound in openSounds do
			UIEffects.playOneShot(sound)
		end
	end)
	UIManager.OnClosed(WINDOW_NAME, function()
		cancelSectionScroll()
		for _, t in spinTweens do
			t:Pause()
		end
		closeGift()
		setBlur(false)
	end)

	gui.Destroying:Connect(function()
		for _, t in spinTweens do
			t:Cancel()
		end
		table.clear(spinTweens)
	end)
	buildShop()
	bindCanvas()
	fitWindow()
	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(fitWindow)
	Players.PlayerAdded:Connect(function()
		if giftOverlay and giftOverlay.Visible then
			refreshGiftPlayers()
		end
	end)
	Players.PlayerRemoving:Connect(function()
		if giftOverlay and giftOverlay.Visible then
			task.defer(refreshGiftPlayers)
		end
	end)
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed or not (giftOverlay and giftOverlay.Visible) then
			return
		end
		if input.KeyCode == Enum.KeyCode.Escape or input.KeyCode == Enum.KeyCode.ButtonB then
			closeGift()
		end
	end)

	local camera = Workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
			fitWindow()
		end)
	end

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
