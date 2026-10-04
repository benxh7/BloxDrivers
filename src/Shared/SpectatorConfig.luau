-- Ubicación en Studio: ReplicatedStorage > SpectatorConfig (ModuleScript)
-- Textos, motivos de reporte y atributos del modo espectador.
local Config = {}
-- Solo Studio: espectearte a vos mismo sin ronda activa, para probar.
Config.DebugSelfSpectate = true
Config.RoundAttribute = "SpectatorRoundActive"
Config.ParticipantAttribute = "Spectatable"
Config.RoleAttribute = "RoundRole"
Config.HUDIcon = "rbxassetid://91917957775118"
Config.HeartIcon = "rbxassetid://115365429901908"
Config.Hover = { Scale = 1.06, Rotation = 5, Duration = 0.14 }
Config.Revive = { Visible = true, Attribute = "Revives", TemplateOnly = true }
Config.MaxDetailsLength = 800
Config.Reasons = {
	{
		Id = "Exploiting",
		Title = "Exploiting",
		Description = "Flying, Aimbot, Teleporting, Speed Hacks, Noclip, Wall hacks, etc",
	},
	{
		Id = "BugAbusing",
		Title = "Bug Abusing",
		Description = "Repeated abusing of known bugs that give a significant advantage",
	},
	{
		Id = "ExplicitActs",
		Title = "Explicit Acts",
		Description = "Doing inappropriate things to other players, and or saying",
	},
}
Config.Messages = {
	Empty = "Nothing to spectate at the moment.",
	Details = "Please describe what happened in the details box.",
	Reason = "Please select a report reason.",
	Sent = "Report sent. Thank you!",
	Preview = "Report preview validated. Discord is not configured.",
	DebugPreview = "Debug report validated. Nothing was sent to Discord.",
	NotConfigured = "Reports are not available yet. Please try again later.",
	Failed = "The report could not be sent. Please try again.",
	TargetGone = "This player is no longer available to report.",
	TooLong = "Please shorten the details (maximum 800 characters).",
	Busy = "Please wait before sending another report.",
	Revive = "Revive is a preview. No life or purchase was used.",
}
return Config
