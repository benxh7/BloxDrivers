-- Ubicación en Studio: ReplicatedFirst > LoadingScreen > UpdateLog (ModuleScript)
-- Panel "Update Log" de la pantalla de carga: tamaño según la pantalla y, en pantallas chicas,
-- un botón para abrirlo y cerrarlo. El texto de las notas se escribe en Studio.
local TextService = game:GetService("TextService")

local UpdateLog = {}

-- Tamaño de diseño del panel (px); se escala para entrar en la pantalla.
local DESIGN_WIDTH = 460
local DESIGN_HEIGHT = 680
-- Por debajo de esto el panel se oculta y aparece UpdatesToggle.
local COMPACT_WIDTH = 900
local COMPACT_HEIGHT = 500
-- Padding horizontal de las notas (px de diseño) y aire extra al final del scroll.
local NOTES_PADDING = 31
local NOTES_EXTRA = 30

function UpdateLog.attach(gui: ScreenGui)
	local panel = gui:FindFirstChild("UpdateLog")
	local toggle = gui:FindFirstChild("UpdatesToggle")
	if not (panel and toggle) then
		return
	end
	local notes = panel.Notes
	local content = notes.Content
	local opened = false
	local measureVersion = 0

	-- El alto del texto depende del ancho real: se mide con TextService y se ajusta el canvas.
	local function measureNotes()
		measureVersion += 1
		local version = measureVersion
		local params = Instance.new("GetTextBoundsParams")
		params.Font = content.FontFace
		params.Size = content.TextSize
		params.Text = content.Text
		params.Width = math.max(1, notes.AbsoluteSize.X / panel.ResponsiveScale.Scale - NOTES_PADDING)
		local ok, bounds = pcall(TextService.GetTextBoundsAsync, TextService, params)
		params:Destroy()
		if not ok or version ~= measureVersion or not panel.Parent then
			return
		end
		local height = math.ceil(bounds.Y)
		content.Size = UDim2.new(1, -NOTES_PADDING, 0, height + 4)
		notes.CanvasSize = UDim2.fromOffset(0, height + NOTES_EXTRA)
	end

	local function fit()
		local size = gui.AbsoluteSize
		local compact = size.X < COMPACT_WIDTH or size.Y < COMPACT_HEIGHT
		toggle.Visible = compact and not opened
		panel.MobileClose.Visible = compact
		panel.Visible = not compact or opened
		local scale
		if compact then
			scale = math.max(0.1, math.min((size.X - 36) / DESIGN_WIDTH, (size.Y - 82) / DESIGN_HEIGHT, 1))
			panel.Position = UDim2.new(1, -18, 0, 58)
		else
			scale = math.min(size.X * 0.27 / DESIGN_WIDTH, size.Y * 0.82 / DESIGN_HEIGHT, 1)
			panel.Position = UDim2.new(1, -math.max(20, size.X * 0.035), 0, size.Y * 0.09)
		end
		panel.ResponsiveScale.Scale = scale
		task.defer(measureNotes)
	end

	toggle.Activated:Connect(function()
		opened = true
		fit()
	end)
	panel.MobileClose.Activated:Connect(function()
		opened = false
		fit()
	end)
	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)
	content:GetPropertyChangedSignal("Text"):Connect(measureNotes)
	content:GetPropertyChangedSignal("TextSize"):Connect(measureNotes)
	fit()
end

return UpdateLog
