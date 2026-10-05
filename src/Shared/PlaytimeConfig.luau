-- Ubicación en Studio: ReplicatedStorage > PlaytimeConfig (ModuleScript)
-- Plantilla local: no entrega recompensas ni guarda datos. Tiempos en segundos de sesión.
local Config = {}
Config.HeaderIcon = "rbxassetid://79623377979473"
Config.StudioTimeOffsetSeconds = 0 -- Solo Studio: 1200 permite revisar muchos READY.
-- Fracción de su lugar en la grilla que ocupa cada tarjeta (1 = sin aire, más bajo = más chica).
Config.CardScale = 0.88
Config.Rewards = {
	{ Id = "Cash75", Title = "$75 Cash", Seconds = 0, Icon = "rbxassetid://105607438768052" },
	{ Id = "Cash125", Title = "$125 Cash", Seconds = 60, Icon = "rbxassetid://133495653316055" },
	{ Id = "Cash200", Title = "$200 Cash", Seconds = 120, Icon = "rbxassetid://83574433548351" },
	{
		Id = "EffectCase",
		Title = "1 Basic Effect Case",
		CardTitle = "1 Basic Effect\nCase",
		Seconds = 180,
		Icon = "rbxassetid://79856150434822",
	},
	{ Id = "Cash300", Title = "$300 Cash", Seconds = 300, Icon = "rbxassetid://85864455116402" },
	{ Id = "Revive", Title = "+1 Revive", Seconds = 420, Icon = "rbxassetid://115365429901908" },
	{
		Id = "SniperCase",
		Title = "1 Basic Sniper Case",
		CardTitle = "1 Basic Sniper\nCase",
		Seconds = 600,
		Icon = "rbxassetid://96479466263272",
	},
	{ Id = "Cash400", Title = "$400 Cash", Seconds = 900, Icon = "rbxassetid://101510053154843" },
	{ Id = "Cash500", Title = "$500 Cash", Seconds = 1200, Icon = "rbxassetid://93557666275221" },
	{ Id = "TwoCases", Title = "2 Basic Sniper Cases", Seconds = 1800, Icon = "rbxassetid://96479466263272", IconCount = 2 },
	-- Icono provisional: sustituir por el arte del objeto final.
	{ Id = "Flamingo", Title = "Flamingo Sniper", Seconds = 5400, Icon = "rbxassetid://79623377979473" },
}
Config.Rows = {
	{ "Cash75", "Cash125", "Cash200", "EffectCase" },
	{ "Cash300", "Revive", "SniperCase", "Cash400" },
	{ "Cash500", "TwoCases", "Flamingo" },
}
Config.States = {
	Ready = { Text = "READY", Color = Color3.fromRGB(255, 237, 70) },
	Claimed = { Text = "CLAIMED", Color = Color3.fromRGB(105, 255, 144) },
	Waiting = { Color = Color3.new(1, 1, 1) },
}
return Config
