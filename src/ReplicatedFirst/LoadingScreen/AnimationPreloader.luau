local Players = game:GetService("Players")

-- `PreloadAsync` reporta OK sobre un AnimationId sin bajar nada: la única forma de
-- cachear una animación es pasarla por LoadAnimation en un Animator de verdad.
local AnimationPreloader = {}

local localPlayer = Players.LocalPlayer

-- Corremos desde el menú, así que el personaje ya debería existir; igual se espera
-- por si la carga fue más rápida que el spawn.
local ANIMATOR_TIMEOUT = 20

local function waitForAnimator(): Animator?
	local deadline = os.clock() + ANIMATOR_TIMEOUT
	repeat
		local character = localPlayer.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
		if animator then return animator :: Animator end
		task.wait(0.2)
	until os.clock() > deadline
	return nil
end

-- Carga cada animación una vez para que quede en el caché del cliente. BLOQUEA
-- hasta terminar: llamar desde una corrutina. Devuelve cuántas se cargaron.
function AnimationPreloader.preload(ids: { string }, onProcessed: (() -> ())?): number
	if #ids == 0 then return 0 end

	local animator = waitForAnimator()
	if not animator then
		-- Sin Animator no hay forma de cachearlas; el que llama sigue igual.
		if onProcessed then
			for _ = 1, #ids do
				onProcessed()
			end
		end
		return 0
	end

	local loaded = 0
	for _, id in ids do
		local animation = Instance.new("Animation")
		animation.AnimationId = id

		-- En pcall: un ID mal escrito o de otro dueño no debe cortar la tanda.
		local ok, track = pcall(function()
			return animator:LoadAnimation(animation)
		end)
		if ok and track then
			-- El track se descarta, pero el ASSET ya quedó cacheado para la sesión.
			track:Destroy()
			loaded += 1
		end
		animation:Destroy()

		if onProcessed then
			onProcessed()
		end
	end

	return loaded
end

return AnimationPreloader
