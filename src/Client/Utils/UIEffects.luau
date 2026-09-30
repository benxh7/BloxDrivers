-- Ubicación en Studio: StarterPlayer > StarterPlayerScripts > Utils > UIEffects (ModuleScript)
--
-- Efectos y helpers de UI compartidos por TODOS los controllers: animación de
-- ventanas (popIn / popOut), "pop" de botón, sonidos de click y búsqueda tolerante
-- de hijos armados en Studio. Solo cliente.
--
-- Todas las animaciones van por UIScale y no por Size/Position: no pelean con
-- UIAspectRatioConstraint, UIListLayout ni con el diseño en Scale de Studio.
-- OJO: Roblox aplica UN solo UIScale por objeto. No pongas un UIScale propio en el
-- Frame `Main` de una ventana ni en un botón: UIEffects crea y usa el suyo.
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local ContentProvider = game:GetService("ContentProvider")
local Debris = game:GetService("Debris")
local UserInputService = game:GetService("UserInputService")

local DebugConfig = require(ReplicatedStorage:WaitForChild("DebugConfig"))

local UIEffects = {}

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- ─── Ajustes ────────────────────────────────────────────────────────────────────

-- Mismo asset que UBG a pedido (si da error de permisos, resubirlo a esta cuenta).
UIEffects.ClickSoundId = "rbxassetid://103282937573040"
UIEffects.ClickVolume = 0.5

-- "Pop" de botón: cuánto crece y cuánto tarda cada mitad del rebote.
UIEffects.PopScale = 1.12
UIEffects.PopDuration = 0.09

-- Hover (UIEffects.bindHover): escala por defecto y duración del tween.
UIEffects.HoverScale = 1.06
UIEffects.HoverDuration = 0.14

-- Ventanas: desde qué escala entran / hacia cuál salen, y cuánto tardan.
UIEffects.WindowHiddenScale = 0.85
UIEffects.WindowOpenDuration = 0.22
UIEffects.WindowCloseDuration = 0.14

-- Cuánto vive un clon de playOneShot antes de que Debris lo borre.
UIEffects.OneShotLifetime = 10

local POP_OUT = TweenInfo.new(UIEffects.PopDuration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local POP_IN = TweenInfo.new(UIEffects.PopDuration, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
local HOVER = TweenInfo.new(UIEffects.HoverDuration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local WINDOW_OPEN = TweenInfo.new(UIEffects.WindowOpenDuration, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local WINDOW_CLOSE = TweenInfo.new(UIEffects.WindowCloseDuration, Enum.EasingStyle.Quad, Enum.EasingDirection.In)

local WINDOW_SCALE_NAME = "WindowScale"
local POP_SCALE_NAME = "PopScale"

local function getScale(object: GuiObject, name: string): UIScale
	local scale = object:FindFirstChild(name)
	if scale and scale:IsA("UIScale") then
		return scale
	end
	local created = Instance.new("UIScale")
	created.Name = name
	created.Parent = object
	return created
end

-- ─── Sonidos ────────────────────────────────────────────────────────────────────

-- Uno solo, reutilizable y precargado: creando un Sound por click, el primero
-- esperaba a que el asset cargara y sonaba tarde.
local clickSound = Instance.new("Sound")
clickSound.Name = "UIClick"
clickSound.SoundId = UIEffects.ClickSoundId
clickSound.Volume = UIEffects.ClickVolume
clickSound.Parent = SoundService

task.spawn(function()
	local ok, err = pcall(ContentProvider.PreloadAsync, ContentProvider, { clickSound })
	if not ok then
		DebugConfig.warn("[UIEffects] No se pudo precargar el click: " .. tostring(err))
	end
end)

function UIEffects.playClickSound()
	clickSound:Play()
end

-- Sonido suelto que se destruye solo al terminar.
function UIEffects.playSound(soundId: string, volume: number?)
	if soundId == "" or soundId == "rbxassetid://0" then
		return
	end
	local sound = Instance.new("Sound")
	sound.SoundId = soundId
	sound.Volume = volume or 0.5
	sound.Parent = playerGui
	sound.Ended:Once(function()
		sound:Destroy()
	end)
	sound:Play()
end

-- Crea un Sound reutilizable en SoundService (nil si el ID está vacío).
function UIEffects.makeSound(name: string, soundId: string, volume: number): Sound?
	if soundId == "" or soundId == "rbxassetid://0" then
		return nil
	end
	local sound = Instance.new("Sound")
	sound.Name = name
	sound.SoundId = soundId
	sound.Volume = volume
	sound.Parent = SoundService
	return sound
end

-- Para sonidos que se pisan entre sí: un :Play() sobre el MISMO Sound que todavía
-- suena reinicia el clip, así que va un clon descartable.
function UIEffects.playOneShot(sound: Sound?)
	if not sound then
		return
	end
	local clone = sound:Clone()
	clone.Parent = SoundService
	clone:Play()
	Debris:AddItem(clone, UIEffects.OneShotLifetime)
end

-- ─── Botones ────────────────────────────────────────────────────────────────────

local popping: { [GuiObject]: boolean } = {}
-- Escala de reposo de cada botón con hover activo (sin entrada = 1). El pop del click
-- crece desde acá y vuelve acá, así hover y click comparten el mismo UIScale.
local hoverBase: { [GuiObject]: number } = {}

function UIEffects.popButton(button: GuiObject)
	if popping[button] then
		return
	end
	popping[button] = true

	local scale = getScale(button, POP_SCALE_NAME)
	local grow = TweenService:Create(scale, POP_OUT, { Scale = (hoverBase[button] or 1) * UIEffects.PopScale })
	grow.Completed:Once(function()
		local back = TweenService:Create(scale, POP_IN, { Scale = hoverBase[button] or 1 })
		back.Completed:Once(function()
			popping[button] = nil
		end)
		back:Play()
	end)
	grow:Play()
end

-- Conecta un botón con click + pop + callback. `Activated` cubre mouse, touch y
-- gamepad, así que funciona igual en PC y celular. Devuelve la conexión.
function UIEffects.bindButton(button: GuiButton, callback: () -> ()): RBXScriptConnection
	return button.Activated:Connect(function()
		UIEffects.playClickSound()
		UIEffects.popButton(button)
		callback()
	end)
end

export type HoverOptions = {
	-- Escala con el mouse encima (default UIEffects.HoverScale).
	Scale: number?,
	-- Grados que gira hacia la derecha con el mouse encima (default 0 = no gira).
	Rotation: number?,
	-- Qué objeto gira (default el mismo botón). Ej. solo el ícono de un botón del HUD.
	RotateTarget: GuiObject?,
	-- Objeto que solo se ve con el mouse encima (ej. el marco detrás de un ícono): un
	-- CanvasGroup (usa GroupTransparency) o un ImageLabel (ImageTransparency). Con hover
	-- toma la transparencia que tiene en Studio; en reposo queda invisible.
	Reveal: (CanvasGroup | ImageLabel)?,
}

-- Hover: crece un poco y (opcional) gira hacia la derecha; vuelve al salir el mouse.
-- En pantallas solo táctiles no se conecta: sin mouse, MouseLeave no llega nunca y el
-- botón quedaría agrandado.
function UIEffects.bindHover(object: GuiObject, options: HoverOptions?)
	local opts: HoverOptions = options or {}
	local reveal = opts.Reveal
	local revealProperty = if reveal and reveal:IsA("CanvasGroup") then "GroupTransparency" else "ImageTransparency"
	local revealTransparency = if reveal then (reveal :: any)[revealProperty] else 1
	if reveal then
		(reveal :: any)[revealProperty] = 1
	end
	if UserInputService.TouchEnabled and not UserInputService.MouseEnabled then
		return
	end
	local hoverScale = opts.Scale or UIEffects.HoverScale
	local rotation = opts.Rotation or 0
	local target = opts.RotateTarget or object
	local baseRotation = target.Rotation
	local scale = getScale(object, POP_SCALE_NAME)

	local function setHovered(hovered: boolean)
		if reveal then
			TweenService:Create(reveal, HOVER, { [revealProperty] = if hovered then revealTransparency else 1 }):Play()
		end
		hoverBase[object] = if hovered then hoverScale else nil
		-- Si hay un pop en curso, él mismo vuelve a la escala nueva al terminar.
		if not popping[object] then
			TweenService:Create(scale, HOVER, { Scale = hoverBase[object] or 1 }):Play()
		end
		if rotation ~= 0 then
			TweenService:Create(target, HOVER, { Rotation = baseRotation + (if hovered then rotation else 0) }):Play()
		end
	end

	object.MouseEnter:Connect(function()
		setHovered(true)
	end)
	object.MouseLeave:Connect(function()
		setHovered(false)
	end)
end

-- ─── Ventanas ───────────────────────────────────────────────────────────────────

local windowTweens: { [GuiObject]: Tween } = {}

-- Cancela el tween anterior de la misma ventana: abrir/cerrar rápido nunca deja la
-- ventana a medio camino ni ejecuta el "ocultar" de un cierre ya reemplazado.
local function playWindowTween(frame: GuiObject, info: TweenInfo, goal: number, onCompleted: (() -> ())?)
	local previous = windowTweens[frame]
	if previous then
		previous:Cancel()
	end

	local tween = TweenService:Create(getScale(frame, WINDOW_SCALE_NAME), info, { Scale = goal })
	windowTweens[frame] = tween
	tween.Completed:Once(function(state: Enum.PlaybackState)
		if windowTweens[frame] == tween then
			windowTweens[frame] = nil
		end
		if state == Enum.PlaybackState.Completed and onCompleted then
			onCompleted()
		end
	end)
	tween:Play()
end

-- Muestra la ventana creciendo con un rebote.
function UIEffects.popIn(frame: GuiObject)
	if not frame.Visible then
		getScale(frame, WINDOW_SCALE_NAME).Scale = UIEffects.WindowHiddenScale
		frame.Visible = true
	end
	playWindowTween(frame, WINDOW_OPEN, 1)
end

-- Achica la ventana y la oculta al terminar. `onHidden` corre solo si el cierre
-- terminó de verdad (no si un popIn lo interrumpió).
function UIEffects.popOut(frame: GuiObject, onHidden: (() -> ())?)
	if not frame.Visible then
		if onHidden then
			onHidden()
		end
		return
	end
	playWindowTween(frame, WINDOW_CLOSE, UIEffects.WindowHiddenScale, function()
		frame.Visible = false
		if onHidden then
			onHidden()
		end
	end)
end

-- ─── Búsqueda de hijos armados en Studio ────────────────────────────────────────

-- WaitForChild con timeout + warn: un nombre que no coincide EXACTO con lo armado en
-- Studio no debe colgar el script sin aviso.
function UIEffects.findChild(parent: Instance, name: string, tag: string?): Instance?
	local child = parent:WaitForChild(name, 5)
	if not child then
		DebugConfig.warn(("[%s] No se encontró '%s' dentro de '%s'"):format(tag or "UI", name, parent:GetFullName()))
	end
	return child
end

return UIEffects
