-- Ubicación en Studio: StarterPlayer > StarterPlayerScripts > Utils > MobileHUDLayout (ModuleScript)
-- En táctil reacomoda LeftButtons y Currency del HUD según los atributos de LeftButtons.MobileLayout.
local Input = game:GetService("UserInputService")
local Layout = {}
function Layout.Attach(gui, touchOverride)
	local holder, panel = gui.LeftButtons, gui.Currency
	local grid = holder:FindFirstChildOfClass("UIGridLayout")
	local aspect = holder:FindFirstChildOfClass("UIAspectRatioConstraint")
	local config = holder.MobileLayout
	local original = {
		Size = holder.Size,
		Position = holder.Position,
		Anchor = holder.AnchorPoint,
		Cell = grid.CellSize,
		Gap = grid.CellPadding,
		Max = grid.FillDirectionMaxCells,
		PanelSize = panel.Size,
		PanelPosition = panel.Position,
		PanelAnchor = panel.AnchorPoint,
	}
	local holderScale = Instance.new("UIScale")
	holderScale.Name = "MobileReferenceScale"
	holderScale.Parent = holder
	local panelScale = Instance.new("UIScale")
	panelScale.Name = "MobileReferenceScale"
	panelScale.Parent = panel
	local labels = {}
	for _, button in holder:GetChildren() do
		local label = button:FindFirstChild("Label")
		if label and label:IsA("TextLabel") then
			labels[label] = label.TextSize
		end
	end
	local applied = false
	local function fit()
		local mobile = if touchOverride ~= nil then touchOverride else Input.TouchEnabled
		if not mobile then
			if applied then
				holder.Size = original.Size
				holder.Position = original.Position
				holder.AnchorPoint = original.Anchor
				grid.CellSize = original.Cell
				grid.CellPadding = original.Gap
				grid.FillDirectionMaxCells = original.Max
				panel.Size = original.PanelSize
				panel.Position = original.PanelPosition
				panel.AnchorPoint = original.PanelAnchor
				holderScale.Scale = 1
				panelScale.Scale = 1
				for label, textSize in labels do
					label.TextSize = textSize
				end
				if aspect then
					aspect.Parent = holder
				end
				applied = false
			end
			gui:SetAttribute("MobileHUDLayout", false)
			return
		end
		gui:SetAttribute("MobileHUDLayout", true)
		applied = true
		for label in labels do
			label.TextSize = 22
		end
		if aspect then
			aspect.Parent = config
		end
		local size = gui.AbsoluteSize
		local scale = math.min(size.Y / (config:GetAttribute("ReferenceHeight") or 656), size.X * 0.38 / 228, 1.25)
		holderScale.Scale = scale
		panelScale.Scale = scale
		holder.AnchorPoint = Vector2.zero
		holder.Size = config:GetAttribute("Size")
		holder.Position = config:GetAttribute("Position")
		grid.CellSize = config:GetAttribute("CellSize")
		grid.CellPadding = config:GetAttribute("CellPadding")
		grid.FillDirectionMaxCells = 2
		panel.AnchorPoint = Vector2.zero
		panel.Size = config:GetAttribute("CurrencySize")
		panel.Position = config:GetAttribute("CurrencyPosition")
	end
	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)
	Input:GetPropertyChangedSignal("TouchEnabled"):Connect(fit)
	fit()
	return fit
end
return Layout
