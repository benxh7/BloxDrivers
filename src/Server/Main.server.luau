-- Ubicación en Studio: ServerScriptService > Main (Script)
--
-- Único punto de arranque del servidor. Espejo de ClientMain:
--   1. Crea los Remotes (requerir el módulo los instancia) ANTES que cualquier servicio,
--      así un cliente nunca espera un remote que el servidor todavía no creó.
--   2. Requiere todos los ModuleScripts de `Services` (recursivo) cuyo nombre termine
--      en "Service" y llama a su `Init()` si lo tienen. Los que empiezan con "_" se
--      ignoran (plantillas / desactivados).
--
-- Sumar un servicio nuevo = crear `Services/<Sistema>/<Nombre>Service.luau` con Init().
-- No hace falta tocar este archivo.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

require(ReplicatedStorage:WaitForChild("Remotes"))

local Services = ServerScriptService:WaitForChild("Services")

local function isService(instance: Instance): boolean
	return instance:IsA("ModuleScript")
		and instance.Name:sub(1, 1) ~= "_"
		and instance.Name:sub(-#"Service") == "Service"
end

-- Primero TODOS los require y después los Init: así un servicio puede requerir a
-- otro en su nivel superior sin depender del orden en que se inicializan.
local loaded: { { name: string, module: any } } = {}

local modules = {}
for _, descendant in Services:GetDescendants() do
	if isService(descendant) then
		table.insert(modules, descendant)
	end
end
-- Orden determinista: mismo arranque en cada servidor.
table.sort(modules, function(a, b)
	return a.Name < b.Name
end)

for _, module in modules do
	local ok, result = pcall(require, module)
	if ok then
		table.insert(loaded, { name = module.Name, module = result })
	else
		warn(("[Main] No se pudo cargar %s: %s"):format(module:GetFullName(), tostring(result)))
	end
end

-- Cada Init en su propio hilo: uno que espera (WaitForChild, DataStore) o que falla no
-- frena el arranque de los demás.
for _, entry in loaded do
	local service = entry.module
	if typeof(service) == "table" and typeof(service.Init) == "function" then
		task.spawn(function()
			local ok, err = xpcall(service.Init, debug.traceback)
			if not ok then
				warn(("[Main] %s.Init falló:\n%s"):format(entry.name, tostring(err)))
			end
		end)
	end
end
