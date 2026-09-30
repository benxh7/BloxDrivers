local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SimulatorCircleConfig = require(ReplicatedStorage.SimulatorCircleConfig)
local DebugConfig = require(ReplicatedStorage.DebugConfig)

--[[ NPCs del lobby. Cada uno es un Model con Humanoid que vive DENTRO de su aro
	(SimulatorCircles/<Aro>/<NPC>): moverlo se lleva al NPC con él, y el aro pasa a ser
	la zona, así que no hay radio que emparejar a mano contra el dibujo.

	Cada NPC lleva un ModuleScript `Config` con lo SUYO (nombre, subtítulo, su idle);
	el formato del cartel es global y vive en NPCConfig.Billboard. ]]
local NPCConfig = {}

-- Nombre del ModuleScript que cada NPC lleva adentro con lo suyo. Es OTRA cosa que
-- este módulo: acá viven los defaults, allá los valores de ese NPC.
NPCConfig.ConfigName = "NPCConfig"

local FOLDER_WAIT_TIMEOUT = 30
-- Un Model replica antes que sus hijos: el Humanoid puede tardar en aparecer y sin
-- esperarlo un NPC que llega tarde no se detectaría nunca.
local HUMANOID_WAIT_TIMEOUT = 10

-- Lo que puede declarar el Config de cada NPC. Una clave que no esté acá se ignora,
-- así un typo en el Config de un NPC no se cuela como un ajuste inventado.
NPCConfig.Defaults = {
	-- Vacío = usa el nombre del Model.
	Title = "",
	Subtitle = "",

	-- "" = el NPC se queda quieto, sin idle.
	IdleAnimation = "",

	-- Radio en studs de la zona que le abre la GUI al jugador. 0 = sale del aro que lo
	-- contiene, que es lo que se quiere casi siempre: la zona coincide con el dibujo.
	ZoneRadius = 0,
	-- Ventana de UIManager que se abre al entrar al aro (ej. "Shop"), la misma que
	-- registra su controller. "" = este NPC no abre nada.
	Gui = "",

	-- Alto del cartel sobre la cabeza.
	BillboardHeight = 3,
}

--[[ Seguimiento con la mirada. General para TODOS los NPCs, como el cartel.
	Cada cliente los apunta a SU propio personaje y eso no replica, así que a vos te
	miran a vos y al de al lado lo miran a él, cada uno en su pantalla. ]]
NPCConfig.Look = {
	-- Distancia en studs a la que te empieza a seguir.
	Radius = 25,
	-- Qué tan rápido alcanza el ángulo (fracción por segundo). Más alto = más seco.
	TurnSpeed = 6,
	-- Tope de giro en grados hacia cada lado desde su pose original. 180 = se da
	-- vuelta entero; bajalo si el NPC está contra una pared y no querés que se dé
	-- vuelta hacia ella.
	MaxAngleDegrees = 180,
}

-- El LOOK del cartel es global a propósito: se toca una vez y cambian todos los NPCs.
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

	-- La rayita debajo del nombre.
	LineColor = Color3.fromRGB(255, 255, 255),
	LineThicknessPixels = 2,
	LineWidthScale = 0.85,
}

function NPCConfig.get(model: Model)
	local settings = table.clone(NPCConfig.Defaults)

	local module = model:FindFirstChild(NPCConfig.ConfigName)
	if module and module:IsA("ModuleScript") then
		-- En pcall: un Config roto tiene que costar UN npc con los defaults, nunca
		-- tumbar al resto.
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

	-- Sin un ID numérico adentro (vacío, un placeholder de ejemplo, o 0) el NPC
	-- simplemente NO tiene idle. Se normaliza acá para que no llegue como un ID roto y
	-- termine avisado como error de carga, que es otra cosa.
	local animationId = tonumber(settings.IdleAnimation:match("%d+") or "")
	if not animationId or animationId <= 0 then
		settings.IdleAnimation = ""
	end

	return settings
end

-- El descubrimiento vive acá y no en cada consumidor: los dos servicios y el controller
-- de zonas lo comparten, así el recorrido se escribe una sola vez.
-- `onAdded(npc, ring)` — el aro va aparte porque de él sale el radio de la zona.
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
					-- Lo que distingue al NPC del resto del aro es tener Humanoid.
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
