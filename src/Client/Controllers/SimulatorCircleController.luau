-- Ubicación en Studio: StarterPlayer > StarterPlayerScripts > Controllers > SimulatorCircleController (ModuleScript)
--
-- Lasers que suben y bajan en el borde de cada aro de Workspace.SimulatorCircles.
-- Todo del lado del CLIENTE: es puro adorno, así que nada replica ni cuesta red.
-- Todos los números se ajustan en SimulatorCircleConfig (o por aro, con Attributes).
--
-- Son Beams y no Parts apiladas: el Beam interpola el ancho de Width0 a Width1, así
-- que la punta sale CONTINUA (apilar cajas se ve como un pilar sobre otro), su
-- transparencia ya es un degradado a lo largo, y encara siempre a la cámara.
--
-- Traído de UBG (SimulatorCircleController.client.luau), pasado a ModuleScript con Init().
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SimulatorCircleConfig = require(ReplicatedStorage:WaitForChild("SimulatorCircleConfig"))
local DebugConfig = require(ReplicatedStorage:WaitForChild("DebugConfig"))

local SimulatorCircleController = {}

-- El nombre lo comparte el config: `measure` tiene que saltear esta carpeta al medir.
local RAYS_FOLDER_NAME = SimulatorCircleConfig.RaysFolderName
local FOLDER_WAIT_TIMEOUT = 30
local GEOMETRY_WAIT_TIMEOUT = 10

type Ray = {
	beam: Beam,
	tip: Attachment,
	maxHeight: number,
	phase: number,
	speed: number,
}
type Circle = { rays: { Ray }, settings: { [string]: any } }

local circles: { [Model]: Circle } = {}

local function lerp(from: number, to: number, alpha: number): number
	return from + (to - from) * alpha
end

-- Cadena de prioridad: lo que diga el modelo gana, y recién al final el default.
local function rayColorFor(model: Model, settings): Color3
	local base: Color3? = nil

	local override = model:GetAttribute("RayColor")
	if typeof(override) == "Color3" then
		base = override
	elseif model.PrimaryPart then
		base = model.PrimaryPart.Color
	end

	if not base then
		return SimulatorCircleConfig.FallbackColor
	end

	local h, s, v = Color3.toHSV(base)
	return Color3.fromHSV(h, math.min(s * settings.SaturationBoost, 1), math.min(v * settings.BrightnessBoost, 1))
end

-- Un Model replica parte por parte: medirlo a medio llegar daría una caja equivocada
-- y los lasers quedarían con el radio y la altura de otro aro.
local function waitForGeometry(model: Model): boolean
	local elapsed = 0
	while not model:FindFirstChildWhichIsA("BasePart", true) do
		if elapsed >= GEOMETRY_WAIT_TIMEOUT or not model.Parent then
			return false
		end
		elapsed += task.wait()
	end
	task.wait()
	return model.Parent ~= nil
end

-- `wave` (0-1) es lo alto que está el laser ahora: mueve la punta y apaga el haz entero
-- al bajar, aparte del degradado que ya tiene a lo largo.
local function updateRay(ray: Ray, wave: number, settings)
	local height = lerp(settings.RayMinHeight, ray.maxHeight, wave)
	ray.tip.Position = Vector3.new(ray.tip.Position.X, height, ray.tip.Position.Z)

	local fade = (1 - wave) * settings.RayFadeWithHeight
	local base = settings.RayBaseTransparency
	local tip = settings.RayTipTransparency

	ray.beam.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, base + (1 - base) * fade),
		NumberSequenceKeypoint.new(1, tip + (1 - tip) * fade),
	})
end

-- Sembrado con la posición del aro: cada uno tiene su propio desorden, pero el MISMO
-- en cada sesión y en todos los clientes. Con un seed al azar, cada playtest movería
-- los lasers de lugar y no se podría comparar un ajuste contra otro.
local function rngFor(centerX: number, centerZ: number): Random
	return Random.new(math.floor(centerX * 73 + centerZ * 179))
end

local function buildCircle(model: Model)
	-- Se destruyen antes de medir: si no, la caja del modelo incluiría los lasers de
	-- la vuelta anterior y el aro iría creciendo solo en cada re-run de Studio.
	local existing = model:FindFirstChild(RAYS_FOLDER_NAME)
	if existing then
		existing:Destroy()
	end

	local settings = SimulatorCircleConfig.settingsFor(model)

	local bounds = SimulatorCircleConfig.measure(model)
	if not bounds then
		DebugConfig.warn("[SimulatorCircle] " .. model.Name .. " no tiene ninguna BasePart")
		return
	end

	local centerX = bounds.centerX
	local centerZ = bounds.centerZ
	local radius = bounds.radius * settings.RayRadiusScale
	local groundY = bounds.groundY + settings.GroundOffset

	local folder = Instance.new("Folder")
	folder.Name = RAYS_FOLDER_NAME

	-- Los Attachment necesitan colgar de una BasePart. Va sin rotar, así que la
	-- posición de cada Attachment es directamente su offset contra el centro del aro.
	local anchor = Instance.new("Part")
	anchor.Name = "Anchor"
	anchor.Size = Vector3.one
	anchor.CFrame = CFrame.new(centerX, groundY, centerZ)
	anchor.Anchored = true
	anchor.Transparency = 1
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.CastShadow = false
	anchor.Parent = folder

	local color = ColorSequence.new(rayColorFor(model, settings))
	local rng = rngFor(centerX, centerZ)
	local slice = 2 * math.pi / settings.RayCount
	local rays: { Ray } = {}

	for index = 1, settings.RayCount do
		-- Reparto parejo MÁS un corrimiento dentro de su propio hueco: al azar puro
		-- se amontonan y dejan claros, y el aro se ve mal repartido.
		local angle = (index - 1) * slice + rng:NextNumber(-0.5, 0.5) * slice * settings.AngleJitter
		local rayRadius = radius * (1 + rng:NextNumber(-1, 1) * settings.RadiusJitter)
		local x = math.cos(angle) * rayRadius
		local z = math.sin(angle) * rayRadius

		local root = Instance.new("Attachment")
		root.Name = "Root" .. index
		root.Position = Vector3.new(x, 0, z)
		root.Parent = anchor

		local tip = Instance.new("Attachment")
		tip.Name = "Tip" .. index
		tip.Position = Vector3.new(x, settings.RayMinHeight, z)
		tip.Parent = anchor

		local beam = Instance.new("Beam")
		beam.Name = "Ray" .. index
		beam.Attachment0 = root
		beam.Attachment1 = tip
		beam.Width0 = settings.RayThickness
		beam.Width1 = settings.RayThickness * settings.RayTipScale
		-- Encara siempre a la cámara: es lo que lo hace ver como un haz de luz y no
		-- como una cinta plana que desaparece de perfil.
		beam.FaceCamera = true
		beam.LightEmission = 1
		beam.LightInfluence = 0
		beam.Segments = 1
		beam.CurveSize0 = 0
		beam.CurveSize1 = 0
		beam.Color = color
		beam.Parent = anchor

		local ray: Ray = {
			beam = beam,
			tip = tip,
			maxHeight = settings.RayMaxHeight * (1 - rng:NextNumber(0, settings.HeightJitter)),
			-- El término ordenado es el que da la oleada dando la vuelta al aro; el
			-- jitter arranca a cada uno en un punto distinto de su ciclo.
			phase = (index - 1) / settings.RayCount * settings.WaveTurns + rng:NextNumber() * settings.PhaseJitter,
			-- Su propia velocidad: con una sola, todos comparten frecuencia y el ritmo
			-- se nota igual aunque arranquen desfasados.
			speed = settings.Speed * math.max(1 + rng:NextNumber(-1, 1) * settings.SpeedJitter, 0.15),
		}
		updateRay(ray, 0, settings)
		rays[index] = ray
	end

	folder.Parent = model
	circles[model] = { rays = rays, settings = settings }
	DebugConfig.print(("[SimulatorCircle] %s: %d lasers"):format(model.Name, settings.RayCount))
end

local function onModelAdded(child: Instance)
	if not child:IsA("Model") then
		return
	end
	task.spawn(function()
		if not waitForGeometry(child) then
			DebugConfig.warn("[SimulatorCircle] " .. child.Name .. " no tiene ninguna BasePart")
			return
		end
		buildCircle(child)
	end)
end

-- Los lasers cuelgan del modelo, así que se van con él: alcanza con soltar la entrada.
local function onModelRemoved(child: Instance)
	circles[child :: Model] = nil
end

function SimulatorCircleController.Init()
	local folder = Workspace:WaitForChild(SimulatorCircleConfig.FolderName, FOLDER_WAIT_TIMEOUT)
	if not folder then
		DebugConfig.warn(("[SimulatorCircle] Sin aros: falta Workspace.%s"):format(SimulatorCircleConfig.FolderName))
		return
	end

	for _, child in folder:GetChildren() do
		onModelAdded(child)
	end
	folder.ChildAdded:Connect(onModelAdded)
	folder.ChildRemoved:Connect(onModelRemoved)

	-- UN solo Heartbeat para todos los aros, no una conexión por modelo.
	local elapsed = 0
	RunService.Heartbeat:Connect(function(deltaTime: number)
		elapsed += deltaTime

		for model, circle in circles do
			if not model.Parent then
				continue
			end

			local settings = circle.settings
			for _, ray in circle.rays do
				local phase = elapsed * ray.speed + ray.phase
				updateRay(ray, (math.sin(phase * 2 * math.pi) + 1) / 2, settings)
			end
		end
	end)
end

return SimulatorCircleController
