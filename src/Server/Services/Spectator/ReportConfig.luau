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
}
