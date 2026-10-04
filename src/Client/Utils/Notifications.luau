-- Ubicación en Studio: StarterPlayer > StarterPlayerScripts > Utils > Notifications (ModuleScript)
-- Notifications.Show("Claimed $75 Cash!", {Theme="Success", Duration=3})
-- Opcional: Colors={Color3,...}, StrokeColor=Color3, Duration=number.
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UIEffects = require(script.Parent.UIEffects)
local Notifications = {}
Notifications.Themes = {
	Success = {
		Colors = { Color3.fromRGB(210, 255, 45), Color3.fromRGB(65, 245, 0) },
		StrokeColor = Color3.fromRGB(49, 125, 18),
	},
	Info = {
		Colors = { Color3.fromRGB(170, 250, 255), Color3.fromRGB(45, 175, 255) },
		StrokeColor = Color3.fromRGB(15, 65, 120),
	},
	Special = {
		Colors = { Color3.fromRGB(255, 225, 110), Color3.fromRGB(255, 140, 40) },
		StrokeColor = Color3.fromRGB(130, 65, 12),
	},
	Error = {
		Colors = { Color3.fromRGB(255, 155, 155), Color3.fromRGB(255, 65, 80) },
		StrokeColor = Color3.fromRGB(130, 20, 35),
	},
}
local gui
local active = {}
local function layout()
	if not gui then
		return
	end
	local height = math.clamp(gui.AbsoluteSize.Y * 0.063, 30, 52)
	for index, label in active do
		label.Size = UDim2.new(0.92, 0, 0, height)
		label.Position = UDim2.new(0.5, 0, 0.90, -(#active - index) * (height + 2))
		label.TextOutline.Thickness = math.clamp(height * 0.065, 1.5, 3.2)
	end
end
local function getGui()
	if gui then
		return gui
	end
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	gui = playerGui:FindFirstChild("NotificationsGui")
	if not gui then
		gui = Instance.new("ScreenGui")
		gui.Name = "NotificationsGui"
		gui.ResetOnSpawn = false
		gui.IgnoreGuiInset = true
		gui.DisplayOrder = 100
		gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
		gui.Parent = playerGui
	end
	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(layout)
	return gui
end
local function remove(label)
	local index = table.find(active, label)
	if index then
		table.remove(active, index)
	end
	label:Destroy()
	layout()
end
function Notifications.Show(message, options)
	options = options or {}
	local theme = Notifications.Themes[options.Theme or "Success"] or Notifications.Themes.Success
	local colors = options.Colors or theme.Colors
	assert(type(message) == "string", "Notification message must be a string")
	assert(#colors >= 2, "Notification Colors requires at least two Color3 values")
	local label = RS:WaitForChild("UITemplates"):WaitForChild("ToastMessage"):Clone()
	label.Text = message
	label.Visible = true
	local keys = {}
	for index, color in colors do
		table.insert(keys, ColorSequenceKeypoint.new((index - 1) / (#colors - 1), color))
	end
	label.UIGradient.Color = ColorSequence.new(keys)
	label.TextOutline.Color = options.StrokeColor or theme.StrokeColor
	local parent = getGui()
	while #active >= 4 do
		remove(active[1])
	end
	table.insert(active, label)
	label.Parent = parent
	if options.SoundId then
		UIEffects.playSound(options.SoundId, options.Volume or 0.5)
	end
	layout()
	local scale = label:FindFirstChildOfClass("UIScale")
	scale.Scale = 0.84
	TweenService:Create(scale, TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 })
		:Play()
	task.delay(math.clamp(options.Duration or 3, 0.5, 15), function()
		if not label.Parent then
			return
		end
		local fade = TweenService:Create(label, TweenInfo.new(0.35), { TextTransparency = 1 })
		TweenService:Create(label.TextOutline, TweenInfo.new(0.35), { Transparency = 1 }):Play()
		fade.Completed:Once(function()
			remove(label)
		end)
		fade:Play()
	end)
	return label
end
return Notifications
