-- Ubicación en Studio: ReplicatedFirst > LoadingScreen > AnimationPreloader (ModuleScript)
local Players = game:GetService("Players")

-- PreloadAsync da OK sobre un AnimationId sin bajar nada: la única forma de cachear
-- una animación es un LoadAnimation en un Animator real.
local AnimationPreloader = {}

local localPlayer = Players.LocalPlayer

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

-- BLOQUEA hasta terminar (llamar desde una corrutina). Devuelve cuántas se cargaron.
function AnimationPreloader.preload(ids: { string }, onProcessed: (() -> ())?): number
	if #ids == 0 then return 0 end

	local animator = waitForAnimator()
	if not animator then
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

		-- Un ID mal escrito o de otro dueño no debe cortar la tanda.
		local ok, track = pcall(function()
			return animator:LoadAnimation(animation)
		end)
		if ok and track then
			-- El track se descarta; el asset queda cacheado igual.
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
