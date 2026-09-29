local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local GameRemotes = require(ReplicatedStorage.Remotes.GameRemotes)
local DebugConfig = require(ReplicatedStorage.DebugConfig)
local VotingMapConfig = require(ReplicatedStorage.VotingMapConfig)

-- El catálogo sale de ServerStorage.Maps: nombre = folder, imagen = su value
-- `Image`. Como ServerStorage no se replica, viaja al cliente por la red.
--
-- Traído de UBG y desacoplado de su GameRoundSystem: acá `runVoteWindow` manda
-- directo por GameRemotes.fireAll en vez de pasar por un bus de ronda. Llamalo
-- desde donde quieras abrir una votación (ej. entre carreras).
local MapVoteService = {}

MapVoteService.VOTE_DURATION = 15

local MAPS_FOLDER_NAME = "Maps" -- ServerStorage.Maps
-- Nombres aceptados para el value con el asset ID de la imagen (el primero que exista).
local IMAGE_VALUE_NAMES = { "Image", "ImageID", "ImageId", "Icon", "Thumbnail" }
local MAX_OPTIONS = 3 -- cuántos mapas se muestran a la vez en la votación

type MapEntry = { Id: string, Name: string, Image: string }

local votes: { [number]: string } = {} -- UserId -> mapId votado

local options: { MapEntry } = {}
local optionById: { [string]: boolean } = {}

-- Solo se acepta votar con una votación abierta (la GUI vive dentro de MAP_VOTE).
local voteActive = false

-- Staleness-guard de ventanas: si arranca una nueva, la corrutina de la vieja se
-- retira sin disparar su cierre (si no, cerraría la GUI de la que recién empezó).
local windowGeneration = 0

-- Acepta Number/Int (asset ID) o String ("123" / "rbxassetid://123").
local function resolveImage(mapFolder: Instance): string
	local value
	for _, name in IMAGE_VALUE_NAMES do
		local child = mapFolder:FindFirstChild(name)
		if child and child:IsA("ValueBase") then
			value = child
			break
		end
	end
	if not value then return "" end
	local raw = (value :: any).Value
	if typeof(raw) == "number" then
		return raw > 0 and ("rbxassetid://" .. math.floor(raw)) or ""
	elseif typeof(raw) == "string" then
		local s = (raw:gsub("%s+", ""))
		if s == "" or s == "0" then return "" end
		if s:match("^rbxassetid://") or s:match("^rbxthumb://") or s:match("^http") then
			return s
		end
		return "rbxassetid://" .. s
	end
	return ""
end

local function scanAllMaps(): { MapEntry }
	local all = {}
	local folder = ServerStorage:FindFirstChild(MAPS_FOLDER_NAME)
	if not folder then return all end
	for _, mapFolder in folder:GetChildren() do
		table.insert(all, {
			Id = mapFolder.Name,
			Name = mapFolder.Name,
			Image = resolveImage(mapFolder),
		})
	end
	return all
end

local function pickOptions(all: { MapEntry }): { MapEntry }
	if #all <= MAX_OPTIONS then return all end
	local shuffled = table.clone(all)
	for i = #shuffled, 2, -1 do
		local j = math.random(i)
		shuffled[i], shuffled[j] = shuffled[j], shuffled[i]
	end
	local picked = {}
	for i = 1, MAX_OPTIONS do
		picked[i] = shuffled[i]
	end
	return picked
end

local function buildOptions()
	options = pickOptions(scanAllMaps())
	optionById = {}
	for _, map in options do
		optionById[map.Id] = true
	end
end

-- Self-heal si nadie llamó startVote todavía (ej. la GUI pide estado suelta).
local function getOptions(): { MapEntry }
	if #options == 0 then
		buildOptions()
	end
	return options
end

-- Estado que viaja al cliente: { [mapId] = { userId, ... } }. Incluye TODAS las
-- opciones (con lista vacía) para que la GUI no asuma nada.
local function buildState(): { [string]: { number } }
	local byMap = {}
	for _, map in getOptions() do
		byMap[map.Id] = {}
	end
	for userId, mapId in votes do
		if byMap[mapId] then
			table.insert(byMap[mapId], userId)
		end
	end
	return byMap
end

local function pushAll()
	GameRemotes.fireAll("mapVoteState", buildState())
end

-- Abre una votación nueva: re-sortea las opciones, limpia los votos y manda
-- catálogo + estado a todos. Devuelve las opciones mostradas.
function MapVoteService.startVote(): { MapEntry }
	table.clear(votes)
	buildOptions()
	voteActive = true

	GameRemotes.fireAll("mapVoteCatalog", options)
	pushAll()
	return options
end

-- Cierra la votación y devuelve el mapa ganador: el más votado, desempatando al
-- azar entre los empatados. Sin votos (o sin mapas), uno al azar de las opciones.
function MapVoteService.finishVote(): string?
	voteActive = false
	if #options == 0 then return nil end

	local counts: { [string]: number } = {}
	for _, mapId in votes do
		counts[mapId] = (counts[mapId] or 0) + 1
	end

	local best = 0
	local tied: { string } = {}
	for _, map in options do
		local count = counts[map.Id] or 0
		if count > best then
			best = count
			tied = { map.Id }
		elseif count == best then
			table.insert(tied, map.Id)
		end
	end

	return tied[math.random(#tied)]
end

function MapVoteService.isVoteActive(): boolean
	return voteActive
end

-- BLOQUEA hasta terminar: llamar desde una corrutina. `shouldAbort` se consulta en
-- CADA tick, y al cortar igual avisa el cierre o la GUI queda abierta.
function MapVoteService.runVoteWindow(duration: number, shouldAbort: (() -> boolean)?): string?
	windowGeneration += 1
	local myGeneration = windowGeneration

	MapVoteService.startVote()
	GameRemotes.fireAll("mapVoteStart", duration)

	-- Espera a que las cards terminen de entrar en el cliente antes de contar: si no, el
	-- tiempo baja mientras todavía caen y el cliente (que lo congela hasta tenerlas)
	-- mostraría un salto. Deriva de VotingMapConfig, igual que la animación del cliente.
	task.wait(VotingMapConfig.entranceDuration(#options) + VotingMapConfig.EntranceBuffer)
	if windowGeneration ~= myGeneration then return nil end
	if shouldAbort and shouldAbort() then
		MapVoteService.finishVote()
		GameRemotes.fireAll("mapVoteEnd", nil)
		return nil
	end

	for timeLeft = duration, 1, -1 do
		-- Otra ventana arrancó: la vieja se retira EN SILENCIO, sin cerrarle la GUI a la nueva.
		if windowGeneration ~= myGeneration then return nil end
		if shouldAbort and shouldAbort() then
			MapVoteService.finishVote()
			GameRemotes.fireAll("mapVoteEnd", nil)
			return nil
		end
		GameRemotes.fireAll("mapVoteTick", timeLeft)
		task.wait(1)
	end

	if windowGeneration ~= myGeneration then return nil end

	local winner = MapVoteService.finishVote()
	GameRemotes.fireAll("mapVoteEnd", winner)

	-- Le da aire a la celebración del ganador antes de devolver: quien llama puede
	-- encadenar la siguiente acción (ej. cargar el mapa) justo después.
	task.wait(VotingMapConfig.celebrationDuration())
	if windowGeneration ~= myGeneration then return nil end
	return winner
end

GameRemotes.CastMapVote.OnServerEvent:Connect(function(player: Player, mapId: any)
	-- Valida el mapId contra las opciones mostradas, nunca confía en el cliente.
	if not voteActive then return end
	if typeof(mapId) ~= "string" or not optionById[mapId] then return end

	-- Re-votar el mismo mapa lo desvota; votar otro mueve el voto.
	if votes[player.UserId] == mapId then
		votes[player.UserId] = nil
	else
		votes[player.UserId] = mapId
	end
	pushAll()
end)

GameRemotes.RequestMapVoteState.OnServerEvent:Connect(function(player: Player)
	GameRemotes.fireTo(player, "mapVoteCatalog", getOptions())
	GameRemotes.fireTo(player, "mapVoteState", buildState())
end)

-- Corre la misma ventana real de votación sin depender de ninguna ronda.
GameRemotes.DebugMapVote.OnServerEvent:Connect(function(player: Player)
	if not DebugConfig.CHEATS_ENABLED then return end
	if voteActive then
		DebugConfig.print("[MapVoteService] Debug: ya hay una votación abierta, se ignora")
		return
	end

	DebugConfig.print("[MapVoteService] Debug: votación arrancada por " .. player.Name)
	task.spawn(function()
		local winner = MapVoteService.runVoteWindow(MapVoteService.VOTE_DURATION)
		DebugConfig.print("[MapVoteService] Debug: ganó " .. tostring(winner))
	end)
end)

Players.PlayerRemoving:Connect(function(player: Player)
	if votes[player.UserId] then
		votes[player.UserId] = nil
		pushAll()
	end
end)

return MapVoteService
