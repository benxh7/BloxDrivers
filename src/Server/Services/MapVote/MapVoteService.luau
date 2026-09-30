-- Ubicación en Studio: ServerScriptService > Services > MapVote > MapVoteService (ModuleScript)
-- Votación de mapa (autoridad). Catálogo desde ServerStorage.Maps, que no replica: viaja
-- por el bus UpdateUI. `runVoteWindow(duration)` corre una ventana entera.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Remotes = require(ReplicatedStorage:WaitForChild("Remotes"))
local DebugConfig = require(ReplicatedStorage:WaitForChild("DebugConfig"))
local VotingMapConfig = require(ReplicatedStorage:WaitForChild("VotingMapConfig"))

local MapVoteService = {}

MapVoteService.VOTE_DURATION = 15

local MAPS_FOLDER_NAME = "Maps"
-- Nombres aceptados para el value con la imagen de cada mapa (gana el primero que exista).
local IMAGE_VALUE_NAMES = { "Image", "ImageID", "ImageId", "Icon", "Thumbnail" }
-- Mapas que se muestran a la vez.
local MAX_OPTIONS = 3

-- Cada voto es un broadcast a TODOS: sin cooldown, un cliente inundaría la red de todos.
local CAST_VOTE_COOLDOWN = 0.25
local REQUEST_STATE_COOLDOWN = 2
local DEBUG_VOTE_COOLDOWN = 1

type MapEntry = { Id: string, Name: string, Image: string }

-- UserId -> mapId votado.
local votes: { [number]: string } = {}

local options: { MapEntry } = {}
local optionById: { [string]: boolean } = {}

local voteActive = false

-- Si arranca otra ventana, la corrutina de la vieja se retira sin cerrar la GUI de la nueva.
local windowGeneration = 0

-- Acepta Number (asset ID) o String ("123" / "rbxassetid://123").
local function resolveImage(mapFolder: Instance): string
	local value
	for _, name in IMAGE_VALUE_NAMES do
		local child = mapFolder:FindFirstChild(name)
		if child and child:IsA("ValueBase") then
			value = child
			break
		end
	end
	if not value then
		return ""
	end
	local raw = (value :: any).Value
	if typeof(raw) == "number" then
		return if raw > 0 then "rbxassetid://" .. math.floor(raw) else ""
	elseif typeof(raw) == "string" then
		local s = (raw:gsub("%s+", ""))
		if s == "" or s == "0" then
			return ""
		end
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
	if not folder then
		return all
	end
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
	if #all <= MAX_OPTIONS then
		return all
	end
	local shuffled = table.clone(all)
	for i = #shuffled, 2, -1 do
		local j = math.random(i)
		shuffled[i], shuffled[j] = shuffled[j], shuffled[i]
	end
	return table.move(shuffled, 1, MAX_OPTIONS, 1, {})
end

local function buildOptions()
	options = pickOptions(scanAllMaps())
	optionById = {}
	for _, map in options do
		optionById[map.Id] = true
	end
end

-- Por si la GUI pide el estado antes de cualquier startVote.
local function getOptions(): { MapEntry }
	if #options == 0 then
		buildOptions()
	end
	return options
end

-- { [mapId] = { userId, ... } }, con TODAS las opciones aunque estén vacías.
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
	Remotes.fireAll("mapVoteState", buildState())
end

function MapVoteService.startVote(): { MapEntry }
	table.clear(votes)
	buildOptions()
	voteActive = true

	Remotes.fireAll("mapVoteCatalog", options)
	pushAll()
	return options
end

-- Empate o sin votos: al azar entre los empatados.
function MapVoteService.finishVote(): string?
	voteActive = false
	if #options == 0 then
		return nil
	end

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

local function abortWindow(): nil
	MapVoteService.finishVote()
	Remotes.fireAll("mapVoteEnd", nil)
	return nil
end

-- BLOQUEA (llamar desde una corrutina). `shouldAbort` se consulta en cada tick; al cortar
-- igual avisa el cierre, o la GUI quedaría abierta.
function MapVoteService.runVoteWindow(duration: number, shouldAbort: (() -> boolean)?): string?
	windowGeneration += 1
	local myGeneration = windowGeneration

	MapVoteService.startVote()
	Remotes.fireAll("mapVoteStart", duration)

	-- Espera a que entren las cards en el cliente: si no, el tiempo baja mientras caen.
	task.wait(VotingMapConfig.entranceDuration(#options) + VotingMapConfig.EntranceBuffer)
	if windowGeneration ~= myGeneration then
		return nil
	end
	if shouldAbort and shouldAbort() then
		return abortWindow()
	end

	for timeLeft = duration, 1, -1 do
		if windowGeneration ~= myGeneration then
			return nil
		end
		if shouldAbort and shouldAbort() then
			return abortWindow()
		end
		Remotes.fireAll("mapVoteTick", timeLeft)
		task.wait(1)
	end

	if windowGeneration ~= myGeneration then
		return nil
	end

	local winner = MapVoteService.finishVote()
	Remotes.fireAll("mapVoteEnd", winner)

	-- Espera la celebración: quien llama puede cargar el mapa apenas vuelve.
	task.wait(VotingMapConfig.celebrationDuration())
	if windowGeneration ~= myGeneration then
		return nil
	end
	return winner
end

local function onCastVote(player: Player, mapId: any)
	if not voteActive then
		return
	end
	if typeof(mapId) ~= "string" or not optionById[mapId] then
		return
	end

	-- Re-votar el mismo mapa lo desvota; votar otro mueve el voto.
	votes[player.UserId] = if votes[player.UserId] == mapId then nil else mapId
	pushAll()
end

local function onRequestState(player: Player)
	Remotes.fireTo(player, "mapVoteCatalog", getOptions())
	Remotes.fireTo(player, "mapVoteState", buildState())
end

-- Gate obligatorio en el servidor: el remote existe aunque el botón no esté en pantalla.
local function onDebugVote(player: Player)
	if not DebugConfig.CHEATS_ENABLED then
		return
	end
	if voteActive then
		DebugConfig.print("[MapVoteService] Debug: ya hay una votación abierta, se ignora")
		return
	end

	DebugConfig.print("[MapVoteService] Debug: votación arrancada por " .. player.Name)
	task.spawn(function()
		local winner = MapVoteService.runVoteWindow(MapVoteService.VOTE_DURATION)
		DebugConfig.print("[MapVoteService] Debug: ganó " .. tostring(winner))
	end)
end

function MapVoteService.Init()
	Remotes.onServerEvent("CastMapVote", onCastVote, CAST_VOTE_COOLDOWN)
	Remotes.onServerEvent("RequestMapVoteState", onRequestState, REQUEST_STATE_COOLDOWN)
	Remotes.onServerEvent("DebugMapVote", onDebugVote, DEBUG_VOTE_COOLDOWN)

	Players.PlayerRemoving:Connect(function(player: Player)
		if votes[player.UserId] then
			votes[player.UserId] = nil
			pushAll()
		end
	end)
end

return MapVoteService
