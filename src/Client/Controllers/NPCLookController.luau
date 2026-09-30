-- Ubicación en Studio: StarterPlayer > StarterPlayerScripts > Controllers > NPCLookController (ModuleScript)
-- Los NPCs miran al jugador local. Desde el cliente no replica: a cada uno lo miran a él.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local NPCConfig = require(ReplicatedStorage:WaitForChild("NPCConfig"))
local DebugConfig = require(ReplicatedStorage:WaitForChild("DebugConfig"))

local NPCLookController = {}

local player = Players.LocalPlayer
local look = NPCConfig.Look

type Watcher = {
	joint: Motor6D,
	restC0: CFrame,
	root: BasePart,
	yaw: number,
}

local watchers: { [Model]: Watcher } = {}

-- R6 y R15: en los dos, el único Motor6D del HumanoidRootPart es el del torso.
local function findRootJoint(root: BasePart): Motor6D?
	for _, child in root:GetChildren() do
		if child:IsA("Motor6D") then
			return child
		end
	end
	return nil
end

local function onNPCAdded(npc: Model)
	task.spawn(function()
		local root = npc:WaitForChild("HumanoidRootPart", 10)
		if not (root and root:IsA("BasePart")) then
			DebugConfig.warn(("[NPCLookController] %s no tiene HumanoidRootPart"):format(npc.Name))
			return
		end

		local joint = findRootJoint(root)
		if not joint then
			DebugConfig.warn(("[NPCLookController] %s no tiene el Motor6D de la raíz"):format(npc.Name))
			return
		end

		-- El giro va sobre la pose original: sin nadie cerca mira a donde quedó en Studio.
		watchers[npc] = { joint = joint, restC0 = joint.C0, root = root, yaw = 0 }
	end)
end

local function onHeartbeat(deltaTime: number)
	if next(watchers) == nil then
		return
	end

	local character = player.Character
	local playerRoot = character and character:FindFirstChild("HumanoidRootPart")
	local position = playerRoot and (playerRoot :: BasePart).Position

	-- Exponencial: independiente de los FPS.
	local alpha = 1 - math.exp(-look.TurnSpeed * deltaTime)
	local maxYaw = math.rad(look.MaxAngleDegrees)

	for npc, watcher in watchers do
		if not npc.Parent then
			watchers[npc] = nil
			continue
		end

		local target = 0
		if position and (position - watcher.root.Position).Magnitude <= look.Radius then
			-- En el espacio del root: el giro sale plano aunque el NPC esté inclinado.
			local direction = watcher.root.CFrame:VectorToObjectSpace(position - watcher.root.Position)
			target = math.clamp(math.atan2(-direction.X, -direction.Z), -maxYaw, maxYaw)
		end

		-- Camino corto: de +179° a -179° no da la vuelta larga.
		local delta = (target - watcher.yaw + math.pi) % (2 * math.pi) - math.pi
		watcher.yaw += delta * alpha

		-- C0 y no Transform: Transform lo pisa la animación de idle en cada frame.
		watcher.joint.C0 = CFrame.Angles(0, watcher.yaw, 0) * watcher.restC0
	end
end

function NPCLookController.Init()
	NPCConfig.observe(onNPCAdded, function(npc: Model)
		watchers[npc] = nil
	end)
	RunService.Heartbeat:Connect(onHeartbeat)
end

return NPCLookController
