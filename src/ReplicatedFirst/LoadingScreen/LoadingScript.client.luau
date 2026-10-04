-- Ubicación en Studio: ReplicatedFirst > LoadingScreen > LoadingScript (LocalScript)
-- Pantalla de carga: precarga, menú con cámara y botón SKIP/PLAY, y la ola de cierre.
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local ContentProvider = game:GetService("ContentProvider")
local TweenService = game:GetService("TweenService")
local StarterGui = game:GetService("StarterGui")
local StarterPack = game:GetService("StarterPack")
local StarterPlayer = game:GetService("StarterPlayer")
local Lighting = game:GetService("Lighting")
local MaterialService = game:GetService("MaterialService")
local SoundService = game:GetService("SoundService")

-- WaitForChild: desde ReplicatedFirst, ReplicatedStorage puede no haber replicado todavía.
local DebugConfig = require(ReplicatedStorage:WaitForChild("DebugConfig"))
local PreloadAssets = require(ReplicatedStorage:WaitForChild("PreloadAssets"))
local MenuCameraConfig = require(ReplicatedStorage:WaitForChild("MenuCameraConfig"))
local MenuCamera = require(script.Parent:WaitForChild("MenuCamera"))
local PreloadRunner = require(script.Parent:WaitForChild("PreloadRunner"))
local Responsive = require(script.Parent:WaitForChild("Responsive"))
local WaveTransition = require(script.Parent:WaitForChild("WaveTransition"))
local Remotes = require(ReplicatedStorage:WaitForChild("Remotes"))
local setLoadingComplete = Remotes.event("SetLoadingComplete")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local startClock = os.clock()

ReplicatedFirst:RemoveDefaultLoadingScreen()

-- LoadingGui es una plantilla de Studio: se muestra un clon.
local template = script.Parent:WaitForChild("LoadingGui") :: ScreenGui
local gui = template:Clone()
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = false
gui.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets
gui.DisplayOrder = 1000
gui.Parent = playerGui

local background = gui:WaitForChild("Background") :: GuiObject
local center = background:WaitForChild("Center") :: Frame
local actionButton = center:WaitForChild("SkipButton") :: TextButton
local tipLabel = center:WaitForChild("TipFrame"):WaitForChild("TipLabel") :: TextLabel

local fitResponsive = Responsive.attach(gui)

-- Reemplazar con tips propios de BloxDrivers.
local TIPS = {
	"Tip: check the rewards menu for free bonuses.",
}

local LOADING_MESSAGES = {
	"Loading",
}

local SKIP_DELAY = 8
-- El porcentaje se refresca más seguido que la frase: sube en vivo debajo de ella.
local LABEL_REFRESH = 0.1
local LOADING_MESSAGE_SECONDS = 1.5
local TIP_SECONDS = 3.5
-- Probabilidad de que el próximo turno sea un tip y no una frase de carga.
local TIP_CHANCE = 0.3
local READY_TEXT = "Ready! (100%)"
-- En Studio la precarga es instantánea: sin mínimo, PLAY aparecería antes de ver nada.
local MIN_DISPLAY_TIME = 2
local SKIP_TEXT = "Skip Loading"
local PLAY_TEXT = "Play"
-- Al 100% se apaga el UIGradient del botón: multiplica al BackgroundColor3 y ensuciaría el verde.
local PLAY_BUTTON_COLOR = Color3.fromRGB(46, 204, 113)
local PLAY_BUTTON_TINT_SECONDS = 0.4
-- DROP en escala del padre.
local PLAY_BUTTON_GROW = 1.12
local PLAY_BUTTON_DROP = 0.035
local PLAY_BUTTON_REVEAL_SECONDS = 0.5
local HOVER_SCALE = 1.06
local HOVER_SECONDS = 0.15

-- Assets de UBG. Acá va una CANCIÓN en loop: el whoosh de la ola ya suena solo en
-- WaveTransition, y puesto acá sonaría en bucle toda la carga.
local MENU_MUSIC_ID = "rbxassetid://129514825232523"
local MENU_MUSIC_VOLUME = 0.5
local MENU_MUSIC_FADEOUT = 0.6
local CLICK_SOUND_ID = "rbxassetid://15675059323"
local CLICK_SOUND_VOLUME = 0.8

-- Logo: se busca por nombre; si no, el primer ImageLabel que no sea la textura del fondo.
local LOGO_NAME = "Logo"
-- Respiración: 0.06 = ±6%, y segundos por medio ciclo.
local LOGO_BREATH_SCALE = 0.06
local LOGO_BREATH_SECONDS = 3.5
-- Bamboleo: grados a cada lado. Tiempo distinto al de la respiración a propósito: no se
-- sincronizan y se ve orgánico.
local LOGO_TILT_DEGREES = 4
local LOGO_TILT_SECONDS = 4.5

-- DEBUG: simula una precarga lenta para ver SKIP -> PLAY. VOLVER A FALSE ANTES DE PUBLICAR.
local TEST_ASSETS = false
local TEST_ASSET_DURATION = 60

actionButton.Visible = false

local function isRealSound(id: string): boolean
	return id ~= "" and id ~= "rbxassetid://0"
end

-- En SoundService y no en la GUI: destruir la GUI no corta el fade de salida.
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

-- Uno solo y precargado: uno por click haría esperar al asset en el primer play.
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

-- Background es un Frame (no CanvasGroup): el fade va objeto por objeto según su clase.
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
		if not skip then
			return false
		end
		for _, excluded in skip do
			if instance == excluded or instance:IsDescendantOf(excluded) then
				return true
			end
		end
		return false
	end

	local function apply(instance: Instance)
		if isSkipped(instance) then
			return
		end
		local properties = FADE_PROPERTIES[instance.ClassName]
		if not properties then
			return
		end
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

	-- Un TextButton dibuja su Text ADEMÁS de sus hijos: con TextLabel propio, se vacía.
	actionButton.Text = if hasLabel then "" else text
end

local function scaleUDim2(size: UDim2, factor: number): UDim2
	return UDim2.new(size.X.Scale * factor, size.X.Offset * factor, size.Y.Scale * factor, size.Y.Offset * factor)
end

-- UIScale y no Size: PLAY ya tweenea su Size al desplegarse y el hover lo pisaría.
local function attachHover(button: GuiButton)
	-- Crece desde el AnchorPoint: descentrado, se estira hacia abajo y a la derecha.
	if button.AnchorPoint ~= Vector2.new(0.5, 0.5) then
		DebugConfig.warn(
			"[LoadingScreen] " .. button.Name .. ": poné AnchorPoint en 0.5, 0.5 para que crezca desde su centro"
		)
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

-- Mismos keypoints que el original: lerpSequence recorre las dos en paralelo.
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
	if not gradient then
		return
	end

	-- Se lleva a blanco (no tiñe) antes de apagarlo: si no, salto de color. ColorSequence
	-- no se puede tweenear: se interpola a mano.
	local from = gradient.Color
	local to = solidVersionOf(from, Color3.new(1, 1, 1))
	task.spawn(function()
		local startedAt = os.clock()
		while gradient.Parent do
			local alpha = math.min((os.clock() - startedAt) / PLAY_BUTTON_TINT_SECONDS, 1)
			gradient.Color = lerpSequence(from, to, alpha)
			if alpha >= 1 then
				break
			end
			task.wait()
		end
		-- Enabled y no Destroy: no se toca lo armado en Studio.
		gradient.Enabled = false
	end)
end

local animatedTexture = background:FindFirstChild("AnimatedTexture")

local function findLogo(): ImageLabel?
	local byName = gui:FindFirstChild(LOGO_NAME, true)
	if byName and byName:IsA("ImageLabel") then
		return byName
	end

	for _, descendant in gui:GetDescendants() do
		if descendant:IsA("ImageLabel") and not (animatedTexture and descendant:IsDescendantOf(animatedTexture)) then
			return descendant
		end
	end
	return nil
end

-- Sine InOut frena en los extremos: parece respiración y no un rebote.
local function animateLogo(logo: ImageLabel)
	-- Rotation gira alrededor del AnchorPoint: descentrado, el logo se desplaza en arco.
	if logo.AnchorPoint ~= Vector2.new(0.5, 0.5) then
		DebugConfig.warn(
			"[LoadingScreen] " .. logo.Name .. ": poné AnchorPoint en 0.5, 0.5 para que gire sobre su centro"
		)
	end

	-- UIScale y no Size: no pelea con UIAspectRatioConstraint ni con el layout del padre.
	local scale = logo:FindFirstChildOfClass("UIScale") or Instance.new("UIScale")
	scale.Parent = logo
	scale.Scale = 1 - LOGO_BREATH_SCALE
	TweenService
		:Create(
			scale,
			TweenInfo.new(LOGO_BREATH_SECONDS, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
			{
				Scale = 1 + LOGO_BREATH_SCALE,
			}
		)
		:Play()

	logo.Rotation = -LOGO_TILT_DEGREES
	TweenService
		:Create(logo, TweenInfo.new(LOGO_TILT_SECONDS, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), {
			Rotation = LOGO_TILT_DEGREES,
		})
		:Play()
end

local logo = findLogo()
if logo then
	animateLogo(logo)
else
	DebugConfig.warn(
		"[LoadingScreen] Sin imagen de menú: no hay ningún '" .. LOGO_NAME .. "' ni otro ImageLabel en LoadingGui"
	)
end

-- El logo puede colgar del Background: sin excluirlo, el fade de la escena 3D lo borraría.
local revealSkip: { Instance } = { center }
if logo then
	table.insert(revealSkip, logo)
end

local doneLoading = false
-- Hasta apretar el botón no se dispara SetLoadingComplete: el servidor lo ve como Loading.
local entered = false
local loadedAlpha = 0

local labelThread = task.spawn(function()
	local rng = Random.new()

	-- Al azar puro, la misma frase salía dos veces seguidas.
	local function pickDifferent(pool: { string }, current: string): string
		if #pool < 2 then
			return pool[1]
		end
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
			-- El thread sigue vivo a propósito: el task.cancel del cierre siempre tiene a quién.
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

		-- Tope 99: el 100% es de READY_TEXT, no aparece mientras PreloadAsync no volvió.
		local percent = math.min(math.floor(loadedAlpha * 100), 99)
		tipLabel.Text = string.format("%s (%d%%)", currentText, percent)
		task.wait(LABEL_REFRESH)
	end
end)

-- CoreGui que el juego controla (ej. la mochila). El menú corre ANTES que su dueño: si las
-- guardara, al restaurar prendería lo que el juego apagó.
local GAME_MANAGED_CORE_GUI = { [Enum.CoreGuiType.Backpack] = true }

local hiddenGuis: { [ScreenGui]: boolean } = {}
local enabledConns: { [ScreenGui]: RBXScriptConnection } = {}
local guiAddedConn: RBXScriptConnection? = nil
local coreGuiStates: { [Enum.CoreGuiType]: boolean } = {}

-- La ola de cierre se parentea con el watchdog todavía activo: no debe apagarla.
local ownGuis: { [Instance]: boolean } = { [gui] = true }

local function hideGui(instance: Instance)
	if ownGuis[instance] or not instance:IsA("ScreenGui") then
		return
	end
	local screenGui = instance :: ScreenGui
	hiddenGuis[screenGui] = screenGui.Enabled
	screenGui.Enabled = false

	-- Apagarla una vez no alcanza: su dueño la vuelve a prender.
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

	-- Uno por uno: SetCoreGuiEnabled(All, true) prendería lo que el juego dejó apagado.
	for _, coreType in Enum.CoreGuiType:GetEnumItems() do
		if coreType == Enum.CoreGuiType.All or GAME_MANAGED_CORE_GUI[coreType] then
			continue
		end
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

	-- Antes de restaurar: si no, cada Enabled = true se apagaría solo.
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

-- Se congela con WalkSpeed/JumpPower y no con ControlModule: no depende de que
-- StarterPlayerScripts tenga el PlayerModule insertado.
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

	-- Revalidado después de esperar: si entró mientras tanto, congelarlo lo trabaría adentro.
	if entered then
		return
	end

	savedWalkSpeed = humanoid.WalkSpeed
	savedJumpPower = humanoid.JumpPower
	humanoid.WalkSpeed = 0
	humanoid.JumpPower = 0
	frozenHumanoid = humanoid
end)

-- Si el lobby nunca replica, el fondo se queda puesto y el menú funciona igual.
task.spawn(function()
	if not MenuCamera.start() then
		DebugConfig.warn("[LoadingScreen] Sin punto de cámara en el lobby: se mantiene el fondo")
		return
	end
	if entered then
		MenuCamera.stop()
		return
	end
	fadeSubtree(background, MenuCameraConfig.RevealSeconds, revealSkip)
end)

-- Sin timeout duro: adelantarse es decisión del jugador.
task.delay(SKIP_DELAY, function()
	if entered or doneLoading then
		return
	end
	setButtonText(SKIP_TEXT)
	actionButton.Visible = true
end)

actionButton.Activated:Connect(function()
	if clickSound then
		clickSound:Play()
	end
	if entered then
		return
	end
	entered = true
	actionButton.Interactable = false
end)

if TEST_ASSETS then
	DebugConfig.warn(
		"[LoadingScreen] TEST_ASSETS activo — simulando una precarga de "
			.. TEST_ASSET_DURATION
			.. "s. Recordá volver a false antes de publicar."
	)
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
	task.spawn(function()
		if not game:IsLoaded() then
			game.Loaded:Wait()
		end
		local seen, ids = {}, {}
		local function add(id)
			id = PreloadAssets.normalize(id)
			if id and not seen[id] then
				seen[id] = true
				table.insert(ids, id)
			end
		end
		local roots = {
			ReplicatedStorage,
			ReplicatedFirst,
			StarterGui,
			playerGui,
			workspace,
			StarterPack,
			StarterPlayer,
			Lighting,
			SoundService,
			MaterialService,
		}
		for _, root in roots do
			PreloadAssets.forEachAssetId(root, add)
		end
		for _, id in PreloadAssets.collect() do
			add(id)
		end
		local manifest = ReplicatedStorage:WaitForChild("ServerAssetManifest", 15)
		local function manifestIds(callback)
			if not manifest then
				return
			end
			for line in manifest.Value:gmatch("[^\n]+") do
				local id, class, property = line:match("^([^\t]+)\t([^\t]+)\t([^\t]+)$")
				if id then
					PreloadAssets.Kinds[id] = { Class = class, Property = property }
					callback(id)
				else
					callback(line)
				end
			end
		end
		manifestIds(add)
		gui:SetAttribute("PreloadTotal", #ids)
		local result = PreloadRunner.Run(ids, function(processed, total, failed)
			loadedAlpha = if total > 0 then processed / total else 1
			if gui.Parent then
				gui:SetAttribute("PreloadProcessed", processed)
				gui:SetAttribute("PreloadFailed", failed)
			end
		end, 60)
		if result.Failed > 0 or result.TimedOut > 0 then
			READY_TEXT = "Ready — some assets will retry in game"
			warn(("[LoadingScreen] %d failed; %d pending"):format(result.Failed, result.TimedOut))
		end
		if gui.Parent then
			gui:SetAttribute("PreloadTimedOut", result.TimedOut)
			gui:SetAttribute("PreloadComplete", true)
		end
		doneLoading = true
		-- Lo que aparezca después se encola solo: no hay lista manual.
		local pending = {}
		local scheduled = false
		local function queue(id)
			id = PreloadAssets.normalize(id)
			if not id or seen[id] then
				return
			end
			seen[id] = true
			table.insert(pending, id)
			if scheduled then
				return
			end
			scheduled = true
			task.delay(0.5, function()
				while #pending > 0 do
					local batch = pending
					pending = {}
					PreloadRunner.Run(batch, function() end, 45)
				end
				scheduled = false
			end)
		end
		for _, root in roots do
			root.DescendantAdded:Connect(function(o)
				task.defer(function()
					PreloadAssets.scanInstance(o, queue)
				end)
			end)
			-- Lo que apareció durante la primera precarga.
			PreloadAssets.forEachAssetId(root, queue)
		end
		if manifest then
			manifest.Changed:Connect(function()
				manifestIds(queue)
			end)
		end
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
	fitResponsive()
	local buttonSize = actionButton.Size
	local buttonPosition = actionButton.Position
	gui:SetAttribute("LoadingReady", true)
	setButtonText(PLAY_TEXT)
	actionButton.Visible = true

	-- Ya estaba como SKIP: el cambio se anuncia agrandándolo, no apareciendo de la nada.
	TweenService
		:Create(
			actionButton,
			TweenInfo.new(PLAY_BUTTON_REVEAL_SECONDS, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
			{
				Size = scaleUDim2(buttonSize, PLAY_BUTTON_GROW),
				Position = buttonPosition + UDim2.new(0, 0, PLAY_BUTTON_DROP, 0),
			}
		)
		:Play()
	tintButtonGreen()

	while not entered do
		task.wait()
	end
end

-- Antes del fade: el fade es cosmético y no cambia si el jugador está listo.
setLoadingComplete:FireServer()

task.cancel(labelThread)

if menuMusic then
	local music = menuMusic
	TweenService:Create(music, TweenInfo.new(MENU_MUSIC_FADEOUT, Enum.EasingStyle.Linear), { Volume = 0 }):Play()
	task.delay(MENU_MUSIC_FADEOUT, function()
		music:Destroy()
	end)
end

-- Bajo el negro de la ola se cambia el menú por el juego antes de revelar.
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
