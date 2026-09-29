local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local ContentProvider = game:GetService("ContentProvider")

local DebugConfig = require(ReplicatedStorage.DebugConfig)

-- Sonido de click, "pop" de botón y findChild, compartidos por las GUIs.
-- Client-only: usa PlayerGui.
local UIHelpers = {}

local player = Players.LocalPlayer
local playerGui = player and player:WaitForChild("PlayerGui")

-- Mismo asset que UBG a pedido.
UIHelpers.ClickSoundId = "rbxassetid://103282937573040"
UIHelpers.ClickVolume = 0.5

-- "Pop" de botón: cuánto crece y cuánto tarda cada mitad del rebote.
UIHelpers.PopScale = 1.12
UIHelpers.PopDuration = 0.09

local POP_OUT = TweenInfo.new(UIHelpers.PopDuration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local POP_IN = TweenInfo.new(UIHelpers.PopDuration, Enum.EasingStyle.Quad, Enum.EasingDirection.In)

function UIHelpers.playSound(soundId: string, volume: number?)
	if not soundId or soundId == "" or soundId == "rbxassetid://0" then return end

	local sound = Instance.new("Sound")
	sound.SoundId = soundId
	sound.Volume = volume or 0.5
	sound.Parent = playerGui
	sound:Play()
	sound.Ended:Once(function()
		sound:Destroy()
	end)
end

-- Uno solo, reutilizable y precargado: creando un Sound por click, el primero
-- esperaba a que el asset cargara (hasta ~10s) y sonaba tarde.
local clickSound = Instance.new("Sound")
clickSound.Name = "UIClick"
clickSound.SoundId = UIHelpers.ClickSoundId
clickSound.Volume = UIHelpers.ClickVolume
clickSound.Parent = SoundService

task.spawn(function()
	pcall(function()
		ContentProvider:PreloadAsync({ clickSound })
	end)
end)

function UIHelpers.playClickSound()
	clickSound:Play()
end

local popping: { [Instance]: boolean } = {}

-- Por UIScale y no por Size/Position: no pelea con UIAspectRatioConstraint ni con
-- el posicionado manual de los layouts.
function UIHelpers.popButton(button: GuiObject)
	if popping[button] then return end
	popping[button] = true

	local uiScale = button:FindFirstChild("PopScale") :: UIScale?
	if not uiScale then
		uiScale = Instance.new("UIScale")
		uiScale.Name = "PopScale"
		uiScale.Parent = button
	end

	local grow = TweenService:Create(uiScale, POP_OUT, { Scale = UIHelpers.PopScale })
	grow.Completed:Connect(function()
		local back = TweenService:Create(uiScale, POP_IN, { Scale = 1 })
		back.Completed:Connect(function()
			popping[button] = nil
		end)
		back:Play()
	end)
	grow:Play()
end

-- WaitForChild con timeout + warn: un nombre que no coincide EXACTO con lo armado
-- en Studio no debe colgar el script sin aviso.
function UIHelpers.findChild(parent: Instance, name: string, tag: string?): Instance?
	local child = parent:WaitForChild(name, 5)
	if not child then
		DebugConfig.warn(("[%s] No se encontró '%s' dentro de '%s'"):format(tag or "UI", name, parent:GetFullName()))
	end
	return child
end

return UIHelpers
