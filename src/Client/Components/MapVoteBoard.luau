-- Ubicación en Studio: StarterPlayer > StarterPlayerScripts > Components > MapVoteBoard (ModuleScript)
-- Segunda vista reutilizable de la votación (cards en fila), sin uso todavía. Ej.: un
-- tablero de solo lectura en el lobby con `interactive = false`.
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Utils = script.Parent.Parent:WaitForChild("Utils")
local UIEffects = require(Utils:WaitForChild("UIEffects"))
local VoterAvatars = require(Utils:WaitForChild("VoterAvatars"))
local Remotes = require(ReplicatedStorage:WaitForChild("Remotes"))

local MapVoteBoard = {}
MapVoteBoard.__index = MapVoteBoard

-- Voto propio o ganador.
local VOTED_GOLD = Color3.fromRGB(255, 200, 45)
-- Fondo del mapa sin imagen.
local FALLBACK_COLOR = Color3.fromRGB(38, 41, 50)
-- Fracción del ALTO de la imagen (cuadradas por RelativeYY).
local AVATAR_SIZE = 0.25

local WINNER_MOVE_DURATION = 0.45
local LOSER_FADE_DURATION = 0.25

type MapEntry = { Id: string, Name: string, Image: string }

function MapVoteBoard.new(config: {
	cardsFrame: GuiObject,
	layout: UIListLayout,
	template: GuiObject,
	interactive: boolean?,
})
	local self = setmetatable({}, MapVoteBoard)
	self.cardsFrame = config.cardsFrame
	self.layout = config.layout
	self.template = config.template
	self.interactive = config.interactive == true
	self.cards = {}
	self.cardFrames = {}
	return self
end

-- En Scale y descontando el padding: sigue valiendo si cambia la resolución.
function MapVoteBoard:relayout()
	local count = #self.cardFrames
	if count == 0 then
		return
	end
	local frameWidth = math.max(self.cardsFrame.AbsoluteSize.X, 1)
	local pad = self.layout.Padding
	local paddingScale = pad.Scale + pad.Offset / frameWidth
	local cardWidth = (1 - paddingScale * (count - 1)) / count
	for _, card in self.cardFrames do
		card.Size = UDim2.new(cardWidth, 0, card.Size.Y.Scale, card.Size.Y.Offset)
	end
end

function MapVoteBoard:build(list: { MapEntry })
	for _, card in self.cardFrames do
		card:Destroy()
	end
	table.clear(self.cardFrames)
	table.clear(self.cards)

	-- El reveal saca el layout para mover una card sola; acá vuelve a su lugar.
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
				-- Sin popButton: agrandaría la card entera con las fotitos.
				UIEffects.playClickSound()
				Remotes.event("CastMapVote"):FireServer(map.Id)
			end)
		else
			image.Active = false
			image.AutoButtonColor = false
		end
	end

	self:relayout()
end

-- Con la votación cerrada, el GANADOR queda dorado aunque no lo hayas votado.
function MapVoteBoard:paint(state: { [string]: { number } }?, winnerMapId: string?, localUserId: number)
	if not state then
		return
	end
	local mapIds = {}
	for mapId in self.cards do
		table.insert(mapIds, mapId)
	end
	VoterAvatars.updatePositions(mapIds, state)

	for mapId, entry in self.cards do
		local voters = state[mapId] or {}
		entry.votes.Text = ("Votes: %d"):format(#voters)

		local highlighted = winnerMapId == mapId
			or (winnerMapId == nil and table.find(voters, localUserId) ~= nil)
		entry.name.TextColor3 = if highlighted then VOTED_GOLD else entry.nameDefault
		entry.votes.TextColor3 = if highlighted then VOTED_GOLD else entry.voteDefault
		if entry.margin then
			entry.margin.Color = if highlighted then VOTED_GOLD else entry.marginDefault
		end

		for _, child in entry.image:GetChildren() do
			if child:IsA("ImageLabel") then
				child:Destroy()
			end
		end
		for _, userId in voters do
			local pos = VoterAvatars.getPosition(mapId, userId)
			local avatar = Instance.new("ImageLabel")
			avatar.Name = tostring(userId)
			avatar.SizeConstraint = Enum.SizeConstraint.RelativeYY
			avatar.Size = UDim2.fromScale(AVATAR_SIZE, AVATAR_SIZE)
			avatar.AnchorPoint = Vector2.new(0.5, 0.5)
			avatar.Position = UDim2.fromScale(pos.X, pos.Y)
			avatar.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
			avatar.BackgroundTransparency = 0.4
			-- No intercepta el click del ImageButton.
			avatar.Active = false

			local avatarCorner = Instance.new("UICorner")
			avatarCorner.CornerRadius = UDim.new(1, 0)
			avatarCorner.Parent = avatar

			avatar.Parent = entry.image
			VoterAvatars.applyThumbnail(avatar, userId)
		end
	end
end

-- El UIListLayout mueve a TODOS sus hijos: se congelan las posiciones y se desparenta
-- (no se destruye: es el de Studio, y `build` lo devuelve).
function MapVoteBoard:reveal(mapId: string)
	local winnerCard: GuiObject? = nil
	local framePosition = self.cardsFrame.AbsolutePosition
	local frameSize = self.cardsFrame.AbsoluteSize
	local width = math.max(frameSize.X, 1)
	local height = math.max(frameSize.Y, 1)

	for _, card in self.cardFrames do
		local relative = card.AbsolutePosition - framePosition
		card.Position = UDim2.fromScale(
			(relative.X + card.AbsoluteSize.X * card.AnchorPoint.X) / width,
			(relative.Y + card.AbsoluteSize.Y * card.AnchorPoint.Y) / height
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
					Position = UDim2.fromScale(
						0.5 + (card.AbsoluteSize.X / width) * (card.AnchorPoint.X - 0.5),
						0.5 + (card.AbsoluteSize.Y / height) * (card.AnchorPoint.Y - 0.5)
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
				scale :: UIScale,
				TweenInfo.new(LOSER_FADE_DURATION, Enum.EasingStyle.Back, Enum.EasingDirection.In),
				{ Scale = 0 }
			)
			shrink.Completed:Once(function()
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
