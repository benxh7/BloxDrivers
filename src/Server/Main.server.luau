-- Ubicación en Studio: ServerScriptService > Main (Script)
-- Crea los Remotes y arranca todo ModuleScript de `Services` terminado en "Service" (ignora "_*").
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

-- Antes que los servicios: un cliente nunca espera un remote que todavía no existe.
require(ReplicatedStorage:WaitForChild("Remotes"))
local DebugConfig = require(ReplicatedStorage:WaitForChild("DebugConfig"))

local Services = ServerScriptService:WaitForChild("Services")

local function isService(instance: Instance): boolean
	return instance:IsA("ModuleScript")
		and instance.Name:sub(1, 1) ~= "_"
		and instance.Name:sub(-#"Service") == "Service"
end

-- Todos los require antes que los Init: un servicio puede requerir a otro en su
-- nivel superior sin depender del orden.
local loaded: { { name: string, module: any } } = {}

local modules = {}
for _, descendant in Services:GetDescendants() do
	if isService(descendant) then
		table.insert(modules, descendant)
	end
end
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

-- Un hilo por Init: uno que espera (WaitForChild, DataStore) o falla no frena a los demás.
for _, entry in loaded do
	local service = entry.module
	if typeof(service) == "table" and typeof(service.Init) == "function" then
		task.spawn(function()
			local ok, err = xpcall(service.Init, debug.traceback)
			if not ok then
				warn(("[Main] %s.Init falló:\n%s"):format(entry.name, tostring(err)))
				return
			end
			DebugConfig.print(("[%s] Loaded"):format(entry.name))
		end)
	end
end
