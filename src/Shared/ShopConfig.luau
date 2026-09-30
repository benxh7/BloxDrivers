-- Ubicación en Studio: ReplicatedStorage > ShopConfig (ModuleScript)
-- Catálogo y estilo de la tienda. Agregar un item = su entrada en `Items` y su Id en `Rows`.
-- Kind: "Product" (varias compras), "GamePass" (una vez, pasa a OWNED) o "View" (abre ViewTarget).
local ShopConfig = {}

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
	Gift = "rbxassetid://114937842017271",
	Gem = "rbxassetid://123458803098584",
}

-- Placeholders: reemplazar por el arte final.
local ART = {
	Coins = "rbxassetid://77032605127812",
	Crown = "rbxassetid://81455229876046",
	Shield = "rbxassetid://137799890267118",
	PassBackground = "rbxassetid://104433970768289",
}

-- Degradé (arriba, abajo). Buy / View / Owned son los estados del botón de compra.
ShopConfig.ButtonColors = {
	Buy = { Color3.fromRGB(105, 225, 25), Color3.fromRGB(40, 195, 10) },
	View = { Color3.fromRGB(110, 205, 255), Color3.fromRGB(40, 150, 230) },
	Owned = { Color3.fromRGB(175, 175, 188), Color3.fromRGB(115, 115, 130) },
	Gift = { Color3.fromRGB(45, 55, 240), Color3.fromRGB(215, 85, 255) },
	Gem = { Color3.fromRGB(35, 95, 250), Color3.fromRGB(40, 175, 255) },
}

-- Todos los botones de las tarjetas. Grosores en px a 1080 de alto.
ShopConfig.ButtonStyle = {
	-- Scale del lado más corto.
	CornerRadius = 0.05,
	OutlineColor = Color3.fromRGB(18, 18, 32),
	OutlineThickness = 3.5,
	-- Aro claro por dentro del borde: el degradé del botón aclarado (RimLighten 0..1).
	RimThickness = 3,
	RimLighten = 0.45,
	PriceFont = Font.new("rbxasset://fonts/families/FredokaOne.json"),
	PriceStrokeColor = Color3.fromRGB(18, 18, 32),
	PriceStrokeThickness = 3,
	-- Separación regalo-compra y gema-compra (fracción del ancho de Actions).
	Gap = 0.06,
}

-- Tamaños en px a 1080 de alto: en pantallas más chicas se achican en proporción.
ShopConfig.Style = {
	-- Esquinas de todas las capas (Scale del lado más corto).
	CornerRadius = 0.12,
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
	Layout = { CardGap = 0.055, RowGap = 0.065, SidePadding = 0.06, EdgePadding = 0.055 },
	-- Scale = cuánto crece, Rotation = grados a la derecha, Duration = segundos.
	Hover = {
		Card = { Scale = 1.03, Duration = 0.3 },
		Button = { Scale = 1.07, Rotation = 3, Duration = 0.3 },
	},
	-- Desenfoque del mundo con la tienda abierta.
	Blur = { Size = 16, Duration = 0.2 },
	-- Se abre desde el centro, de FromScale a su tamaño normal en Duration segundos.
	Open = { FromScale = 0.1, Duration = 0.35 },
}

-- Suenan juntos al abrir la tienda.
ShopConfig.Sounds = {
	Open = { "rbxassetid://127488139302452", "rbxassetid://98891178613563" },
	Volume = 0.5,
}

-- El flujo de regalar todavía no existe: con true el botón solo avisa por consola.
ShopConfig.GiftEnabled = true

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
		RingThickness = 10,
		TitleColor = Color3.fromRGB(255, 250, 205),
		DescriptionColor = Color3.fromRGB(235, 55, 70),
		DescriptionAlign = "Right",
		Featured = true,
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
		RingThickness = 9,
		Outline = Color3.fromRGB(150, 180, 255),
		TitleColor = Color3.fromRGB(135, 125, 255),
		TitleStroke = Color3.fromRGB(15, 10, 60),
		Pattern = false,
		Banner = true,
	},
	Cash2x = {
		Kind = "GamePass",
		Title = "2x Cash",
		Description = "- 2x Cash from all sources",
		ProductId = 0,
		Price = 199,
		Image = "rbxassetid://0",
		Color = { Color3.fromRGB(130, 235, 90), Color3.fromRGB(40, 175, 60) },
		Icon = ART.Coins,
		IconLayout = { Position = UDim2.fromScale(0.45, 0.62), Size = UDim2.fromScale(0.5, 0.58) },
		Glow = Color3.fromRGB(60, 230, 90),
		Pattern = false,
		Gem = true,
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
	Cash1K = {
		Kind = "Product",
		Title = "+1K Cash",
		ProductId = 0,
		Price = 25,
		Reward = { Type = "Cash", Amount = 1000 },
		Image = "rbxassetid://0",
		Color = { Color3.fromRGB(255, 120, 200), Color3.fromRGB(230, 50, 150) },
		Icon = ART.Coins,
		Glow = Color3.fromRGB(255, 100, 195),
		PatternColor = Color3.new(1, 1, 1),
		PatternTransparency = 0.7,
	},
	Cash5K = {
		Kind = "Product",
		Title = "+5K Cash",
		ProductId = 0,
		Price = 99,
		Reward = { Type = "Cash", Amount = 5000 },
		Image = "rbxassetid://0",
		Color = { Color3.fromRGB(255, 120, 200), Color3.fromRGB(230, 50, 150) },
		Icon = ART.Coins,
		Glow = Color3.fromRGB(255, 100, 195),
		PatternColor = Color3.new(1, 1, 1),
		PatternTransparency = 0.7,
	},
	Cash25K = {
		Kind = "Product",
		Title = "+25K Cash",
		ProductId = 0,
		Price = 399,
		Reward = { Type = "Cash", Amount = 25000 },
		Image = "rbxassetid://0",
		Color = { Color3.fromRGB(255, 120, 200), Color3.fromRGB(230, 50, 150) },
		Icon = ART.Coins,
		Glow = Color3.fromRGB(255, 100, 195),
		PatternColor = Color3.new(1, 1, 1),
		PatternTransparency = 0.7,
	},
} :: { [string]: Item }

-- Filas de arriba hacia abajo.
ShopConfig.Rows = {
	{ Items = { "StarterBundle" }, CardAspect = 1.32, Width = 0.47 },
	{ Items = { "ChampionPass" }, CardAspect = 2.85, Width = 0.97 },
	{ Items = { "Cash2x", "VIP" }, CardAspect = 1.6 },
	{ Items = { "Cash1K", "Cash5K", "Cash25K" }, CardAspect = 0.95 },
} :: { Row }

function ShopConfig.get(itemId: string): Item?
	return ShopConfig.Items[itemId]
end

return ShopConfig
