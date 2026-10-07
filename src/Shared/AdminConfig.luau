-- Ubicación en Studio: ReplicatedStorage > AdminConfig (ModuleScript)
-- Rangos, permisos, límites y estilo del Admin Panel. El servidor valida todo con esta tabla.
local ShopConfig = require(script.Parent:WaitForChild("ShopConfig"))

local Config = {}

-- Siempre Owner, aunque no estén en el DataStore. El creador del juego (usuario) se suma solo.
Config.OwnerUserIds = {} :: { number }
-- En Studio el jugador de prueba es Owner, para poder probar el panel sin publicar.
Config.StudioIsOwner = true

-- Cada cuánto se relee la lista de admins, por si se pierde un aviso de MessagingService.
Config.ReloadInterval = 120

-- Level más alto manda: solo se puede sancionar, dar o quitar rangos MÁS BAJOS que el propio.
Config.Ranks = {
	Owner = { Level = 3, Label = "OWNER", Color = Color3.fromRGB(255, 200, 40), Palette = "Orange" },
	Admin = { Level = 2, Label = "ADMIN", Color = Color3.fromRGB(255, 70, 80), Palette = "Red" },
	Moderator = { Level = 1, Label = "MODERATOR", Color = Color3.fromRGB(60, 190, 255), Palette = "Blue" },
}
-- Orden del botón de rango en "Grant Access" (Owner no se puede dar desde el panel).
Config.GrantableRanks = { "Moderator", "Admin" }

-- Level mínimo de cada acción.
Config.Permissions = {
	Announce = 1,
	ServerMessage = 1,
	StartPoll = 1,
	EndPoll = 1,
	Kick = 1,
	Warn = 1,
	Teleport = 1,
	Bring = 1,
	Ban = 2,
	Unban = 2,
	Grant = 2,
	Revoke = 2,
	ListAdmins = 1,
	Inspect = 1,
	Lookup = 1,
	ViewLogs = 1,
}

-- Logs por jugador (en su perfil). Cada categoría guarda las últimas MaxPerCategory entradas.
Config.Logs = {
	MaxPerCategory = 50,
	-- Cada cuánto se actualiza la duración de la sesión en curso.
	SessionUpdateSeconds = 60,
	-- Orden de las pestañas del Player Panel. `Button` es el botón dentro de LogsCard e `Icon`
	-- la imagen de las entradas que no traen una propia (las compras usan la del producto).
	Categories = {
		{ Id = "Purchase", Button = "PurchaseTab", Palette = "Green", Icon = "rbxassetid://74016484606228" },
		{ Id = "Moderation", Button = "ModerationTab", Palette = "Red", Icon = "rbxassetid://84416250652005" },
		{ Id = "Report", Button = "ReportTab", Palette = "Orange", Icon = "rbxassetid://91917957775118" },
		{ Id = "Code", Button = "CodeTab", Palette = "Purple", Icon = "rbxassetid://76717751961083" },
		{ Id = "Session", Button = "SessionTab", Palette = "Blue", Icon = "rbxassetid://117339607031815" },
		{ Id = "Staff", Button = "StaffTab", Palette = "Blue", Icon = "rbxassetid://84416250652005" },
	},
	-- Pestaña que junta todas las categorías, ordenadas por fecha.
	All = { Button = "AllTab", Palette = "Orange" },
	-- Opciones del botón de período, en el orden en que cicla. Days = nil: sin filtro;
	-- Days = 0: desde la medianoche de hoy (hora local del que mira).
	Periods = {
		{ Label = "ALL TIME", Days = nil },
		{ Label = "TODAY", Days = 0 },
		{ Label = "LAST 7 DAYS", Days = 7 },
		{ Label = "LAST 30 DAYS", Days = 30 },
	},
}

Config.Limits = {
	Message = 200,
	Reason = 150,
	PollQuestion = 100,
	PollOption = 30,
	PollMinOptions = 2,
	PollMaxOptions = 4,
	PollMinSeconds = 10,
	PollMaxSeconds = 600,
	-- Tope de un ban temporal; "perm" no tiene tope.
	MaxBanDays = 365,
}

-- Segundos en pantalla del anuncio de arriba y del resultado del poll.
Config.AnnouncementDuration = 7
Config.PollResultDuration = 6

-- Pestañas: `Id` busca el botón "<Id>Tab" en Main.Tabs y `Page` el Frame dentro de
-- Main.Pages. El texto y el orden de cada pestaña se diseñan en Studio.
Config.Tabs = {
	{ Id = "Server", Page = "ServerPage" },
	{ Id = "Player", Page = "PlayerPage" },
	{ Id = "Admins", Page = "AdminsPage" },
}

-- Unidades del tiempo de ban ("30m", "12h", "7d", "2w"). Un número solo = días.
Config.BanUnits = { s = 1, m = 60, h = 3600, d = 86400, w = 604800 }

Config.Icons = {
	Panel = "rbxassetid://84416250652005",
}

-- Announcement y PollEnd son assets de UBG. Success/Error suenan con cada respuesta del panel:
-- no usar el de cobrar recompensas (Daily/Playtime), que se confunde con un premio.
Config.Sounds = {
	Announcement = "rbxassetid://127438224839678",
	PollEnd = "rbxassetid://124793974135748",
	Success = "rbxassetid://85240253037283",
	Error = "rbxassetid://124387798635805",
}

-- "Voz" del anuncio, estilo Undertale: suena mientras se escribe cada letra.
Config.Voice = {
	-- Plantillas de voz. Pitch = tono base (1 = original, más alto = más agudo).
	Presets = {
		Default = { Sound = "rbxassetid://110969462696032", Volume = 0.5, Pitch = 1 },
		Female = { Sound = "rbxassetid://2633343843", Volume = 0.5, Pitch = 1 },
		-- Beep con la voz de benxh. Sound vacío = usa Default hasta que se cargue el ID.
		benxh = { Sound = "rbxassetid://85179944862997", Volume = 1.0, Pitch = 1 },
		esme = { Sound = "rbxassetid://76405550074157", Volume = 1.0, Pitch = 1.5 },
	},
	-- Voz de cada miembro del staff: [UserId] = "Female" (un preset) o "rbxassetid://..." (propia).
	-- Sin entrada = Default.
	ByUserId = {
		[3815857302] = "benxh", -- iHazeHD > Voice
		[1308587919] = "esme", -- 666_Jh0rlya > Voice
		-- [123456789] = "Female",                -- usa la plantilla
		-- [987654321] = "rbxassetid://SU_SONIDO", -- sonido propio	
	} :: { [number]: string },
	-- Variación aleatoria del tono por letra (0.06 = ±6%); 0 = siempre igual.
	PitchVariation = 0.06,
	-- Suena cada N letras: 1 = en todas (más "parloteo"), 2-3 = más suave con sonidos largos.
	SoundEvery = 2,
}

-- Escritura del anuncio: segundos por letra y cuántas letras "dura" la pausa tras . , ! ?
Config.Typing = {
	LetterDelay = 0.04,
	PunctuationPause = 5,
	-- Mensajes con menos de ShortLetters letras se escriben más lento, hasta MaxSlowdown veces.
	ShortLetters = 20,
	MaxSlowdown = 3,
	-- Puntos suspensivos ("..." o "…"): cada punto suena, con esta pausa (s) y este tono.
	DotDelay = 0.3,
	DotPitch = 0.85,
	-- Cuánto crece el avatar en cada sonido ("habla"); 1 = sin movimiento.
	TalkScale = 1.07,
}

Config.Open = ShopConfig.Style.Open
Config.Blur = ShopConfig.Style.Blur

-- Gradiente de 3 colores de cada botón (arriba, medio, abajo), igual que SettingsConfig.Style.
Config.Palettes = {
	Green = { Color3.fromRGB(135, 255, 0), Color3.fromRGB(25, 245, 0), Color3.fromRGB(0, 207, 0) },
	Red = { Color3.fromRGB(238, 137, 142), Color3.fromRGB(255, 51, 58), Color3.fromRGB(255, 0, 12) },
	Blue = { Color3.fromRGB(150, 235, 255), Color3.fromRGB(45, 185, 255), Color3.fromRGB(0, 125, 235) },
	Purple = { Color3.fromRGB(234, 99, 229), Color3.fromRGB(192, 31, 215), Color3.fromRGB(112, 0, 155) },
	Orange = { Color3.fromRGB(255, 225, 110), Color3.fromRGB(255, 170, 40), Color3.fromRGB(230, 110, 0) },
	Grey = { Color3.fromRGB(205, 210, 225), Color3.fromRGB(140, 150, 178), Color3.fromRGB(92, 102, 130) },
}

return Config
