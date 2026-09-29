local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local NPCConfig = require(ReplicatedStorage.NPCConfig)
local SimulatorCircleConfig = require(ReplicatedStorage.SimulatorCircleConfig)
local Icon = require(ReplicatedStorage:WaitForChild("TopbarPlus"):WaitForChild("Icon"))
local DebugConfig = require(ReplicatedStorage.DebugConfig)

--[[ Pisar el aro de un NPC abre su GUI, salir la cierra. El centro y el radio salen de
	la GEOMETRÍA del aro que contiene al NPC (`ZoneRadius = 0`), medida igual que la de
	los lasers: la zona coincide sola con lo que se ve dibujado en el piso.

	100% del cliente: abrir una GUI propia no es una acción de juego, no hay nada que
	validar del lado del servidor y no hace falta ningún remote. ]]

-- No hace falta por frame: entrar a una zona no es un evento de 1 frame. Mismo
-- criterio de muestreo que AnkleBreakerService.
local SAMPLE_INTERVAL = 0.15
local FALLBACK_RADIUS = 12

type Zone = { x: number, z: number, radius: number, gui: string, inside: boolean }

local player = Players.LocalPlayer
local zones: { [Model]: Zone } = {}

-- Se resuelve al entrar y no al arrancar: cada GUI crea su propio ícono cuando carga,
-- y este controller puede correr antes que ella.
local function setGuiOpen(guiName: string, open: boolean)
	local icon = Icon.getIcon(guiName)
	if not icon then
		DebugConfig.warn(("[NPCZone] No existe el ícono '%s'"):format(guiName))
		return
	end
	if open then
		icon:select()
	else
		icon:deselect()
	end
end

-- `npc` queda para el log de abajo, que está comentado.
local function setInside(npc: Model, zone: Zone, inside: boolean)
	if zone.inside == inside then return end
	zone.inside = inside

	-- DebugConfig.print(("[NPCZone] %s %s"):format(npc.Name, inside and "entró" or "salió"))
	if zone.gui ~= "" then
		setGuiOpen(zone.gui, inside)
	end
end

NPCConfig.observe(function(npc: Model, ring: Model)
	local settings = NPCConfig.get(npc)
	local bounds = SimulatorCircleConfig.measure(ring)
	local center = bounds and Vector2.new(bounds.centerX, bounds.centerZ)
		or Vector2.new(npc:GetPivot().Position.X, npc:GetPivot().Position.Z)

	zones[npc] = {
		x = center.X,
		z = center.Y,
		-- El aro manda salvo que el Config pida un radio propio.
		radius = if settings.ZoneRadius > 0
			then settings.ZoneRadius
			else (bounds and bounds.radius or FALLBACK_RADIUS),
		gui = settings.Gui,
		inside = false,
	}
end, function(npc: Model)
	zones[npc] = nil
end)

task.spawn(function()
	while true do
		task.wait(SAMPLE_INTERVAL)

		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		-- En ronda se juega en la arena: nada tiene que abrirse solo ahí. Se sigue
		-- recorriendo igual para que al volver al lobby las zonas queden en "afuera".
		local canEnter = root ~= nil and not player:GetAttribute("InRound")

		for npc, zone in zones do
			if not npc.Parent then
				zones[npc] = nil
				continue
			end

			local inside = false
			if canEnter then
				local position = (root :: BasePart).Position
				-- Solo en XZ: es un círculo en el piso, y con la distancia real un
				-- balcón justo encima del aro contaría como estar adentro.
				inside = Vector2.new(position.X - zone.x, position.Z - zone.z).Magnitude <= zone.radius
			end

			setInside(npc, zone, inside)
		end
	end
end)

-- DebugConfig.print("[NPCZoneController] Initialized")
