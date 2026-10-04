-- Ubicación en Studio: ReplicatedStorage > DailyConfig (ModuleScript)
-- Plantilla de sesión: no entrega objetos ni persiste progreso.
local Config = {}
Config.HeaderIcon = "rbxassetid://130147541805143"
Config.DaySeconds = 86400 -- Espera desde la última reclamación. Editable para la demo.
Config.StudioClaimedDays = 0 -- Vista de ejemplo: 3 muestra Day 4 READY.
Config.OpenSound = "rbxassetid://139719503904449"
Config.Rewards = {
	{ Title = "$150 Cash", Icon = "rbxassetid://105607438768052" },
	{ Title = "$250 Cash", Icon = "rbxassetid://133495653316055" },
	{ Title = "1 Basic Effect Case", Icon = "rbxassetid://79856150434822" },
	{ Title = "$350 Cash", Icon = "rbxassetid://83574433548351" },
	{ Title = "+1 Revive", Icon = "rbxassetid://115365429901908" },
	{ Title = "1 Basic Sniper Case", Icon = "rbxassetid://96479466263272" },
	{ Title = "$500 Cash + 1 Basic Sniper Case", Icon = "rbxassetid://96479466263272", Special = true },
	{ Title = "$400 Cash", Icon = "rbxassetid://85864455116402" },
	{ Title = "1 Basic Effect Case", Icon = "rbxassetid://79856150434822" },
	{ Title = "+1 Revive", Icon = "rbxassetid://115365429901908" },
	{ Title = "1 Basic Sniper Case", Icon = "rbxassetid://96479466263272" },
	{ Title = "$750 Cash", Icon = "rbxassetid://101510053154843" },
	{ Title = "2 Basic Sniper Cases", Icon = "rbxassetid://96479466263272", IconCount = 2 },
	{ Title = "1 Limited Case + $1,000 Cash", Icon = "rbxassetid://130147541805143", Special = true },
}
Config.States = {
	Ready = { Text = "READY", Color = Color3.fromRGB(255, 237, 70) },
	Claimed = { Text = "CLAIMED", Color = Color3.fromRGB(105, 255, 144) },
	Locked = { Text = "LOCKED", Color = Color3.fromRGB(170, 170, 170) },
}
return Config
