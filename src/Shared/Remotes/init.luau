-- Ubicación en Studio: ReplicatedStorage > Remotes (ModuleScript)
-- Única fuente de RemoteEvents/Functions: agregar uno = sumar su nombre a EVENTS o
-- FUNCTIONS. El servidor los crea como hijos de este módulo; el cliente los espera.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local IS_SERVER = RunService:IsServer()

local EVENTS = {
	-- Bus servidor → cliente: (evento, ...payload). Ver fireAll / onUpdate.
	"UpdateUI",

	-- LoadingScreen.
	"SetLoadingComplete",

	-- Map Vote.
	"CastMapVote",
	"RequestMapVoteState",
	"DebugMapVote",

	-- Tienda.
	"RequestShopPurchase",

	-- Espectador.
	"SetSpectatorTarget",

	-- Admin Panel: voto de un jugador en el poll activo.
	"VotePoll",
}

local FUNCTIONS: { string } = {
	-- Códigos.
	"RedeemCode",

	-- Tienda.
	"GetShopOwned",

	-- Espectador.
	"SubmitPlayerReport",

	-- Admin Panel.
	"AdminRequest",
	"GetActivePoll",
}

local UPDATE_UI = "UpdateUI"

local Remotes = {}

-- Un nombre no declarado es un typo: error inmediato en vez de esperar para siempre.
local declared: { [string]: string } = {}
for _, name in EVENTS do
	declared[name] = "RemoteEvent"
end
for _, name in FUNCTIONS do
	declared[name] = "RemoteFunction"
end

local cache: { [string]: Instance } = {}

-- El nivel superior corre una vez por VM: solo el servidor crea las instancias, o cada
-- lado tendría copias sueltas.
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

-- El cooldown solo frena el spam: el handler igual tiene que validar tipos y rangos.

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

-- Pedidos del mismo jugador antes de `cooldown` segundos se descartan en silencio.
function Remotes.onServerEvent(name: string, handler: (player: Player, ...any) -> (), cooldown: number?): RBXScriptConnection
	assert(IS_SERVER, "[Remotes] onServerEvent solo se usa desde el servidor")
	return Remotes.event(name).OnServerEvent:Connect(function(player: Player, ...)
		if allow(player, name, cooldown) then
			handler(player, ...)
		end
	end)
end

-- Un pedido descartado por cooldown devuelve nil.
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

-- Bus UpdateUI: un solo RemoteEvent por nombre de evento, para avisos que no justifican
-- un remote propio.

function Remotes.fireAll(event: string, ...: any)
	Remotes.event(UPDATE_UI):FireAllClients(event, ...)
end

function Remotes.fireTo(player: Player, event: string, ...: any)
	Remotes.event(UPDATE_UI):FireClient(player, event, ...)
end

local updateHandlers: { [string]: { (...any) -> () } } = {}
local updateConnection: RBXScriptConnection? = nil

-- Devuelve la función para desuscribirse. Un hilo por handler: si uno falla, los demás
-- reciben el evento igual.
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
