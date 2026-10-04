-- Ubicación en Studio: StarterPlayer > StarterPlayerScripts > Controllers > HUDController (ModuleScript)
-- HUD siempre visible: NO se registra en UIManager, solo conecta sus botones con BUTTONS.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UIManager = require(script.Parent:WaitForChild("UIManager"))
local Utils = script.Parent.Parent:WaitForChild("Utils")
local UIEffects = require(Utils:WaitForChild("UIEffects"))
local MobileHUDLayout = require(Utils:WaitForChild("MobileHUDLayout"))
local DebugConfig = require(ReplicatedStorage:WaitForChild("DebugConfig"))

local HUDController = {}

local GUI_NAME = "HUD"

-- Botón del HUD (se busca en cualquier nivel) -> ventana de UIManager. Si no existe, se ignora.
local BUTTONS: { [string]: string } = {
	ShopButton = "Shop",
	CodesButton = "Codes",
	DailyButton = "DailyRewards",
	PlaytimeButton = "PlaytimeRewards",
	SettingsButton = "Settings",
	InventoryButton = "Inventory",
}

-- Hover: cuánto crece el botón y cuántos grados gira su `Icon`.
local HOVER_SCALE = 1.1
local HOVER_ROTATION = 14

-- Click + hover estándar del HUD (gira el `Icon`, el `Glow` solo se ve con hover). Para botones
-- que no abren una ventana, ej. SpectateButton desde SpectatorController.
function HUDController.BindButton(button: GuiButton, callback: () -> ())
	UIEffects.bindButton(button, callback)
	local icon = button:FindFirstChild("Icon")
	local glow = button:FindFirstChild("Glow")
	UIEffects.bindHover(button, {
		Scale = HOVER_SCALE,
		Rotation = HOVER_ROTATION,
		RotateTarget = if icon and icon:IsA("GuiObject") then icon else nil,
		Reveal = if glow and (glow:IsA("CanvasGroup") or glow:IsA("ImageLabel")) then glow else nil,
	})
end

function HUDController.Init()
	local gui = UIManager.WaitForGui(GUI_NAME)
	if not gui then
		return
	end

	MobileHUDLayout.Attach(gui)
	for buttonName, windowName in BUTTONS do
		local button = gui:FindFirstChild(buttonName, true)
		if button and button:IsA("GuiButton") then
			HUDController.BindButton(button, function()
				UIManager.Toggle(windowName)
			end)
		else
			DebugConfig.print(("[HUDController] '%s' no está en el HUD todavía, se ignora"):format(buttonName))
		end
	end
end

return HUDController
