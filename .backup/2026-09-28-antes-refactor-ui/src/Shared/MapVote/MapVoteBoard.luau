local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local UIHelpers = require(ReplicatedStorage.UIHelpers)
local GameRemotes = require(ReplicatedStorage.Remotes.GameRemotes)

-- Motor de UNA vista de la votación, usado por las DOS (panel y holograma de la
-- pared) para no duplicar nada. Client-only.
local MapVoteBoard = {}
MapVoteBoard.__index = MapVoteBoard

local VOTED_GOLD = Color3.fromRGB(255, 200, 45) -- voto propio (o ganador)
local FALLBACK_COLOR = Color3.fromRGB(38, 41, 50) -- fondo del mapa sin imagen
local AVATAR_SIZE = 38 -- px de cada fotito sobre la imagen del mapa
local AVATAR_MIN_DIST = 0.22 -- separación mínima entre fotitos (Scale de la imagen)
local PLACE_TRIES = 25

local WINNER_MOVE_DURATION = 0.45 -- el ganador viaja al centro
local LOSER_FADE_DURATION = 0.25 -- las otras se achican y desaparecen

type MapEntry = { Id: string, Name: string, Image: string }

-- COMPARTIDOS entre vistas: la fotito es una llamada web, y las posiciones tienen
-- que coincidir o cada vista sortearía otro lugar para el mismo votante.
local thumbCache: { [number]: string } = {}
local placed: { [string]: { [number]: Vector2 } } = {}
local rng = Random.new()

local function applyThumbnail(image: ImageLabel, userId: number)
	local cached = thumbCache[userId]
	if cached then
		image.Image = cached
		return
	end
	task.spawn(function()
		local ok, content = pcall(function()
			return Players:GetUserThumbnailAsync(userId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size48x48)
		end)
		if ok and content then
			thumbCache[userId] = content
			if image.Parent then
				image.Image = content
			end
		end
	end)
end

-- Sortea un lugar libre: prueba candidatos y devuelve el primero que no choque con
-- otra fotito; si está lleno, el que MENOS se superponga (chocar recién ahí).
local function pickFreeSpot(taken: { [number]: Vector2 }): Vector2
	local best = Vector2.new(0.5, 0.5)
	local bestDist = -1
	for _ = 1, PLACE_TRIES do
		local candidate = Vector2.new(rng:NextNumber(0.12, 0.88), rng:NextNumber(0.12, 0.88))
		local minDist = math.huge
		for _, pos in taken do
			minDist = math.min(minDist, (candidate - pos).Magnitude)
		end
		if minDist >= AVATAR_MIN_DIST then
			return candidate
		end
		if minDist > bestDist then
			bestDist = minDist
			best = candidate
		end
	end
	return best
end

-- Una vez por estado, no por vista: así las fotitos de quien no cambió el voto no
-- saltan de lugar.
function MapVoteBoard.updatePositions(catalog: { MapEntry }?, state: { [string]: { number } })
	if not catalog then return end
	for _, map in catalog do
		local voters = state[map.Id] or {}
		local taken = placed[map.Id] or {}
		placed[map.Id] = taken
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

-- `cardsFrame` recibe las cards, `layout` es su UIListLayout (se desparenta durante
-- el reveal), `template` es el molde a clonar e `interactive` decide si se puede
-- votar clickeando (la pared es solo de lectura).
function MapVoteBoard.new(config: {
	cardsFrame: GuiObject,
	layout: UIListLayout,
	template: Instance,
	interactive: boolean?,
})
	local self = setmetatable({}, MapVoteBoard)
	self.cardsFrame = config.cardsFrame
	self.layout = config.layout
	self.template = config.template
	self.interactive = config.interactive == true
	self.cards = {}
	self.cardFrames = {}
	self.lastLayoutWidth = -1

	self.cardsFrame:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		self:relayout()
	end)

	return self
end

-- Reparte el ancho real en PÍXELES descontando el padding del UIListLayout. Solo
-- depende del ANCHO: el alto cambia cada frame durante la apertura.
function MapVoteBoard:relayout(force: boolean?)
	local count = #self.cardFrames
	local frameWidth = self.cardsFrame.AbsoluteSize.X
	if frameWidth <= 0 or count == 0 then return end
	if not force and frameWidth == self.lastLayoutWidth then return end
	self.lastLayoutWidth = frameWidth

	local pad = self.layout.Padding
	local paddingPx = pad.Scale * frameWidth + pad.Offset
	local cardWidthPx = math.floor((frameWidth - paddingPx * (count - 1)) / count)
	if cardWidthPx <= 0 then return end
	for _, card in self.cardFrames do
		card.Size = UDim2.new(0, cardWidthPx, card.Size.Y.Scale, card.Size.Y.Offset)
	end
end

function MapVoteBoard:build(list: { MapEntry })
	for _, card in self.cardFrames do
		card:Destroy()
	end
	table.clear(self.cardFrames)
	table.clear(self.cards)

	-- El reveal del ganador saca el layout de juego para mover una card sola; acá
	-- vuelve a su lugar (votación nueva, las cards otra vez en fila).
	self.layout.Parent = self.cardsFrame

	for index, map in list do
		local card = self.template:Clone()
		card.Name = map.Id
		card.LayoutOrder = index
		card.Visible = true
		card.Parent = self.cardsFrame
		table.insert(self.cardFrames, card)

		local image = card:WaitForChild("MapImage") :: ImageButton
		local nameLabel = card:WaitForChild("NameLabel") :: TextLabel
		local voteLabel = card:WaitForChild("VoteLabel") :: TextLabel
		local margin = image:FindFirstChildWhichIsA("UIStroke")

		image.ClipsDescendants = true
		-- `Crop` y no el `Stretch` default: mantiene la proporción y recorta CENTRADO,
		-- así que conviene encuadrar lo importante al medio.
		image.ScaleType = Enum.ScaleType.Crop
		image.Image = map.Image
		if map.Image == "" then
			image.BackgroundColor3 = FALLBACK_COLOR
		end
		nameLabel.Text = map.Name

		self.cards[map.Id] = {
			name = nameLabel,
			votes = voteLabel,
			image = image,
			margin = margin,
			nameDefault = nameLabel.TextColor3,
			voteDefault = voteLabel.TextColor3,
			marginDefault = margin and margin.Color,
		}

		if self.interactive then
			image.Activated:Connect(function()
				-- Sin `popButton` a propósito: el "pop" agrandaba la card entera junto
				-- con las fotitos de los votantes que cuelgan de la imagen.
				UIHelpers.playClickSound()
				GameRemotes.CastMapVote:FireServer(map.Id)
			end)
		else
			-- Vista de solo lectura (la pared): que no se comporte como botón.
			image.Active = false
			image.AutoButtonColor = false
		end
	end

	self:relayout(true)
end

-- Repinta contadores, color del voto propio y fotitos desde el estado dado. Con la
-- votación cerrada, el GANADOR queda dorado (aunque no lo hayas votado).
function MapVoteBoard:paint(state: { [string]: { number } }?, winnerMapId: string?, localUserId: number)
	if not state then return end
	for mapId, entry in self.cards do
		local voters = state[mapId] or {}
		entry.votes.Text = ("Votes: %d"):format(#voters)

		local highlighted = winnerMapId == mapId
			or (winnerMapId == nil and table.find(voters, localUserId) ~= nil)
		entry.name.TextColor3 = highlighted and VOTED_GOLD or entry.nameDefault
		entry.votes.TextColor3 = highlighted and VOTED_GOLD or entry.voteDefault
		if entry.margin then
			entry.margin.Color = highlighted and VOTED_GOLD or entry.marginDefault
		end

		for _, child in entry.image:GetChildren() do
			if child:IsA("ImageLabel") then
				child:Destroy()
			end
		end
		for _, userId in voters do
			local pos = placed[mapId] and placed[mapId][userId] or Vector2.new(0.5, 0.5)
			local avatar = Instance.new("ImageLabel")
			avatar.Name = tostring(userId)
			avatar.Size = UDim2.fromOffset(AVATAR_SIZE, AVATAR_SIZE)
			avatar.AnchorPoint = Vector2.new(0.5, 0.5)
			avatar.Position = UDim2.fromScale(pos.X, pos.Y)
			avatar.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
			avatar.BackgroundTransparency = 0.4
			-- No debe interceptar el click del ImageButton (se vota sobre la fotito igual).
			avatar.Active = false
			avatar.Parent = entry.image

			local avatarCorner = Instance.new("UICorner")
			avatarCorner.CornerRadius = UDim.new(1, 0)
			avatarCorner.Parent = avatar

			applyThumbnail(avatar, userId)
		end
	end
end

-- El UIListLayout posiciona a TODOS sus hijos, así que para mover una card sola hay
-- que congelar la posición de cada una y desparentar el layout. Nunca se destruye:
-- es la instancia de Studio, y `build` lo devuelve a su lugar.
function MapVoteBoard:reveal(mapId: string)
	local winnerCard: GuiObject? = nil
	local frameSize = self.cardsFrame.AbsoluteSize

	for _, card in self.cardFrames do
		local relative = card.AbsolutePosition - self.cardsFrame.AbsolutePosition
		card.Position = UDim2.fromOffset(
			relative.X + card.AbsoluteSize.X * card.AnchorPoint.X,
			relative.Y + card.AbsoluteSize.Y * card.AnchorPoint.Y
		)
		if card.Name == mapId then
			winnerCard = card
		end
	end
	self.layout.Parent = nil

	for _, card in self.cardFrames do
		if card == winnerCard then
			TweenService:Create(
				card,
				TweenInfo.new(WINNER_MOVE_DURATION, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
				{
					Position = UDim2.fromOffset(
						frameSize.X * 0.5 + card.AbsoluteSize.X * (card.AnchorPoint.X - 0.5),
						frameSize.Y * 0.5 + card.AbsoluteSize.Y * (card.AnchorPoint.Y - 0.5)
					),
				}
			):Play()
		else
			local scale = card:FindFirstChild("RevealScale") :: UIScale?
			if not scale then
				scale = Instance.new("UIScale")
				scale.Name = "RevealScale"
				scale.Parent = card
			end

			local shrink = TweenService:Create(
				scale,
				TweenInfo.new(LOSER_FADE_DURATION, Enum.EasingStyle.Back, Enum.EasingDirection.In),
				{ Scale = 0 }
			)
			shrink.Completed:Connect(function()
				card.Visible = false
			end)
			shrink:Play()
		end
	end
end

function MapVoteBoard:hasCard(mapId: string): boolean
	return self.cards[mapId] ~= nil
end

return MapVoteBoard
