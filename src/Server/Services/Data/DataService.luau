-- Ubicación en Studio: ServerScriptService > Services > Data > DataService (ModuleScript)
-- Dueño de EasyProfileStore: crea el store de jugadores y avisa cuándo carga cada perfil.
local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")
local RS = game:GetService("ReplicatedStorage")
local EasyProfileStore = require(ServerStorage:WaitForChild("EasyProfileStore"))
local DebugConfig = require(RS:WaitForChild("DebugConfig"))

local DataService = {}

-- Cambiar el nombre arranca un store nuevo y vacío (se pierden todos los datos).
local STORE_NAME = "PlayerData_v1"

-- Campos nuevos se agregan acá: Reconcile los completa en perfiles viejos.
DataService.Template = {
	-- Rango del Admin Panel. Rank "" = sin rango. UpdatedAt ordena cambios que llegan por mensaje.
	Admin = { Rank = "", GrantedBy = 0, GrantedByName = "", GrantedAt = 0, UpdatedAt = 0 },
	-- Reportes recibidos. Reporters = { [userId string] = true }; AlertedAt = Unique del último aviso.
	Reports = { Total = 0, Unique = 0, Reporters = {}, AlertedAt = 0 },
	-- Logs del Admin Panel: { [categoría] = { { At, Text }, ... } }, el más nuevo primero.
	Logs = { Purchase = {}, Moderation = {}, Report = {}, Code = {}, Session = {}, Staff = {} },
	-- Totales de por vida de los logs (Logs guarda solo los últimos): { ["Moderation"] = n, ["Moderation:Ban"] = n }.
	LogCounts = {},
	-- Auditoría si es staff: Counts = { [acción] = n } y Sanctions = { ban/kick/warn, ... }.
	Staff = { Counts = {}, Sanctions = {} },
}

-- EasyProfileStore usa UN solo store: lo crea este módulo al requerirse (antes de cualquier
-- Init), así otros servicios pueden usar EasyProfileStore.DatasLoaded desde su Init.
EasyProfileStore.New(STORE_NAME, DataService.Template)

local loadedCallbacks: { (Player, any) -> () } = {}
local removedCallbacks: { (Player) -> () } = {}

function DataService.OnProfileLoaded(fn: (Player, any) -> ())
	table.insert(loadedCallbacks, fn)
	for player, profile in EasyProfileStore.Profiles do
		task.spawn(fn, player, profile)
	end
end

function DataService.OnProfileRemoved(fn: (Player) -> ())
	table.insert(removedCallbacks, fn)
end

function DataService.GetProfile(player: Player): any?
	return EasyProfileStore.Profiles[player]
end

-- Datos de cualquier jugador, solo lectura: el perfil vivo si está en este servidor, si no la
-- última versión guardada (los mensajes pendientes recién se aplican cuando vuelve a entrar).
function DataService.ReadData(userId: number): any?
	local player = Players:GetPlayerByUserId(userId)
	local profile = player and EasyProfileStore.Profiles[player]
	if profile then
		return profile.Data
	end
	local store = EasyProfileStore.DatasLoaded
	if not store then
		return nil
	end
	local ok, saved = pcall(store.GetAsync, store, "Player_" .. userId)
	return if ok and saved then saved.Data else nil
end

-- Mensajes del canal de EasyProfileStore (PublishMessage), filtrados por `Type`.
function DataService.OnMessage(messageType: string, fn: (Player, any, () -> ()) -> ())
	EasyProfileStore.SuscribeMessage:Connect(function(player, message, processed)
		if type(message) == "table" and message.Type == messageType then
			fn(player, message, processed)
		end
	end)
end

function DataService.Init()
	EasyProfileStore.OnError:Connect(function(message)
		DebugConfig.warn("[DataService] EasyProfileStore: " .. tostring(message))
	end)
	EasyProfileStore.onPlayerJoined(function(player, profile)
		for _, fn in loadedCallbacks do
			task.spawn(fn, player, profile)
		end
	end)
	EasyProfileStore.onPlayerRemoved(function(player)
		for _, fn in removedCallbacks do
			task.spawn(fn, player)
		end
	end)
end

return DataService
