-- Ubicación en Studio: StarterPlayer > StarterPlayerScripts > Controllers > DialogueController (ModuleScript)
-- Ventana "Dialogue": al usar el prompt de un NPC muestra su retrato 3D y escribe sus líneas.
-- Click/tap/Enter/Espacio/A: si escribe, completa la línea; si no, pasa a la siguiente o cierra.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ProximityPromptService = game:GetService("ProximityPromptService")
local CollectionService = game:GetService("CollectionService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local UIManager = require(script.Parent:WaitForChild("UIManager"))
local Utils = script.Parent.Parent:WaitForChild("Utils")
local UIEffects = require(Utils:WaitForChild("UIEffects"))
local UITemplates = require(Utils:WaitForChild("UITemplates"))
local AnimatedDialogueText = require(Utils:WaitForChild("AnimatedDialogueText"))
local Config = require(ReplicatedStorage:WaitForChild("DialogueConfig"))
local NPCConfig = require(ReplicatedStorage:WaitForChild("NPCConfig"))

local DialogueController = {}

local GUI_NAME = "DialogueGui"
local GLYPH_TEMPLATE = "DialogueGlyph"
-- El prompt se usa a Prompt.Distance; este margen cubre que el jugador siga caminando.
local OPEN_DISTANCE_MARGIN = 3
-- Px que el panel suma por encima del alto del texto (nombre, hint y bordes).
local PANEL_CHROME = 92
local TEXT_AREA_PADDING = 14
-- Balanceo procedural del retrato (radianes y velocidades).
local SWAY = { Shoulder = math.rad(5), Neck = math.rad(3), Body = math.rad(1.4) }

local player = Players.LocalPlayer
local gui, main, stage, panel, portrait
local text, voice
local panelBaseSize: UDim2
local npc: Model? = nil
local entry: Config.Entry? = nil
local lineIndex = 1
local clock = 0
local frameConnection: RBXScriptConnection? = nil

local portraitModel: Model? = nil
local portraitTrack: AnimationTrack? = nil
local joints: { { Joint: Motor6D, Rest: CFrame } } = {}

local function isOpen(): boolean
	return UIManager.IsOpen(Config.WindowName)
end

local function rootPosition(): Vector3?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return root and (root :: BasePart).Position
end

local function clearPortrait()
	if portraitTrack then
		portraitTrack:Stop()
		portraitTrack = nil
	end
	if portraitModel then
		portraitModel:Destroy()
		portraitModel = nil
	end
	table.clear(joints)
end

-- Encuadra al NPC entero según el FOV y la proporción del ViewportFrame.
local function fitPortrait()
	local camera = portrait.CurrentCamera
	if not (portraitModel and camera) then
		return
	end
	local settings = Config.Portrait
	local box, size = portraitModel:GetBoundingBox()
	local center = box.Position + Vector3.new(0, size.Y * settings.VerticalFocus, 0)
	local aspect = math.max(0.3, portrait.AbsoluteSize.X / math.max(1, portrait.AbsoluteSize.Y))
	local tangent = math.tan(math.rad(settings.FieldOfView / 2))
	local distance = math.max(size.Y / 2 / tangent, size.X / 2 / (tangent * aspect)) * settings.FramingScale
	camera.CFrame = CFrame.lookAt(center + Vector3.new(0, 0, -distance), center)
end

local function idleAnimationFor(source: Model): string
	local id = entry and entry.IdleAnimation or ""
	if id == "" then
		id = Config.Portrait.IdleAnimation
	end
	if id == "" then
		id = NPCConfig.get(source).IdleAnimation
	end
	return id
end

-- Copia local del NPC dentro del WorldModel: sin scripts, prompts ni sonidos, y quieta.
local function createPortrait(source: Model)
	clearPortrait()
	-- Clone devuelve nil si Archivable es false; se restaura enseguida.
	local archivable = source.Archivable
	source.Archivable = true
	local copy = source:Clone()
	source.Archivable = archivable
	copy.Name = "PortraitNPC"
	for _, item in copy:GetDescendants() do
		if item:IsA("LuaSourceContainer") or item:IsA("ProximityPrompt") or item:IsA("Sound") or item:IsA("BillboardGui") then
			item:Destroy()
		elseif item:IsA("BasePart") then
			item.CanCollide = false
			item.Anchored = item.Name == "HumanoidRootPart"
		elseif item:IsA("Motor6D") then
			table.insert(joints, { Joint = item, Rest = item.C0 })
		end
	end
	local humanoid = copy:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	end
	-- Se orienta por el HumanoidRootPart, no por el pivot del Model: el pivot de un NPC puede
	-- apuntar a otro lado que su cuerpo y el retrato quedaba girado. Su frente (-Z) mira a la cámara.
	local facing = CFrame.Angles(0, math.rad(Config.Portrait.YawDegrees), 0)
	local root = copy:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		local rootOffset = copy:GetPivot():ToObjectSpace(root.CFrame.Rotation + copy:GetPivot().Position)
		copy:PivotTo(facing * rootOffset:Inverse())
	else
		copy:PivotTo(facing)
	end
	copy.Parent = portrait.WorldModel
	portraitModel = copy

	local animationId = idleAnimationFor(source)
	if humanoid and animationId:match("%d+") then
		local animator = humanoid:FindFirstChildOfClass("Animator") or Instance.new("Animator")
		animator.Parent = humanoid
		local animation = Instance.new("Animation")
		animation.AnimationId = animationId
		local ok, track = pcall(animator.LoadAnimation, animator, animation)
		animation:Destroy()
		if ok then
			portraitTrack = track
			track.Looped = true
			track:Play()
		end
	end
	fitPortrait()
end

-- El panel crece hacia arriba si el texto no entra en el alto diseñado en Studio.
local function layoutText()
	local contentHeight = text:Layout()
	if not contentHeight then
		return
	end
	local baseHeight = stage.AbsoluteSize.Y * panelBaseSize.Y.Scale + panelBaseSize.Y.Offset
	local extra = math.max(0, contentHeight + PANEL_CHROME - baseHeight)
	panel.Size = UDim2.new(panelBaseSize.X, UDim.new(panelBaseSize.Y.Scale, panelBaseSize.Y.Offset + extra))
	panel.TextArea.Size = UDim2.new(panel.TextArea.Size.X, UDim.new(0, contentHeight + TEXT_AREA_PADDING))
end

local function updateHint()
	local current = entry
	if not current then
		return
	end
	panel.Hint.Text = if not text:IsFinished()
		then "(Tap to skip)"
		elseif lineIndex < #current.Lines then "(Click/Tap to continue)"
		else "(Click/Tap to close)"
end

local function showLine()
	local current = entry
	if not current then
		return
	end
	text:Set(current.Lines[lineIndex])
	layoutText()
	fitPortrait()
	updateHint()
end

function DialogueController.Close()
	UIManager.Close(Config.WindowName)
end

local function advance()
	local current = entry
	if not (isOpen() and current) then
		return
	end
	if not text:IsFinished() then
		text:Skip()
		voice:Stop()
		updateHint()
	elseif lineIndex < #current.Lines then
		lineIndex += 1
		showLine()
	else
		DialogueController.Close()
	end
end

-- `pitch` lo da el texto: 1 en letras, DotPitch en los puntos de "...".
local function speak(pitch: number)
	local settings = Config.Voice
	voice.PlaybackSpeed = settings.Pitch * pitch * (1 + (math.random() * 2 - 1) * settings.PitchVariation)
	voice.TimePosition = 0
	voice:Play()
end

local function animateSway()
	if not Config.Portrait.ProceduralIdle or (portraitTrack and portraitTrack.IsPlaying) then
		return
	end
	local wave = math.sin(clock * 1.9)
	for _, item in joints do
		local name = item.Joint.Name:lower()
		local pitch = if name:find("shoulder") then SWAY.Shoulder * wave
			elseif name:find("neck") then SWAY.Neck * math.sin(clock * 1.25)
			else SWAY.Body * wave
		local roll = if name:find("shoulder") then math.rad(4) * math.sin(clock * 1.3) else 0
		item.Joint.C0 = item.Rest * CFrame.Angles(pitch, 0, roll)
	end
end

-- Conectado solo con la ventana abierta.
local function onFrame(dt: number)
	clock += dt
	local source = npc
	local position = rootPosition()
	local tooFar = position and source and (position - source:GetPivot().Position).Magnitude > Config.CloseDistance
	if not (source and source:IsDescendantOf(Workspace) and position) or tooFar then
		DialogueController.Close()
		return
	end
	text:Update(dt)
	updateHint()
	animateSway()
end

local function open(source: Model)
	-- Con la pantalla de carga encima, el diálogo se abriría detrás y el clic en PLAY lo avanzaría.
	if isOpen() or player:GetAttribute("LoadingComplete") ~= true then
		return
	end
	local found = Config.get(source)
	local position = rootPosition()
	if not (found and position) then
		return
	end
	if (position - source:GetPivot().Position).Magnitude > Config.Prompt.Distance + OPEN_DISTANCE_MARGIN then
		return
	end
	npc = source
	entry = found
	lineIndex = 1
	clock = 0
	panel.NPCName.Text = found.Name or source.Name
	UIManager.Open(Config.WindowName)
	createPortrait(source)
	portrait.ImageTransparency = 1
	TweenService:Create(portrait, TweenInfo.new(Config.Portrait.FadeIn), { ImageTransparency = 0 }):Play()
	frameConnection = RunService.RenderStepped:Connect(onFrame)
	showLine()
end

local function onPromptTriggered(prompt: ProximityPrompt, who: Player)
	if who ~= player or prompt.Name ~= Config.PromptName then
		return
	end
	local source = prompt:FindFirstAncestorOfClass("Model")
	if source and CollectionService:HasTag(source, Config.Tag) then
		open(source)
	end
end

local ADVANCE_KEYS = {
	[Enum.KeyCode.Return] = true,
	[Enum.KeyCode.Space] = true,
	[Enum.KeyCode.ButtonA] = true,
}

local function onInput(input: InputObject, processed: boolean)
	if processed or not isOpen() or UserInputService:GetFocusedTextBox() then
		return
	end
	local isClick = input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch
	if isClick or ADVANCE_KEYS[input.KeyCode] then
		advance()
	end
end

function DialogueController.Init()
	gui = UIManager.WaitForGui(GUI_NAME)
	if not gui then
		return
	end
	main = gui:WaitForChild("Main")
	stage = main:WaitForChild("Stage")
	panel = stage:WaitForChild("Panel")
	portrait = stage:WaitForChild("Portrait")
	panelBaseSize = panel.Size

	local template = UITemplates.get(GLYPH_TEMPLATE)
	if not template then
		return
	end
	-- Mismo ritmo y voz que los anuncios: cuenta solo letras y los "..." suenan punto por punto.
	text = AnimatedDialogueText.new(panel.TextArea, template :: TextLabel, Config.Typing, Config.Voice.SoundEvery)
	text.OnSpeak = speak
	voice = UIEffects.makeSound("DialogueVoice", Config.Voice.Sound, Config.Voice.Volume)
		or Instance.new("Sound")

	local camera = Instance.new("Camera")
	camera.FieldOfView = Config.Portrait.FieldOfView
	camera.Parent = portrait
	portrait.CurrentCamera = camera

	-- Sin pop: el diálogo aparece en su lugar, sobre el juego, sin blur.
	UIManager.Register(Config.WindowName, main, { Animate = false, CloseOnButtonB = true })
	UIManager.OnClosed(Config.WindowName, function()
		if frameConnection then
			frameConnection:Disconnect()
			frameConnection = nil
		end
		npc = nil
		entry = nil
		voice:Stop()
		text:Clear()
		clearPortrait()
	end)

	panel.Advance.Activated:Connect(advance)
	ProximityPromptService.PromptTriggered:Connect(onPromptTriggered)
	UserInputService.InputBegan:Connect(onInput)
	player.CharacterAdded:Connect(DialogueController.Close)
	-- En carrera no hay diálogos (mismo atributo que usa NPCZoneController).
	player:GetAttributeChangedSignal("InRound"):Connect(function()
		if player:GetAttribute("InRound") then
			DialogueController.Close()
		end
	end)
	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		if isOpen() then
			layoutText()
			fitPortrait()
		end
	end)
end

return DialogueController
