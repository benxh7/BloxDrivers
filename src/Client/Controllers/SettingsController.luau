-- Ubicación en Studio: StarterPlayer > StarterPlayerScripts > Controllers > SettingsController (ModuleScript)
-- Ventana "Settings": filas desde SettingsConfig. Expone Get/Set/Changed y atributos locales
-- Settings_*; no concede pases ni cambia probabilidades en el servidor.
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local Lighting = game:GetService("Lighting")
local ContentProvider = game:GetService("ContentProvider")
local UIS = game:GetService("UserInputService")
local SoundService = game:GetService("SoundService")
local CollectionService = game:GetService("CollectionService")
local Workspace = game:GetService("Workspace")
local UIManager = require(script.Parent:WaitForChild("UIManager"))
local Utils = script.Parent.Parent:WaitForChild("Utils")
local UIEffects = require(Utils:WaitForChild("UIEffects"))
local UITemplates = require(Utils:WaitForChild("UITemplates"))
local Signal = require(Utils:WaitForChild("Signal"))
local WindowLayout = require(Utils:WaitForChild("WindowLayout"))
local Config = require(RS:WaitForChild("SettingsConfig"))

local Controller = {}
Controller.Changed = Signal.new()
local player = Players.LocalPlayer
local definitions, values, rows = {}, {}, {}
local gui, main, content, overlay, setBlur
local initialized = false
local activeDrag = nil
local cameraConnection
local musicGroups = {}
local baseGroupVolumes = {}
local toggleSound: Sound?
for _, item in Config.Rows do
	definitions[item.Id] = item
	if item.Default ~= nil then
		values[item.Id] = item.Default
	end
end
local function formatValue(value)
	return string.format("%.2f", value):gsub("0+$", ""):gsub("%.$", "")
end
local function paintScope(root, kind)
	local r = root:FindFirstChild("Reticle")
	if not r then
		return
	end
	r.Circle.Enabled = kind == 1 or kind == 4
	r.Horizontal.Visible = kind == 2 or kind == 4
	r.Vertical.Visible = kind == 2 or kind == 4
	r.Dot.Visible = true
	r.Dot.Size = UDim2.fromOffset(if kind == 3 then 6 else 3, if kind == 3 then 6 else 3)
end
local function paint(id)
	local row = rows[id]
	if not row then
		return
	end
	local item = definitions[id]
	local value = values[id]
	if item.Kind == "Toggle" or item.Kind == "Action" or item.Kind == "Scope" then
		local b = row.ActionButton
		local colors = if item.Kind == "Toggle" and not value then Config.Style.Off else Config.Style.On
		b.UIGradient.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, colors[1]),
			ColorSequenceKeypoint.new(0.5, colors[2]),
			ColorSequenceKeypoint.new(1, colors[3]),
		})
		b.Inner.Rim.Color = Color3.new(1, 1, 1)
		b.Inner.Rim.UIGradient.Color =
			ColorSequence.new(colors[1]:Lerp(Color3.new(1, 1, 1), 0.65), colors[3]:Lerp(Color3.new(1, 1, 1), 0.45))
		b.Label.Text = if item.Kind == "Action"
			then "Open"
			elseif item.Kind == "Scope" then "Scope " .. value
			elseif value then "ON"
			else "OFF"
		if item.Kind == "Scope" then
			paintScope(row.Preview, value)
			if overlay then
				paintScope(overlay.ScopePreview, value)
			end
		end
	elseif item.Kind == "Slider" then
		row.ValueBox.Text = formatValue(value)
		row.Slider.Knob.Position = UDim2.fromScale((value - item.Min) / (item.Max - item.Min), 0.5)
	end
end
local function apply(id, value)
	if id == "CameraFOV" then
		if Workspace.CurrentCamera then
			Workspace.CurrentCamera.FieldOfView = value
		end
	elseif id == "Shadows" then
		Lighting.GlobalShadows = value
	elseif id == "MusicVolume" then
		for group in musicGroups do
			if group.Parent then
				group.Volume = baseGroupVolumes[group] * value
			end
		end
	end
end
function Controller.Get(id)
	return values[id]
end
function Controller.Set(id, value)
	local item = definitions[id]
	if not item or item.Kind == "Action" then
		return false
	end
	if item.Kind == "Toggle" then
		if typeof(value) ~= "boolean" then
			return false
		end
	else
		if typeof(value) ~= "number" or value ~= value or math.abs(value) == math.huge then
			return false
		end
		if item.Kind == "Scope" then
			value = math.clamp(math.round(value), 1, item.Count)
		else
			value = math.clamp(math.round((value - item.Min) / item.Step) * item.Step + item.Min, item.Min, item.Max)
		end
	end
	local changed = values[id] ~= value
	values[id] = value
	player:SetAttribute("Settings_" .. id, value)
	apply(id, value)
	paint(id)
	if changed then
		Controller.Changed:Fire(id, value)
	end
	return true
end
local function trackGroup(group)
	if musicGroups[group] then
		return
	end
	musicGroups[group] = true
	baseGroupVolumes[group] = group.Volume
	group.Volume = baseGroupVolumes[group] * values.MusicVolume
	group.Destroying:Once(function()
		musicGroups[group] = nil
		baseGroupVolumes[group] = nil
	end)
end
local function bindMusic()
	local defaultGroup = SoundService:FindFirstChild("Music")
	if not defaultGroup or not defaultGroup:IsA("SoundGroup") then
		defaultGroup = Instance.new("SoundGroup")
		defaultGroup.Name = "SettingsMusic"
		defaultGroup.Volume = 1
		defaultGroup.Parent = SoundService
	end
	trackGroup(defaultGroup)
	local function inspect(object)
		if
			object:IsA("SoundGroup")
			and (
				object.Name == "Music"
				or object:GetAttribute("IsMusic") == true
				or CollectionService:HasTag(object, "Music")
			)
		then
			trackGroup(object)
		elseif object:IsA("Sound") then
			local name = object.Name:lower()
			local isMusic = object:GetAttribute("IsMusic") == true
				or CollectionService:HasTag(object, "Music")
				or name == "music"
				or name == "backgroundmusic"
				or name == "lobbymusic"
			if isMusic then
				if object.SoundGroup then
					trackGroup(object.SoundGroup)
				else
					object.SoundGroup = defaultGroup
				end
			end
		end
	end
	-- Solo donde puede sonar música en runtime: escuchar todo `game` dispara por cada instancia.
	for _, root in { Workspace, SoundService, RS, Lighting, player:WaitForChild("PlayerGui") } do
		for _, object in root:GetDescendants() do
			inspect(object)
		end
		root.DescendantAdded:Connect(inspect)
	end
	CollectionService:GetInstanceAddedSignal("Music"):Connect(inspect)
end
local function endDrag()
	activeDrag = nil
	if content then
		content.ScrollingEnabled = true
	end
end
local function setFromX(item, track, x)
	local width = track.AbsoluteSize.X
	if width <= 0 then
		return
	end
	local alpha = math.clamp((x - track.AbsolutePosition.X) / width, 0, 1)
	Controller.Set(item.Id, item.Min + (item.Max - item.Min) * alpha)
end
local function bindSlider(row, item)
	local track = row.Slider
	track.InputBegan:Connect(function(input)
		if
			input.UserInputType ~= Enum.UserInputType.MouseButton1
			and input.UserInputType ~= Enum.UserInputType.Touch
		then
			return
		end
		if activeDrag then
			return
		end
		activeDrag = { input = input, track = track, item = item }
		content.ScrollingEnabled = false
		setFromX(item, track, input.Position.X)
	end)
	UIEffects.bindHover(track, { Scale = 1, Sound = true })
	row.ValueBox.FocusLost:Connect(function()
		local number = tonumber(row.ValueBox.Text:gsub(",", "."))
		if not number or not Controller.Set(item.Id, number) then
			paint(item.Id)
		end
	end)
	track.SelectionGained:Connect(function()
		track.Rail.BackgroundColor3 = Color3.fromRGB(23, 55, 65)
	end)
	track.SelectionLost:Connect(function()
		track.Rail.BackgroundColor3 = Color3.fromRGB(5, 5, 14)
	end)
	track.InputBegan:Connect(function(input)
		if input.KeyCode == Enum.KeyCode.Left or input.KeyCode == Enum.KeyCode.DPadLeft then
			Controller.Set(item.Id, values[item.Id] - item.Step)
		elseif input.KeyCode == Enum.KeyCode.Right or input.KeyCode == Enum.KeyCode.DPadRight then
			Controller.Set(item.Id, values[item.Id] + item.Step)
		end
	end)
end
local function showStats()
	overlay.Title.Text = "YOUR STATS"
	overlay.ScopePreview.Visible = false
	overlay.Body.Visible = true
	local lines = {}
	local stats = player:FindFirstChild("leaderstats")
	if stats then
		for _, stat in stats:GetChildren() do
			if stat:IsA("ValueBase") then
				table.insert(lines, stat.Name .. ":  " .. tostring(stat.Value))
			end
		end
	end
	if #lines == 0 then
		table.insert(lines, player.DisplayName)
		table.insert(lines, "@" .. player.Name)
		table.insert(lines, "")
		table.insert(lines, "No race stats yet.")
	end
	overlay.Body.Text = table.concat(lines, "\n")
	content.Visible = false
	overlay.Visible = true
end
local function showScope()
	overlay.Title.Text = "SCOPE " .. values.ScopeType
	overlay.Body.Visible = false
	overlay.ScopePreview.Visible = true
	paintScope(overlay.ScopePreview, values.ScopeType)
	content.Visible = false
	overlay.Visible = true
end
local function buildRows()
	for _, child in content:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	for index, item in Config.Rows do
		local template = if item.Kind == "Slider"
			then "SettingsSlider"
			elseif item.Kind == "Scope" then "SettingsScope"
			else "SettingsToggle"
		local row = UITemplates.clone(template)
		if not row then
			continue
		end
		row.Name = item.Id
		row.LayoutOrder = index
		row.NameLabel.Text = item.Label
		row.Parent = content
		rows[item.Id] = row
		if item.Kind == "Slider" then
			bindSlider(row, item)
		else
			UIEffects.bindButton(row.ActionButton, function()
				if item.Kind == "Action" then
					showStats()
				elseif item.Kind == "Scope" then
					Controller.Set(item.Id, values[item.Id] % item.Count + 1)
				else
					if Controller.Set(item.Id, not values[item.Id]) and not UIEffects.ClickSoundEnabled then
						-- bindButton ya reproduce el clic cuando está habilitado globalmente.
						UIEffects.playOneShot(toggleSound)
					end
				end
			end)
			UIEffects.bindHover(row.ActionButton, { Scale = 1.06, Rotation = 5, Duration = 0.14 })
			if item.Kind == "Scope" then
				UIEffects.bindButton(row.Preview, showScope)
				UIEffects.bindHover(row.Preview, { Scale = 1.02 })
			end
		end
		paint(item.Id)
	end
end
local function scaleStrokes()
	local factor = math.clamp(main.AbsoluteSize.X / 900, 0.5, 1)
	for _, s in main:GetDescendants() do
		if s:IsA("UIStroke") and s:GetAttribute("ResponsiveThickness") == true then
			-- Opt-in: sin el atributo se respeta el Thickness diseñado en SettingsGui.
			local base = s:GetAttribute("BaseThickness") or s.Thickness
			s.Thickness = math.max(1, base * factor)
		end
	end
end
local function fitRows()
	local width = content.AbsoluteSize.X
	if width <= 0 then
		return
	end
	local side = math.floor(width * 0.06)
	local rowWidth = math.max(1, width - side * 2)
	local compact = rowWidth < 480
	local shortScreen = gui.AbsoluteSize.Y < 450
	local height = if shortScreen then 64 else math.clamp(rowWidth * 0.12, 64, 104)
	local gap = math.clamp(rowWidth * 0.025, 12, 20)
	local pad = content.UIPadding
	pad.PaddingLeft = UDim.new(0, side)
	pad.PaddingRight = UDim.new(0, side)
	pad.PaddingTop = UDim.new(0, if shortScreen then 14 else math.clamp(width * 0.075, 22, 62))
	pad.PaddingBottom = UDim.new(0, 18)
	content.UIListLayout.Padding = UDim.new(0, gap)
	for id, row in rows do
		local item = definitions[id]
		local h = if item.Kind == "Scope"
			then math.max(130, height * 1.65)
			elseif compact and item.Kind == "Slider" then 106
			else height
		row.Size = UDim2.new(1, 0, 0, h)
		row.NameLabel.TextLimit.MaxTextSize = math.clamp(rowWidth * 0.047, 18, 38)
		if item.Kind == "Slider" then
			if compact then
				row.NameLabel.Position = UDim2.fromScale(0.035, 0.05)
				row.NameLabel.Size = UDim2.fromScale(0.93, 0.34)
				row.ValueBox.Position = UDim2.fromScale(0.035, 0.47)
				row.ValueBox.Size = UDim2.fromScale(0.23, 0.43)
				row.Slider.Position = UDim2.fromScale(0.32, 0.42)
				row.Slider.Size = UDim2.fromScale(0.62, 0.54)
			else
				row.NameLabel.Position = UDim2.fromScale(0.018, 0.1)
				row.NameLabel.Size = UDim2.fromScale(0.425, 0.8)
				row.ValueBox.Position = UDim2.fromScale(0.45, 0.18)
				row.ValueBox.Size = UDim2.fromScale(0.16, 0.64)
				row.Slider.Position = UDim2.fromScale(0.65, 0.16)
				row.Slider.Size = UDim2.fromScale(0.31, 0.68)
			end
			local k = math.clamp(height * 0.29, 24, 30)
			row.Slider.Knob.Size = UDim2.fromOffset(k, k)
		elseif item.Kind == "Scope" then
			row.NameLabel.Size = UDim2.fromScale(0.71, 0.34)
			row.ActionButton.Position = UDim2.fromScale(0.04, 0.58)
			row.ActionButton.Size = UDim2.fromScale(if compact then 0.39 else 0.27, 0.33)
			row.ActionButton.Label.TextLimit.MaxTextSize = if compact then 22 else 34
			row.Preview.Size = UDim2.fromOffset(h * 0.82, h * 0.82)
			row.Hint.Text = if UIS.TouchEnabled then "Tap to preview" else "Click to view full scale"
			row.Hint.Position = UDim2.fromScale(0.04, 0.41)
			row.Hint.Size = UDim2.fromScale(0.5, 0.15)
			row.Hint.TextXAlignment = Enum.TextXAlignment.Left
		else
			row.NameLabel.Position = UDim2.fromScale(0.02, 0.1)
			row.NameLabel.Size = UDim2.fromScale(if compact then 0.67 else 0.74, 0.8)
			local actionPosition = UDim2.fromScale(if compact then 0.73 else 0.79, 0.15)
			local actionSize = UDim2.fromScale(if compact then 0.23 else 0.16, 0.7)
			row.ActionButton.Position = actionPosition
			row.ActionButton.Size = actionSize
			row.ActionButton.Label.TextLimit.MaxTextSize = if item.Kind == "Toggle"
				then (if compact then 32 else 47)
				else (if compact then 26 else 38)
			if item.Kind == "Toggle" then
				-- AnchorPoint central hace que UIScale expanda por igual hacia ambos lados.
				local button = row.ActionButton
				button.AnchorPoint = Vector2.new(0.5, 0.5)
				button.Position = UDim2.new(
					actionPosition.X.Scale + actionSize.X.Scale * 0.5,
					actionPosition.X.Offset + actionSize.X.Offset * 0.5,
					actionPosition.Y.Scale + actionSize.Y.Scale * 0.5,
					actionPosition.Y.Offset + actionSize.Y.Offset * 0.5
				)
				button.Size = UDim2.new(
					actionSize.X.Scale * 0.92,
					actionSize.X.Offset * 0.92,
					actionSize.Y.Scale * 0.92,
					actionSize.Y.Offset * 0.92
				)
				button.Label.Position = UDim2.fromScale(0.04, 0.035)
				button.Label.Size = UDim2.fromScale(0.92, 0.93)
			end
		end
	end
	content.CanvasSize = UDim2.fromOffset(
		0,
		content.UIListLayout.AbsoluteContentSize.Y + pad.PaddingTop.Offset + pad.PaddingBottom.Offset
	)
	scaleStrokes()
end
local function fitWindow()
	local size = gui.AbsoluteSize
	if size.X <= 0 or size.Y <= 0 then
		return
	end
	local _, height = WindowLayout.fitMain(size, main)
	local headerHeight = WindowLayout.fitHeader(main.Header, height, 88, 52)
	content.Position = UDim2.fromOffset(0, headerHeight + 6)
	content.Size = UDim2.new(1, 0, 1, -headerHeight - 14)
	overlay.Position = UDim2.fromOffset(12, headerHeight + 14)
	overlay.Size = UDim2.new(1, -24, 1, -headerHeight - 28)
	fitRows()
end
local function watchCamera()
	if cameraConnection then
		cameraConnection:Disconnect()
	end
	local camera = Workspace.CurrentCamera
	if camera then
		camera.FieldOfView = values.CameraFOV
		cameraConnection = camera:GetPropertyChangedSignal("ViewportSize"):Connect(fitWindow)
	end
	fitWindow()
end
function Controller.Init()
	if initialized then
		return
	end
	initialized = true
	gui = UIManager.WaitForGui("SettingsGui")
	if not gui then
		return
	end
	main = gui:WaitForChild("Main")
	content = main:WaitForChild("Content")
	overlay = main:WaitForChild("DetailOverlay")
	overlay.Visible = false
	values.Shadows = Lighting.GlobalShadows
	toggleSound = UIEffects.makeSound("SettingsToggleClick", UIEffects.ClickSoundId, UIEffects.ClickVolume)
	buildRows()
	bindMusic()
	for id, value in values do
		player:SetAttribute("Settings_" .. id, value)
	end
	setBlur = UIEffects.makeBlur("SettingsBlur", Config.Blur.Size, Config.Blur.Duration)
	if toggleSound then
		task.spawn(function()
			pcall(ContentProvider.PreloadAsync, ContentProvider, { toggleSound })
		end)
	end
	UIManager.Register("Settings", main, { HiddenScale = Config.Open.FromScale, OpenDuration = Config.Open.Duration })
	UIManager.OnOpened("Settings", function()
		overlay.Visible = false
		content.Visible = true
		setBlur(true)
	end)
	UIManager.OnClosed("Settings", function()
		endDrag()
		overlay.Visible = false
		setBlur(false)
	end)
	UIEffects.bindHover(main.Header.CloseButton, { Scale = 1.08, Rotation = 5 })
	UIEffects.bindButton(overlay.BackButton, function()
		overlay.Visible = false
		content.Visible = true
	end)
	UIEffects.bindHover(overlay.BackButton, { Scale = 1.06, Rotation = 5, Duration = 0.14 })
	UIS.InputChanged:Connect(function(input)
		local drag = activeDrag
		if not drag then
			return
		end
		if
			input == drag.input
			or (
				drag.input.UserInputType == Enum.UserInputType.MouseButton1
				and input.UserInputType == Enum.UserInputType.MouseMovement
			)
		then
			setFromX(drag.item, drag.track, input.Position.X)
		end
	end)
	UIS.InputEnded:Connect(function(input)
		if activeDrag and (input == activeDrag.input or input.UserInputType == Enum.UserInputType.MouseButton1) then
			endDrag()
		end
	end)
	UIS.WindowFocusReleased:Connect(endDrag)
	UIS.InputBegan:Connect(function(input, processed)
		if processed or not UIManager.IsOpen("Settings") then
			return
		end
		if input.KeyCode == Enum.KeyCode.ButtonB then
			if overlay.Visible then
				overlay.Visible = false
				content.Visible = true
			else
				UIManager.Close("Settings")
			end
		end
	end)
	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(fitWindow)
	content:GetPropertyChangedSignal("AbsoluteSize"):Connect(fitRows)
	content.UIListLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
		content.CanvasSize = UDim2.fromOffset(
			0,
			content.UIListLayout.AbsoluteContentSize.Y
				+ content.UIPadding.PaddingTop.Offset
				+ content.UIPadding.PaddingBottom.Offset
		)
	end)
	Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(watchCamera)
	watchCamera()
	task.defer(fitWindow)
end
return Controller
