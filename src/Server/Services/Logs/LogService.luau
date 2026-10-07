-- Ubicación en Studio: ServerScriptService > Services > Logs > LogService (ModuleScript)
-- Logs por jugador para el Admin Panel: viven en profile.Data.Logs (EasyProfileStore).
local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")
local RS = game:GetService("ReplicatedStorage")
local Config = require(RS:WaitForChild("AdminConfig"))
local EasyProfileStore = require(ServerStorage:WaitForChild("EasyProfileStore"))
local DataService = require(script.Parent.Parent:WaitForChild("Data"):WaitForChild("DataService"))

export type Entry = { At: number, Text: string, Icon: string? }

local LogService = {}

local MESSAGE_TYPE = "Log"
local MAX_TEXT = 300

local categories: { [string]: boolean } = {}
for _, category in Config.Logs.Categories do
	categories[category.Id] = true
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
function LogService.Add(userId: number, category: string, text: string, icon: string?)
	assert(categories[category], "[LogService] Categoría desconocida: " .. tostring(category))
	local entry: Entry = { At = os.time(), Text = text:sub(1, MAX_TEXT), Icon = icon }
	local player = Players:GetPlayerByUserId(userId)
	local profile = player and DataService.GetProfile(player)
	if profile then
		push(profile.Data.Logs, category, entry)
		return
	end
	pcall(function()
		EasyProfileStore:PublishMessage(userId, { Type = MESSAGE_TYPE, Category = category, Entry = entry })
	end)
end

-- Conectado acá: el perfil vivo. Si no: la última versión guardada (de otro servidor o de
-- su última sesión); los mensajes pendientes recién aparecen cuando vuelve a entrar.
function LogService.Get(userId: number): { [string]: { Entry } }?
	local player = Players:GetPlayerByUserId(userId)
	local profile = player and DataService.GetProfile(player)
	if profile then
		return profile.Data.Logs
	end
	local store = EasyProfileStore.DatasLoaded
	if not store then
		return nil
	end
	local ok, saved = pcall(store.GetAsync, store, "Player_" .. userId)
	return if ok and saved then saved.Data.Logs else nil
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
			})
			-- Un mensaje puede llegar después de entradas más nuevas: se reordena por fecha.
			table.sort(profile.Data.Logs[message.Category], function(a, b)
				return a.At > b.At
			end)
		end
		processed()
	end)
end

return LogService
