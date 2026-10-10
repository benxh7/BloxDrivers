-- Ubicación en Studio: ServerScriptService > Services > Logs > LogService (ModuleScript)
-- Logs por jugador para el Admin Panel: viven en profile.Data.Logs (EasyProfileStore).
local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")
local RS = game:GetService("ReplicatedStorage")
local Config = require(RS:WaitForChild("AdminConfig"))
local EasyProfileStore = require(ServerStorage:WaitForChild("EasyProfileStore"))
local DataService = require(script.Parent.Parent:WaitForChild("Data"):WaitForChild("DataService"))

-- Kind: tipo de la entrada (acción del panel: "Ban", "Kick", "Warn"...), para contarlas por tipo.
export type Entry = { At: number, Text: string, Icon: string?, Kind: string? }

local LogService = {}

local MESSAGE_TYPE = "Log"
local MAX_TEXT = 300

local categories: { [string]: boolean } = {}
for _, category in Config.Logs.Categories do
	categories[category.Id] = true
end

local function count(data: any, category: string, kind: string?)
	data.LogCounts = data.LogCounts or {}
	local counts = data.LogCounts
	counts[category] = (counts[category] or 0) + 1
	if kind then
		local key = category .. ":" .. kind
		counts[key] = (counts[key] or 0) + 1
	end
end

local function push(logs: { [string]: { Entry } }, category: string, entry: Entry)
	local list = logs[category]
	if not list then
		list = {}
		logs[category] = list
	end
	table.insert(list, 1, entry)
	while #list > Config.Logs.MaxPerCategory do
		table.remove(list)
	end
end

local function duration(seconds: number): string
	local minutes = math.floor(seconds / 60)
	if minutes < 60 then
		return ("%dm"):format(minutes)
	end
	return ("%dh %dm"):format(minutes // 60, minutes % 60)
end

local function serverLabel(): string
	return if game.JobId ~= "" then "server " .. game.JobId:sub(1, 8) else "Studio"
end

-- Jugador sin perfil en este servidor: va como mensaje del perfil y se guarda al cargarlo.
-- `icon` (opcional): imagen propia de la entrada, ej. la del producto comprado.
function LogService.Add(userId: number, category: string, text: string, icon: string?, kind: string?)
	assert(categories[category], "[LogService] Categoría desconocida: " .. tostring(category))
	local entry: Entry = { At = os.time(), Text = text:sub(1, MAX_TEXT), Icon = icon, Kind = kind }
	local player = Players:GetPlayerByUserId(userId)
	local profile = player and DataService.GetProfile(player)
	if profile then
		push(profile.Data.Logs, category, entry)
		count(profile.Data, category, kind)
		return
	end
	pcall(function()
		EasyProfileStore:PublishMessage(userId, { Type = MESSAGE_TYPE, Category = category, Entry = entry })
	end)
end

-- Devuelve (logs, totales de por vida); fuera de este servidor, la última versión guardada.
function LogService.Get(userId: number): ({ [string]: { Entry } }?, { [string]: number }?)
	local data = DataService.ReadData(userId)
	if not data then
		return nil
	end
	return data.Logs or {}, data.LogCounts or {}
end

-- La entrada de la sesión se reescribe en el lugar: el perfil guarda la tabla, así que la
-- duración llega al DataStore en el autoguardado o al salir.
local function trackSession(player: Player, profile: any)
	local started = os.time()
	local entry: Entry = {
		At = started,
		Text = ("Joined · %s · account age %dd"):format(serverLabel(), player.AccountAge),
	}
	push(profile.Data.Logs, "Session", entry)
	local function update()
		entry.Text = ("Played %s · %s · account age %dd"):format(
			duration(os.time() - started),
			serverLabel(),
			player.AccountAge
		)
	end
	task.spawn(function()
		while player.Parent == Players and profile:IsActive() do
			task.wait(Config.Logs.SessionUpdateSeconds)
			update()
		end
	end)
	player.AncestryChanged:Connect(function()
		if player.Parent ~= Players then
			update()
		end
	end)
end

function LogService.Init()
	DataService.OnProfileLoaded(trackSession)
	DataService.OnMessage(MESSAGE_TYPE, function(player, message, processed)
		local entry = message.Entry
		local kind = if type(entry) == "table" and type(entry.Kind) == "string" then entry.Kind else nil
		local profile = DataService.GetProfile(player)
		if
			profile
			and categories[message.Category]
			and type(entry) == "table"
			and type(entry.At) == "number"
			and type(entry.Text) == "string"
		then
			push(profile.Data.Logs, message.Category, {
				At = entry.At,
				Text = entry.Text:sub(1, MAX_TEXT),
				Icon = if type(entry.Icon) == "string" then entry.Icon else nil,
				Kind = kind,
			})
			count(profile.Data, message.Category, kind)
			-- Un mensaje puede llegar después de entradas más nuevas: se reordena por fecha.
			table.sort(profile.Data.Logs[message.Category], function(a, b)
				return a.At > b.At
			end)
		end
		processed()
	end)
end

return LogService
