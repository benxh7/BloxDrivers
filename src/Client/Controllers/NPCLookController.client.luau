local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local NPCConfig = require(ReplicatedStorage.NPCConfig)
local DebugConfig = require(ReplicatedStorage.DebugConfig)

--[[ Los NPCs te siguen con la mirada dentro de un radio.
	Cada cliente apunta TODOS los NPCs a su propio personaje, y como lo que se toca
	desde el cliente no replica, a vos te miran a vos y al de al lado lo miran a él.
	Por eso tampoco hay que elegir a quién mirar: siempre es el jugador local. ]]

local player = Players.LocalPlayer
local look = NPCConfig.Look

type Watcher = {
	joint: Motor6D,
	restC0: CFrame,
	root: BasePart,
	yaw: number,
}

local watchers: { [Model]: Watcher } = {}

-- Sirve para R6 (`RootJoint`) y R15 (`Root`) sin preguntar por el rig: en los dos, el
-- único Motor6D que cuelga del HumanoidRootPart es el que sostiene al torso.
local function findRootJoint(root: BasePart): Motor6D?
	for _, child in root:GetChildren() do
		if child:IsA("Motor6D") then
			return child
		end
	end
	return nil
end

NPCConfig.observe(function(npc: Model)
	task.spawn(function()
		local root = npc:WaitForChild("HumanoidRootPart", 10)
		if not (root and root:IsA("BasePart")) then
			DebugConfig.warn(("[NPCLook] %s no tiene HumanoidRootPart"):format(npc.Name))
			return
		end

		local joint = findRootJoint(root)
		if not joint then
			DebugConfig.warn(("[NPCLook] %s no tiene el Motor6D de la raíz"):format(npc.Name))
			return
		end

		-- Se guarda su pose original: el giro se aplica SOBRE ella, así el NPC queda
		-- mirando a donde lo dejaste en Studio cuando no hay nadie cerca.
		watchers[npc] = { joint = joint, restC0 = joint.C0, root = root, yaw = 0 }
	end)
end, function(npc: Model)
	watchers[npc] = nil
end)

RunService.Heartbeat:Connect(function(deltaTime: number)
	local character = player.Character
	local playerRoot = character and character:FindFirstChild("HumanoidRootPart")
	local position = playerRoot and (playerRoot :: BasePart).Position

	-- Encuadre exponencial: independiente de los FPS, a diferencia de multiplicar un
	-- factor fijo por frame.
	local alpha = 1 - math.exp(-look.TurnSpeed * deltaTime)
	local maxYaw = math.rad(look.MaxAngleDegrees)

	for npc, watcher in watchers do
		if not npc.Parent then
			watchers[npc] = nil
			continue
		end

		local target = 0
		if position and (position - watcher.root.Position).Magnitude <= look.Radius then
			-- En el espacio del root: el eje Y de ahí es el vertical del NPC, así que
			-- el giro sale plano aunque el modelo esté apoyado en algo inclinado.
			local direction = watcher.root.CFrame:VectorToObjectSpace(position - watcher.root.Position)
			target = math.clamp(math.atan2(-direction.X, -direction.Z), -maxYaw, maxYaw)
		end

		-- Por el camino corto: sin esto, cruzar de +179° a -179° daría la vuelta larga.
		local delta = (target - watcher.yaw + math.pi) % (2 * math.pi) - math.pi
		watcher.yaw += delta * alpha

		-- Se premultiplica: la rotación tiene que ir en el espacio del root (donde Y es
		-- el vertical), no en el del torso, que ya viene rotado por su pose original.
		-- Y se toca C0 y no Transform porque Transform es lo que escribe la animación
		-- de idle en cada frame: ahí el giro se perdería.
		watcher.joint.C0 = CFrame.Angles(0, watcher.yaw, 0) * watcher.restC0
	end
end)

-- DebugConfig.print("[NPCLookController] Initialized")
