-- Ubicación en Studio: StarterPlayer > StarterPlayerScripts > Controllers > VotingMapController (ModuleScript)
-- Panel de votación de mapa. Popup del servidor: NO se registra en UIManager.
-- Movimiento en Scale de `Cards`, derivado del tamaño real de las cards y la pantalla.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UIManager = require(script.Parent:WaitForChild("UIManager"))
local Utils = script.Parent.Parent:WaitForChild("Utils")
local UIEffects = require(Utils:WaitForChild("UIEffects"))
local UITemplates = require(Utils:WaitForChild("UITemplates"))
local VoterAvatars = require(Utils:WaitForChild("VoterAvatars"))
local Remotes = require(ReplicatedStorage:WaitForChild("Remotes"))
local DebugConfig = require(ReplicatedStorage:WaitForChild("DebugConfig"))
local VotingMapConfig = require(ReplicatedStorage:WaitForChild("VotingMapConfig"))

local VotingMapController = {}

local GUI_NAME = "VotingMapGui"
local CARD_TEMPLATE = "MapCard"
local LOG_TAG = "VotingMapController"

-- Fondo de una card sin imagen.
local FALLBACK_IMAGE_COLOR = Color3.fromRGB(38, 41, 50)
local HIDE_DELAY_AFTER_END = VotingMapConfig.celebrationDuration()

-- Del config compartido: el servidor retrasa el conteo esta misma duración.
local DROP_DISTANCE = VotingMapConfig.DropDistance
local DROP_DURATION = VotingMapConfig.DropDuration
local DROP_STAGGER = VotingMapConfig.DropStagger
-- Asset de UBG.
local DROP_SOUND_ID = "rbxassetid://127438224839678"
local DROP_SOUND_VOLUME = 0.5

-- Balanceo con hover o voto. WOBBLE_SPEED alto se lee como temblor.
local HOVER_SCALE = 1.06
local WOBBLE_DEGREES = 2.5
local WOBBLE_SPEED = 4
local WOBBLE_EASE = 14

-- Fotitos: fracción del ALTO de la imagen del mapa (cuadradas).
local AVATAR_SIZE = 0.2
local AVATAR_RING_COLOR = Color3.fromRGB(255, 255, 255)
local AVATAR_RING_THICKNESS = 2

-- Pulso del TimeLabel en cada segundo.
local TIME_PULSE_WHITE = Color3.fromRGB(255, 255, 255)
local TIME_PULSE_BACK = 0.28
local TIME_POP_SCALE = 1.25
local TIME_POP_DURATION = 0.35
-- Tic-tac del reloj (asset de UBG).
local TIME_TICK_SOUND_ID = "rbxassetid://2111554497"
local TIME_TICK_SOUND_VOLUME = 1.0
-- Segundos que se muestra "0s left" antes de revelar al ganador.
local TIME_ZERO_HOLD = VotingMapConfig.ZeroHold

-- Cierre del ganador. WINNER_DROP_DISTANCE en altos de card.
local WINNER_SCALE = 1.35
local WINNER_GROW_DURATION = VotingMapConfig.WinnerGrowDuration
local WINNER_DELAY = VotingMapConfig.WinnerDelay
local WINNER_DROP_DISTANCE = 0.5
local WINNER_MOVE_DURATION = VotingMapConfig.WinnerMoveDuration
local WINNER_HOLD = VotingMapConfig.WinnerHold
local WINNER_EXIT_DURATION = VotingMapConfig.WinnerExitDuration
local LOSER_EXIT_DURATION = 0.55
-- Asset de UBG.
local WINNER_SOUND_ID = "rbxassetid://124793974135748"
local WINNER_SOUND_VOLUME = 0.5

-- Mock de debug: mapas de respaldo, votantes falsos y duración.
local MOCK_MAPS = {
	{ Id = "DebugTrackA", Name = "Track A", Image = "" },
	{ Id = "DebugTrackB", Name = "Track B [NEW!]", Image = "" },
	{ Id = "DebugTrackC", Name = "Track C", Image = "" },
}
local MOCK_FAKE_VOTER_SEED = { { 1, 156 }, { 261 }, { 2, 3 } }
local MOCK_DURATION = 15

type MapEntry = { Id: string, Name: string, Image: string }
type VoteState = { [string]: { number } }

type Card = {
	frame: GuiObject,
	votes: TextLabel?,
	image: ImageLabel?,
	scale: UIScale,
	hovered: boolean,
	voted: boolean,
	done: boolean,
	wobbleIntensity: number,
	wobblePhase: number,
	restPosition: UDim2,
}

local localUserId = Players.LocalPlayer.UserId
local rng = Random.new()

-- `ready` = se encontró todo lo armado en Studio.
local ready = false
local main: GuiObject
local cardsHolder: GuiObject
local timeLabel: TextLabel?
local timeScale: UIScale?
local timeDefaultColor = TIME_PULSE_WHITE
local layout: UIListLayout?
local template: GuiObject

local dropSound: Sound?
local tickSound: Sound?
local winnerSound: Sound?

local cards: { [string]: Card } = {}
local orderedCards: { Card } = {}
-- Último catálogo real: el mock lo usa para mostrar mapas reales.
local lastCatalog: { MapEntry }? = nil

-- El ocultado diferido de una votación no debe tapar la siguiente.
local activityGeneration = 0
-- Hasta que entran todas las cards el contador NO baja.
local mapsReady = false
local lastShownSeconds: number? = nil
local wobbleConnection: RBXScriptConnection? = nil

local mockMode = false
local mockCatalog: { MapEntry } = MOCK_MAPS
local mockFakeVoters: VoteState = {}
local mockVoted: string? = nil
local mockThread: thread? = nil
-- Se asigna más abajo, pero el click de las cards la necesita antes.
local repaintMock: () -> ()

local function toHolderScaleY(pixels: number): number
	return pixels / math.max(cardsHolder.AbsoluteSize.Y, 1)
end

local function cardHeights(frame: GuiObject, amount: number): UDim2
	return UDim2.fromScale(0, toHolderScaleY(frame.AbsoluteSize.Y * amount))
end

-- Hasta salir ENTERA de pantalla: borde superior + alto + la barra superior de Roblox.
local function offscreenDistance(frame: GuiObject): UDim2
	local topInset = GuiService:GetGuiInset().Y
	local pixels = frame.AbsolutePosition.Y + frame.AbsoluteSize.Y * 2 + topInset
	return UDim2.fromScale(0, toHolderScaleY(pixels))
end

local function renderAvatars(card: Card, mapId: string, voters: { number })
	local image = card.image
	if not image then
		return
	end
	for _, child in image:GetChildren() do
		if child:GetAttribute("IsAvatar") then
			child:Destroy()
		end
	end
	for _, userId in voters do
		local pos = VoterAvatars.getPosition(mapId, userId)
		local avatar = Instance.new("ImageLabel")
		avatar:SetAttribute("IsAvatar", true)
		avatar.SizeConstraint = Enum.SizeConstraint.RelativeYY
		avatar.Size = UDim2.fromScale(AVATAR_SIZE, AVATAR_SIZE)
		avatar.AnchorPoint = Vector2.new(0.5, 0.5)
		avatar.Position = UDim2.fromScale(pos.X, pos.Y)
		avatar.BackgroundTransparency = 1
		-- Con ZIndexBehavior Global, el MapImage la taparía.
		avatar.ZIndex = image.ZIndex + 1
		-- No intercepta el click (el ClickCatcher va por encima).
		avatar.Active = false

		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(1, 0)
		corner.Parent = avatar

		local ring = Instance.new("UIStroke")
		ring.Color = AVATAR_RING_COLOR
		ring.Thickness = AVATAR_RING_THICKNESS
		ring.Parent = avatar

		avatar.Parent = image
		VoterAvatars.applyThumbnail(avatar, userId)
	end
end

local function clearCards()
	for _, card in cards do
		card.frame:Destroy()
	end
	table.clear(cards)
	table.clear(orderedCards)
end

local function onCardActivated(mapId: string)
	UIEffects.playClickSound()
	if mockMode then
		mockVoted = if mockVoted == mapId then nil else mapId
		repaintMock()
	else
		-- Solo el Id: el servidor valida votación abierta y opción mostrada.
		Remotes.event("CastMapVote"):FireServer(mapId)
	end
end

local function buildCards(catalog: { MapEntry }?)
	if not (ready and catalog) then
		return
	end
	lastCatalog = catalog
	clearCards()

	-- El reveal saca el layout; acá vuelve para una votación nueva.
	if layout then
		layout.Parent = cardsHolder
	end

	for index, map in catalog do
		local card = template:Clone()
		card.Name = map.Id
		card.LayoutOrder = index
		-- 0,0 para que el UIListLayout apile bien; el reveal pasa a 0.5 (rota sobre su centro).
		card.AnchorPoint = Vector2.zero
		card.Rotation = 0
		card.Visible = true
		card.Parent = cardsHolder

		local nameLabel = card:FindFirstChild("MapNameLabel", true) :: TextLabel?
		local votesLabel = card:FindFirstChild("VotesCountLabel", true) :: TextLabel?
		local mapImage = card:FindFirstChild("MapImage", true) :: ImageLabel?
		if nameLabel then
			nameLabel.Text = map.Name
		end
		if mapImage then
			mapImage.ScaleType = Enum.ScaleType.Crop
			mapImage.Image = map.Image
			if map.Image == "" then
				mapImage.BackgroundColor3 = FALLBACK_IMAGE_COLOR
			end
		end

		local scale = card:FindFirstChildOfClass("UIScale") or Instance.new("UIScale")
		scale.Scale = 1
		scale.Parent = card

		local entry: Card = {
			frame = card,
			votes = votesLabel,
			image = mapImage,
			scale = scale,
			hovered = false,
			voted = false,
			done = false,
			wobbleIntensity = 0,
			wobblePhase = rng:NextNumber(0, math.pi * 2),
			restPosition = card.Position,
		}
		cards[map.Id] = entry
		table.insert(orderedCards, entry)

		-- Botón transparente encima: capta click y hover de TODA la card sin que los hijos
		-- lo intercepten.
		local catcher = Instance.new("TextButton")
		catcher.Name = "ClickCatcher"
		catcher.Size = UDim2.fromScale(1, 1)
		catcher.BackgroundTransparency = 1
		catcher.Text = ""
		catcher.AutoButtonColor = false
		catcher.ZIndex = 50
		catcher.Parent = card

		catcher.Activated:Connect(function()
			onCardActivated(map.Id)
		end)
		catcher.MouseEnter:Connect(function()
			entry.hovered = true
		end)
		catcher.MouseLeave:Connect(function()
			entry.hovered = false
		end)
	end
end

-- Congela las posiciones del layout y lo saca: si no, pisaría los tweens.
local function snapshotAndFreeze()
	if not (layout and layout.Parent) then
		return
	end
	local holderPosition = cardsHolder.AbsolutePosition
	local holderSize = cardsHolder.AbsoluteSize
	for _, card in orderedCards do
		local frame = card.frame
		local center = (frame.AbsolutePosition - holderPosition) + frame.AbsoluteSize / 2
		frame.AnchorPoint = Vector2.new(0.5, 0.5)
		frame.Position = UDim2.fromScale(center.X / math.max(holderSize.X, 1), center.Y / math.max(holderSize.Y, 1))
		card.restPosition = frame.Position
	end
	layout.Parent = nil
end

-- Corre en su propia corrutina (espera al layout).
local function revealCards()
	for _ = 1, 10 do
		local laidOut = cardsHolder.AbsoluteSize.Y > 0
			and orderedCards[1] ~= nil
			and orderedCards[1].frame.AbsoluteSize.Y > 0
		if laidOut then
			break
		end
		task.wait()
	end
	snapshotAndFreeze()

	for index, card in orderedCards do
		local frame = card.frame
		local rest = card.restPosition
		local dropOffset = cardHeights(frame, DROP_DISTANCE)
		frame.Visible = false
		task.delay((index - 1) * DROP_STAGGER, function()
			frame.Position = rest - dropOffset
			frame.Visible = true
			UIEffects.playOneShot(dropSound)
			TweenService:Create(
				frame,
				TweenInfo.new(DROP_DURATION, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
				{ Position = rest }
			):Play()
		end)
	end

	task.delay(VotingMapConfig.entranceDuration(#orderedCards), function()
		mapsReady = true
	end)
end

local function paintState(state: VoteState?)
	if not (ready and state) then
		return
	end
	local mapIds = {}
	for mapId in cards do
		table.insert(mapIds, mapId)
	end
	VoterAvatars.updatePositions(mapIds, state)

	for mapId, card in cards do
		local voters = state[mapId] or {}
		if card.votes then
			card.votes.Text = ("%d votes"):format(#voters)
		end
		card.voted = table.find(voters, localUserId) ~= nil
		renderAvatars(card, mapId, voters)
	end
end

local function pulseTimeLabel(playSound: boolean)
	if not timeLabel then
		return
	end
	if playSound and tickSound then
		tickSound:Play()
	end
	timeLabel.TextColor3 = TIME_PULSE_WHITE
	TweenService:Create(timeLabel, TweenInfo.new(TIME_PULSE_BACK, Enum.EasingStyle.Quad), {
		TextColor3 = timeDefaultColor,
	}):Play()
	if timeScale then
		timeScale.Scale = TIME_POP_SCALE
		TweenService:Create(
			timeScale,
			TweenInfo.new(TIME_POP_DURATION, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
			{ Scale = 1 }
		):Play()
	end
end

local function setTime(seconds: number?)
	if not (timeLabel and typeof(seconds) == "number") then
		return
	end
	-- Hasta que entran todas las cards: valor inicial fijo, se ignoran los ticks.
	if not mapsReady and lastShownSeconds ~= nil then
		return
	end
	local whole = math.max(math.floor(seconds), 0)
	timeLabel.Text = ("%ds left"):format(whole)
	if whole ~= lastShownSeconds then
		local isFirstValue = lastShownSeconds == nil
		lastShownSeconds = whole
		if not isFirstValue then
			-- El 0 pulsa mudo: el tic-tac seguiría sonando encima del ganador.
			pulseTimeLabel(whole > 0)
		end
	end
end

-- Un solo Heartbeat, conectado solo con el panel visible. Las cards `done` quedan afuera.
local function onHeartbeat(dt: number)
	local now = os.clock()
	local ease = 1 - math.exp(-WOBBLE_EASE * dt)
	for _, card in cards do
		if card.done then
			continue
		end
		local target = if card.hovered or card.voted then 1 else 0
		card.wobbleIntensity += (target - card.wobbleIntensity) * ease
		local intensity = card.wobbleIntensity
		card.frame.Rotation = math.sin(now * WOBBLE_SPEED + card.wobblePhase) * WOBBLE_DEGREES * intensity
		card.scale.Scale = 1 + (HOVER_SCALE - 1) * intensity
	end
end

-- Invalida cualquier ocultado pendiente.
local function showPanel()
	activityGeneration += 1
	if main.Visible then
		return
	end
	UIManager.CloseAll()
	main.Visible = true
	if timeLabel then
		timeLabel.Visible = true
	end
	lastShownSeconds = nil
	mapsReady = false
	if not wobbleConnection then
		wobbleConnection = RunService.Heartbeat:Connect(onHeartbeat)
	end
	task.spawn(revealCards)
end

local function hidePanel()
	main.Visible = false
	if wobbleConnection then
		wobbleConnection:Disconnect()
		wobbleConnection = nil
	end
end

-- Back In: se hunde un poco y sale disparada, todo en un solo tween.
local function exitUp(frame: GuiObject, from: UDim2, duration: number)
	local tween = TweenService:Create(
		frame,
		TweenInfo.new(duration, Enum.EasingStyle.Back, Enum.EasingDirection.In),
		{ Position = from - offscreenDistance(frame) }
	)
	tween.Completed:Once(function()
		frame.Visible = false
	end)
	tween:Play()
end

-- `done` saca a las cards del balanceo: si no, el Heartbeat pisaría estos tweens.
local function revealWinner(winnerId: string)
	local lastCard = orderedCards[#orderedCards]
	local winnerTarget = lastCard.restPosition + cardHeights(lastCard.frame, WINNER_DROP_DISTANCE)

	for _, card in orderedCards do
		card.done = true
		card.hovered = false
		card.voted = false
		local frame = card.frame
		frame.Rotation = 0
		card.scale.Scale = 1

		if frame.Name ~= winnerId then
			exitUp(frame, card.restPosition, LOSER_EXIT_DURATION)
			continue
		end

		task.delay(WINNER_DELAY, function()
			local move = TweenService:Create(
				frame,
				TweenInfo.new(WINNER_MOVE_DURATION, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
				{ Position = winnerTarget }
			)
			move.Completed:Once(function()
				if winnerSound then
					winnerSound:Play()
				end
				local grow = TweenService:Create(
					card.scale,
					TweenInfo.new(WINNER_GROW_DURATION, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
					{ Scale = WINNER_SCALE }
				)
				grow.Completed:Once(function()
					task.delay(WINNER_HOLD, exitUp, frame, winnerTarget, WINNER_EXIT_DURATION)
				end)
				grow:Play()
			end)
			move:Play()
		end)
	end
end

local function finishVote(winnerId: string?)
	setTime(0)
	-- Corta el tic-tac del último segundo, que todavía suena.
	if tickSound then
		tickSound:Stop()
	end
	task.delay(TIME_ZERO_HOLD, function()
		if timeLabel then
			timeLabel.Visible = false
		end
		if winnerId and cards[winnerId] then
			revealWinner(winnerId)
		end
	end)
end

local function onVoteEnd(winnerId: string?)
	finishVote(winnerId)
	activityGeneration += 1
	local myGeneration = activityGeneration
	task.delay(HIDE_DELAY_AFTER_END, function()
		if myGeneration == activityGeneration then
			hidePanel()
		end
	end)
end

local function connectServerEvents()
	-- Con el mock corriendo se ignora al servidor: no se mezclan.
	local function unlessMock(handler: (...any) -> ()): (...any) -> ()
		return function(...)
			if not mockMode then
				handler(...)
			end
		end
	end

	Remotes.onUpdate("mapVoteCatalog", unlessMock(buildCards))
	Remotes.onUpdate("mapVoteState", unlessMock(paintState))
	Remotes.onUpdate(
		"mapVoteStart",
		unlessMock(function(duration: number?)
			setTime(duration)
			showPanel()
		end)
	)
	-- También revela el panel a quien entró a mitad de la votación.
	Remotes.onUpdate(
		"mapVoteTick",
		unlessMock(function(timeLeft: number?)
			setTime(timeLeft)
			showPanel()
		end)
	)
	Remotes.onUpdate("mapVoteEnd", unlessMock(onVoteEnd))
end

local function mockState(): VoteState
	local snapshot: VoteState = {}
	for _, map in mockCatalog do
		local voters = table.clone(mockFakeVoters[map.Id] or {})
		if mockVoted == map.Id then
			table.insert(voters, localUserId)
		end
		snapshot[map.Id] = voters
	end
	return snapshot
end

repaintMock = function()
	paintState(mockState())
end

-- Votación de mentira 100% local, sin remotes (ícono de debug de TopbarController).
function VotingMapController.RunMockVote()
	if not DebugConfig.CHEATS_ENABLED then
		return
	end
	if not ready then
		DebugConfig.warn(("[%s] Mock: la GUI no está lista (revisá el armado en Studio)"):format(LOG_TAG))
		return
	end
	if mockThread then
		task.cancel(mockThread)
	end
	mockMode = true
	mockVoted = nil

	mockCatalog = lastCatalog or MOCK_MAPS
	mockFakeVoters = {}
	for index, map in mockCatalog do
		mockFakeVoters[map.Id] = MOCK_FAKE_VOTER_SEED[index] or {}
	end

	buildCards(mockCatalog)
	paintState(mockState())
	-- Reveal forzado aunque el panel siga visible de una corrida anterior.
	main.Visible = false
	showPanel()

	mockThread = task.spawn(function()
		setTime(MOCK_DURATION)
		while not mapsReady do
			task.wait()
		end
		for t = MOCK_DURATION, 1, -1 do
			setTime(t)
			task.wait(1)
		end
		local winnerId = mockVoted
			or (mockCatalog[2] and mockCatalog[2].Id)
			or (mockCatalog[1] and mockCatalog[1].Id)
		finishVote(winnerId)
		task.wait(HIDE_DELAY_AFTER_END)
		hidePanel()
		mockMode = false
		mockThread = nil
	end)
end

local function resolveGui(): boolean
	local gui = UIManager.WaitForGui(GUI_NAME)
	if not gui then
		return false
	end

	local foundMain = UIEffects.findChild(gui, "Main", LOG_TAG)
	if not (foundMain and foundMain:IsA("GuiObject")) then
		return false
	end
	main = foundMain

	local foundHolder = UIEffects.findChild(main, "Cards", LOG_TAG)
	if not (foundHolder and foundHolder:IsA("GuiObject")) then
		return false
	end
	cardsHolder = foundHolder

	local foundTemplate = UITemplates.get(CARD_TEMPLATE)
	if not foundTemplate then
		return false
	end
	template = foundTemplate

	layout = cardsHolder:FindFirstChildOfClass("UIListLayout")
	local foundTime = UIEffects.findChild(main, "TimeLabel", LOG_TAG)
	timeLabel = if foundTime and foundTime:IsA("TextLabel") then foundTime else nil
	return true
end

function VotingMapController.Init()
	if not resolveGui() then
		return
	end
	main.Visible = false

	if timeLabel then
		timeDefaultColor = timeLabel.TextColor3
		local scale = timeLabel:FindFirstChildOfClass("UIScale") or Instance.new("UIScale")
		scale.Parent = timeLabel
		timeScale = scale
	end

	dropSound = UIEffects.makeSound("MapVoteDrop", DROP_SOUND_ID, DROP_SOUND_VOLUME)
	tickSound = UIEffects.makeSound("MapVoteTick", TIME_TICK_SOUND_ID, TIME_TICK_SOUND_VOLUME)
	winnerSound = UIEffects.makeSound("MapVoteWinner", WINNER_SOUND_ID, WINNER_SOUND_VOLUME)

	ready = true
	connectServerEvents()

	-- Por si entramos con una votación ya abierta y nos perdimos el fireAll inicial.
	Remotes.event("RequestMapVoteState"):FireServer()
end

return VotingMapController
