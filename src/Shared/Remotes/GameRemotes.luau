local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Traído de UBG recortado a lo que usan los sistemas de LoadingScreen y Map Vote.
-- Sumá remotes nuevos siguiendo el mismo patrón cuando agregues otro sistema.
local GameRemotes = {}

local updateUi: RemoteEvent

-- Un ModuleScript compartido corre su nivel superior UNA VEZ POR VM: solo el servidor
-- crea las instancias y el cliente las espera, o cada uno tendría copias sueltas.
if RunService:IsServer() then
	local remotesFolder = Instance.new("Folder")
	remotesFolder.Name = "GameRemotes"
	remotesFolder.Parent = ReplicatedStorage

	updateUi = Instance.new("RemoteEvent")
	updateUi.Name = "UpdateUI"
	updateUi.Parent = remotesFolder

	-- Hasta que LoadingScript lo dispare, el jugador no es elegible para el juego.
	local setLoadingComplete = Instance.new("RemoteEvent")
	setLoadingComplete.Name = "SetLoadingComplete"
	setLoadingComplete.Parent = remotesFolder

	-- Solo se acepta votar con una votación abierta, contra las opciones mostradas.
	local castMapVote = Instance.new("RemoteEvent")
	castMapVote.Name = "CastMapVote"
	castMapVote.Parent = remotesFolder

	local requestMapVoteState = Instance.new("RemoteEvent")
	requestMapVoteState.Name = "RequestMapVoteState"
	requestMapVoteState.Parent = remotesFolder

	-- Corre una ventana de votación real sin depender de ninguna ronda (debug/manual).
	local debugMapVote = Instance.new("RemoteEvent")
	debugMapVote.Name = "DebugMapVote"
	debugMapVote.Parent = remotesFolder

	GameRemotes.SetLoadingComplete = setLoadingComplete
	GameRemotes.CastMapVote = castMapVote
	GameRemotes.RequestMapVoteState = requestMapVoteState
	GameRemotes.DebugMapVote = debugMapVote
else
	local remotesFolder = ReplicatedStorage:WaitForChild("GameRemotes")

	updateUi = remotesFolder:WaitForChild("UpdateUI")

	GameRemotes.SetLoadingComplete = remotesFolder:WaitForChild("SetLoadingComplete")
	GameRemotes.CastMapVote = remotesFolder:WaitForChild("CastMapVote")
	GameRemotes.RequestMapVoteState = remotesFolder:WaitForChild("RequestMapVoteState")
	GameRemotes.DebugMapVote = remotesFolder:WaitForChild("DebugMapVote")
end

function GameRemotes.fireAll(event: string, ...: any)
	for _, player in Players:GetPlayers() do
		updateUi:FireClient(player, event, ...)
	end
end

function GameRemotes.fireTo(player: Player, event: string, ...: any)
	updateUi:FireClient(player, event, ...)
end

return GameRemotes
