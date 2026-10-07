-- Ubicación en Studio: ServerScriptService > Services > Admin > AdminRanks (ModuleScript)
-- Rangos del panel sobre EasyProfileStore: el rango vive en profile.Data.Admin de cada jugador.
local Players = game:GetService("Players")
local MessagingService = game:GetService("MessagingService")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local RS = game:GetService("ReplicatedStorage")
local Config = require(RS:WaitForChild("AdminConfig"))
local DebugConfig = require(RS:WaitForChild("DebugConfig"))
local EasyProfileStore = require(ServerStorage:WaitForChild("EasyProfileStore"))
local DataService = require(ServerScriptService:WaitForChild("Services"):WaitForChild("Data"):WaitForChild("DataService"))

export type Entry = {
	Rank: string,
	Name: string,
	GrantedBy: number,
	GrantedByName: string,
	GrantedAt: number,
	UpdatedAt: number,
}

local Ranks = {}

-- Los perfiles de jugadores no se pueden listar: la lista del panel sale de este perfil aparte
-- (mismo store). Solo se usa para mostrar; el rango que vale es el del perfil del jugador.
local INDEX_KEY = "AdminIndex"
local MESSAGE_TYPE = "AdminRank"
-- Aviso instantáneo a otros servidores: el mensaje del perfil solo se lee al entrar o al autoguardar.
local TOPIC = "AdminRanksChanged"
local INDEX_SESSION_TIMEOUT = 20

local index: { [string]: Entry } = {}
local owners: { [number]: boolean } = {}
local listeners: { () -> () } = {}

for _, id in Config.OwnerUserIds do
	owners[id] = true
end
if game.CreatorType == Enum.CreatorType.User and game.CreatorId > 0 then
	owners[game.CreatorId] = true
end

local function store()
	return EasyProfileStore.DatasLoaded
end

local function now(): number
	return DateTime.now().UnixTimestampMillis
end

local function notify()
	for _, fn in listeners do
		task.spawn(fn)
	end
end

function Ranks.OnChanged(fn: () -> ())
	table.insert(listeners, fn)
end

function Ranks.IsOwner(userId: number): boolean
	if owners[userId] then
		return true
	end
	-- En un Local Server de Studio los jugadores de prueba tienen UserId negativo.
	return Config.StudioIsOwner and RunService:IsStudio() and (userId <= 0 or userId == game.CreatorId)
end

local function profileEntry(userId: number): Entry?
	local player = Players:GetPlayerByUserId(userId)
	local profile = player and DataService.GetProfile(player)
	return profile and profile.Data.Admin
end

-- El perfil cargado manda; si el jugador no está en este servidor, se usa el índice.
function Ranks.Entry(userId: number): Entry?
	local entry = profileEntry(userId) or index[tostring(userId)]
	return if entry and Config.Ranks[entry.Rank] then entry else nil
end

function Ranks.Get(userId: number): string?
	if Ranks.IsOwner(userId) then
		return "Owner"
	end
	local entry = Ranks.Entry(userId)
	return entry and entry.Rank
end

function Ranks.Level(userId: number): number
	local rank = Ranks.Get(userId)
	return if rank then Config.Ranks[rank].Level else 0
end

function Ranks.All(): { [string]: Entry }
	local all = table.clone(index)
	for _, player in Players:GetPlayers() do
		local entry = profileEntry(player.UserId)
		local key = tostring(player.UserId)
		if entry and Config.Ranks[entry.Rank] then
			all[key] = table.clone(entry)
			all[key].Name = player.Name
		elseif entry then
			all[key] = nil
		end
	end
	return all
end

local function refreshAttribute(player: Player)
	player:SetAttribute("AdminRank", Ranks.Get(player.UserId))
end

-- Pisa el rango del perfil solo si el cambio es más nuevo (los mensajes pueden llegar tarde).
local function apply(player: Player, entry: Entry): boolean
	local profile = DataService.GetProfile(player)
	if not profile then
		return false
	end
	local current = profile.Data.Admin
	if (current.UpdatedAt or 0) > entry.UpdatedAt then
		return true
	end
	profile.Data.Admin = table.clone(entry)
	refreshAttribute(player)
	notify()
	return true
end

function Ranks.ReloadIndex(): boolean
	local s = store()
	if not s then
		return false
	end
	local ok, profile = pcall(s.GetAsync, s, INDEX_KEY)
	if not ok then
		DebugConfig.warn("[AdminRanks] No se pudo leer el índice: " .. tostring(profile))
		return false
	end
	index = if profile and type(profile.Data.AdminIndex) == "table" then profile.Data.AdminIndex else {}
	for _, player in Players:GetPlayers() do
		refreshAttribute(player)
	end
	notify()
	return true
end

-- Sesión corta sobre el perfil índice: si otro servidor lo tiene, ProfileStore se lo pide.
local function writeIndex(userId: number, entry: Entry?): boolean
	local s = store()
	if not s then
		return false
	end
	local started = os.clock()
	local ok, profile = pcall(s.StartSessionAsync, s, INDEX_KEY, {
		Cancel = function()
			return os.clock() - started > INDEX_SESSION_TIMEOUT
		end,
	})
	if not ok or not profile then
		DebugConfig.warn("[AdminRanks] No se pudo abrir el índice: " .. tostring(profile))
		return false
	end
	local data = if type(profile.Data.AdminIndex) == "table" then profile.Data.AdminIndex else {}
	data[tostring(userId)] = entry
	profile.Data.AdminIndex = data
	profile:EndSession()
	index = data
	return true
end

-- entry.Rank == "" quita el rango.
local function change(userId: number, entry: Entry): (boolean, string?)
	if not store() then
		return false, "Data is not ready"
	end
	local player = Players:GetPlayerByUserId(userId)
	if not (player and apply(player, entry)) then
		local ok = pcall(function()
			EasyProfileStore:PublishMessage(userId, { Type = MESSAGE_TYPE, Entry = entry })
		end)
		if not ok then
			return false, "Could not save, try again"
		end
		task.spawn(pcall, MessagingService.PublishAsync, MessagingService, TOPIC, { UserId = userId, Entry = entry })
	end
	if not writeIndex(userId, if entry.Rank == "" then nil else entry) then
		return false, "Rank saved, but the admin list could not be updated"
	end
	notify()
	return true
end

function Ranks.Set(userId: number, entry: Entry): (boolean, string?)
	entry.UpdatedAt = now()
	return change(userId, entry)
end

function Ranks.Remove(userId: number): (boolean, string?)
	local current = Ranks.Entry(userId)
	return change(userId, {
		Rank = "",
		Name = if current then current.Name else "",
		GrantedBy = 0,
		GrantedByName = "",
		GrantedAt = 0,
		UpdatedAt = now(),
	})
end

function Ranks.Init()
	Players.PlayerAdded:Connect(refreshAttribute)
	for _, player in Players:GetPlayers() do
		refreshAttribute(player)
	end
	DataService.OnProfileLoaded(refreshAttribute)

	-- Rango cambiado mientras el jugador no estaba en este servidor.
	DataService.OnMessage(MESSAGE_TYPE, function(player, message, processed)
		if type(message.Entry) == "table" and type(message.Entry.UpdatedAt) == "number" then
			apply(player, message.Entry)
		end
		processed()
	end)

	pcall(MessagingService.SubscribeAsync, MessagingService, TOPIC, function(message)
		local data = message.Data
		local player = type(data) == "table" and Players:GetPlayerByUserId(data.UserId)
		if player and type(data.Entry) == "table" then
			apply(player, data.Entry)
		end
		task.spawn(Ranks.ReloadIndex)
	end)

	Ranks.ReloadIndex()
	task.spawn(function()
		while true do
			task.wait(Config.ReloadInterval)
			Ranks.ReloadIndex()
		end
	end)
end

return Ranks
