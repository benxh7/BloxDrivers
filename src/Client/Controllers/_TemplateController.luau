-- Ubicación en Studio: StarterPlayer > StarterPlayerScripts > Controllers > _TemplateController (ModuleScript)
-- Plantilla para el controller de una GUI nueva (ClientMain la ignora por el "_").
-- Pasos completos en el checklist "crear una GUI nueva" del README.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UIManager = require(script.Parent:WaitForChild("UIManager"))
local Utils = script.Parent.Parent:WaitForChild("Utils")
local UIEffects = require(Utils:WaitForChild("UIEffects"))
local UITemplates = require(Utils:WaitForChild("UITemplates"))
local Remotes = require(ReplicatedStorage:WaitForChild("Remotes"))

-- local TemplateConfig = require(ReplicatedStorage:WaitForChild("TemplateConfig"))
local TemplateConfig = {
	Items = {
		{ Id = "Example1", Name = "Ejemplo 1" },
		{ Id = "Example2", Name = "Ejemplo 2" },
	},
}

local TemplateController = {}

-- Nombre en UIManager (el que usan HUD, NPCs y Open/Toggle).
local WINDOW_NAME = "Template"
local GUI_NAME = "TemplateGui"
local ROW_TEMPLATE = "TemplateRow"

local main: GuiObject
local list: ScrollingFrame?

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
				-- Solo el Id, nunca precios ni cantidades: el servidor valida y decide.
				Remotes.event("TemplateAction"):FireServer(item.Id)
			end)
		end

		row.Parent = list
	end
end

function TemplateController.Init()
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

	-- El CloseButton (si existe) lo conecta UIManager solo.
	UIManager.Register(WINDOW_NAME, main)

	UIManager.OnOpened(WINDOW_NAME, function()
		if list then
			list.CanvasPosition = Vector2.zero
		end
	end)

	buildList()

	-- El Service lo dispara con Remotes.fireTo(player, "templateUpdated", data).
	Remotes.onUpdate("templateUpdated", function(_data)
		buildList()
	end)
end

return TemplateController
