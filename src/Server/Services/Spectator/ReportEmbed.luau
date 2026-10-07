-- Ubicación en Studio: ServerScriptService > Services > Spectator > ReportEmbed (ModuleScript)
-- Arma el mensaje de Discord de un reporte: encabezado, texto, avatar del reportado y banner.
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("SpectatorConfig"))
local Settings = require(script.Parent.ReportConfig)

local ReportEmbed = {}

-- Las URLs de rbxcdn duran días: una consulta por jugador alcanza para toda la sesión.
local thumbnailCache: { [number]: string } = {}

local reasonTitles: { [string]: string } = {}
for _, entry in Config.Reasons do
	reasonTitles[entry.Id] = entry.Title
end

function ReportEmbed.reasonTitle(reason: string): string
	return reasonTitles[reason] or reason
end

-- `_` es itálica en Discord y los DisplayName admiten más símbolos: se escapan siempre.
local function escape(text: string): string
	return (text:gsub("[\\`*_~|>%[%]]", "\\%0"))
end

-- "DisplayName (@username)" con link al perfil: el DisplayName solo no identifica a nadie.
local function profileLink(player: Player): string
	return ("[%s (@%s)](https://www.roblox.com/users/%d/profile)"):format(
		escape(player.DisplayName),
		escape(player.Name),
		player.UserId
	)
end

-- Los servidores de Roblox no pueden llamar a roblox.com: se pasa por el proxy configurado.
-- Si falla, el reporte sale igual, sin miniatura.
function ReportEmbed.avatarUrl(userId: number): string?
	local cached = thumbnailCache[userId]
	if cached then
		return cached
	end
	local ok, response = pcall(HttpService.RequestAsync, HttpService, {
		Url = Settings.ThumbnailApi:format(userId),
		Method = "GET",
	})
	if not ok or not response.Success then
		return nil
	end
	local decoded, data = pcall(HttpService.JSONDecode, HttpService, response.Body)
	local entry = decoded and type(data) == "table" and type(data.data) == "table" and data.data[1]
	local url = type(entry) == "table" and entry.state == "Completed" and entry.imageUrl
	if type(url) ~= "string" or not url:match("^https://") then
		return nil
	end
	thumbnailCache[userId] = url
	return url
end

-- `details` ya viene validado por ReportPolicy; va en bloque de código para que no se
-- interprete como markdown ni links.
export type ReportCount = { Total: number, Unique: number }

local function countLine(count: ReportCount?): string?
	if not count then
		return nil
	end
	return ("**Reports on this player:** %d from %d different players"):format(count.Total, count.Unique)
end

local function footer()
	return {
		text = ("Place %d · Job %s"):format(game.PlaceId, if game.JobId ~= "" then game.JobId else "Studio"),
	}
end

function ReportEmbed.build(
	reporter: Player,
	target: Player,
	reason: string,
	details: string,
	debugReport: boolean,
	count: ReportCount?
)
	local header = if debugReport then Settings.Embed.DebugHeader else Settings.Embed.Header
	local safeDetails = details:gsub("`", "ˋ")
	local description = table.concat({
		("`%s`"):format(header),
		"",
		("**Reported by:** %s"):format(profileLink(reporter)),
		"",
		("**Reported:** %s"):format(profileLink(target)),
		("**Reason:** %s %s"):format(Settings.Embed.ReasonEmoji, reasonTitles[reason] or reason),
		countLine(count) or "",
		"",
		"**Details:**",
		("```%s```"):format(safeDetails),
		"",
		Settings.Embed.Footnote,
	}, "\n")

	local embed: { [string]: any } = {
		color = Settings.Embed.Color,
		description = description,
		footer = footer(),
		timestamp = DateTime.now():ToIsoDate(),
	}
	local avatar = ReportEmbed.avatarUrl(target.UserId)
	if avatar then
		embed.thumbnail = { url = avatar }
	end
	if Settings.Embed.BannerUrl ~= "" then
		embed.image = { url = Settings.Embed.BannerUrl }
	end
	return { allowed_mentions = { parse = {} }, embeds = { embed } }
end

-- Aviso al webhook de alertas: el jugador pasó el umbral de reporteros distintos.
function ReportEmbed.alert(target: Player, reason: string, count: ReportCount)
	local alert = Settings.Alert
	local embed: { [string]: any } = {
		color = alert.Color,
		description = table.concat({
			("`%s`"):format(alert.Header),
			"",
			("**Player:** %s"):format(profileLink(target)),
			countLine(count),
			("**Latest reason:** %s %s"):format(Settings.Embed.ReasonEmoji, reasonTitles[reason] or reason),
			"",
			"Still in this server: join the Job below to check.",
		}, "\n"),
		footer = footer(),
		timestamp = DateTime.now():ToIsoDate(),
	}
	local avatar = ReportEmbed.avatarUrl(target.UserId)
	if avatar then
		embed.thumbnail = { url = avatar }
	end
	return { allowed_mentions = { parse = {} }, embeds = { embed } }
end

return ReportEmbed
