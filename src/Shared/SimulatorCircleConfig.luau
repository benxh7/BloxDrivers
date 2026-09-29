-- Aros del lobby con lasers en el borde. Único lugar tuneable: el controller no tiene
-- ningún número escrito.
local SimulatorCircleConfig = {}

-- Carpeta en Workspace que los agrupa. Meter un Model adentro alcanza para que se
-- anime: no hay que tocar código ni taguear nada.
SimulatorCircleConfig.FolderName = "SimulatorCircles"

-- Carpeta donde el controller cuelga los lasers que crea en runtime.
SimulatorCircleConfig.RaysFolderName = "Rays"

-- Cada modelo puede pisar cualquiera de estos con un ATTRIBUTE del mismo nombre
-- (Studio > Properties > Attributes). El tipo tiene que coincidir o se ignora.
SimulatorCircleConfig.Defaults = {
	RayCount = 15,
	-- Ancho ENTERO del haz en la base (no es un radio), en studs.
	RayThickness = 0.5,

	-- El laser oscila entre estas dos alturas, en studs.
	RayMinHeight = 1,
	RayMaxHeight = 15,

	-- Radio del anillo como fracción del ancho del modelo (1 = justo el borde).
	RayRadiusScale = 0.92,
	-- Cuánto despega del piso el arranque del laser.
	GroundOffset = 0.2,

	-- Ciclos por segundo: cuántas veces por segundo sube y baja un laser.
	Speed = 0.5,
	-- Reparte los desfases EN ORDEN alrededor del aro: es lo que da la oleada de
	-- activación. 0 = sin oleada, 1 = una onda completa dando la vuelta.
	WaveTurns = 0,

	--[[ Desorden. Todo se sortea UNA vez al armar el aro (no por frame, o temblarían),
	con una semilla sacada de su posición: el mismo aro se ve igual en cada sesión. ]]
	-- Corrimiento angular, en fracción del hueco entre lasers vecinos. 0 = repartidos
	-- perfecto, 1 = puede llegar a pegarse contra el vecino.
	AngleJitter = 0.7,
	-- Cuánto puede entrar o salir del borde, en fracción del radio.
	RadiusJitter = 0.05,
	-- Cuánto puede quedarse corto un laser respecto de RayMaxHeight.
	HeightJitter = 0.4,
	-- Cuánto arranca desfasado cada laser. En 1 empieza cada uno en un punto distinto.
	PhaseJitter = 1,
	-- Cuánto varía la VELOCIDAD de cada laser (0.45 = entre 55% y 145% de Speed).
	-- Sin esto todos oscilan a la misma frecuencia y el ojo agarra el ritmo igual,
	-- por más desfasados que arranquen. Dejarlo abajo de 1 o alguno queda casi quieto.
	SpeedJitter = 0.45,

	-- Ancho de la punta respecto de la base (0.06 = termina casi en pico).
	RayTipScale = 0.06,

	-- Transparencia en la base y en la punta (1 = invisible).
	RayBaseTransparency = 0.55,
	RayTipTransparency = 0.97,
	-- Cuánto se apaga el laser entero cuando baja: 0 = siempre igual de sólido,
	-- 1 = desaparece del todo en su punto más bajo.
	RayFadeWithHeight = 0.75,

	-- El color crudo del modelo sale pálido en Neon, así que se le sube saturación
	-- y brillo. Un solo par de knobs en vez de elegir a mano el color de cada aro.
	SaturationBoost = 1.15,
	BrightnessBoost = 1.35,
}

-- El color NO sale de Defaults: tiene su propia cadena (attribute RayColor ->
-- PrimaryPart del modelo -> esto).
SimulatorCircleConfig.FallbackColor = Color3.fromRGB(255, 215, 0)

-- Lo que NO es el aro: los lasers de la vuelta anterior y el NPC que vive adentro.
-- Sin esto el cuerpo del NPC (y sus accesorios) entra en la medición y corre el radio.
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

--[[ Centro, piso y radio del aro, en coordenadas del MUNDO.
	Model:GetBoundingBox() no sirve: la devuelve orientada al PrimaryPart, y un disco
	suele ser un Cylinder rotado 90°, de donde saldrían el alto y el radio de otro eje. ]]
function SimulatorCircleConfig.measure(model: Model)
	local parts: { BasePart } = {}
	collectRingParts(model, parts)

	local minCorner: Vector3? = nil
	local maxCorner: Vector3? = nil

	for _, part in parts do
		local cf = part.CFrame
		local size = part.Size
		-- Proyección de la caja rotada sobre los ejes del mundo.
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
		-- El borde del aro: los lasers lo achican con RayRadiusScale, la zona lo usa entero.
		radius = math.min(maxCorner.X - minCorner.X, maxCorner.Z - minCorner.Z) / 2,
	}
end

-- El nombre del attribute es la clave del default, así que sumar un tunable nuevo
-- es UNA línea en Defaults y queda pisable por modelo sin tocar nada más.
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
