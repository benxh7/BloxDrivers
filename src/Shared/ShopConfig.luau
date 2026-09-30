-- Ubicación en Studio: ReplicatedStorage > ShopConfig (ModuleScript)
--
-- Catálogo de la tienda (data-driven). ShopController arma las tarjetas recorriendo
-- `Rows`; ShopService valida cada compra contra `Items`. Agregar un item = sumar su
-- entrada en `Items` y su Id en alguna fila de `Rows`. Nada más.
--
-- Kind:
--   "Product"  -> Developer Product (se compra muchas veces). ShopService lo otorga en
--                 ProcessReceipt según su `Reward`.
--   "GamePass" -> Game Pass (una sola vez). La tarjeta pasa a "OWNED".
--   "View"     -> no se compra: el botón dice VIEW y abre la ventana `ViewTarget` de UIManager.
local ShopConfig = {}

export type Reward = {
	-- Tipo de recompensa. ShopService necesita un grant registrado para este Type
	-- (ShopService.RegisterGrant); si no hay, la compra queda pendiente.
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
	-- Línea chica debajo de la barra del título (ej. "- Instantly Open Crates").
	Subtitle: string?,
	Description: string?,
	-- ID del Developer Product o Game Pass. 0 = todavía sin crear: el botón avisa y no compra.
	ProductId: number?,
	-- Precio que se MUESTRA. El que se cobra lo define Roblox según el producto.
	Price: number?,
	Reward: Reward?,
	ViewTarget: string?,
	-- Fondo: imagen a tarjeta completa (rbxassetid://0 = sin imagen) y, si no hay, un
	-- degradé con `Color`.
	Image: string,
	Color: { Color3 },
	-- Dibujo centrado encima del fondo (ícono del item). `IconLayout` lo ubica en Scale.
	Icon: string?,
	IconLayout: IconLayout?,
	-- Color del brillo exterior (y de la línea clara interior). Todas las tarjetas lo
	-- llevan; nil = solo borde negro.
	Glow: Color3?,
	-- Anillo sólido de color entre el borde negro y el brillo (px a 1080). Default
	-- Style.RingThickness = 0: solo brillo. Lo usan el bundle y el pase.
	RingThickness: number?,
	-- Color del borde interior (default negro).
	Outline: Color3?,
	TitleColor: Color3?,
	TitleStroke: Color3?,
	DescriptionColor: Color3?,
	-- "Right" = descripción centrada en la mitad derecha (estilo bundle). Default izquierda.
	DescriptionAlign: ("Left" | "Right")?,
	-- Puntos halftone en la esquina (default true) y su color.
	Pattern: boolean?,
	PatternColor: Color3?,
	PatternTransparency: number?,
	-- Rayos de fondo (estilo VIP).
	Rays: boolean?,
	-- Botón azul con gema arriba del precio. El flujo de gemas todavía no existe.
	Gem: boolean?,
	-- Tarjeta destacada (bundle): botones más grandes y sin hover.
	Featured: boolean?,
	-- Estilo "pase": sin barra de título, título grande a la izquierda y sin hover.
	Banner: boolean?,
}

export type Row = {
	Items: { string },
	-- Proporción ancho/alto de cada tarjeta de la fila.
	CardAspect: number,
	-- Fracción del ancho que ocupa la fila (default 1). Ej. 0.47 = tarjeta destacada centrada.
	Width: number?,
}

-- ─── Assets de la GUI (pegá tus IDs acá) ────────────────────────────────────────
-- El símbolo de Robux del precio NO es una imagen: es el ícono de texto de Roblox
-- (utf8.char(0xE002)) dentro del PriceLabel, así toma el mismo borde que los números.
ShopConfig.Icons = {
	Gift = "rbxassetid://114937842017271",
	Gem = "rbxassetid://123458803098584",
}

-- Imágenes de las tarjetas (placeholders generados; reemplazar por el arte final).
local ART = {
	Coins = "rbxassetid://77032605127812",
	Crown = "rbxassetid://81455229876046",
	Shield = "rbxassetid://137799890267118",
	PassBackground = "rbxassetid://104433970768289",
}

-- Colores (arriba, abajo) del degradé de cada botón. Buy / View / Owned son los
-- estados del botón de compra; Gift y Gem, los botones cuadrados.
ShopConfig.ButtonColors = {
	Buy = { Color3.fromRGB(105, 225, 25), Color3.fromRGB(40, 195, 10) },
	View = { Color3.fromRGB(110, 205, 255), Color3.fromRGB(40, 150, 230) },
	Owned = { Color3.fromRGB(175, 175, 188), Color3.fromRGB(115, 115, 130) },
	Gift = { Color3.fromRGB(45, 55, 240), Color3.fromRGB(215, 85, 255) },
	Gem = { Color3.fromRGB(35, 95, 250), Color3.fromRGB(40, 175, 255) },
}

-- Borde oscuro, aro claro interior y texto del precio de TODOS los botones de las
-- tarjetas (px a 1080 de alto).
ShopConfig.ButtonStyle = {
	-- Esquinas de los botones (Scale del lado más corto).
	CornerRadius = 0.05,
	OutlineColor = Color3.fromRGB(18, 18, 32),
	OutlineThickness = 3.5,
	-- Aro claro pegado por dentro del borde negro: mismo degradé del botón aclarado
	-- hacia el blanco (RimLighten 0..1). RimThickness = grosor en px.
	RimThickness = 3,
	RimLighten = 0.45,
	PriceFont = Font.new("rbxasset://fonts/families/FredokaOne.json"),
	PriceStrokeColor = Color3.fromRGB(18, 18, 32),
	PriceStrokeThickness = 3,
	-- Separación entre el botón de regalo y el de compra (fracción del ancho de Actions).
	Gap = 0.06,
}

-- ─── Estilo de las tarjetas (todo lo visual que se ajusta a mano está acá) ─────────
-- Los tamaños en px están pensados para una pantalla de 1080 px de alto; en pantallas
-- más chicas ShopController los achica en proporción.
ShopConfig.Style = {
	-- Radio de las esquinas de TODAS las capas de la tarjeta (Scale del lado más corto).
	CornerRadius = 0.12,
	-- Grosor del borde negro (px).
	OutlineThickness = 6,
	-- Brillo exterior difuminado (como una sombra de color), con la forma exacta de la
	-- tarjeta: esquinas redondas como las suyas.
	--   Spread = hasta dónde llega por fuera del borde (px); ahí ya es invisible.
	--   Opacity = intensidad pegado al borde (0..1).
	--   Curve = cómo se esfuma: 1 = parejo, 2 = fuerte en el borde y cola larga suave.
	--   Layers = pasos del degradado (1 por px de Spread = sin bandas).
	Glow = { Spread = 22, Opacity = 0.45, Curve = 2, Layers = 22 },
	-- Anillo sólido por defecto (0 = ninguno). Cada item puede pedir el suyo con RingThickness.
	RingThickness = 0,
	-- Línea clara pegada al borde por dentro: cuánto se aclara el color del brillo (0..1).
	InnerLineLighten = 0.45,
	-- Tamaño máximo del texto de la descripción, como fracción del alto de la tarjeta.
	DescriptionTextSize = 0.115,
	-- Espaciado de la lista, como fracción de su ancho (CardGap: entre tarjetas de una fila).
	-- SidePadding / EdgePadding dejan lugar para que el brillo no se corte contra el borde.
	Layout = { CardGap = 0.055, RowGap = 0.065, SidePadding = 0.06, EdgePadding = 0.055 },
	-- Hover: Scale = cuánto crece, Rotation = grados hacia la derecha, Duration = segundos.
	-- Las tarjetas destacadas (Featured) y los pases (Banner) no tienen hover.
	Hover = {
		Card = { Scale = 1.03, Duration = 0.3 },
		Button = { Scale = 1.07, Rotation = 3, Duration = 0.3 },
	},
	-- Desenfoque del mundo mientras la tienda está abierta.
	Blur = { Size = 16, Duration = 0.2 },
	-- Apertura de la ventana: arranca en FromScale (chiquita, desde el centro) y crece
	-- hasta su tamaño normal en Duration segundos.
	Open = { FromScale = 0.1, Duration = 0.35 },
}

-- Sonidos que suenan juntos al abrir la tienda.
ShopConfig.Sounds = {
	Open = { "rbxassetid://127488139302452", "rbxassetid://98891178613563" },
	Volume = 0.5,
}

-- Botón de regalo. El flujo de regalar todavía no existe: con true se muestra y avisa
-- por consola al tocarlo.
ShopConfig.GiftEnabled = true

-- ─── Items ──────────────────────────────────────────────────────────────────────
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

-- ─── Filas (orden de arriba hacia abajo) ────────────────────────────────────────
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
