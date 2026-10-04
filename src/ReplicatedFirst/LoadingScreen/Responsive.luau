-- Ubicación en Studio: ReplicatedFirst > LoadingScreen > Responsive (ModuleScript)
-- Reacomoda el LoadingGui en pantallas chicas; devuelve fit() para volver a aplicarlo.
local Responsive = {}
function Responsive.attach(gui)
	local center = gui.Background.Center
	local button = center.SkipButton
	local tip = center.TipFrame
	local logo = center.Logo
	local original = {}
	for _, o in { center, button, tip, logo, tip.TipLabel } do
		original[o] = { Size = o.Size, Position = o.Position }
	end
	local function fit()
		local size = gui.AbsoluteSize
		local mobile = size.X < 900 or size.Y < 500
		for o, p in original do
			o.Size = p.Size
			o.Position = p.Position
		end
		if mobile then
			center.Size = UDim2.fromScale(0.90, 0.86)
			center.Position = UDim2.fromScale(0.5, 0.5)
			logo.Position = UDim2.fromScale(0.5, 0.30)
			logo.Size = UDim2.fromScale(0.82, 0.56)
			tip.Position = UDim2.fromScale(0.5, 0.68)
			tip.Size = UDim2.fromScale(0.96, 0.16)
			button.Position = UDim2.fromScale(0.5, 0.87)
			button.Size = UDim2.new(0.55, 0, 0, math.clamp(size.Y * 0.105, 44, 60))
			tip.TipLabel.Size = UDim2.fromScale(0.94, 0.9)
			tip.TipLabel.Position = UDim2.fromScale(0.03, 0.05)
		end
		if gui:GetAttribute("LoadingReady") then
			button.Size = UDim2.new(
				button.Size.X.Scale * 1.12,
				button.Size.X.Offset * 1.12,
				button.Size.Y.Scale * 1.12,
				button.Size.Y.Offset * 1.12
			)
			button.Position += UDim2.fromScale(0, 0.035)
		end
	end
	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)
	fit()
	return fit
end
return Responsive
