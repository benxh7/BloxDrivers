-- Ubicación en Studio: StarterPlayer > StarterPlayerScripts > Controllers > NPCZoneController (ModuleScript)
-- Pisar el aro de un NPC abre su ventana y salir la cierra. Solo cliente: abrir una
-- ventana propia no es una acción de juego, no hay nada que validar.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UIManager = require(script.Parent:WaitForChild("UIManager"))
local NPCConfig = require(ReplicatedStorage:WaitForChild("NPCConfig"))
local SimulatorCircleConfig = require(ReplicatedStorage:WaitForChild("SimulatorCircleConfig"))

local NPCZoneController = {}

local SAMPLE_INTERVAL = 0.15
local FALLBACK_RADIUS = 12

type Zone = { x: number, z: number, radius: number, window: string, inside: boolean }

local player = Players.LocalPlayer
local zones: { [Model]: Zone } = {}

local function setInside(zone: Zone, inside: boolean)
	if zone.inside == inside then
		return
	end
	zone.inside = inside

	if zone.window == "" then
		return
	end
	if inside then
		UIManager.Open(zone.window)
	else
		-- Close solo actúa si ESA ventana sigue abierta: no cierra otra que haya abierto.
		UIManager.Close(zone.window)
	end
end

local function onNPCAdded(npc: Model, ring: Model)
	local settings = NPCConfig.get(npc)
	local bounds = SimulatorCircleConfig.measure(ring)
	local pivot = npc:GetPivot().Position
	local center = if bounds then Vector2.new(bounds.centerX, bounds.centerZ) else Vector2.new(pivot.X, pivot.Z)

	zones[npc] = {
		x = center.X,
		z = center.Y,
		-- Sale de la geometría del aro, salvo que el Config pida un radio propio.
		radius = if settings.ZoneRadius > 0
			then settings.ZoneRadius
			else (if bounds then bounds.radius else FALLBACK_RADIUS),
		window = settings.Gui,
		inside = false,
	}
end

local function sample()
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	-- En carrera no se abre nada, pero se sigue recorriendo: al volver al lobby las
	-- zonas quedan en "afuera".
	local canEnter = root ~= nil and not player:GetAttribute("InRound")

	for npc, zone in zones do
		if not npc.Parent then
			zones[npc] = nil
			continue
		end

		local inside = false
		if canEnter then
			local position = (root :: BasePart).Position
			-- Solo XZ: con la distancia 3D, un balcón encima del aro contaría como adentro.
			inside = Vector2.new(position.X - zone.x, position.Z - zone.z).Magnitude <= zone.radius
		end

		setInside(zone, inside)
	end
end

function NPCZoneController.Init()
	NPCConfig.observe(onNPCAdded, function(npc: Model)
		zones[npc] = nil
	end)

	task.spawn(function()
		while true do
			task.wait(SAMPLE_INTERVAL)
			sample()
		end
	end)
end

return NPCZoneController
