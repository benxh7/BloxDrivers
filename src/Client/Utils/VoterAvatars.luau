-- Ubicación en Studio: StarterPlayer > StarterPlayerScripts > Utils > VoterAvatars (ModuleScript)
-- Fotitos de votantes, compartidas por todas las vistas de la votación: mismo lugar en
-- todas y una sola llamada web por thumbnail.
local Players = game:GetService("Players")

local VoterAvatars = {}

-- Separación mínima entre fotitos y zona permitida, en Scale de la imagen.
VoterAvatars.MinDistance = 0.22
VoterAvatars.PlaceTries = 25
VoterAvatars.MinX, VoterAvatars.MaxX = 0.15, 0.85
VoterAvatars.MinY, VoterAvatars.MaxY = 0.2, 0.8

local thumbCache: { [number]: string } = {}
-- mapId -> userId -> posición. Se recuerda: quien no cambió el voto no salta de lugar.
local placed: { [string]: { [number]: Vector2 } } = {}
local rng = Random.new()

function VoterAvatars.applyThumbnail(image: ImageLabel, userId: number)
	local cached = thumbCache[userId]
	if cached then
		image.Image = cached
		return
	end
	task.spawn(function()
		local ok, content = pcall(
			Players.GetUserThumbnailAsync,
			Players,
			userId,
			Enum.ThumbnailType.HeadShot,
			Enum.ThumbnailSize.Size48x48
		)
		if ok and content then
			thumbCache[userId] = content
			if image.Parent then
				image.Image = content
			end
		end
	end)
end

-- Si no hay lugar libre, devuelve el que menos se pisa.
local function pickFreeSpot(taken: { [number]: Vector2 }): Vector2
	local best = Vector2.new(0.5, 0.5)
	local bestDist = -1
	for _ = 1, VoterAvatars.PlaceTries do
		local candidate = Vector2.new(
			rng:NextNumber(VoterAvatars.MinX, VoterAvatars.MaxX),
			rng:NextNumber(VoterAvatars.MinY, VoterAvatars.MaxY)
		)
		local minDist = math.huge
		for _, pos in taken do
			minDist = math.min(minDist, (candidate - pos).Magnitude)
		end
		if minDist >= VoterAvatars.MinDistance then
			return candidate
		end
		if minDist > bestDist then
			bestDist = minDist
			best = candidate
		end
	end
	return best
end

-- Llamar UNA vez por estado, no por vista.
function VoterAvatars.updatePositions(mapIds: { string }, state: { [string]: { number } })
	for _, mapId in mapIds do
		local voters = state[mapId] or {}
		local taken = placed[mapId] or {}
		placed[mapId] = taken
		for userId in taken do
			if not table.find(voters, userId) then
				taken[userId] = nil
			end
		end
		for _, userId in voters do
			if not taken[userId] then
				taken[userId] = pickFreeSpot(taken)
			end
		end
	end
end

function VoterAvatars.getPosition(mapId: string, userId: number): Vector2
	local byMap = placed[mapId]
	return byMap and byMap[userId] or Vector2.new(0.5, 0.5)
end

return VoterAvatars
