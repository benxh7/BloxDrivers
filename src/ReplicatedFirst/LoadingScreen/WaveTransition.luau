-- Ubicación en Studio: ReplicatedFirst > LoadingScreen > WaveTransition (ModuleScript)
-- Ola negra que tapa entrando por la izquierda y revela saliendo por la derecha.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local SoundService = game:GetService("SoundService")
local ContentProvider = game:GetService("ContentProvider")

local WaveTransitionConfig = require(ReplicatedStorage:WaitForChild("WaveTransitionConfig"))

-- El borde curvo sale de N tiras horizontales que se mueven juntas: angostas en el
-- centro y anchas en los extremos.
local WaveTransition = {}

local COVER_DURATION = 0.5
local REVEAL_DURATION = 0.65
-- Negro pleno antes de revelar: da lugar a cambiar la escena debajo.
local HOLD_DURATION = 0.12

-- Más tiras = borde menos escalonado. Son Frames baratos.
local STRIP_COUNT = 120
-- Cuánto sobresale la curva, en fracción del ancho de pantalla.
local CURVE_AMOUNT = 0.18
-- >1 para pasarse de los costados: en teléfonos el borde físico queda fuera del área segura.
local BASE_WIDTH = 1.25
-- Overscan solo abajo (fracción del alto): arriba ya tapa completo.
local BOTTOM_OVERSCAN = 0.12
-- Solape vertical: sin él queda una línea entre tiras.
local STRIP_OVERLAP = 0.2

local COLOR = Color3.new(0, 0, 0)
local EASING_STYLE = Enum.EasingStyle.Quad
local EASING_DIRECTION = Enum.EasingDirection.InOut

-- Centro de las tiras: afuera a la izquierda, centrado, afuera a la derecha (contando la
-- tira más ancha).
local COVER_START = -(BASE_WIDTH + CURVE_AMOUNT) / 2
local COVERED = 0.5
local REVEAL_END = 1 + (BASE_WIDTH + CURVE_AMOUNT) / 2

-- Uno solo y precargado: uno por uso haría esperar al asset en el primer play.
local sweepSound: Sound? = nil
if WaveTransitionConfig.SoundId ~= "" and WaveTransitionConfig.SoundId ~= "rbxassetid://0" then
	local sound = Instance.new("Sound")
	sound.Name = "WaveSweep"
	sound.SoundId = WaveTransitionConfig.SoundId
	sound.Volume = WaveTransitionConfig.SoundVolume
	sound.Parent = SoundService
	sweepSound = sound

	task.spawn(function()
		pcall(function()
			ContentProvider:PreloadAsync({ sound })
		end)
	end)
end

local function playSweep()
	if sweepSound then
		sweepSound:Play()
	end
end

export type Handle = {
	Gui: ScreenGui,
	cover: () -> (),
	reveal: () -> (),
}

-- La GUI se crea ya: el llamador la excluye de su lógica de ocultar HUDs antes de cover().
function WaveTransition.create(parent: Instance): Handle
	local gui = Instance.new("ScreenGui")
	gui.Name = "WaveTransition"
	gui.IgnoreGuiInset = true
	-- Sin esto se recorta al área segura y en teléfonos con notch no llega al borde.
	-- pcall: propiedad nueva del motor.
	pcall(function()
		gui.ScreenInsets = Enum.ScreenInsets.None
	end)
	-- Por encima de la LoadingGui (1000) y del iris (900).
	gui.DisplayOrder = 2000
	gui.ResetOnSpawn = false
	gui.Parent = parent

	local strips: { Frame } = {}
	local stripY: { number } = {}
	local span = 1 + BOTTOM_OVERSCAN
	for i = 1, STRIP_COUNT do
		local yc = ((i - 0.5) / STRIP_COUNT) * span
		-- Por la posición real en pantalla, no por índice: la curva queda centrada aunque
		-- haya overscan abajo.
		local shape = math.sin(math.pi * math.clamp(yc, 0, 1))
		local width = BASE_WIDTH + CURVE_AMOUNT * (1 - shape)

		local strip = Instance.new("Frame")
		strip.Name = "Strip" .. i
		strip.BackgroundColor3 = COLOR
		strip.BorderSizePixel = 0
		strip.AnchorPoint = Vector2.new(0.5, 0.5)
		strip.Size = UDim2.fromScale(width, (span / STRIP_COUNT) * (1 + STRIP_OVERLAP))
		strip.Position = UDim2.fromScale(COVER_START, yc)
		strip.Parent = gui

		strips[i] = strip
		stripY[i] = yc
	end

	-- TweenService no interpola una posición calculada: se tweenea este valor.
	local driver = Instance.new("NumberValue")
	driver.Value = COVER_START
	driver:GetPropertyChangedSignal("Value"):Connect(function()
		local cx = driver.Value
		for i, strip in strips do
			strip.Position = UDim2.fromScale(cx, stripY[i])
		end
	end)

	local function tweenTo(target: number, duration: number)
		local info = TweenInfo.new(duration, EASING_STYLE, EASING_DIRECTION)
		local tween = TweenService:Create(driver, info, { Value = target })
		tween:Play()
		tween.Completed:Wait()
	end

	local handle: Handle = {
		Gui = gui,
		cover = function()
			playSweep()
			tweenTo(COVERED, COVER_DURATION)
			if HOLD_DURATION > 0 then
				task.wait(HOLD_DURATION)
			end
		end,
		reveal = function()
			playSweep()
			tweenTo(REVEAL_END, REVEAL_DURATION)
			gui:Destroy()
		end,
	}
	return handle
end

return WaveTransition
