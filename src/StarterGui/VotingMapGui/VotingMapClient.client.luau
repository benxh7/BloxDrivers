local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local SoundService = game:GetService("SoundService")
local Debris = game:GetService("Debris")

local GameRemotes = require(ReplicatedStorage.Remotes.GameRemotes)
local UIHelpers = require(ReplicatedStorage:WaitForChild("UIHelpers"))
local DebugConfig = require(ReplicatedStorage:WaitForChild("DebugConfig"))
local VotingMapConfig = require(ReplicatedStorage:WaitForChild("VotingMapConfig"))

-- Votación de mapa: panel vertical con 3 MapCards (una debajo de otra) + contador.
-- Consume los eventos de MapVoteService por UpdateUI y vota con CastMapVote.
--
-- IMPORTANTE: esta GUI se arma en STUDIO, no la trae Argon. `Panel` (con `Cards`
-- adentro conteniendo un `UIListLayout` y el template `MapCard`, más `TimeLabel`)
-- tiene que existir como hijos de este ScreenGui o el script se corta en el
-- primer `findChild` que falle. `MapCard` necesita `MapImage` (ImageButton),
-- `NameLabel`/`MapNameLabel` y `VoteLabel`/`VotesCountLabel` (los dos nombres
-- alternativos son tolerados, `FindFirstChild(..., true)` busca anidado).
local player = Players.LocalPlayer
local localUserId = player.UserId

local remotes = ReplicatedStorage:WaitForChild("GameRemotes")
local updateUI = remotes:WaitForChild("UpdateUI")

local gui = script.Parent :: ScreenGui
gui.Enabled = true

local function findChild(parent: Instance, name: string): Instance?
	return UIHelpers.findChild(parent, name, "VotingMap")
end

-- La GUI se arma en Studio; acá se resuelve tolerante (falta un hijo -> warn, no error).
local panel = findChild(gui, "Panel") :: Frame?
if not panel then return end
-- Las cards viven en su propio contenedor (con el UIListLayout adentro); así el
-- TimeLabel, hermano de Cards, NO entra en el layout.
local cardsHolder = findChild(panel, "Cards") :: GuiObject?
if not cardsHolder then return end
local timeLabel = findChild(panel, "TimeLabel") :: TextLabel?
local template = findChild(cardsHolder, "MapCard") :: Frame?
if not template then return end
local layout = cardsHolder:FindFirstChildOfClass("UIListLayout")

-- El template sale del holder para no ocupar lugar en el UIListLayout: queda de molde.
template.Parent = gui
template.Visible = false
panel.Visible = false

-- Fondo de una card cuyo mapa no trae imagen.
local FALLBACK_IMAGE_COLOR = Color3.fromRGB(38, 41, 50)
-- El panel se esconde justo cuando el ganador terminó de salir de pantalla.
local HIDE_DELAY_AFTER_END = VotingMapConfig.celebrationDuration()

-- Entrada: cada card cae desde DROP_DISTANCE px por encima de su lugar, con Back Out
-- (se pasa un poco de largo y vuelve = el "boing"), una tras otra cada STAGGER seg.
-- Salen del config COMPARTIDO: el server retrasa el conteo esta misma duración.
local DROP_DISTANCE = VotingMapConfig.DropDistance
local DROP_DURATION = VotingMapConfig.DropDuration
local DROP_STAGGER = VotingMapConfig.DropStagger
-- Sonido de cada card al caer. Mismo asset que UBG a pedido.
local DROP_SOUND_ID = "rbxassetid://127438224839678"
local DROP_SOUND_VOLUME = 0.5

-- Hover / voto: la card crece un poco y se balancea rotando sobre su centro (los lados
-- izquierdo/derecho suben y bajan). La intensidad sube/baja con easing exponencial.
-- OJO: WOBBLE_SPEED alto se lee como temblor, no como giro — mantenerlo bajo.
local HOVER_SCALE = 1.06
local WOBBLE_DEGREES = 2.5
local WOBBLE_SPEED = 4
local WOBBLE_EASE = 14

-- Fotitos de los votantes sobre la imagen del mapa.
local AVATAR_SIZE = 25
local AVATAR_MIN_DIST = 0.22 -- separación mínima entre fotitos (Scale de la imagen)
local AVATAR_PLACE_TRIES = 25
local AVATAR_RING_COLOR = Color3.fromRGB(255, 255, 255)
local AVATAR_RING_THICKNESS = 2

-- Pulso del TimeLabel en cada segundo: onda blanca en el color + un pop que se asienta.
-- OJO: el TimeLabel debe tener un color base NO blanco o la onda no se ve.
local TIME_PULSE_WHITE = Color3.fromRGB(255, 255, 255)
local TIME_PULSE_BACK = 0.28 -- cuánto tarda en volver del blanco al color original
local TIME_POP_SCALE = 1.25 -- cuánto crece el "pop"
local TIME_POP_DURATION = 0.35 -- cuánto tarda en asentarse
-- Tic-tac del reloj: suena con el pulso, o sea una vez por segundo. Mismo asset que UBG.
local TIME_TICK_SOUND_ID = "rbxassetid://2111554497"
local TIME_TICK_SOUND_VOLUME = 1.0
-- Cuánto se muestra "0s left" antes de esconder el contador y revelar al ganador.
local TIME_ZERO_HOLD = VotingMapConfig.ZeroHold

-- Cierre: los perdedores hacen el INVERSO de la caída (bajan un poco con Back In y
-- salen por arriba), y el ganador crece con un sonido.
local WINNER_SCALE = 1.35
local WINNER_GROW_DURATION = VotingMapConfig.WinnerGrowDuration
-- El ganador NO crece en su lugar: espera a que suban los perdedores, baja un poco a
-- esa posición y ahí crece con el sonido.
local WINNER_DELAY = VotingMapConfig.WinnerDelay
local WINNER_DROP_DISTANCE = 60 -- cuánto baja el ganador antes de crecer
local WINNER_MOVE_DURATION = VotingMapConfig.WinnerMoveDuration
-- Y se va con el mismo boing que los perdedores (Back In: baja un poquito y sale
-- disparado para arriba), pero desde más abajo, así que necesita más distancia.
local WINNER_HOLD = VotingMapConfig.WinnerHold
local WINNER_EXIT_DISTANCE = 700
local WINNER_EXIT_DURATION = VotingMapConfig.WinnerExitDuration
local LOSER_EXIT_DISTANCE = 450 -- px hacia arriba, suficiente para salir de pantalla
local LOSER_EXIT_DURATION = 0.55
-- Sonido al agrandar al ganador. Mismo asset que UBG.
local WINNER_SOUND_ID = "rbxassetid://124793974135748"
local WINNER_SOUND_VOLUME = 0.5

local function makeSound(name: string, id: string, volume: number): Sound?
	if id == "" or id == "rbxassetid://0" then return nil end
	local sound = Instance.new("Sound")
	sound.Name = name
	sound.SoundId = id
	sound.Volume = volume
	sound.Parent = SoundService
	return sound
end

local dropSound = makeSound("MapVoteDrop", DROP_SOUND_ID, DROP_SOUND_VOLUME)
local tickSound = makeSound("MapVoteTick", TIME_TICK_SOUND_ID, TIME_TICK_SOUND_VOLUME)
local winnerSound = makeSound("MapVoteWinner", WINNER_SOUND_ID, WINNER_SOUND_VOLUME)

-- Cuánto vive el clon antes de que Debris lo borre: subilo si algún clip dura más.
local ONE_SHOT_LIFETIME = 10

-- Sonidos que se pisan entre sí (las cards caen cada DropStagger): un :Play() sobre el
-- MISMO Sound que todavía suena se pierde y esa card queda muda, así que va un clon.
local function playOneShot(sound: Sound?)
	if not sound then return end
	local clone = sound:Clone()
	clone.Parent = SoundService
	clone:Play()
	Debris:AddItem(clone, ONE_SHOT_LIFETIME)
end

type Card = {
	frame: Frame,
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

local cards: { [string]: Card } = {}
local orderedCards: { Card } = {}
-- Último catálogo real recibido (lo usa el debug para mostrar mapas/imágenes reales).
local lastCatalog: { { Id: string, Name: string, Image: string } }? = nil

-- Generación para que el ocultado diferido de una votación no tape la siguiente.
local activityGeneration = 0

-- Se prende cuando los 3 mapas terminaron de entrar. Hasta entonces el contador NO
-- baja (se queda congelado en el valor inicial).
local mapsReady = false

-- Debug local (Studio): una votación de mentira que NO toca el server.
-- mockToggleVote se asigna abajo, en el bloque de debug.
local mockMode = false
local mockToggleVote: ((mapId: string) -> ())? = nil

-- Fotitos: la thumbnail es una llamada web (cache), y las posiciones se recuerdan por
-- votante para que no salten de lugar en cada actualización de estado.
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

-- Primer candidato que no choque con otra fotito; si está lleno, el que menos se pise.
local function pickFreeSpot(taken: { [number]: Vector2 }): Vector2
	local best = Vector2.new(0.5, 0.5)
	local bestDist = -1
	for _ = 1, AVATAR_PLACE_TRIES do
		local candidate = Vector2.new(rng:NextNumber(0.15, 0.85), rng:NextNumber(0.2, 0.8))
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

local function updatePositions(state: { [string]: { number } })
	for mapId in cards do
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

local function renderAvatars(card: Card, mapId: string, voters: { number })
	local image = card.image
	if not image then return end
	for _, child in image:GetChildren() do
		if child:GetAttribute("IsAvatar") then
			child:Destroy()
		end
	end
	for _, userId in voters do
		local pos = placed[mapId] and placed[mapId][userId] or Vector2.new(0.5, 0.5)
		local avatar = Instance.new("ImageLabel")
		avatar:SetAttribute("IsAvatar", true)
		avatar.Size = UDim2.fromOffset(AVATAR_SIZE, AVATAR_SIZE)
		avatar.AnchorPoint = Vector2.new(0.5, 0.5)
		avatar.Position = UDim2.fromScale(pos.X, pos.Y)
		avatar.BackgroundTransparency = 1 -- sin fondo oscuro
		-- Por encima del MapImage: con ZIndexBehavior Global, una fotito con ZIndex más
		-- bajo que la imagen queda tapada por ella.
		avatar.ZIndex = image.ZIndex + 1
		-- No debe interceptar el click (el ClickCatcher va por encima).
		avatar.Active = false
		avatar.Parent = image

		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(1, 0)
		corner.Parent = avatar

		local ring = Instance.new("UIStroke")
		ring.Color = AVATAR_RING_COLOR
		ring.Thickness = AVATAR_RING_THICKNESS
		ring.Parent = avatar

		applyThumbnail(avatar, userId)
	end
end

local function clearCards()
	for _, card in cards do
		card.frame:Destroy()
	end
	table.clear(cards)
	table.clear(orderedCards)
end

local function buildCards(catalog: { { Id: string, Name: string, Image: string } }?)
	if not catalog then return end
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
		-- 0.5,0.5 (centro) para que el balanceo rote sobre su centro.
		card.AnchorPoint = Vector2.new(0, 0)
		card.Visible = true
		card.Parent = cardsHolder

		-- Recursivo (segundo arg true): los encuentra aunque estén anidados en un
		-- sub-frame de la card, no solo como hijos directos.
		local nameLabel = card:FindFirstChild("MapNameLabel", true) :: TextLabel?
		local votesLabel = card:FindFirstChild("VotesCountLabel", true) :: TextLabel?
		local mapImage = card:FindFirstChild("MapImage", true) :: ImageLabel?
		if nameLabel then
			nameLabel.Text = map.Name
		end
		if mapImage then
			-- Crop mantiene la proporción y recorta CENTRADO (encuadrá lo importante al medio).
			mapImage.ScaleType = Enum.ScaleType.Crop
			mapImage.Image = map.Image
			if map.Image == "" then
				mapImage.BackgroundColor3 = FALLBACK_IMAGE_COLOR
			end
		end

		local scale = card:FindFirstChildOfClass("UIScale") or Instance.new("UIScale")
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

		-- Un botón transparente por encima capta el click y el hover de TODA la card,
		-- sin que los hijos (imagen, labels, fotitos) lo intercepten.
		local catcher = Instance.new("TextButton")
		catcher.Name = "ClickCatcher"
		catcher.Size = UDim2.fromScale(1, 1)
		catcher.BackgroundTransparency = 1
		catcher.Text = ""
		catcher.AutoButtonColor = false
		catcher.ZIndex = 50
		catcher.Parent = card

		catcher.Activated:Connect(function()
			UIHelpers.playClickSound()
			if mockMode and mockToggleVote then
				mockToggleVote(map.Id)
			else
				GameRemotes.CastMapVote:FireServer(map.Id)
			end
		end)
		catcher.MouseEnter:Connect(function()
			entry.hovered = true
		end)
		catcher.MouseLeave:Connect(function()
			entry.hovered = false
		end)
	end
end

-- Congela las posiciones que dio el layout (a offset, centradas) y lo saca, para
-- poder tweenear la caída y el balanceo sin que el layout las pise.
local function snapshotAndFreeze()
	if not (layout and layout.Parent) then return end
	for _, card in orderedCards do
		local frame = card.frame
		local center = (frame.AbsolutePosition - cardsHolder.AbsolutePosition) + frame.AbsoluteSize / 2
		frame.AnchorPoint = Vector2.new(0.5, 0.5)
		frame.Position = UDim2.fromOffset(center.X, center.Y)
		card.restPosition = frame.Position
	end
	layout.Parent = nil
end

-- Caída escalonada con overshoot. Corre en su propia corrutina (espera al layout).
local function revealCards()
	for _ = 1, 10 do
		local ready = cardsHolder.AbsoluteSize.Y > 0
			and orderedCards[1] ~= nil
			and orderedCards[1].frame.AbsoluteSize.Y > 0
		if ready then break end
		task.wait()
	end
	snapshotAndFreeze()

	for index, card in orderedCards do
		local frame = card.frame
		local rest = card.restPosition
		frame.Visible = false
		task.delay((index - 1) * DROP_STAGGER, function()
			frame.Position = rest + UDim2.fromOffset(0, -DROP_DISTANCE)
			frame.Visible = true
			playOneShot(dropSound)
			TweenService:Create(
				frame,
				TweenInfo.new(DROP_DURATION, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
				{ Position = rest }
			):Play()
		end)
	end

	-- Cuando aterriza la última: el contador puede empezar a bajar.
	task.delay((#orderedCards - 1) * DROP_STAGGER + DROP_DURATION, function()
		mapsReady = true
	end)
end

local function paintState(state: { [string]: { number } }?)
	if not state then return end
	updatePositions(state)
	for mapId, card in cards do
		local voters = state[mapId] or {}
		if card.votes then
			card.votes.Text = ("%d votes"):format(#voters)
		end
		card.voted = table.find(voters, localUserId) ~= nil
		renderAvatars(card, mapId, voters)
	end
end

-- UIScale propio para el pop (no toca Size) y color base para la onda blanca.
local timeScale: UIScale? = nil
local timeDefaultColor = timeLabel and timeLabel.TextColor3 or TIME_PULSE_WHITE
if timeLabel then
	local s = timeLabel:FindFirstChildOfClass("UIScale") or Instance.new("UIScale")
	s.Parent = timeLabel
	timeScale = s
end

local function pulseTimeLabel(playSound: boolean)
	if not timeLabel then return end
	if playSound and tickSound then
		tickSound:Play()
	end
	-- Onda blanca: salta a blanco y vuelve al color original.
	timeLabel.TextColor3 = TIME_PULSE_WHITE
	TweenService:Create(timeLabel, TweenInfo.new(TIME_PULSE_BACK, Enum.EasingStyle.Quad), {
		TextColor3 = timeDefaultColor,
	}):Play()
	-- Pop que se asienta: salta a TIME_POP_SCALE y vuelve a 1 con Back Out (se pasa un
	-- poco y se acomoda = el wobble corto).
	if timeScale then
		timeScale.Scale = TIME_POP_SCALE
		TweenService:Create(timeScale, TweenInfo.new(TIME_POP_DURATION, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
			Scale = 1,
		}):Play()
	end
end

local lastShownSeconds: number? = nil

local function setTime(seconds: number?)
	if not (timeLabel and seconds) then return end
	-- Hasta que estén los 3 mapas en pantalla el tiempo no baja: se muestra el valor
	-- inicial (primera llamada) y se ignoran los ticks siguientes.
	if not mapsReady and lastShownSeconds ~= nil then return end
	-- floor: "15s left", nunca "15.9s left".
	local whole = math.max(math.floor(seconds), 0)
	timeLabel.Text = ("%ds left"):format(whole)
	if whole ~= lastShownSeconds then
		-- El valor inicial NO pulsa: no es un tic, y además llega dos veces (mapVoteStart
		-- lo muestra y showPanel resetea lastShownSeconds, así que el primer tick lo repite).
		local isFirstValue = lastShownSeconds == nil
		lastShownSeconds = whole
		if not isFirstValue then
			-- El 0 pulsa MUDO: el clip de tic-tac dura varios segundos y seguiría sonando
			-- por encima de la animación del ganador.
			pulseTimeLabel(whole > 0)
		end
	end
end

-- Revela el panel (una vez) e invalida cualquier ocultado pendiente. Restaura el
-- contador (lo esconde el cierre de la votación anterior).
local function showPanel()
	activityGeneration += 1
	if panel.Visible then return end
	panel.Visible = true
	if timeLabel then
		timeLabel.Visible = true
	end
	lastShownSeconds = nil
	mapsReady = false
	task.spawn(revealCards)
end

local function hidePanel()
	panel.Visible = false
end

-- Back In es el boing entero en un solo tween: se hunde un poco antes de arrancar y
-- recién ahí sale disparada hacia arriba.
local function exitUp(frame: Frame, from: UDim2, distance: number, duration: number)
	local tween = TweenService:Create(
		frame,
		TweenInfo.new(duration, Enum.EasingStyle.Back, Enum.EasingDirection.In),
		{ Position = from - UDim2.fromOffset(0, distance) }
	)
	tween.Completed:Connect(function()
		frame.Visible = false
	end)
	tween:Play()
end

-- Cierre: los perdedores salen con el INVERSO de la caída. El ganador espera a que suban,
-- baja un poco a esa posición, ahí crece con el sonido y al final se va con el mismo
-- boing. `done` saca a la card del balanceo para que estos tweens no se los pise el
-- Heartbeat.
local function revealWinner(winnerId: string)
	-- Destino FIJO para el ganador: la posición del último mapa (el de abajo) más el
	-- drop. Gane el que gane, siempre baja al mismo lugar.
	local lastCard = orderedCards[#orderedCards]
	local winnerTarget = lastCard.restPosition + UDim2.fromOffset(0, WINNER_DROP_DISTANCE)

	for _, card in orderedCards do
		card.done = true
		card.hovered = false
		card.voted = false
		local frame = card.frame
		frame.Rotation = 0
		if frame.Name == winnerId then
			local target = winnerTarget
			task.delay(WINNER_DELAY, function()
				local move = TweenService:Create(
					frame,
					TweenInfo.new(WINNER_MOVE_DURATION, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
					{ Position = target }
				)
				move.Completed:Connect(function()
					if winnerSound then
						winnerSound:Play()
					end
					local grow = TweenService:Create(
						card.scale,
						TweenInfo.new(WINNER_GROW_DURATION, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
						{ Scale = WINNER_SCALE }
					)
					grow.Completed:Connect(function()
						task.delay(WINNER_HOLD, function()
							exitUp(frame, target, WINNER_EXIT_DISTANCE, WINNER_EXIT_DURATION)
						end)
					end)
					grow:Play()
				end)
				move:Play()
			end)
		else
			exitUp(frame, card.restPosition, LOSER_EXIT_DISTANCE, LOSER_EXIT_DURATION)
		end
	end
end

-- Al terminar: el contador llega a "0s left", se muestra un instante y se esconde;
-- ahí se revela al ganador.
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

-- Balanceo de las cards con hover o voto: centro fijo, los lados suben/bajan. Un solo
-- Heartbeat para todas; la intensidad va a 1 (activa) o 0 (inactiva) con easing. Las
-- cards `done` (cierre) quedan afuera: sus tweens propios mandan.
RunService.Heartbeat:Connect(function(dt: number)
	local now = os.clock()
	local ease = 1 - math.exp(-WOBBLE_EASE * dt)
	for _, card in cards do
		if card.done then
			continue
		end
		local target = (card.hovered or card.voted) and 1 or 0
		card.wobbleIntensity += (target - card.wobbleIntensity) * ease
		local intensity = card.wobbleIntensity
		card.frame.Rotation = math.sin(now * WOBBLE_SPEED + card.wobblePhase) * WOBBLE_DEGREES * intensity
		card.scale.Scale = 1 + (HOVER_SCALE - 1) * intensity
	end
end)

updateUI.OnClientEvent:Connect(function(event: string, payload: any)
	if event == "mapVoteCatalog" then
		buildCards(payload)
	elseif event == "mapVoteState" then
		paintState(payload)
	elseif event == "mapVoteStart" then
		setTime(payload)
		showPanel()
	elseif event == "mapVoteTick" then
		-- Los ticks son fireAll cada segundo: también revelan a quien entró a mitad.
		setTime(payload)
		showPanel()
	elseif event == "mapVoteEnd" then
		finishVote(payload)
		activityGeneration += 1
		local myGeneration = activityGeneration
		task.delay(HIDE_DELAY_AFTER_END, function()
			if myGeneration == activityGeneration then
				hidePanel()
			end
		end)
	end
end)

-- Catch-up si entramos con una votación ya abierta (nos perdimos el fireAll inicial).
GameRemotes.RequestMapVoteState:FireServer()

-- Botón de debug SOLO en Studio: corre una votación de MENTIRA 100% local (arma las
-- cards, revela, cuenta 15->0 y deja votar), sin disparar ningún remote.
-- Es un botón aparte del "Debug: Map Vote" (ese sí corre la ventana real).
if DebugConfig.CHEATS_ENABLED then
	local Icon = require(ReplicatedStorage:WaitForChild("TopbarPlus"):WaitForChild("Icon"))

	-- Fallback si todavía no llegó el catálogo real (RequestMapVoteState al cargar).
	local MOCK_MAPS = {
		{ Id = "DebugTrackA", Name = "Track A", Image = "" },
		{ Id = "DebugTrackB", Name = "Track B [NEW!]", Image = "" },
		{ Id = "DebugTrackC", Name = "Track C", Image = "" },
	}
	-- Votantes falsos por POSICIÓN de mapa (userIds reales para que se vean las fotitos).
	local MOCK_FAKE_VOTER_SEED = { { 1, 156 }, { 261 }, { 2, 3 } }
	local MOCK_DURATION = 15

	local mockCatalog: { { Id: string, Name: string, Image: string } } = MOCK_MAPS
	local mockFakeVoters: { [string]: { number } } = {}
	local mockVoted: string? = nil
	local mockThread: thread? = nil

	local function mockState(): { [string]: { number } }
		local snapshot: { [string]: { number } } = {}
		for _, map in mockCatalog do
			local voters = table.clone(mockFakeVoters[map.Id] or {})
			if mockVoted == map.Id then
				table.insert(voters, localUserId)
			end
			snapshot[map.Id] = voters
		end
		return snapshot
	end

	mockToggleVote = function(mapId: string)
		mockVoted = if mockVoted == mapId then nil else mapId
		paintState(mockState())
	end

	local function runMockVote()
		if mockThread then
			task.cancel(mockThread)
		end
		mockMode = true
		mockVoted = nil

		-- Mapas REALES (nombres + imágenes) si ya llegó el catálogo; si no, el fallback.
		mockCatalog = lastCatalog or MOCK_MAPS
		mockFakeVoters = {}
		for index, map in mockCatalog do
			mockFakeVoters[map.Id] = MOCK_FAKE_VOTER_SEED[index] or {}
		end

		buildCards(mockCatalog)
		paintState(mockState())
		-- Forzar el reveal aunque el panel viniera visible de una corrida anterior.
		panel.Visible = false
		showPanel()

		mockThread = task.spawn(function()
			-- Muestra el valor inicial y espera a que estén los 3 mapas antes de contar.
			setTime(MOCK_DURATION)
			while not mapsReady do
				task.wait()
			end
			for t = MOCK_DURATION, 1, -1 do
				setTime(t)
				task.wait(1)
			end
			-- Ganador: tu voto, o el mapa del medio (para probar "gana el central").
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

	-- Evita duplicar el ícono si el script se re-corre (play-testing en Studio).
	local existing = Icon.getIcon("MapVoteDebug")
	if existing then
		existing:destroy()
	end

	local debugIcon = Icon.new()
	debugIcon:setName("MapVoteDebug")
	debugIcon:setLabel("Map Vote (Debug)")
	debugIcon:oneClick(true)
	debugIcon.selected:Connect(runMockVote)
end
