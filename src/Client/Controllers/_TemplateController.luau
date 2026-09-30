-- Ubicación en Studio: StarterPlayer > StarterPlayerScripts > Controllers > _TemplateController (ModuleScript)
--
-- ════════════════════════════════════════════════════════════════════════════════
--  PLANTILLA — copiá este archivo para crear el controller de una GUI nueva.
--  ClientMain lo IGNORA porque su nombre empieza con "_".
-- ════════════════════════════════════════════════════════════════════════════════
--
-- Pasos (ejemplo con "Inventory"):
--   1. Copiá este archivo como `Controllers/InventoryController.luau` y reemplazá
--      "Template" por "Inventory" (nombres emparejados: InventoryGui ↔ InventoryController
--      ↔ InventoryService ↔ InventoryConfig).
--   2. En Studio: StarterGui > InventoryGui (ScreenGui, ResetOnSpawn = false,
--      DisplayOrder 10) con un Frame `Main` (Visible = false) y, si hace falta, un
--      `CloseButton` adentro. Todo en Scale.
--   3. Si muestra una lista: creá `Shared/InventoryConfig.luau` con los datos y la
--      plantilla de cada fila en ReplicatedStorage > UITemplates.
--   4. Si pide algo al servidor: declarás el remote en `Shared/Remotes/init.luau` y lo
--      manejás en `Server/Services/Inventory/InventoryService.luau`.
--   5. Para abrirla: sumá `InventoryButton = "Inventory"` en HUDController.BUTTONS.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UIManager = require(script.Parent:WaitForChild("UIManager"))
local Utils = script.Parent.Parent:WaitForChild("Utils")
local UIEffects = require(Utils:WaitForChild("UIEffects"))
local UITemplates = require(Utils:WaitForChild("UITemplates"))
local Remotes = require(ReplicatedStorage:WaitForChild("Remotes"))

-- Config con los datos a mostrar (descomentá cuando exista).
-- local TemplateConfig = require(ReplicatedStorage:WaitForChild("TemplateConfig"))
local TemplateConfig = {
	Items = {
		{ Id = "Example1", Name = "Ejemplo 1" },
		{ Id = "Example2", Name = "Ejemplo 2" },
	},
}

local TemplateController = {}

-- Nombre con el que se registra en UIManager (lo que usan HUD, NPCs y Open/Toggle).
local WINDOW_NAME = "Template"
-- Nombre de la ScreenGui en StarterGui.
local GUI_NAME = "TemplateGui"
-- Plantilla de cada fila en ReplicatedStorage > UITemplates.
local ROW_TEMPLATE = "TemplateRow"

-- Referencias que se llenan en Init.
local main: GuiObject
local list: ScrollingFrame?

-- Arma una fila por item del Config: agregar un item nuevo = editar SOLO el Config.
local function buildList()
	if not list then
		return
	end
	for _, child in list:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end

	for index, item in TemplateConfig.Items do
		local row = UITemplates.clone(ROW_TEMPLATE)
		if not row then
			return
		end
		row.Name = item.Id
		row.LayoutOrder = index

		local nameLabel = row:FindFirstChild("NameLabel", true)
		if nameLabel and nameLabel:IsA("TextLabel") then
			nameLabel.Text = item.Name
		end

		local actionButton = row:FindFirstChild("ActionButton", true)
		if actionButton and actionButton:IsA("GuiButton") then
			UIEffects.bindButton(actionButton, function()
				-- El cliente solo PIDE: manda el Id (nunca precios ni cantidades) y el
				-- servidor valida y decide. Requiere declarar "TemplateAction" en Remotes.
				Remotes.event("TemplateAction"):FireServer(item.Id)
			end)
		end

		row.Parent = list
	end
end

function TemplateController.Init()
	-- 1. Buscar la GUI y su Main (armados en Studio).
	local gui = UIManager.WaitForGui(GUI_NAME)
	if not gui then
		return
	end
	local found = UIEffects.findChild(gui, "Main", GUI_NAME)
	if not (found and found:IsA("GuiObject")) then
		return
	end
	main = found
	list = main:FindFirstChild("List", true) :: ScrollingFrame?

	-- 2. Registrar la ventana. El CloseButton (si existe) se conecta solo.
	UIManager.Register(WINDOW_NAME, main)

	-- 3. Reaccionar al abrirse: ej. volver el scroll arriba.
	UIManager.OnOpened(WINDOW_NAME, function()
		if list then
			list.CanvasPosition = Vector2.zero
		end
	end)

	-- 4. Contenido data-driven desde el Config.
	buildList()

	-- 5. Escuchar al servidor por el bus UpdateUI (ej. "templateUpdated" desde el Service
	--    con Remotes.fireTo(player, "templateUpdated", data)).
	Remotes.onUpdate("templateUpdated", function(_data)
		buildList()
	end)
end

return TemplateController
