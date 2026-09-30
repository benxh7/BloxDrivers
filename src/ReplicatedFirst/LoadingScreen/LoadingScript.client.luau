local ReplicatedFirst = game:GetService("ReplicatedFirst")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local ContentProvider = game:GetService("ContentProvider")
local TweenService = game:GetService("TweenService")
local StarterGui = game:GetService("StarterGui")

-- WaitForChild: corre muy temprano en ReplicatedFirst, ReplicatedStorage puede
-- no haber replicado sus hijos todavía.
local DebugConfig = require(ReplicatedStorage:WaitForChild("DebugConfig"))
local PreloadAssets = require(ReplicatedStorage:WaitForChild("PreloadAssets"))
local MenuCameraConfig = require(ReplicatedStorage:WaitForChild("MenuCameraConfig"))
local MenuCamera = require(script.Parent:WaitForChild("MenuCamera"))
local AnimationPreloader = require(script.Parent:WaitForChild("AnimationPreloader"))
local WaveTransition = require(script.Parent:WaitForChild("WaveTransition"))
local SoundService = game:GetService("SoundService")
local Remotes = require(ReplicatedStorage:WaitForChild("Remotes"))
local setLoadingComplete = Remotes.event("SetLoadingComplete")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local startClock = os.clock()

-- DebugConfig.print("[LoadingScreen] Starting")

ReplicatedFirst:RemoveDefaultLoadingScreen()

-- LoadingGui es una plantilla (armada en Studio, nunca se muestra directo): se
-- clona y el clon es la GUI real.
local template = script.Parent:WaitForChild("LoadingGui") :: ScreenGui
local gui = template:Clone()
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 1000
gui.Parent = playerGui

-- DebugConfig.print("[LoadingScreen] Gui parented to PlayerGui")

local background = gui:WaitForChild("Background") :: GuiObject
local center = background:WaitForChild("Center") :: Frame
local actionButton = center:WaitForChild("SkipButton") :: TextButton
local tipLabel = center:WaitForChild("TipFrame"):WaitForChild("TipLabel") :: TextLabel

-- Traído de UBG sin su flavor text — reemplazá con tips propios de BloxDrivers.
local TIPS = {
	"Tip: personalizá estos textos en LoadingScript.client.luau.",
}

local LOADING_MESSAGES = {
	"Loading",
}

local SKIP_DELAY = 8
-- El TEXTO rota cada tantos segundos, pero el PORCENTAJE se refresca aparte y más
-- seguido: así el número sube en vivo debajo de la misma frase.
local LABEL_REFRESH = 0.1
local LOADING_MESSAGE_SECONDS = 1.5
-- Los tips duran más: hay que llegar a leerlos.
local TIP_SECONDS = 3.5
-- Probabilidad de que el próximo turno sea un tip en vez de una frase de carga.
-- Al ser al azar, de a ratos caen dos tips seguidos, que es lo que se busca.
local TIP_CHANCE = 0.3
local READY_TEXT = "Ready! (100%)"
-- Mínimo en pantalla antes de ofrecer PLAY: en Studio la precarga puede terminar
-- en un instante y el botón aparecería antes de que se llegue a ver nada.
local MIN_DISPLAY_TIME = 2
-- Un solo botón para las dos cosas: adelantarse a la precarga o entrar ya listo.
local SKIP_TEXT = "Skip Loading"
local PLAY_TEXT = "Play"
-- Al llegar a 100% el botón queda VERDE PLANO: el degradado rojo que traiga se
-- apaga. Un UIGradient multiplica al BackgroundColor3, así que dejarlo prendido
-- ensuciaría el verde.
local PLAY_BUTTON_COLOR = Color3.fromRGB(46, 204, 113)
local PLAY_BUTTON_TINT_SECONDS = 0.4
-- Se agranda y se despliega un poco más abajo (DROP en escala del padre).
local PLAY_BUTTON_GROW = 1.12
local PLAY_BUTTON_DROP = 0.05
local PLAY_BUTTON_REVEAL_SECONDS = 0.5
local HOVER_SCALE = 1.06
local HOVER_SECONDS = 0.15

-- Música de fondo del menú (en loop) y click del botón (SKIP/PLAY). Mismos
-- assets que UBG a pedido. La música se desvanece al entrar al juego.
-- OJO: acá va una CANCIÓN de fondo, NO el sonido de la ola — ese ya suena solo al
-- dar Play (WaveTransition usa WaveTransitionConfig.SoundId). Poner el whoosh acá
-- lo deja sonando en bucle toda la carga.
local MENU_MUSIC_ID = "rbxassetid://129514825232523"
local MENU_MUSIC_VOLUME = 0.5
local MENU_MUSIC_FADEOUT = 0.6
local CLICK_SOUND_ID = "rbxassetid://15675059323"
local CLICK_SOUND_VOLUME = 0.8

-- Imagen del menú (logo): respira y se bambolea. Se busca por nombre; si no está,
-- se toma el primer ImageLabel que no sea la textura animada del fondo.
local LOGO_NAME = "Logo"
-- Respiración: cuánto crece y encoge (0.06 = ±6%) y cuánto tarda medio ciclo.
local LOGO_BREATH_SCALE = 0.06
local LOGO_BREATH_SECONDS = 3.5
-- Bamboleo: grados a cada lado y cuánto tarda ir de un extremo al otro. Los dos
-- tiempos son distintos a propósito, para que no se sincronicen y se vea orgánico.
local LOGO_TILT_DEGREES = 4
local LOGO_TILT_SECONDS = 4.5

-- DEBUG: simula una precarga de TEST_ASSET_DURATION segundos para ver el menú y el
-- paso SKIP -> PLAY sin depender de que Studio tarde. VOLVER A FALSE ANTES DE PUBLICAR.
local TEST_ASSETS = false
local TEST_ASSET_DURATION = 60

-- Última red, hoy VACÍA a propósito. Un ID solo llega acá si está escrito dentro
-- del código de un Script, que es lo único que ninguna fuente puede ver
-- (`Script.Source` no se lee en runtime). Antes de agregar uno: movelo a un config
-- y sumá ese config a `PreloadAssets.SOURCES`.
local EXTRA_PRELOAD_IDS = {}

actionButton.Visible = false

local function isRealSound(id: string): boolean
	return id ~= "" and id ~= "rbxassetid://0"
end

-- Música de fondo en loop mientras dura el menú. Parented a SoundService (no a la
-- GUI): así el fade de salida no la corta antes de tiempo cuando se destruye la GUI.
local menuMusic: Sound? = nil
if isRealSound(MENU_MUSIC_ID) then
	local music = Instance.new("Sound")
	music.Name = "LoadingMenuMusic"
	music.SoundId = MENU_MUSIC_ID
	music.Volume = MENU_MUSIC_VOLUME
	music.Looped = true
	music.Parent = SoundService
	music:Play()
	menuMusic = music
end

-- Un solo Sound precargado: creando uno por click, el primer play espera al asset.
local clickSound: Sound? = nil
if isRealSound(CLICK_SOUND_ID) then
	local sound = Instance.new("Sound")
	sound.Name = "LoadingClick"
	sound.SoundId = CLICK_SOUND_ID
	sound.Volume = CLICK_SOUND_VOLUME
	sound.Parent = SoundService
	clickSound = sound

	task.spawn(function()
		pcall(function()
			ContentProvider:PreloadAsync({ sound })
		end)
	end)
end

-- Un ScreenGui no tiene un único "alpha" y Background es un Frame (no CanvasGroup),
-- así que el fade se aplica hoja por hoja según la clase.
local FADE_PROPERTIES: { [string]: { string } } = {
	Frame = { "BackgroundTransparency" },
	CanvasGroup = { "GroupTransparency" },
	ScrollingFrame = { "BackgroundTransparency", "ScrollBarImageTransparency" },
	ImageLabel = { "BackgroundTransparency", "ImageTransparency" },
	ImageButton = { "BackgroundTransparency", "ImageTransparency" },
	TextLabel = { "BackgroundTransparency", "TextTransparency", "TextStrokeTransparency" },
	TextButton = { "BackgroundTransparency", "TextTransparency", "TextStrokeTransparency" },
	TextBox = { "BackgroundTransparency", "TextTransparency", "TextStrokeTransparency" },
	UIStroke = { "Transparency" },
}

local function fadeSubtree(root: Instance, duration: number, skip: { Instance }?)
	local info = TweenInfo.new(duration, Enum.EasingStyle.Quad)
	local function isSkipped(instance: Instance): boolean
		if not skip then return false end
		for _, excluded in skip do
			if instance == excluded or instance:IsDescendantOf(excluded) then return true end
		end
		return false
	end

	local function apply(instance: Instance)
		if isSkipped(instance) then return end
		local properties = FADE_PROPERTIES[instance.ClassName]
		if not properties then return end
		local goal: { [string]: number } = {}
		for _, property in properties do
			goal[property] = 1
		end
		TweenService:Create(instance, info, goal):Play()
	end

	apply(root)
	for _, descendant in root:GetDescendants() do
		apply(descendant)
	end
end

local function setButtonText(text: string)
	local hasLabel = false
	for _, descendant in actionButton:GetDescendants() do
		if descendant:IsA("TextLabel") then
			descendant.Text = text
			hasLabel = true
		end
	end

	-- Un TextButton dibuja su propio Text ADEMÁS de sus hijos: si el botón trae su
	-- TextLabel diseñado, el del botón se vacía o se verían los dos encimados.
	actionButton.Text = if hasLabel then "" else text
end

local function scaleUDim2(size: UDim2, factor: number): UDim2
	return UDim2.new(
		size.X.Scale * factor,
		size.X.Offset * factor,
		size.Y.Scale * factor,
		size.Y.Offset * factor
	)
end

-- Por UIScale y NO por Size: el botón de PLAY ya tweenea su Size al desplegarse, y
-- tocando los dos el hover lo devolvería al tamaño viejo.
local function attachHover(button: GuiButton)
	-- El crecimiento sale del AnchorPoint: descentrado, el botón se estira hacia
	-- abajo y a la derecha en vez de crecer parejo.
	if button.AnchorPoint ~= Vector2.new(0.5, 0.5) then
		DebugConfig.warn("[LoadingScreen] " .. button.Name .. ": poné AnchorPoint en 0.5, 0.5 para que crezca desde su centro")
	end

	local scale = button:FindFirstChildOfClass("UIScale") or Instance.new("UIScale")
	scale.Parent = button

	local function tweenTo(target: number)
		TweenService:Create(scale, TweenInfo.new(HOVER_SECONDS, Enum.EasingStyle.Quad), {
			Scale = target,
		}):Play()
	end

	button.MouseEnter:Connect(function()
		tweenTo(HOVER_SCALE)
	end)
	button.MouseLeave:Connect(function()
		tweenTo(1)
	end)
end

for _, descendant in center:GetDescendants() do
	if descendant:IsA("GuiButton") then
		attachHover(descendant)
	end
end

-- Mismos keypoints y tiempos que el original: así lerpSequence puede recorrer las
-- dos secuencias en paralelo.
local function solidVersionOf(sequence: ColorSequence, color: Color3): ColorSequence
	local keypoints = {}
	for _, keypoint in sequence.Keypoints do
		table.insert(keypoints, ColorSequenceKeypoint.new(keypoint.Time, color))
	end
	return ColorSequence.new(keypoints)
end

local function lerpSequence(from: ColorSequence, to: ColorSequence, alpha: number): ColorSequence
	local keypoints = {}
	for index, keypoint in from.Keypoints do
		local target = to.Keypoints[index]
		table.insert(keypoints, ColorSequenceKeypoint.new(keypoint.Time, keypoint.Value:Lerp(target.Value, alpha)))
	end
	return ColorSequence.new(keypoints)
end

local function tintButtonGreen()
	TweenService:Create(actionButton, TweenInfo.new(PLAY_BUTTON_TINT_SECONDS, Enum.EasingStyle.Quad), {
		BackgroundColor3 = PLAY_BUTTON_COLOR,
	}):Play()

	local gradient = actionButton:FindFirstChildOfClass("UIGradient")
	if not gradient then return end

	-- El degradado se lleva a blanco (neutro: multiplicar por blanco no tiñe) a la
	-- par del fondo, y recién ahí se apaga. Apagarlo de una daría un salto de color.
	-- ColorSequence no es un tipo tweeneable, así que se interpola a mano.
	local from = gradient.Color
	local to = solidVersionOf(from, Color3.new(1, 1, 1))
	task.spawn(function()
		local startedAt = os.clock()
		while gradient.Parent do
			local alpha = math.min((os.clock() - startedAt) / PLAY_BUTTON_TINT_SECONDS, 1)
			gradient.Color = lerpSequence(from, to, alpha)
			if alpha >= 1 then break end
			task.wait()
		end
		-- Enabled y no Destroy: no se toca lo que armaste en Studio.
		gradient.Enabled = false
	end)
end

-- La textura animada del fondo también es un ImageLabel: queda fuera de la búsqueda.
local animatedTexture = background:FindFirstChild("AnimatedTexture")

local function findLogo(): ImageLabel?
	local byName = gui:FindFirstChild(LOGO_NAME, true)
	if byName and byName:IsA("ImageLabel") then return byName end

	for _, descendant in gui:GetDescendants() do
		if descendant:IsA("ImageLabel") and not (animatedTexture and descendant:IsDescendantOf(animatedTexture)) then
			return descendant
		end
	end
	return nil
end

-- Respiración y bamboleo en loop infinito (RepeatCount -1 + Reverses). Sine InOut
-- frena en los extremos: eso es lo que lo hace parecer respiración y no un rebote.
local function animateLogo(logo: ImageLabel)
	-- Rotation gira alrededor del AnchorPoint: descentrado, el logo se DESPLAZA
	-- en arco en vez de girar sobre sí mismo.
	if logo.AnchorPoint ~= Vector2.new(0.5, 0.5) then
		DebugConfig.warn("[LoadingScreen] " .. logo.Name .. ": poné AnchorPoint en 0.5, 0.5 para que gire sobre su centro")
	end

	-- UIScale en vez de tocar Size: no pelea con un UIAspectRatioConstraint ni
	-- con el layout del padre.
	local scale = logo:FindFirstChildOfClass("UIScale") or Instance.new("UIScale")
	scale.Parent = logo
	scale.Scale = 1 - LOGO_BREATH_SCALE
	TweenService:Create(scale, TweenInfo.new(LOGO_BREATH_SECONDS, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), {
		Scale = 1 + LOGO_BREATH_SCALE,
	}):Play()

	logo.Rotation = -LOGO_TILT_DEGREES
	TweenService:Create(logo, TweenInfo.new(LOGO_TILT_SECONDS, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), {
		Rotation = LOGO_TILT_DEGREES,
	}):Play()
end

local logo = findLogo()
if logo then
	animateLogo(logo)
else
	DebugConfig.warn("[LoadingScreen] Sin imagen de menú: no hay ningún '" .. LOGO_NAME .. "' ni otro ImageLabel en LoadingGui")
end

-- El logo puede colgar del Background y no de Center: sin excluirlo, el fade que
-- descubre la escena 3D se lo llevaría puesto.
local revealSkip: { Instance } = { center }
if logo then
	table.insert(revealSkip, logo)
end

local doneLoading = false
-- El jugador NO entra al juego hasta apretar el botón: hasta entonces no se
-- dispara SetLoadingComplete, así que el servidor lo sigue viendo como Loading.
local entered = false
-- 0-1 de la precarga: lo alimenta el callback de PreloadAsync.
local loadedAlpha = 0

local labelThread = task.spawn(function()
	local rng = Random.new()

	-- No repetir la frase que ya está en pantalla: al azar puro salía dos veces
	-- seguidas bastante seguido.
	local function pickDifferent(pool: { string }, current: string): string
		if #pool < 2 then return pool[1] end
		local pick = current
		while pick == current do
			pick = pool[rng:NextInteger(1, #pool)]
		end
		return pick
	end

	local currentText = LOADING_MESSAGES[1]
	local holdUntil = 0

	while true do
		if doneLoading then
			-- 100%: se queda fijo. El thread sigue vivo a propósito, así el
			-- task.cancel del cierre siempre tiene a quién cancelar.
			tipLabel.Text = READY_TEXT
			task.wait(LABEL_REFRESH)
			continue
		end

		if os.clock() >= holdUntil then
			if rng:NextNumber() < TIP_CHANCE then
				currentText = pickDifferent(TIPS, currentText)
				holdUntil = os.clock() + TIP_SECONDS
			else
				currentText = pickDifferent(LOADING_MESSAGES, currentText)
				holdUntil = os.clock() + LOADING_MESSAGE_SECONDS
			end
		end

		-- Tope en 99: el 100% queda reservado para READY_TEXT, así no aparece un
		-- "(100%)" mientras PreloadAsync todavía no volvió.
		local percent = math.min(math.floor(loadedAlpha * 100), 99)
		tipLabel.Text = string.format("%s (%d%%)", currentText, percent)
		task.wait(LABEL_REFRESH)
	end
end)


-- Con el fondo transparente se vería el HUD detrás del menú: se apagan todas las
-- ScreenGui (y las que aparezcan) y se restaura su estado al entrar.
-- CoreGui con dueño en el juego (ej. tu HUD apagando la mochila). El menú no las
-- toca: corre ANTES que ese dueño, así que las guardaría en su default de Roblox y
-- al restaurar volvería a encender lo que el juego apagó.
local GAME_MANAGED_CORE_GUI = { [Enum.CoreGuiType.Backpack] = true }

local hiddenGuis: { [ScreenGui]: boolean } = {}
local enabledConns: { [ScreenGui]: RBXScriptConnection } = {}
local guiAddedConn: RBXScriptConnection? = nil
local coreGuiStates: { [Enum.CoreGuiType]: boolean } = {}

-- GUIs propias del menú que el watchdog NO debe apagar (la GUI de carga y, cuando
-- se crea, la de la ola de cierre — se parentea con el watchdog todavía activo).
local ownGuis: { [Instance]: boolean } = { [gui] = true }

local function hideGui(instance: Instance)
	if ownGuis[instance] or not instance:IsA("ScreenGui") then return end
	local screenGui = instance :: ScreenGui
	hiddenGuis[screenGui] = screenGui.Enabled
	screenGui.Enabled = false

	-- Apagarla una vez no alcanza: su dueño la vuelve a prender por su cuenta (los
	-- emotes con B/G, sin ir más lejos). Se la reapaga mientras dure el menú.
	enabledConns[screenGui] = screenGui:GetPropertyChangedSignal("Enabled"):Connect(function()
		if screenGui.Enabled then
			screenGui.Enabled = false
		end
	end)
end

local function hideGameGuis()
	for _, child in playerGui:GetChildren() do
		hideGui(child)
	end
	guiAddedConn = playerGui.ChildAdded:Connect(hideGui)

	-- Se guarda el estado de cada CoreGuiType por separado: restaurar con
	-- SetCoreGuiEnabled(All, true) prendería cosas que el juego dejó apagadas.
	for _, coreType in Enum.CoreGuiType:GetEnumItems() do
		if coreType == Enum.CoreGuiType.All or GAME_MANAGED_CORE_GUI[coreType] then continue end
		pcall(function()
			coreGuiStates[coreType] = StarterGui:GetCoreGuiEnabled(coreType)
			StarterGui:SetCoreGuiEnabled(coreType, false)
		end)
	end
	-- El topbar de Roblox se dibuja sobre CUALQUIER ScreenGui.
	pcall(function()
		StarterGui:SetCore("TopbarEnabled", false)
	end)
end

local function restoreGameGuis()
	if guiAddedConn then
		guiAddedConn:Disconnect()
		guiAddedConn = nil
	end

	-- Los watchdogs se cortan ANTES de restaurar: si no, cada Enabled = true de acá
	-- abajo se apagaría solo.
	for _, connection in enabledConns do
		connection:Disconnect()
	end
	table.clear(enabledConns)

	for screenGui, wasEnabled in hiddenGuis do
		if screenGui.Parent then
			screenGui.Enabled = wasEnabled
		end
	end
	table.clear(hiddenGuis)

	for coreType, wasEnabled in coreGuiStates do
		pcall(function()
			StarterGui:SetCoreGuiEnabled(coreType, wasEnabled)
		end)
	end
	table.clear(coreGuiStates)
	pcall(function()
		StarterGui:SetCore("TopbarEnabled", true)
	end)
end

hideGameGuis()

-- Congelar el input: se pisa WalkSpeed/JumpPower del Humanoid en vez de pasar por
-- PlayerModule/ControlModule (el paquete default de Roblox — no un archivo de este
-- proyecto, y no hace falta para que el personaje camine: eso ya lo maneja el
-- motor solo). Más simple, y no depende de que StarterPlayerScripts tenga esos
-- scripts insertados.
local frozenHumanoid: Humanoid? = nil
local savedWalkSpeed: number? = nil
local savedJumpPower: number? = nil

task.spawn(function()
	local character = player.Character or player.CharacterAdded:Wait()
	local humanoid = character:WaitForChild("Humanoid", 10) :: Humanoid?
	if not humanoid then
		DebugConfig.warn("[LoadingScreen] Sin Humanoid, el jugador puede moverse en el menú")
		return
	end

	-- Revalidado DESPUÉS de esperar: si entró mientras tanto, ya se descongeló
	-- (no corrió todavía porque esto recién está por hacerlo) y congelar ahora lo
	-- dejaría trabado dentro del juego.
	if entered then return end

	savedWalkSpeed = humanoid.WalkSpeed
	savedJumpPower = humanoid.JumpPower
	humanoid.WalkSpeed = 0
	humanoid.JumpPower = 0
	frozenHumanoid = humanoid
end)

-- La cámara arranca cuando el lobby replicó, no antes: recién ahí se descubre la
-- escena. Si nunca llega, el fondo se queda puesto y el menú funciona igual.
task.spawn(function()
	if not MenuCamera.start() then
		DebugConfig.warn("[LoadingScreen] Sin punto de cámara en el lobby: se mantiene el fondo")
		return
	end
	if entered then
		MenuCamera.stop()
		return
	end
	-- DebugConfig.print("[LoadingScreen] Cámara del menú activa, descubriendo la escena")
	fadeSubtree(background, MenuCameraConfig.RevealSeconds, revealSkip)
end)


local buttonSize = actionButton.Size
local buttonPosition = actionButton.Position

-- Aparece a los SKIP_DELAY sin timeout duro (adelantarse es decisión del jugador).
task.delay(SKIP_DELAY, function()
	if entered or doneLoading then return end
	setButtonText(SKIP_TEXT)
	actionButton.Visible = true
end)

actionButton.Activated:Connect(function()
	if clickSound then
		clickSound:Play()
	end
	if entered then return end
	entered = true
	actionButton.Interactable = false
	-- DebugConfig.print("[LoadingScreen] Entered by player (doneLoading=" .. tostring(doneLoading) .. ")")
end)

if TEST_ASSETS then
	DebugConfig.warn("[LoadingScreen] TEST_ASSETS activo — simulando una precarga de " .. TEST_ASSET_DURATION .. "s. Recordá volver a false antes de publicar.")
	task.spawn(function()
		local elapsed = 0
		while elapsed < TEST_ASSET_DURATION and not entered do
			elapsed += task.wait()
			loadedAlpha = math.min(elapsed / TEST_ASSET_DURATION, 1)
		end
		doneLoading = true
		DebugConfig.print("[LoadingScreen] TEST_ASSETS simulation finished")
	end)
else
	-- Se pasan IDs (strings) y NO instancias: el callback corre una vez por ID, y una
	-- instancia puede traer varios (un MeshPart tiene MeshId y TextureID).
	local function isRealAsset(id: string): boolean
		return id ~= "" and id ~= "rbxassetid://0"
	end

	-- Contenedores ESTÁTICOS: mismo contenido en cada sesión, así que el total sale
	-- idéntico siempre.
	local SCAN_CONTAINERS: { Instance } = {
		ReplicatedStorage,
		ReplicatedFirst,
		game:GetService("StarterGui"),
		game:GetService("StarterPack"),
		game:GetService("StarterPlayer"),
		game:GetService("Lighting"),
		game:GetService("SoundService"),
	}

	-- IsLoaded ANTES de mirar Workspace: corremos tan temprano que barrer a medio
	-- replicar devuelve un total inestable.
	if not game:IsLoaded() then
		game.Loaded:Wait()
	end

	-- Solo lo estático: el mapa activo y los personajes se crean en runtime y harían
	-- bailar el total entre corridas.
	local RUNTIME_WORKSPACE_FOLDERS = { Maps = true }

	for _, child in workspace:GetChildren() do
		if RUNTIME_WORKSPACE_FOLDERS[child.Name] then continue end
		if Players:GetPlayerFromCharacter(child) then continue end
		table.insert(SCAN_CONTAINERS, child)
	end

	-- Set y no lista: el mismo ID aparece en decenas de instancias y descargarlo una
	-- vez alcanza. Sin dedup el total varía según lo que haya replicado.
	local seen: { [string]: true } = {}
	local assetsToLoad: { string } = {}

	local function addAsset(id: string)
		if not isRealAsset(id) or seen[id] then return end
		seen[id] = true
		table.insert(assetsToLoad, id)
	end

	-- Se marcan como vistas ANTES del barrido para que no entren a PreloadAsync, que
	-- sobre una animación reporta OK sin bajar nada. Las carga AnimationPreloader.
	local animationIds = PreloadAssets.collectAnimationIds()
	for _, id in animationIds do
		seen[id] = true
	end

	for _, container in SCAN_CONTAINERS do
		PreloadAssets.forEachAssetId(container, addAsset)
	end
	-- IDs que viven como strings dentro de los catálogos: el barrido de arriba lee
	-- propiedades de Instances y no puede verlos. En pcall: un catálogo roto no debe
	-- voltear la pantalla de carga.
	local okCatalogs, catalogIds = pcall(function()
		return PreloadAssets.collect()
	end)
	if okCatalogs and typeof(catalogIds) == "table" then
		for _, id in catalogIds do
			addAsset(id)
		end
	else
		DebugConfig.warn("[LoadingScreen] No se pudieron leer los assets de los catálogos: " .. tostring(catalogIds))
	end

	-- ServerStorage no se replica: lo enumera el servidor (ver ServerAssetManifest).
	-- Tenerlo en memoria es lo que permite que MAP_LOAD_DELAY sea corto.
	local manifest = ReplicatedStorage:WaitForChild("ServerAssetManifest", 5)
	if manifest and manifest:IsA("StringValue") then
		local count = 0
		for id in manifest.Value:gmatch("[^\n]+") do
			addAsset(id)
			count += 1
		end
		DebugConfig.print("[LoadingScreen] " .. count .. " assets de ServerStorage desde el manifiesto")
	else
		DebugConfig.warn("[LoadingScreen] Sin ServerAssetManifest: lo de ServerStorage se va a cargar en pleno juego")
	end

	for _, id in EXTRA_PRELOAD_IDS do
		addAsset(id)
	end
	local totalAssets = #assetsToLoad + #animationIds

	DebugConfig.print("[LoadingScreen] Preloading " .. #assetsToLoad .. " assets + " .. #animationIds .. " animaciones")

	local loadedCount = 0
	local function countOne()
		loadedCount += 1
		if totalAssets > 0 then
			loadedAlpha = loadedCount / totalAssets
		end
	end

	-- Las dos fases corren en paralelo y la última prende doneLoading: las
	-- animaciones esperan al personaje y tardarían de más en serie.
	local pendingPhases = 2
	local function finishPhase()
		pendingPhases -= 1
		if pendingPhases == 0 then
			doneLoading = true
			DebugConfig.print("[LoadingScreen] Preload finished (" .. loadedCount .. "/" .. totalAssets .. ")")
		end
	end

	task.spawn(function()
		ContentProvider:PreloadAsync(assetsToLoad, function(_contentId, _status)
			countOne()
		end)
		finishPhase()
	end)

	task.spawn(function()
		local ok, loaded = pcall(AnimationPreloader.preload, animationIds, countOne)
		if ok then
			DebugConfig.print("[LoadingScreen] " .. tostring(loaded) .. "/" .. #animationIds .. " animaciones cacheadas")
		else
			DebugConfig.warn("[LoadingScreen] No se pudieron precargar las animaciones: " .. tostring(loaded))
		end
		finishPhase()
	end)
end

while not doneLoading and not entered do
	task.wait()
end

if not entered then
	local elapsed = os.clock() - startClock
	if elapsed < MIN_DISPLAY_TIME then
		task.wait(MIN_DISPLAY_TIME - elapsed)
	end
end

if not entered then
	setButtonText(PLAY_TEXT)
	actionButton.Visible = true

	-- Ya venía en pantalla como SKIP: el cambio se anuncia agrandándolo y
	-- desplegándolo hacia abajo, no apareciendo de la nada. Back Out le da el rebote.
	TweenService:Create(actionButton, TweenInfo.new(PLAY_BUTTON_REVEAL_SECONDS, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Size = scaleUDim2(buttonSize, PLAY_BUTTON_GROW),
		Position = buttonPosition + UDim2.new(0, 0, PLAY_BUTTON_DROP, 0),
	}):Play()
	tintButtonGreen()

	while not entered do
		task.wait()
	end
end

-- Recién acá es elegible para el juego: el servidor lo tenía como Loading
-- mientras miraba el menú. Antes del fade cosmético, que no cambia si está listo.
setLoadingComplete:FireServer()
-- DebugConfig.print("[LoadingScreen] SetLoadingComplete fired")

task.cancel(labelThread)

-- La música se desvanece durante el barrido en vez de cortarse de golpe.
if menuMusic then
	local music = menuMusic
	TweenService:Create(music, TweenInfo.new(MENU_MUSIC_FADEOUT, Enum.EasingStyle.Linear), { Volume = 0 }):Play()
	task.delay(MENU_MUSIC_FADEOUT, function()
		music:Destroy()
	end)
end

-- Ola de cierre: tapa la pantalla desde la izquierda y, bajo el negro, se swappea
-- el menú por el juego (cámara, HUD, se destruye la GUI) antes de revelar.
local wave = WaveTransition.create(playerGui)
ownGuis[wave.Gui] = true
wave.cover()

MenuCamera.stop()
if frozenHumanoid and frozenHumanoid.Parent then
	frozenHumanoid.WalkSpeed = savedWalkSpeed or frozenHumanoid.WalkSpeed
	frozenHumanoid.JumpPower = savedJumpPower or frozenHumanoid.JumpPower
end
restoreGameGuis()
gui:Destroy()

wave.reveal()
DebugConfig.print("[LoadingScreen] Done (" .. string.format("%.2f", os.clock() - startClock) .. "s)")
