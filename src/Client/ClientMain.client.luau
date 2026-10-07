-- Ubicación en Studio: StarterPlayer > StarterPlayerScripts > ClientMain (LocalScript)
-- Arranca UIManager y después todo ModuleScript de `Controllers` (ignora los "_*").
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DebugConfig = require(ReplicatedStorage:WaitForChild("DebugConfig"))
local Controllers = script.Parent:WaitForChild("Controllers")

local FIRST = "UIManager"

local function load(module: ModuleScript): any
	local ok, result = pcall(require, module)
	if not ok then
		warn(("[ClientMain] No se pudo cargar %s: %s"):format(module.Name, tostring(result)))
		return nil
	end
	return result
end

local function init(name: string, controller: any)
	if typeof(controller) ~= "table" or typeof(controller.Init) ~= "function" then
		return
	end
	local ok, err = xpcall(controller.Init, debug.traceback)
	if not ok then
		warn(("[ClientMain] %s.Init falló:\n%s"):format(name, tostring(err)))
		return
	end
	-- Sale cuando Init TERMINA: uno que se queda esperando su GUI nunca dice Loaded.
	DebugConfig.print(("[%s] Loaded"):format(name))
end

-- Sincrónico: los demás controllers lo usan en su Init.
init(FIRST, load(Controllers:WaitForChild(FIRST) :: ModuleScript))

-- Todos los require antes que los Init: un controller puede requerir a otro en su
-- nivel superior sin depender del orden.
local modules: { ModuleScript } = {}
for _, child in Controllers:GetChildren() do
	if child:IsA("ModuleScript") and child.Name ~= FIRST and child.Name:sub(1, 1) ~= "_" then
		table.insert(modules, child)
	end
end
table.sort(modules, function(a, b)
	return a.Name < b.Name
end)

local loaded: { { name: string, controller: any } } = {}
for _, module in modules do
	local controller = load(module)
	if controller then
		table.insert(loaded, { name = module.Name, controller = controller })
	end
end

-- Un hilo por Init: uno que espera su GUI o que falla no frena a los demás.
for _, entry in loaded do
	task.spawn(init, entry.name, entry.controller)
end
