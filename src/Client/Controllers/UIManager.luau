-- Ubicación en Studio: StarterPlayer > StarterPlayerScripts > Controllers > UIManager (ModuleScript)
-- Una sola ventana abierta a la vez. No se registran el HUD ni los popups del servidor.
-- Un `CloseButton` dentro del Main (en cualquier nivel) se conecta solo a Close(name).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Utils = script.Parent.Parent:WaitForChild("Utils")
local UIEffects = require(Utils:WaitForChild("UIEffects"))
local Signal = require(Utils:WaitForChild("Signal"))
local DebugConfig = require(ReplicatedStorage:WaitForChild("DebugConfig"))

export type WindowOptions = {
	-- false = sin popIn/popOut. Default true.
	Animate: boolean?,
	-- Escala desde la que entra y hacia la que sale (0.1 = se abre desde el centro).
	HiddenScale: number?,
	OpenDuration: number?,
}

type Window = {
	frame: GuiObject,
	animate: boolean,
	hiddenScale: number?,
	openDuration: number?,
	closeConnection: RBXScriptConnection?,
}

local UIManager = {}

-- Preferí OnOpened/OnClosed, que filtran por nombre.
UIManager.Opened = Signal.new()
UIManager.Closed = Signal.new()

local GUI_WAIT_TIMEOUT = 10
local CLOSE_BUTTON_NAME = "CloseButton"

local windows: { [string]: Window } = {}
local current: string? = nil
local playerGui: PlayerGui? = nil

local function getPlayerGui(): PlayerGui
	if not playerGui then
		playerGui = Players.LocalPlayer:WaitForChild("PlayerGui") :: PlayerGui
	end
	return playerGui :: PlayerGui
end

function UIManager.Init()
	getPlayerGui()
end

-- Pasado el timeout avisa pero SIGUE esperando: las ScreenGuis se clonan recién cuando
-- aparece el personaje, y en un arranque lento eso tarda más.
function UIManager.WaitForGui(guiName: string, timeout: number?): ScreenGui?
	local container = getPlayerGui()
	local gui = container:WaitForChild(guiName, timeout or GUI_WAIT_TIMEOUT)
	if not gui then
		DebugConfig.warn(("[UIManager] '%s' todavía no está en PlayerGui, se sigue esperando"):format(guiName))
		gui = container:WaitForChild(guiName)
	end
	if not gui:IsA("ScreenGui") then
		DebugConfig.warn(("[UIManager] No se encontró la ScreenGui '%s' en PlayerGui"):format(guiName))
		return nil
	end
	return gui
end

function UIManager.Register(name: string, mainFrame: GuiObject, options: WindowOptions?)
	local previous = windows[name]
	if previous then
		DebugConfig.warn(("[UIManager] '%s' ya estaba registrada, se reemplaza"):format(name))
		if previous.closeConnection then
			previous.closeConnection:Disconnect()
		end
	end

	local window: Window = {
		frame = mainFrame,
		animate = not (options and options.Animate == false),
		hiddenScale = options and options.HiddenScale,
		openDuration = options and options.OpenDuration,
		closeConnection = nil,
	}

	local closeButton = mainFrame:FindFirstChild(CLOSE_BUTTON_NAME, true)
	if closeButton and closeButton:IsA("GuiButton") then
		window.closeConnection = UIEffects.bindButton(closeButton, function()
			UIManager.Close(name)
		end)
	end

	windows[name] = window
	mainFrame.Visible = current == name
end

local function show(window: Window)
	if window.animate then
		UIEffects.popIn(window.frame, window.hiddenScale, window.openDuration)
	else
		window.frame.Visible = true
	end
end

local function hide(window: Window)
	if window.animate then
		UIEffects.popOut(window.frame, nil, window.hiddenScale)
	else
		window.frame.Visible = false
	end
end

function UIManager.Open(name: string): boolean
	local window = windows[name]
	if not window then
		DebugConfig.warn(("[UIManager] Open('%s'): no hay ninguna ventana registrada con ese nombre"):format(name))
		return false
	end
	if current == name then
		return true
	end

	if current then
		UIManager.Close(current)
	end

	current = name
	show(window)
	UIManager.Opened:Fire(name)
	return true
end

function UIManager.Close(name: string)
	if current ~= name then
		return
	end
	current = nil
	local window = windows[name]
	if window then
		hide(window)
	end
	UIManager.Closed:Fire(name)
end

function UIManager.Toggle(name: string)
	if current == name then
		UIManager.Close(name)
	else
		UIManager.Open(name)
	end
end

function UIManager.CloseAll()
	if current then
		UIManager.Close(current)
	end
end

function UIManager.IsOpen(name: string): boolean
	return current == name
end

function UIManager.GetOpen(): string?
	return current
end

function UIManager.OnOpened(name: string, callback: () -> ())
	return UIManager.Opened:Connect(function(opened: string)
		if opened == name then
			callback()
		end
	end)
end

function UIManager.OnClosed(name: string, callback: () -> ())
	return UIManager.Closed:Connect(function(closed: string)
		if closed == name then
			callback()
		end
	end)
end

return UIManager
