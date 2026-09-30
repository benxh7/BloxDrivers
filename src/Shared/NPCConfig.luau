-- Ubicación en Studio: ReplicatedStorage > NPCConfig (ModuleScript)
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SimulatorCircleConfig = require(ReplicatedStorage.SimulatorCircleConfig)
local DebugConfig = require(ReplicatedStorage.DebugConfig)

-- NPC = Model con Humanoid dentro de su aro (SimulatorCircles/<Aro>/<NPC>): el aro es su
-- zona. Lo propio de cada uno va en un ModuleScript hijo; acá los defaults y lo global.
local NPCConfig = {}

-- Nombre del ModuleScript hijo de cada NPC (no confundir con este módulo).
NPCConfig.ConfigName = "NPCConfig"

local FOLDER_WAIT_TIMEOUT = 30
-- Un Model replica antes que sus hijos: sin esperar, un Humanoid tardío no se detectaría.
local HUMANOID_WAIT_TIMEOUT = 10

-- Una clave que no esté acá se ignora: un typo no se cuela como ajuste inventado.
NPCConfig.Defaults = {
	-- Vacío = usa el nombre del Model.
	Title = "",
	Subtitle = "",

	-- "" = el NPC se queda quieto, sin idle.
	IdleAnimation = "",

	-- Radio en studs de la zona. 0 = el del aro (casi siempre lo que se quiere).
	ZoneRadius = 0,
	-- Ventana de UIManager que abre al entrar al aro (ej. "Shop"). "" = ninguna.
	Gui = "",

	-- Studs del cartel sobre la cabeza.
	BillboardHeight = 3,
}

-- Seguimiento con la mirada, común a todos los NPCs.
NPCConfig.Look = {
	-- Studs a los que empieza a seguirte.
	Radius = 25,
	-- Más alto = gira más seco.
	TurnSpeed = 6,
	-- Grados máximos hacia cada lado. Bajalo si el NPC está contra una pared.
	MaxAngleDegrees = 180,
}

-- Estilo del cartel, común a todos los NPCs.
NPCConfig.Billboard = {
	WidthPixels = 260,
	HeightPixels = 74,
	MaxDistance = 90,

	TitleSize = 26,
	SubtitleSize = 18,
	TitleColor = Color3.fromRGB(255, 255, 255),
	SubtitleColor = Color3.fromRGB(225, 225, 235),
	StrokeColor = Color3.fromRGB(0, 0, 0),
	StrokeThickness = 2.5,

	LineColor = Color3.fromRGB(255, 255, 255),
	LineThicknessPixels = 2,
	LineWidthScale = 0.85,
}

function NPCConfig.get(model: Model)
	local settings = table.clone(NPCConfig.Defaults)

	local module = model:FindFirstChild(NPCConfig.ConfigName)
	if module and module:IsA("ModuleScript") then
		-- Un Config roto deja a ESE NPC con los defaults, sin tumbar al resto.
		local ok, custom = pcall(require, module)
		if ok and typeof(custom) == "table" then
			for key, value in custom do
				if typeof(value) == typeof(settings[key]) then
					settings[key] = value
				else
					DebugConfig.warn(("[NPCConfig] %s: se ignora '%s'"):format(model.Name, tostring(key)))
				end
			end
		else
			DebugConfig.warn(("[NPCConfig] %s: su Config no devuelve una tabla"):format(model.Name))
		end
	end

	if settings.Title == "" then
		settings.Title = model.Name
	end

	-- Sin ID numérico (vacío, placeholder o 0) = sin idle, y no un error de carga.
	local animationId = tonumber(settings.IdleAnimation:match("%d+") or "")
	if not animationId or animationId <= 0 then
		settings.IdleAnimation = ""
	end

	return settings
end

-- `onAdded(npc, ring)`: el aro va aparte porque de él sale el radio de la zona.
function NPCConfig.observe(onAdded: (Model, Model) -> (), onRemoved: ((Model) -> ())?)
	task.spawn(function()
		local folderName = SimulatorCircleConfig.FolderName
		local folder = Workspace:WaitForChild(folderName, FOLDER_WAIT_TIMEOUT)
		if not folder then
			DebugConfig.warn(("[NPCConfig] Sin NPCs: falta Workspace.%s"):format(folderName))
			return
		end

		local function watchRing(ring: Instance)
			if not ring:IsA("Model") then return end

			local function handleChild(child: Instance)
				if not child:IsA("Model") then return end
				task.spawn(function()
					if not child:WaitForChild("Humanoid", HUMANOID_WAIT_TIMEOUT) then return end
					onAdded(child, ring)
				end)
			end

			for _, child in ring:GetChildren() do
				handleChild(child)
			end
			ring.ChildAdded:Connect(handleChild)

			if onRemoved then
				ring.ChildRemoved:Connect(function(child)
					if child:IsA("Model") then
						onRemoved(child)
					end
				end)
			end
		end

		for _, ring in folder:GetChildren() do
			watchRing(ring)
		end
		folder.ChildAdded:Connect(watchRing)
	end)
end

return NPCConfig
