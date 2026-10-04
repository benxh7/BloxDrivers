-- Ubicación en Studio: ReplicatedStorage > SettingsConfig (ModuleScript)
-- Filas de Settings (plantillas de UITemplates). Duran la sesión: no escriben DataStores.
local ShopConfig = require(script.Parent:WaitForChild("ShopConfig"))
local Config = {}
Config.Icons = {
	Gear = "rbxassetid://127247998973980",
	Close = "rbxassetid://117755047033603",
}
Config.Sounds = ShopConfig.Sounds
Config.Open = ShopConfig.Style.Open
Config.Blur = ShopConfig.Style.Blur
Config.Style = {
	Font = Font.new("rbxasset://fonts/families/Montserrat.json", Enum.FontWeight.ExtraBold),
	On = { Color3.fromRGB(135, 255, 0), Color3.fromRGB(25, 245, 0), Color3.fromRGB(0, 207, 0) },
	Off = { Color3.fromRGB(238, 137, 142), Color3.fromRGB(255, 51, 58), Color3.fromRGB(255, 0, 12) },
}
Config.Rows = {
	{ Id = "SniperChance", Label = "Chance to be\nsniper:", Kind = "Toggle", Default = true },
	{ Id = "DoubleSniperChance", Label = "2x Sniper Chance:", Kind = "Toggle", Default = false },
	{ Id = "TradingRequests", Label = "Trading Request", Kind = "Toggle", Default = true },
	{ Id = "StatsProximity", Label = "View Stats Proximity", Kind = "Toggle", Default = true },
	{ Id = "ViewStats", Label = "View Your Stats", Kind = "Action" },
	{ Id = "MusicVolume", Label = "Music Volume:", Kind = "Slider", Default = 1, Min = 0, Max = 1, Step = 0.01 },
	{ Id = "ScopeSensitivity", Label = "Scope Sensitivity", Kind = "Slider", Default = 0.15, Min = 0.05, Max = 1, Step = 0.01 },
	{ Id = "SniperSensitivity", Label = "Sniper Sensitivity", Kind = "Slider", Default = 1, Min = 0.1, Max = 2, Step = 0.01 },
	{ Id = "CameraFOV", Label = "Camera FOV", Kind = "Slider", Default = 70, Min = 50, Max = 110, Step = 1 },
	{ Id = "ScopeType", Label = "Sniper Scope Type", Kind = "Scope", Default = 4, Count = 4 },
	{ Id = "Shadows", Label = "Shadows", Kind = "Toggle", Default = true },
}
-- MusicVolume afecta al SoundGroup "Music", a lo marcado con IsMusic=true o tag Music, y a
-- los Sounds llamados Music / BackgroundMusic / LobbyMusic.
return Config
