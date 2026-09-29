local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local NPCConfig = require(ReplicatedStorage.NPCConfig)
local DebugConfig = require(ReplicatedStorage.DebugConfig)

-- Idle de cada NPC. Corre en el SERVIDOR porque una animación cargada acá replica
-- sola: todos ven al NPC en la MISMA pose, en vez de que cada cliente la arranque
-- cuando le llega y queden desfasados entre sí.

local tracks: { [Model]: AnimationTrack } = {}

local function logState(model: Model, track: AnimationTrack)
	DebugConfig.print(("[NPCAnimations] Playing %s isPlaying: %s"):format(model.Name, tostring(track.IsPlaying)))
end

local function setupNPC(model: Model)
	local settings = NPCConfig.get(model)
	-- Sin idle no es un error: el NPC simplemente se queda quieto.
	if settings.IdleAnimation == "" then
		-- DebugConfig.print(("[NPCAnimations] %s sin animación de idle"):format(model.Name))
		return
	end

	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		DebugConfig.warn(("[NPCAnimations] %s no tiene Humanoid"):format(model.Name))
		return
	end

	-- El Animator es el que reproduce de verdad; Humanoid:LoadAnimation está deprecado
	-- y sin Animator la animación no replica a los clientes.
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = humanoid
	end

	local animation = Instance.new("Animation")
	animation.AnimationId = settings.IdleAnimation

	-- Una animación de otro dueño no carga y tira error: el NPC se queda quieto, pero
	-- el resto tiene que seguir andando.
	local ok, track = pcall(function()
		return animator:LoadAnimation(animation)
	end)
	if not ok or not track then
		DebugConfig.warn(("[NPCAnimations] %s: no cargó %s"):format(model.Name, settings.IdleAnimation))
		return
	end

	track.Looped = true
	track.Priority = Enum.AnimationPriority.Idle
	track:Play()

	tracks[model] = track
	logState(model, track)
end

local function teardownNPC(model: Model)
	local track = tracks[model]
	if track then
		track:Stop()
		tracks[model] = nil
	end
end

NPCConfig.observe(setupNPC, teardownNPC)

-- Se repite el log con cada jugador que entra: es JUSTO cuando importa saber si el
-- NPC sigue animado, y es lo que se ve en la consola al probar.
Players.PlayerAdded:Connect(function()
	for model, track in tracks do
		logState(model, track)
	end
end)
