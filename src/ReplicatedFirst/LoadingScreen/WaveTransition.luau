local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local SoundService = game:GetService("SoundService")
local ContentProvider = game:GetService("ContentProvider")

local WaveTransitionConfig = require(ReplicatedStorage:WaitForChild("WaveTransitionConfig"))

-- Ola de cierre del menú de carga: un frente negro que entra desde la IZQUIERDA
-- tapando toda la pantalla (cover), y sale por la DERECHA revelando el juego
-- (reveal).
--
-- El borde NO es recto sino una lente (||||||||) : se arma con N tiras horizontales,
-- angostas en el centro de la pantalla y anchas en los extremos. Como todas se mueven
-- juntas pero con distinto ancho, la del medio va atrás (borde ( al tapar) y adelante
-- (borde ) al revelar).
local WaveTransition = {}

-- Un poquito más lento que un barrido recto para que se lea la curva.
local COVER_DURATION = 0.5
local REVEAL_DURATION = 0.65
-- Negro pleno un instante antes de revelar: da lugar a swappear la escena debajo.
local HOLD_DURATION = 0.12

-- Cantidad de tiras: el borde curvo es una escalera de N escalones, así que MÁS
-- tiras = menos pixelado. Son Frames baratos (una property por tick), no escatimes.
local STRIP_COUNT = 120
-- Cuánto sobresale la panza del centro, en fracción del ANCHO de pantalla.
local CURVE_AMOUNT = 0.18
-- Ancho base de cada tira (1 = pantalla entera). >1 para pasarse por izquierda y
-- derecha: en teléfonos el borde físico queda fuera del área segura.
local BASE_WIDTH = 1.25
-- Cuánto se pasa la ola por ABAJO (fracción del alto). Arriba ya tapa completo, así
-- que el overscan es solo hacia abajo.
local BOTTOM_OVERSCAN = 0.12
-- Las tiras se solapan un poco en vertical para que no quede una línea entre filas.
local STRIP_OVERLAP = 0.2

local COLOR = Color3.new(0, 0, 0)
local EASING_STYLE = Enum.EasingStyle.Quad
local EASING_DIRECTION = Enum.EasingDirection.InOut

-- Posiciones del centro (cx) de las tiras. Fuera de pantalla a izquierda / centrado
-- / fuera a derecha. El (BASE_WIDTH+CURVE_AMOUNT)/2 asegura que la tira más ancha
-- también quede completamente afuera en los extremos.
local COVER_START = -(BASE_WIDTH + CURVE_AMOUNT) / 2
local COVERED = 0.5
local REVEAL_END = 1 + (BASE_WIDTH + CURVE_AMOUNT) / 2

-- Uno solo y precargado: creando uno por uso, el primer play espera al asset.
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

-- Crea la GUI ya, así el llamador puede excluirla de su lógica de ocultar HUDs
-- ANTES de que cover() la use.
function WaveTransition.create(parent: Instance): Handle
	local gui = Instance.new("ScreenGui")
	gui.Name = "WaveTransition"
	gui.IgnoreGuiInset = true
	-- ScreenInsets None: sin esto la GUI se recorta al área segura y en teléfonos con
	-- notch/bordes queda más chica que la pantalla → la ola no llega al borde físico.
	-- En pcall porque es una propiedad relativamente nueva del motor.
	pcall(function()
		gui.ScreenInsets = Enum.ScreenInsets.None
	end)
	-- Por encima de la LoadingGui (1000) y del iris (900).
	gui.DisplayOrder = 2000
	gui.ResetOnSpawn = false
	gui.Parent = parent

	local strips: { Frame } = {}
	local stripY: { number } = {}
	-- Las tiras cubren de 0 (arriba) a 1+BOTTOM_OVERSCAN (pasándose por abajo).
	local span = 1 + BOTTOM_OVERSCAN
	for i = 1, STRIP_COUNT do
		local yc = ((i - 0.5) / STRIP_COUNT) * span
		-- shape según la posición REAL en pantalla (yc clampeado 0..1), no según el
		-- índice: así la panza de la lente queda centrada en el centro físico aunque
		-- haya overscan abajo. sin(pi*y): 1 en el centro, 0 en los bordes. Invertido con
		-- (1-shape) → angosto en el centro y ancho en los extremos, la lente (||||||||).
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

	-- NumberValue de por medio: TweenService no interpola una posición calculada.
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
