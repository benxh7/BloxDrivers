-- Ubicación en Studio: ReplicatedStorage > SimulatorCircleConfig (ModuleScript)
-- Aros del lobby y sus lasers: todos los números ajustables del controller están acá.
local SimulatorCircleConfig = {}

-- Carpeta de Workspace: meter un Model adentro alcanza para que se anime.
SimulatorCircleConfig.FolderName = "SimulatorCircles"

SimulatorCircleConfig.RaysFolderName = "Rays"

-- Cada aro puede pisar cualquiera con un Attribute del mismo nombre (y mismo tipo).
SimulatorCircleConfig.Defaults = {
	RayCount = 15,
	-- Ancho entero del haz en la base (no radio), en studs.
	RayThickness = 0.5,

	-- Alturas entre las que oscila, en studs.
	RayMinHeight = 1,
	RayMaxHeight = 15,

	-- Fracción del ancho del aro (1 = justo el borde).
	RayRadiusScale = 0.92,
	-- Cuánto despega del piso la base.
	GroundOffset = 0.2,

	-- Veces por segundo que sube y baja.
	Speed = 0.5,
	-- Oleada alrededor del aro: 0 = sin oleada, 1 = una onda completa por vuelta.
	WaveTurns = 0,

	-- Desorden, sorteado una vez por aro con semilla fija. Ángulo: 0 = parejos, 1 = puede
	-- pegarse al vecino.
	AngleJitter = 0.7,
	-- Entrada/salida del borde, en fracción del radio.
	RadiusJitter = 0.05,
	-- Cuánto puede quedarse corto respecto de RayMaxHeight.
	HeightJitter = 0.4,
	-- Desfase inicial: en 1 cada uno arranca en un punto distinto.
	PhaseJitter = 1,
	-- Variación de velocidad (0.45 = 55%..145%): sin ella el ojo nota el ritmo común.
	-- Abajo de 1, o alguno queda casi quieto.
	SpeedJitter = 0.45,

	-- Ancho de la punta respecto de la base (0.06 = casi en pico).
	RayTipScale = 0.06,

	RayBaseTransparency = 0.55,
	RayTipTransparency = 0.97,
	-- Cuánto se apaga al bajar: 0 = siempre igual, 1 = desaparece en su punto más bajo.
	RayFadeWithHeight = 0.75,

	-- El color del aro sale pálido en Neon: se le sube saturación y brillo.
	SaturationBoost = 1.15,
	BrightnessBoost = 1.35,
}

-- Último recurso del color: attribute RayColor -> PrimaryPart del aro -> esto.
SimulatorCircleConfig.FallbackColor = Color3.fromRGB(255, 215, 0)

-- Sin excluir los lasers y el NPC, su cuerpo entraría en la medición y correría el radio.
local function isNotRing(instance: Instance): boolean
	return instance.Name == SimulatorCircleConfig.RaysFolderName
		or (instance:IsA("Model") and instance:FindFirstChildOfClass("Humanoid") ~= nil)
end

local function collectRingParts(parent: Instance, found: { BasePart })
	for _, child in parent:GetChildren() do
		if isNotRing(child) then continue end
		if child:IsA("BasePart") then
			table.insert(found, child)
		end
		collectRingParts(child, found)
	end
end

-- En coordenadas del mundo. No GetBoundingBox: se orienta al PrimaryPart, y un disco suele
-- ser un Cylinder rotado 90° (daría el alto y el radio de otro eje).
function SimulatorCircleConfig.measure(model: Model)
	local parts: { BasePart } = {}
	collectRingParts(model, parts)

	local minCorner: Vector3? = nil
	local maxCorner: Vector3? = nil

	for _, part in parts do
		local cf = part.CFrame
		local size = part.Size
		local half = Vector3.new(
			math.abs(cf.XVector.X) * size.X + math.abs(cf.YVector.X) * size.Y + math.abs(cf.ZVector.X) * size.Z,
			math.abs(cf.XVector.Y) * size.X + math.abs(cf.YVector.Y) * size.Y + math.abs(cf.ZVector.Y) * size.Z,
			math.abs(cf.XVector.Z) * size.X + math.abs(cf.YVector.Z) * size.Y + math.abs(cf.ZVector.Z) * size.Z
		) / 2

		local low = cf.Position - half
		local high = cf.Position + half
		minCorner = if minCorner then minCorner:Min(low) else low
		maxCorner = if maxCorner then maxCorner:Max(high) else high
	end

	if not (minCorner and maxCorner) then
		return nil
	end

	return {
		centerX = (minCorner.X + maxCorner.X) / 2,
		centerZ = (minCorner.Z + maxCorner.Z) / 2,
		groundY = minCorner.Y,
		radius = math.min(maxCorner.X - minCorner.X, maxCorner.Z - minCorner.Z) / 2,
	}
end

function SimulatorCircleConfig.settingsFor(model: Model)
	local settings = {}
	for key, default in SimulatorCircleConfig.Defaults do
		local override = model:GetAttribute(key)
		if typeof(override) == typeof(default) then
			settings[key] = override
		else
			settings[key] = default
		end
	end
	return settings
end

return SimulatorCircleConfig
