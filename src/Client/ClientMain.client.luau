-- Ubicación en Studio: StarterPlayer > StarterPlayerScripts > ClientMain (LocalScript)
--
-- Único punto de arranque del cliente. Espejo de Server/Main:
--   1. UIManager primero, requerido e inicializado SINCRÓNICO: el resto lo usa en su Init.
--   2. Todos los demás ModuleScripts de `Controllers` (orden alfabético) se requieren y
--      después se llama a su `Init()` si lo tienen. Los que empiezan con "_" se ignoran
--      (ej. _TemplateController).
--
-- Sumar un controller nuevo = crear `Controllers/<Nombre>Controller.luau` con Init().
-- No hace falta tocar este archivo.
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
	end
end

-- 1) UIManager
init(FIRST, load(Controllers:WaitForChild(FIRST) :: ModuleScript))

-- 2) El resto: primero TODOS los require (un controller puede requerir a otro en su
-- nivel superior sin depender del orden) y después los Init.
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

-- Cada Init en su propio hilo: uno que espera su GUI (WaitForChild) o que falla no
-- frena el arranque de los demás.
for _, entry in loaded do
	task.spawn(init, entry.name, entry.controller)
end
