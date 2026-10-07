-- Ubicación en Studio: ReplicatedStorage > ShopConfig (ModuleScript)
-- Catálogo y estilo de la tienda. Agregar un item = su entrada en `Items` y su Id en `Rows`.
-- Kind: "Product" (varias compras), "GamePass" (una vez, pasa a OWNED) o "View" (abre ViewTarget).
local ShopConfig = {}

-- Misma familia y peso visual que usa SettingsGui.
ShopConfig.Font = Font.new("rbxasset://fonts/families/Montserrat.json", Enum.FontWeight.Heavy, Enum.FontStyle.Normal)

export type Reward = {
	-- Necesita un grant registrado (ShopService.RegisterGrant) o la compra queda pendiente.
	Type: string,
	Amount: number,
}

export type IconLayout = {
	Position: UDim2,
	Size: UDim2,
}

export type Item = {
	Kind: "Product" | "GamePass" | "View",
	Title: string,
	Subtitle: string?,
	Description: string?,
	-- 0 = todavía sin crear: el botón avisa y no compra.
	ProductId: number?,
	-- Solo se MUESTRA: el que se cobra lo define Roblox.
	Price: number?,
	Reward: Reward?,
	ViewTarget: string?,
	-- Sin imagen (rbxassetid://0), el fondo es el degradé de `Color`.
	Image: string,
	Color: { Color3 },
	Icon: string?,
	IconLayout: IconLayout?,
	-- Brillo exterior y línea clara interior. nil = solo borde negro.
	Glow: Color3?,
	-- Anillo sólido entre el borde negro y el brillo (px).
	RingThickness: number?,
	Outline: Color3?,
	TitleColor: Color3?,
	TitleStroke: Color3?,
	DescriptionColor: Color3?,
	-- "Right" = centrada en la mitad derecha (estilo bundle).
	DescriptionAlign: ("Left" | "Right")?,
	-- Puntos halftone de la esquina (default true).
	Pattern: boolean?,
	PatternColor: Color3?,
	PatternTransparency: number?,
	SpinDecal: boolean?,
	Rays: boolean?,
	-- Botón de gema (el flujo de gemas todavía no existe).
	Gem: boolean?,
	-- Bundle: botones más grandes y sin hover.
	Featured: boolean?,
	-- Pase: sin barra de título, título grande a la izquierda y sin hover.
	Banner: boolean?,
}

export type Row = {
	Items: { string },
	-- Ancho/alto de cada tarjeta.
	CardAspect: number,
	-- Fracción del ancho que ocupa la fila (default 1).
	Width: number?,
}

-- El de Robux no va acá: es el glifo de texto utf8.char(0xE002), con el mismo borde que el precio.
ShopConfig.Icons = {
	CashPattern = "rbxassetid://105607438768052",
	Shop = "rbxassetid://135748009349034",
	Halftone = "rbxassetid://97604529937489",
	Gift = "rbxassetid://121134508495965",
	Gem = "rbxassetid://83700565477340",
}

-- Arte de los packs locales. Procedencia e IDs en ShopAssets/manifest.json.
local ART = {
	Coins = "rbxassetid://105607438768052",
	CashStacks = "rbxassetid://133495653316055",
	CashPile = "rbxassetid://83574433548351",
	CashBag = "rbxassetid://85864455116402",
	CashCrate = "rbxassetid://101510053154843",
	CashSafe = "rbxassetid://93557666275221",
	Heart = "rbxassetid://115365429901908",
	Chest = "rbxassetid://96479466263272",
	Crown = "rbxassetid://81455229876046",
	Shield = "rbxassetid://137799890267118",
	PassBackground = "rbxassetid://104433970768289",
	Gem = ShopConfig.Icons.Gem,
	Gems500 = "rbxassetid://97465423896694",
	Gems1K = "rbxassetid://134735027357120",
	Gems4K = "rbxassetid://139650626264040",
	Gems10K = "rbxassetid://102213869313610",
}

-- Degradé (arriba, abajo). Buy / View / Owned son los estados del botón de compra.
ShopConfig.ButtonColors = {
	Buy = { Color3.fromRGB(145, 255, 45), Color3.fromRGB(30, 245, 10), Color3.fromRGB(0, 190, 0) },
	View = { Color3.fromRGB(155, 230, 255), Color3.fromRGB(55, 180, 245), Color3.fromRGB(20, 125, 220) },
	Owned = { Color3.fromRGB(205, 205, 218), Color3.fromRGB(150, 150, 168), Color3.fromRGB(100, 100, 120) },
	Gift = { Color3.fromRGB(115, 90, 255), Color3.fromRGB(170, 70, 245), Color3.fromRGB(235, 65, 255) },
	Gem = { Color3.fromRGB(105, 230, 255), Color3.fromRGB(20, 175, 255), Color3.fromRGB(25, 85, 235) },
}

-- Todos los botones de las tarjetas. Grosores en px a 1080 de alto.
ShopConfig.ButtonStyle = {
	-- Scale del lado más corto.
	CornerRadius = 0.05,
	OutlineColor = Color3.fromRGB(18, 18, 32),
	OutlineThickness = 3,
	-- Aro claro por dentro del borde: el degradé del botón aclarado (RimLighten 0..1).
	RimThickness = 3,
	RimLighten = 0.55,
	PriceFont = ShopConfig.Font,
	PriceStrokeColor = Color3.fromRGB(18, 18, 32),
	PriceStrokeThickness = 3,
	-- Separación regalo-compra y gema-compra (fracción del ancho de Actions).
	Gap = 0.06,
}

-- Tamaños en px a 1080 de alto: en pantallas más chicas se achican en proporción.
ShopConfig.Style = {
	-- Esquinas de todas las capas (Scale del lado más corto).
	CornerRadius = 0.10,
	OutlineThickness = 6,
	-- Spread = px por fuera del borde, Opacity = intensidad pegado al borde, Curve = 1 parejo
	-- / 2 fuerte en el borde y cola suave, Layers = 1 por px de Spread (sin bandas).
	Glow = { Spread = 22, Opacity = 0.45, Curve = 2, Layers = 22 },
	-- Anillo por defecto (0 = ninguno).
	RingThickness = 0,
	-- Cuánto se aclara el color del brillo para la línea interior (0..1).
	InnerLineLighten = 0.45,
	-- Texto máximo de la descripción, en fracción del alto de la tarjeta.
	DescriptionTextSize = 0.115,
	-- Fracciones del ancho de la lista. Los paddings dejan lugar para que no se corte el brillo.
	Layout = { CardGap = 0.055, RowGap = 0.06, SidePadding = 0.045, EdgePadding = 0.055 },
	-- Scale = cuánto crece, Rotation = grados a la derecha, Duration = segundos.
	Hover = {
		Card = { Scale = 1.03, Duration = 0.3 },
		Button = { Scale = 1.07, Rotation = 5, Duration = 0.3 },
	},
	-- Desenfoque del mundo con la tienda abierta.
	Blur = { Size = 16, Duration = 0.2 },
	-- Se abre desde el centro, de FromScale a su tamaño normal en Duration segundos.
	Open = { FromScale = 0.1, Duration = 0.35 },
}

-- Scale: tamaño de los rayos respecto del ícono de la card (más de 1 = asoman alrededor).
ShopConfig.SpinDecal = { Image = "rbxassetid://122287190167781", SecondsPerTurn = 12, Transparency = 0.15, Scale = 1.5 }

-- Campana + swoosh: exclusivos de la tienda, suenan juntos al abrirla. El resto de las
-- ventanas solo tienen el clic del botón.
ShopConfig.Sounds = {
	Open = { "rbxassetid://127488139302452", "rbxassetid://98891178613563" },
	Volume = 1.0,
}

-- Muestra el selector de destinatario. Los ProductId en 0 mantienen el catálogo como demo.
ShopConfig.GiftEnabled = true

local function product(
	title: string,
	price: number,
	rewardType: string,
	amount: number,
	colors: { Color3 },
	glow: Color3,
	icon: string?
): Item
	return {
		Kind = "Product",
		Title = title,
		ProductId = 0,
		Price = price,
		Reward = { Type = rewardType, Amount = amount },
		Image = "rbxassetid://0",
		Color = colors,
		Icon = icon,
		Glow = glow,
		PatternColor = Color3.fromRGB(65, 65, 65),
		PatternTransparency = 0.05,
	}
end

ShopConfig.Items = {
	StarterBundle = {
		Kind = "Product",
		Title = "STARTER BUNDLE",
		Description = "5K Cash\n1X Nitro Boost",
		ProductId = 0,
		Price = 149,
		Reward = { Type = "Cash", Amount = 5000 },
		Image = "rbxassetid://0",
		Color = { Color3.fromRGB(255, 230, 70), Color3.fromRGB(245, 155, 20) },
		Icon = ART.Coins,
		IconLayout = { Position = UDim2.fromScale(0.28, 0.6), Size = UDim2.fromScale(0.55, 0.62) },
		Glow = Color3.fromRGB(255, 225, 60),
		RingThickness = 2,
		TitleColor = Color3.fromRGB(255, 250, 205),
		DescriptionColor = Color3.fromRGB(235, 55, 70),
		DescriptionAlign = "Right",
		Featured = true,
		SpinDecal = true,
	},
	ChampionPass = {
		Kind = "View",
		Title = "Champion Pass",
		Description = "Unlock the second row of rewards",
		ViewTarget = "Pass",
		Image = ART.PassBackground,
		Color = { Color3.fromRGB(40, 30, 120), Color3.fromRGB(15, 10, 50) },
		Icon = ART.Shield,
		IconLayout = { Position = UDim2.fromScale(0.875, 0.3), Size = UDim2.fromScale(0.2, 0.5) },
		Glow = Color3.fromRGB(70, 120, 255),
		RingThickness = 2,
		Outline = Color3.fromRGB(150, 180, 255),
		TitleColor = Color3.fromRGB(135, 125, 255),
		TitleStroke = Color3.fromRGB(15, 10, 60),
		Pattern = false,
		Banner = true,
	},
	SniperChance2x = {
		Kind = "GamePass",
		Title = "2x Sniper Chance",
		Description = "",
		ProductId = 0,
		Price = 299,
		Image = "rbxassetid://0",
		Color = { Color3.fromRGB(55, 225, 245), Color3.fromRGB(20, 150, 205) },
		Glow = Color3.fromRGB(40, 225, 255),
		PatternColor = Color3.fromRGB(65, 65, 65),
		PatternTransparency = 0.05,
		Gem = true,
	},
	CrateSkip = {
		Kind = "GamePass",
		Title = "Crate Skip",
		Subtitle = "Instantly Open Crates",
		Description = "",
		Icon = ART.Chest,
		ProductId = 0,
		Price = 49,
		Image = "rbxassetid://0",
		Color = { Color3.fromRGB(125, 85, 255), Color3.fromRGB(45, 25, 155) },
		Glow = Color3.fromRGB(140, 90, 255),
		PatternColor = Color3.fromRGB(65, 65, 65),
		PatternTransparency = 0.05,
		Gem = true,
	},
	Cash2x = {
		Kind = "GamePass",
		Title = "2x Cash",
		Description = "- 2x Cash from all sources",
		ProductId = 0,
		Price = 199,
		Image = "rbxassetid://0",
		Color = { Color3.fromRGB(130, 235, 90), Color3.fromRGB(40, 175, 60) },
		Icon = ART.CashStacks,
		IconLayout = { Position = UDim2.fromScale(0.45, 0.62), Size = UDim2.fromScale(0.5, 0.58) },
		Glow = Color3.fromRGB(60, 230, 90),
		Pattern = false,
		Gem = true,
		SpinDecal = true,
	},
	VIP = {
		Kind = "GamePass",
		Title = "VIP",
		Description = "- +50% Cash\n- VIP Chat Tag",
		ProductId = 0,
		Price = 149,
		Image = "rbxassetid://0",
		Color = { Color3.fromRGB(255, 215, 60), Color3.fromRGB(245, 150, 30) },
		Icon = ART.Crown,
		IconLayout = { Position = UDim2.fromScale(0.45, 0.62), Size = UDim2.fromScale(0.5, 0.62) },
		Glow = Color3.fromRGB(255, 200, 50),
		Rays = true,
		Pattern = false,
		Gem = true,
	},
	Revive1 = product(
		"+1 Revive",
		10,
		"Revive",
		1,
		{ Color3.fromRGB(255, 105, 205), Color3.fromRGB(225, 30, 145) },
		Color3.fromRGB(255, 80, 200),
		ART.Heart
	),
	Revive3 = product(
		"+3 Revive",
		30,
		"Revive",
		3,
		{ Color3.fromRGB(255, 105, 205), Color3.fromRGB(225, 30, 145) },
		Color3.fromRGB(255, 80, 200),
		ART.Heart
	),
	Revive10 = product(
		"+10 Revive",
		100,
		"Revive",
		10,
		{ Color3.fromRGB(255, 105, 205), Color3.fromRGB(225, 30, 145) },
		Color3.fromRGB(255, 80, 200),
		ART.Heart
	),
	Gems100 = product(
		"+100 Gems",
		100,
		"Gems",
		100,
		{ Color3.fromRGB(190, 238, 255), Color3.fromRGB(35, 175, 245) },
		Color3.fromRGB(50, 220, 255),
		ART.Gem
	),
	Gems500 = product(
		"+500 Gems",
		500,
		"Gems",
		500,
		{ Color3.fromRGB(190, 238, 255), Color3.fromRGB(35, 175, 245) },
		Color3.fromRGB(50, 220, 255),
		ART.Gems500
	),
	Gems1K = product(
		"+1K Gems",
		1000,
		"Gems",
		1000,
		{ Color3.fromRGB(190, 238, 255), Color3.fromRGB(35, 175, 245) },
		Color3.fromRGB(50, 220, 255),
		ART.Gems1K
	),
	Gems4K = product(
		"+4K Gems",
		4000,
		"Gems",
		4000,
		{ Color3.fromRGB(180, 230, 255), Color3.fromRGB(25, 155, 235) },
		Color3.fromRGB(30, 205, 255),
		ART.Gems4K
	),
	Gems10K = product(
		"+10K Gems",
		10000,
		"Gems",
		10000,
		{ Color3.fromRGB(180, 230, 255), Color3.fromRGB(25, 155, 235) },
		Color3.fromRGB(30, 205, 255),
		ART.Gems10K
	),
	Cash10K = product(
		"+10K Cash",
		100,
		"Cash",
		10000,
		{ Color3.fromRGB(165, 245, 100), Color3.fromRGB(55, 185, 45) },
		Color3.fromRGB(115, 240, 75),
		ART.Coins
	),
	Cash25K = product(
		"+25K Cash",
		180,
		"Cash",
		25000,
		{ Color3.fromRGB(165, 245, 100), Color3.fromRGB(55, 185, 45) },
		Color3.fromRGB(115, 240, 75),
		ART.CashStacks
	),
	Cash75K = product(
		"+75K Cash",
		352,
		"Cash",
		75000,
		{ Color3.fromRGB(165, 245, 100), Color3.fromRGB(55, 185, 45) },
		Color3.fromRGB(115, 240, 75),
		ART.CashPile
	),
	Cash150K = product(
		"+150K Cash",
		599,
		"Cash",
		150000,
		{ Color3.fromRGB(150, 235, 85), Color3.fromRGB(42, 165, 38) },
		Color3.fromRGB(105, 225, 65),
		ART.CashBag
	),
	Cash300K = product(
		"+300K Cash",
		999,
		"Cash",
		300000,
		{ Color3.fromRGB(150, 235, 85), Color3.fromRGB(42, 165, 38) },
		Color3.fromRGB(105, 225, 65),
		ART.CashCrate
	),
	Cash500K = product(
		"+500K Cash",
		1499,
		"Cash",
		500000,
		{ Color3.fromRGB(140, 225, 75), Color3.fromRGB(35, 150, 32) },
		Color3.fromRGB(95, 215, 55),
		ART.CashSafe
	),
} :: { [string]: Item }

-- SpinDecal en el pack más grande de cada fila: resalta lo que más conviene comprar. Pocos a
-- propósito: si gira todo, ninguno destaca.
for _, id in { "Revive10", "Gems10K", "Cash500K" } do
	ShopConfig.Items[id].SpinDecal = true
end

-- Filas de arriba hacia abajo.
ShopConfig.Rows = {
	{ Items = { "StarterBundle" }, CardAspect = 1.32, Width = 0.49 },
	{ Items = { "ChampionPass" }, CardAspect = 2.85, Width = 0.97 },
	{ Items = { "SniperChance2x", "CrateSkip" }, CardAspect = 1.6 },
	{ Items = { "Cash2x", "VIP" }, CardAspect = 1.6 },
	{ Items = { "Revive1", "Revive3", "Revive10" }, CardAspect = 0.92 },
	{ Items = { "Gems100", "Gems500", "Gems1K" }, CardAspect = 0.82 },
	{ Items = { "Gems4K", "Gems10K" }, CardAspect = 1.15 },
	{ Items = { "Cash10K", "Cash25K", "Cash75K" }, CardAspect = 0.95 },
	{ Items = { "Cash150K", "Cash300K" }, CardAspect = 1.35 },
	{ Items = { "Cash500K" }, CardAspect = 1.05, Width = 0.48 },
} :: { Row }

function ShopConfig.get(itemId: string): Item?
	return ShopConfig.Items[itemId]
end

return ShopConfig
