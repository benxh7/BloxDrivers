-- Ubicación en Studio: StarterPlayer > StarterPlayerScripts > Controllers > VotingMapController (ModuleScript)
--
-- Votación de mapa (cliente). Pareja de MapVoteService: consume sus eventos por el bus
-- UpdateUI y vota con el remote CastMapVote. Muestra un panel vertical con una card por
-- mapa (caen una tras otra), el contador, las fotitos de los votantes y el cierre con
-- el ganador.
--
-- Es un POPUP manejado por el servidor (DisplayOrder 20), no una ventana: NO se registra
-- en UIManager. Al abrirse cierra la ventana que el jugador tuviera abierta.
--
-- Armado en Studio (lo visual NO lo trae Argon):
--   StarterGui > VotingMapGui (ScreenGui)
--     └ Main (Frame, Visible = false)
--         ├ Cards (Frame, con un UIListLayout adentro)
--         └ TimeLabel (TextLabel, color base NO blanco o el pulso no se ve)
--   ReplicatedStorage > UITemplates > MapCard (Frame)
--     con MapImage (ImageLabel/ImageButton), MapNameLabel y VotesCountLabel en cualquier nivel.
--
-- Todo el movimiento va en Scale del contenedor `Cards` y las distancias se derivan del
-- tamaño REAL de las cards y de la pantalla: se ve igual en PC, celular y tablet.
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

-- ─── Ajustes ────────────────────────────────────────────────────────────────────

-- Fondo de una card cuyo mapa no trae imagen.
local FALLBACK_IMAGE_COLOR = Color3.fromRGB(38, 41, 50)
-- El panel se esconde justo cuando el ganador terminó de salir de pantalla.
local HIDE_DELAY_AFTER_END = VotingMapConfig.celebrationDuration()

-- Entrada: cada card cae desde DropDistance ALTOS DE CARD por encima de su lugar, con
-- Back Out (se pasa un poco y vuelve = el "boing"), una tras otra cada DropStagger seg.
-- Salen del config COMPARTIDO: el servidor retrasa el conteo esta misma duración.
local DROP_DISTANCE = VotingMapConfig.DropDistance
local DROP_DURATION = VotingMapConfig.DropDuration
local DROP_STAGGER = VotingMapConfig.DropStagger
-- Mismo asset que UBG a pedido.
local DROP_SOUND_ID = "rbxassetid://127438224839678"
local DROP_SOUND_VOLUME = 0.5

-- Hover / voto: la card crece un poco y se balancea rotando sobre su centro. La
-- intensidad sube/baja con easing exponencial. WOBBLE_SPEED alto se lee como temblor.
local HOVER_SCALE = 1.06
local WOBBLE_DEGREES = 2.5
local WOBBLE_SPEED = 4
local WOBBLE_EASE = 14

-- Fotitos de los votantes: tamaño en Scale del ALTO de la imagen del mapa (cuadradas).
local AVATAR_SIZE = 0.2
local AVATAR_RING_COLOR = Color3.fromRGB(255, 255, 255)
local AVATAR_RING_THICKNESS = 2

-- Pulso del TimeLabel en cada segundo: onda blanca en el color + un pop que se asienta.
local TIME_PULSE_WHITE = Color3.fromRGB(255, 255, 255)
local TIME_PULSE_BACK = 0.28
local TIME_POP_SCALE = 1.25
local TIME_POP_DURATION = 0.35
-- Tic-tac del reloj, una vez por segundo. Mismo asset que UBG.
local TIME_TICK_SOUND_ID = "rbxassetid://2111554497"
local TIME_TICK_SOUND_VOLUME = 1.0
-- Cuánto se muestra "0s left" antes de esconder el contador y revelar al ganador.
local TIME_ZERO_HOLD = VotingMapConfig.ZeroHold

-- Cierre: los perdedores hacen el INVERSO de la caída y salen por arriba; el ganador
-- espera, baja un poco (WINNER_DROP_DISTANCE altos de card), crece con un sonido y se
-- va con el mismo boing.
local WINNER_SCALE = 1.35
local WINNER_GROW_DURATION = VotingMapConfig.WinnerGrowDuration
local WINNER_DELAY = VotingMapConfig.WinnerDelay
local WINNER_DROP_DISTANCE = 0.5
local WINNER_MOVE_DURATION = VotingMapConfig.WinnerMoveDuration
local WINNER_HOLD = VotingMapConfig.WinnerHold
local WINNER_EXIT_DURATION = VotingMapConfig.WinnerExitDuration
local LOSER_EXIT_DURATION = 0.55
-- Mismo asset que UBG.
local WINNER_SOUND_ID = "rbxassetid://124793974135748"
local WINNER_SOUND_VOLUME = 0.5

-- Debug (mock local): mapas de respaldo, votantes falsos por posición y duración.
local MOCK_MAPS = {
	{ Id = "DebugTrackA", Name = "Track A", Image = "" },
	{ Id = "DebugTrackB", Name = "Track B [NEW!]", Image = "" },
	{ Id = "DebugTrackC", Name = "Track C", Image = "" },
}
local MOCK_FAKE_VOTER_SEED = { { 1, 156 }, { 261 }, { 2, 3 } }
local MOCK_DURATION = 15

-- ─── Estado ─────────────────────────────────────────────────────────────────────

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

-- Referencias de la GUI (se llenan en Init; `ready` = todo encontrado).
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
-- Último catálogo real recibido (lo usa el mock para mostrar mapas/imágenes reales).
local lastCatalog: { MapEntry }? = nil

-- Generación para que el ocultado diferido de una votación no tape la siguiente.
local activityGeneration = 0
-- Se prende cuando todas las cards terminaron de entrar; hasta entonces el contador
-- NO baja (queda congelado en el valor inicial).
local mapsReady = false
local lastShownSeconds: number? = nil
local wobbleConnection: RBXScriptConnection? = nil

-- Mock local (Studio): una votación de mentira que NO toca el servidor.
local mockMode = false
local mockCatalog: { MapEntry } = MOCK_MAPS
local mockFakeVoters: VoteState = {}
local mockVoted: string? = nil
local mockThread: thread? = nil
-- Se asigna en la sección del mock (más abajo): el click de las cards la necesita antes.
local repaintMock: () -> ()

-- ─── Helpers de Scale ───────────────────────────────────────────────────────────

-- Píxeles verticales -> Scale del contenedor Cards (todas las posiciones van ahí).
local function toHolderScaleY(pixels: number): number
	return pixels / math.max(cardsHolder.AbsoluteSize.Y, 1)
end

-- `amount` altos de la card, expresado en Scale del contenedor.
local function cardHeights(frame: GuiObject, amount: number): UDim2
	return UDim2.fromScale(0, toHolderScaleY(frame.AbsoluteSize.Y * amount))
end

-- Distancia hacia arriba para que la card salga ENTERA de la pantalla, sea cual sea la
-- resolución: su borde superior + su alto + la barra superior de Roblox.
local function offscreenDistance(frame: GuiObject): UDim2
	local topInset = GuiService:GetGuiInset().Y
	local pixels = frame.AbsolutePosition.Y + frame.AbsoluteSize.Y * 2 + topInset
	return UDim2.fromScale(0, toHolderScaleY(pixels))
end

-- ─── Fotitos ────────────────────────────────────────────────────────────────────

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
		-- RelativeYY: ancho y alto salen del ALTO de la imagen -> siempre cuadrada.
		avatar.SizeConstraint = Enum.SizeConstraint.RelativeYY
		avatar.Size = UDim2.fromScale(AVATAR_SIZE, AVATAR_SIZE)
		avatar.AnchorPoint = Vector2.new(0.5, 0.5)
		avatar.Position = UDim2.fromScale(pos.X, pos.Y)
		avatar.BackgroundTransparency = 1
		-- Por encima del MapImage (con ZIndexBehavior Global la taparía).
		avatar.ZIndex = image.ZIndex + 1
		-- No debe interceptar el click (el ClickCatcher va por encima).
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

-- ─── Cards ──────────────────────────────────────────────────────────────────────

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
		-- Solo se manda el Id: el servidor valida que la votación esté abierta y que el
		-- mapa sea una de las opciones mostradas.
		Remotes.event("CastMapVote"):FireServer(mapId)
	end
end

local function buildCards(catalog: { MapEntry }?)
	if not (ready and catalog) then
		return
	end
	lastCatalog = catalog
	clearCards()

	-- El reveal saca el layout para congelar posiciones; acá vuelve (votación nueva).
	if layout then
		layout.Parent = cardsHolder
	end

	for index, map in catalog do
		local card = template:Clone()
		card.Name = map.Id
		card.LayoutOrder = index
		-- AnchorPoint 0,0 para que el UIListLayout lo apile bien; el reveal lo pasa a
		-- 0.5,0.5 para que el balanceo rote sobre su centro.
		card.AnchorPoint = Vector2.zero
		card.Rotation = 0
		card.Visible = true
		card.Parent = cardsHolder

		-- Recursivo: los encuentra aunque estén anidados en un sub-frame de la card.
		local nameLabel = card:FindFirstChild("MapNameLabel", true) :: TextLabel?
		local votesLabel = card:FindFirstChild("VotesCountLabel", true) :: TextLabel?
		local mapImage = card:FindFirstChild("MapImage", true) :: ImageLabel?
		if nameLabel then
			nameLabel.Text = map.Name
		end
		if mapImage then
			-- Crop mantiene la proporción y recorta CENTRADO.
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

		-- Botón transparente por encima: capta el click y el hover de TODA la card sin
		-- que los hijos (imagen, labels, fotitos) lo intercepten. Activated = PC y celular.
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

-- Congela las posiciones que dio el layout (en Scale, centradas) y lo saca, para poder
-- tweenear la caída y el balanceo sin que el layout las pise.
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

-- Caída escalonada con overshoot. Corre en su propia corrutina (espera al layout).
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

	-- Cuando aterriza la última: el contador puede empezar a bajar.
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

-- ─── Contador ───────────────────────────────────────────────────────────────────

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
	-- Hasta que estén todas las cards en pantalla el tiempo no baja: se muestra el valor
	-- inicial (primera llamada) y se ignoran los ticks siguientes.
	if not mapsReady and lastShownSeconds ~= nil then
		return
	end
	local whole = math.max(math.floor(seconds), 0)
	timeLabel.Text = ("%ds left"):format(whole)
	if whole ~= lastShownSeconds then
		-- El valor inicial NO pulsa: no es un tic.
		local isFirstValue = lastShownSeconds == nil
		lastShownSeconds = whole
		if not isFirstValue then
			-- El 0 pulsa MUDO: el clip de tic-tac seguiría sonando encima del ganador.
			pulseTimeLabel(whole > 0)
		end
	end
end

-- ─── Panel ──────────────────────────────────────────────────────────────────────

-- Balanceo de las cards con hover o voto: un solo Heartbeat para todas, conectado
-- SOLO mientras el panel está visible. Las cards `done` (cierre) quedan afuera.
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

-- Revela el panel (una vez) e invalida cualquier ocultado pendiente.
local function showPanel()
	activityGeneration += 1
	if main.Visible then
		return
	end
	-- La votación manda: se cierra la ventana que el jugador tuviera abierta.
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

-- Back In es el boing entero en un solo tween: se hunde un poco y sale disparada
-- hacia arriba hasta quedar fuera de pantalla.
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

-- Cierre: los perdedores salen con el INVERSO de la caída. El ganador espera a que
-- suban, baja a un lugar FIJO (debajo de la última card), crece con el sonido y se va.
-- `done` saca a las cards del balanceo para que el Heartbeat no pise estos tweens.
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

-- Al terminar: el contador llega a "0s left", se muestra un instante y se esconde; ahí
-- se revela al ganador.
local function finishVote(winnerId: string?)
	setTime(0)
	-- Corta el tic-tac que arrancó en el último segundo y todavía suena.
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

-- ─── Eventos del servidor ───────────────────────────────────────────────────────

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
	-- Mientras corre el mock, lo que manda el servidor se ignora (no se mezclan).
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
	-- Los ticks llegan a todos cada segundo: también revelan el panel a quien entró a mitad.
	Remotes.onUpdate(
		"mapVoteTick",
		unlessMock(function(timeLeft: number?)
			setTime(timeLeft)
			showPanel()
		end)
	)
	Remotes.onUpdate("mapVoteEnd", unlessMock(onVoteEnd))
end

-- ─── Mock local (solo Studio) ───────────────────────────────────────────────────

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

-- Corre una votación de MENTIRA 100% local: arma las cards, revela, cuenta y deja
-- votar, sin disparar ningún remote. La usa el ícono de debug de TopbarController.
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

	-- Mapas REALES (nombres + imágenes) si ya llegó el catálogo; si no, los de respaldo.
	mockCatalog = lastCatalog or MOCK_MAPS
	mockFakeVoters = {}
	for index, map in mockCatalog do
		mockFakeVoters[map.Id] = MOCK_FAKE_VOTER_SEED[index] or {}
	end

	buildCards(mockCatalog)
	paintState(mockState())
	-- Forzar el reveal aunque el panel viniera visible de una corrida anterior.
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
		-- Ganador: tu voto, o el mapa del medio.
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

-- ─── Init ───────────────────────────────────────────────────────────────────────

-- Resuelve todo lo armado en Studio. false (con warn) si falta algo obligatorio.
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

	-- UIScale propio para el pop del contador (no toca Size) y color base para la onda.
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

	-- Catch-up si entramos con una votación ya abierta (nos perdimos el fireAll inicial).
	Remotes.event("RequestMapVoteState"):FireServer()
end

return VotingMapController
