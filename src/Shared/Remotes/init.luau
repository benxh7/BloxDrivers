-- Ubicación en Studio: ReplicatedStorage > Remotes (ModuleScript)
--
-- Punto ÚNICO de acceso a los RemoteEvents / RemoteFunctions del juego, desde el
-- cliente y desde el servidor. Las instancias viven como hijos de este mismo
-- ModuleScript, así que en el explorador se ven en ReplicatedStorage > Remotes > <Nombre>.
--
--   Servidor: al primer `require` crea TODOS los remotes declarados abajo.
--   Cliente:  los espera bajo demanda (WaitForChild) la primera vez que se piden.
--
-- Agregar un remote nuevo = sumar su nombre a EVENTS o FUNCTIONS. Nada más.
--
-- Uso:
--   local Remotes = require(ReplicatedStorage:WaitForChild("Remotes"))
--   Remotes.event("CastMapVote"):FireServer(mapId)                      -- cliente
--   Remotes.onServerEvent("CastMapVote", handler, 0.25)                -- servidor (con cooldown)
--   Remotes.fireAll("mapVoteTick", 10) / Remotes.onUpdate("mapVoteTick", fn)  -- bus UpdateUI
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local IS_SERVER = RunService:IsServer()

-- RemoteEvents del juego. Un comentario por grupo para saber quién los usa.
local EVENTS = {
	-- Bus genérico servidor → cliente: (evento: string, ...payload). Ver fireAll / onUpdate.
	"UpdateUI",

	-- LoadingScreen: el cliente avisa que terminó de cargar.
	"SetLoadingComplete",

	-- Map Vote (MapVoteService ↔ VotingMapController).
	"CastMapVote",
	"RequestMapVoteState",
	"DebugMapVote",

	-- Tienda (ShopController → ShopService): el cliente manda solo el Id del item.
	"RequestShopPurchase",
}

-- RemoteFunctions del juego (cliente pide y espera respuesta).
local FUNCTIONS: { string } = {
	-- Tienda: Ids de los Game Passes que ya tiene el jugador.
	"GetShopOwned",
}

local UPDATE_UI = "UpdateUI"

local Remotes = {}

-- nombre -> ClassName esperado. Pedir un nombre no declarado es un error de tipeo:
-- se corta enseguida en vez de quedarse esperando para siempre un remote que no existe.
local declared: { [string]: string } = {}
for _, name in EVENTS do
	declared[name] = "RemoteEvent"
end
for _, name in FUNCTIONS do
	declared[name] = "RemoteFunction"
end

local cache: { [string]: Instance } = {}

-- Un ModuleScript compartido corre su nivel superior UNA VEZ POR VM: solo el servidor
-- crea las instancias y el cliente las espera; si no, cada lado tendría copias sueltas.
if IS_SERVER then
	for name, className in declared do
		local remote = Instance.new(className)
		remote.Name = name
		remote.Parent = script
		cache[name] = remote
	end
end

local function get(name: string, className: string): Instance
	local remote = cache[name]
	if remote then
		return remote
	end
	if declared[name] ~= className then
		error(("[Remotes] '%s' no está declarado como %s en ReplicatedStorage.Remotes"):format(name, className), 3)
	end
	remote = script:WaitForChild(name)
	cache[name] = remote
	return remote
end

function Remotes.event(name: string): RemoteEvent
	return get(name, "RemoteEvent") :: RemoteEvent
end

function Remotes.func(name: string): RemoteFunction
	return get(name, "RemoteFunction") :: RemoteFunction
end

-- ─── Servidor: listeners con rate limit ─────────────────────────────────────────
-- Todo lo que llega del cliente es controlado por el cliente: el handler igual tiene
-- que validar tipos y rangos. El cooldown solo frena el spam (un exploiter puede
-- disparar un remote miles de veces por segundo).

local lastCall: { [Player]: { [string]: number } } = {}

local function allow(player: Player, name: string, cooldown: number?): boolean
	if not cooldown or cooldown <= 0 then
		return true
	end
	local now = os.clock()
	local perPlayer = lastCall[player]
	if not perPlayer then
		perPlayer = {}
		lastCall[player] = perPlayer
	end
	local last = perPlayer[name]
	if last and now - last < cooldown then
		return false
	end
	perPlayer[name] = now
	return true
end

-- Conecta un handler a un RemoteEvent. Los pedidos que llegan antes de `cooldown`
-- segundos desde el último del mismo jugador se descartan en silencio.
function Remotes.onServerEvent(name: string, handler: (player: Player, ...any) -> (), cooldown: number?): RBXScriptConnection
	assert(IS_SERVER, "[Remotes] onServerEvent solo se usa desde el servidor")
	return Remotes.event(name).OnServerEvent:Connect(function(player: Player, ...)
		if allow(player, name, cooldown) then
			handler(player, ...)
		end
	end)
end

-- Igual para RemoteFunctions. Un pedido descartado por cooldown devuelve nil.
function Remotes.onServerInvoke(name: string, handler: (player: Player, ...any) -> ...any, cooldown: number?)
	assert(IS_SERVER, "[Remotes] onServerInvoke solo se usa desde el servidor")
	Remotes.func(name).OnServerInvoke = function(player: Player, ...)
		if not allow(player, name, cooldown) then
			return nil
		end
		return handler(player, ...)
	end
end

if IS_SERVER then
	Players.PlayerRemoving:Connect(function(player: Player)
		lastCall[player] = nil
	end)
end

-- ─── Bus UpdateUI (servidor → cliente) ──────────────────────────────────────────
-- Un solo RemoteEvent multiplexado por nombre de evento: sirve para avisos de UI que
-- no justifican un remote propio. El cliente se suscribe por nombre con onUpdate.

function Remotes.fireAll(event: string, ...: any)
	Remotes.event(UPDATE_UI):FireAllClients(event, ...)
end

function Remotes.fireTo(player: Player, event: string, ...: any)
	Remotes.event(UPDATE_UI):FireClient(player, event, ...)
end

local updateHandlers: { [string]: { (...any) -> () } } = {}
local updateConnection: RBXScriptConnection? = nil

-- Cliente: `handler(...)` corre cada vez que el servidor manda `event`. Devuelve una
-- función para desuscribirse. Cada handler corre en su propio hilo: si uno falla, los
-- demás igual reciben el evento.
function Remotes.onUpdate(event: string, handler: (...any) -> ()): () -> ()
	assert(not IS_SERVER, "[Remotes] onUpdate solo se usa desde el cliente")

	local list = updateHandlers[event]
	if not list then
		list = {}
		updateHandlers[event] = list
	end
	table.insert(list, handler)

	if not updateConnection then
		updateConnection = Remotes.event(UPDATE_UI).OnClientEvent:Connect(function(name: string, ...)
			local handlers = updateHandlers[name]
			if not handlers then
				return
			end
			for _, fn in table.clone(handlers) do
				task.spawn(fn, ...)
			end
		end)
	end

	return function()
		local index = table.find(list, handler)
		if index then
			table.remove(list, index)
		end
	end
end

return Remotes
