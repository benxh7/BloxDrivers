-- Ubicación en Studio: ServerScriptService > Services > Npc > NPCAnimationService (ModuleScript)
-- Idle de cada NPC. En el servidor porque así replica: todos lo ven en la misma pose,
-- sin desfase entre clientes.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local NPCConfig = require(ReplicatedStorage:WaitForChild("NPCConfig"))
local DebugConfig = require(ReplicatedStorage:WaitForChild("DebugConfig"))

local NPCAnimationService = {}

local tracks: { [Model]: AnimationTrack } = {}

local function logState(model: Model, track: AnimationTrack)
	DebugConfig.print(("[NPCAnimations] Playing %s isPlaying: %s"):format(model.Name, tostring(track.IsPlaying)))
end

local function setupNPC(model: Model)
	local settings = NPCConfig.get(model)
	if settings.IdleAnimation == "" then
		DebugConfig.print(("[NPCAnimations] %s has no idle animation (static)"):format(model.Name))
		return
	end

	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		DebugConfig.warn(("[NPCAnimations] %s no tiene Humanoid"):format(model.Name))
		return
	end

	-- Humanoid:LoadAnimation está deprecado y sin Animator la animación no replica.
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = humanoid
	end

	local animation = Instance.new("Animation")
	animation.AnimationId = settings.IdleAnimation

	-- Una animación de otro dueño tira error: ese NPC queda quieto y el resto sigue.
	local ok, track = pcall(function()
		return (animator :: Animator):LoadAnimation(animation)
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

function NPCAnimationService.Init()
	NPCConfig.observe(setupNPC, teardownNPC)

	-- Log por cada jugador que entra: es justo cuando importa saber si sigue animado.
	Players.PlayerAdded:Connect(function()
		for model, track in tracks do
			logState(model, track)
		end
	end)
end

return NPCAnimationService
