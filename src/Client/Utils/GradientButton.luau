-- Ubicación en Studio: StarterPlayer > StarterPlayerScripts > Utils > GradientButton (ModuleScript)
-- Pinta un botón con la forma de SettingsToggle.ActionButton (UIGradient + Inner.Rim) con 3 colores.
local GradientButton = {}

function GradientButton.paint(button: GuiObject, colors: { Color3 })
	local gradient = button:FindFirstChild("UIGradient") :: UIGradient?
	if gradient then
		gradient.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, colors[1]),
			ColorSequenceKeypoint.new(0.5, colors[2]),
			ColorSequenceKeypoint.new(1, colors[3]),
		})
	end
	local rim = button:FindFirstChild("Inner") and button.Inner:FindFirstChild("Rim")
	local rimGradient = rim and rim:FindFirstChild("UIGradient") :: UIGradient?
	if rimGradient then
		rimGradient.Color =
			ColorSequence.new(colors[1]:Lerp(Color3.new(1, 1, 1), 0.65), colors[3]:Lerp(Color3.new(1, 1, 1), 0.45))
	end
end

return GradientButton
