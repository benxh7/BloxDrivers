-- Ubicación en Studio: ServerScriptService > Services > Spectator > ReportConfig (ModuleScript)
-- SOLO SERVIDOR. La URL del webhook NO va acá: vive en los Secrets de Roblox (ver WebhookSecret).
return {
	SendDebugReports = true, -- En Studio, el autorreporte llega como [DEBUG TEST].
	-- Nombre del secreto con la URL completa (https://discord.com/api/webhooks/ID/TOKEN), dominio
	-- discord.com. Se carga en Creator Dashboard > Secrets; para Studio, en Game Settings > Security.
	WebhookSecret = "DiscordReportWebhook",
	CooldownSeconds = 60, -- por reportero + objetivo, en este servidor
	AttemptInterval = 2,
	StudioDryRun = false, -- sin secreto: en Studio solo valida, nunca dice "enviado"
	-- Avatar busto del reportado (%d = UserId). roproxy porque el servidor no puede llamar a roblox.com.
	ThumbnailApi = "https://thumbnails.roproxy.com/v1/users/avatar-bust?userIds=%d&size=420x420&format=Png&isCircular=false",
	Embed = {
		Color = 0xF5D90A, -- barra lateral del mensaje
		Header = "Player report (unverified)",
		DebugHeader = "[DEBUG TEST] Self-report",
		ReasonEmoji = "🚩",
		Footnote = "Can a staff member review this?",
		-- Imagen ancha debajo del mensaje (URL https pública). "" = sin banner.
		BannerUrl = "",
	},
}
