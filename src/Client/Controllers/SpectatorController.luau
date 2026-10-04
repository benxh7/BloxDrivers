-- Ubicación en Studio: StarterPlayer > StarterPlayerScripts > Controllers > SpectatorController (ModuleScript)
-- Modo espectador (botón SpectateButton del HUD) y panel de reportes "SpectatorReport".
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Input = game:GetService("UserInputService")
local TextService = game:GetService("TextService")
local Config = require(RS:WaitForChild("SpectatorConfig"))
local Remotes = require(RS:WaitForChild("Remotes"))
local UIManager = require(script.Parent.UIManager)
local HUDController = require(script.Parent.HUDController)
local Utils = script.Parent.Parent.Utils
local Effects = require(Utils.UIEffects)
local Notify = require(Utils.Notifications)
local Controller = {}
local player = Players.LocalPlayer
local gui, controls, revive, report, main, detailsBox
local target, reportTarget, selected
local active = false
local savedCamera, savedSubject, savedType
local sending = false
local measureVersion = 0
local function sizeDetails()
	measureVersion += 1
	local version = measureVersion
	local text = detailsBox.Text
	detailsBox.AutomaticSize = Enum.AutomaticSize.None
	detailsBox.TextScaled = text == ""
	detailsBox.TextSize = if text == "" then 46 else 26
	if text == "" then
		detailsBox.Size = UDim2.new(1, -6, 1, 0)
		return
	end
	task.spawn(function()
		local scale = report.ResponsiveScale.Scale
		local params = Instance.new("GetTextBoundsParams")
		params.Font = detailsBox.FontFace
		params.Size = 26
		params.Text = text
		params.Width = math.max(1, main.DetailsCard.DetailsScroll.AbsoluteSize.X / scale - 38)
		local ok, bounds = pcall(function()
			return TextService:GetTextBoundsAsync(params)
		end)
		params:Destroy()
		if version ~= measureVersion or not detailsBox.Parent then
			return
		end
		local height = if ok then bounds.Y + 42 else math.ceil(#text / 24) * 30 + 42
		detailsBox.Size = UDim2.new(1, -6, 0, math.max(main.DetailsCard.DetailsScroll.AbsoluteSize.Y / scale, height))
	end)
end
local function toast(code, theme)
	Notify.Show(Config.Messages[code] or code, { Theme = theme or "Error", Duration = 3 })
end
local function targets()
	local list = {}
	if Config.DebugSelfSpectate and RunService:IsStudio() then
		local own = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		if own and own.Health > 0 then
			table.insert(list, player)
		end
	end
	if RS:GetAttribute(Config.RoundAttribute) ~= true then
		return list
	end
	for _, p in Players:GetPlayers() do
		local h = p.Character and p.Character:FindFirstChildOfClass("Humanoid")
		if p ~= player and p:GetAttribute(Config.ParticipantAttribute) == true and h and h.Health > 0 then
			table.insert(list, p)
		end
	end
	table.sort(list, function(a, b)
		return a.UserId < b.UserId
	end)
	return list
end
local function closeReport()
	UIManager.Close("SpectatorReport")
	reportTarget = nil
	selected = nil
end
local function restoreCamera()
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	local own = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	camera.CameraType = if savedCamera == camera then savedType or Enum.CameraType.Custom else Enum.CameraType.Custom
	camera.CameraSubject = if savedSubject and savedSubject.Parent then savedSubject else own
end
function Controller.Stop()
	if not active then
		return
	end
	active = false
	target = nil
	closeReport()
	controls.Visible = false
	revive.Visible = false
	Remotes.event("SetSpectatorTarget"):FireServer(0)
	restoreCamera()
end
local function showTarget(p)
	target = p
	local camera = workspace.CurrentCamera
	local humanoid = p.Character and p.Character:FindFirstChildOfClass("Humanoid")
	if camera and humanoid then
		camera.CameraType = Enum.CameraType.Custom
		camera.CameraSubject = humanoid
	end
	local role = p:GetAttribute(Config.RoleAttribute)
	if p == player and Config.DebugSelfSpectate and RunService:IsStudio() then
		role = "DEBUG SELF"
	end
	controls.TargetLabel.Text = ("SPECTATING: %s [%s]"):format(
		p.DisplayName,
		type(role) == "string" and role:upper() or "PLAYER"
	)
	Remotes.event("SetSpectatorTarget"):FireServer(p.UserId)
end
function Controller.Start()
	if active then
		Controller.Stop()
		return
	end
	local list = targets()
	if #list == 0 then
		toast("Empty")
		return
	end
	UIManager.CloseAll()
	savedCamera = workspace.CurrentCamera
	savedSubject = savedCamera and savedCamera.CameraSubject
	savedType = savedCamera and savedCamera.CameraType
	active = true
	controls.Visible = true
	revive.Visible = Config.Revive.Visible
	showTarget(list[1])
end
local function cycle(direction)
	local list = targets()
	if #list == 0 then
		Controller.Stop()
		toast("Empty")
		return
	end
	local index = table.find(list, target) or 1
	closeReport()
	showTarget(list[(index - 1 + direction) % #list + 1])
end
local function styleSelection()
	for _, entry in Config.Reasons do
		local row = main.Reasons:FindFirstChild(entry.Id, true)
		if row then
			local on = selected == entry.Id
			TweenService:Create(
				row.Outline,
				TweenInfo.new(0.12),
				{ Color = if on then Color3.fromRGB(255, 78, 83) else Color3.new() }
			):Play()
		end
	end
end
local function fit()
	local s = gui.AbsoluteSize
	local reportOpen = UIManager.IsOpen("SpectatorReport")
	local scale = math.min(1, (s.X - 28) / 500, s.Y * 0.23 / 130)
	controls.Visible = active and not reportOpen
	controls.ResponsiveScale.Scale = scale
	controls.Position = UDim2.new(0.5, 0, 1, -12)
	revive.ResponsiveScale.Scale = math.min(1, scale)
	revive.Position = UDim2.new(0.5, 0, 1, -(130 * scale + 37))
	revive.Visible = active and Config.Revive.Visible and not reportOpen
	local reportScale = math.max(0.1, math.min(1, (s.X - 40) / report.Size.X.Offset, (s.Y - 48) / report.Size.Y.Offset))
	report.ResponsiveScale.Scale = reportScale
	report.Position = UDim2.fromScale(0.5, 0.5)
	main.Reasons.CanvasSize = UDim2.fromOffset(0, main.Reasons.Layout.AbsoluteContentSize.Y / reportScale + 4)
	sizeDetails()
end
local function openReport()
	if not target then
		return
	end
	reportTarget = target.UserId
	selected = nil
	main.PlayerName.Text = target.Name
	detailsBox.Text = ""
	main.DetailsCard.DetailsScroll.CanvasPosition = Vector2.zero
	styleSelection()
	UIManager.Open("SpectatorReport")
	fit()
end
local function send()
	if sending or not reportTarget then
		return
	end
	local details = detailsBox.Text
	if details:gsub("%s", ""):gsub(utf8.char(0x200B), ""):gsub(utf8.char(0xA0), "") == "" then
		toast("Details")
		return
	end
	if not selected then
		toast("Reason")
		return
	end
	if not utf8.len(details) or utf8.len(details) > Config.MaxDetailsLength then
		toast("TooLong")
		return
	end
	sending = true
	report.SendButton.Label.Text = "Sending..."
	report.SendButton.Interactable = false
	local id = reportTarget
	local reason = selected
	task.spawn(function()
		local ok, result = pcall(function()
			return Remotes.func("SubmitPlayerReport"):InvokeServer(id, reason, details)
		end)
		sending = false
		report.SendButton.Label.Text = "Send"
		report.SendButton.Interactable = true
		if not ok or type(result) ~= "table" then
			toast("Failed")
			return
		end
		if result.Code == "Cooldown" then
			toast(("Please wait %d seconds before reporting this player again."):format(result.Remaining or 60))
			return
		end
		toast(
			result.Code,
			if result.Ok
				then (if result.Code == "Preview" or result.Code == "DebugPreview" then "Info" else "Success")
				else "Error"
		)
		if result.Ok and reportTarget == id then
			closeReport()
			fit()
		end
	end)
end
function Controller.Init()
	gui = UIManager.WaitForGui("SpectatorGui")
	controls = gui.Controls
	revive = gui.Revive
	report = gui.ReportPanel
	main = report.Main
	detailsBox = main.DetailsCard.DetailsScroll.Details
	revive.ReviveButton.Heart.Image = Config.HeartIcon
	-- Latido opt-in (atributo HeartbeatEnabled) en esta imagen, no en la plantilla compartida.
	local heart = revive.ReviveButton.Heart
	local beatScale = heart:FindFirstChild("HeartbeatScale") or Instance.new("UIScale")
	beatScale.Name = "HeartbeatScale"
	beatScale.Parent = heart
	local elapsed = 0
	local beatConnection
	beatConnection = RunService.RenderStepped:Connect(function(dt)
		if not gui.Parent then
			beatConnection:Disconnect()
			return
		end
		if
			not gui.Enabled
			or not revive.Visible
			or not heart.Visible
			or heart:GetAttribute("HeartbeatEnabled") ~= true
		then
			elapsed = 0
			beatScale.Scale = 1
			return
		end
		local period = math.max(0.8, tonumber(heart:GetAttribute("HeartbeatPeriod")) or 1.5)
		elapsed = (elapsed + dt) % period
		local phase = elapsed / period
		local pulse = 0
		if phase < 0.22 then
			pulse = math.sin(math.pi * phase / 0.22) ^ 2
		elseif phase >= 0.28 and phase < 0.46 then
			pulse = 0.65 * math.sin(math.pi * (phase - 0.28) / 0.18) ^ 2
		end
		local peak = math.clamp(tonumber(heart:GetAttribute("HeartbeatMaxScale")) or 1.09, 1, 1.2)
		beatScale.Scale = 1 + (peak - 1) * pulse
	end)
	UIManager.Register("SpectatorReport", report, { Animate = false })
	UIManager.OnClosed("SpectatorReport", function()
		reportTarget = nil
		selected = nil
		detailsBox:ReleaseFocus()
		fit()
	end)
	UIManager.Opened:Connect(function(name)
		if active and name ~= "SpectatorReport" then
			Controller.Stop()
		end
	end)
	local hud = UIManager.WaitForGui("HUD")
	local entry = hud.LeftButtons:WaitForChild("SpectateButton")
	entry.Icon.Image = Config.HUDIcon
	HUDController.BindButton(entry, Controller.Start)
	for name, callback in
		{
			PreviousButton = function()
				cycle(-1)
			end,
			NextButton = function()
				cycle(1)
			end,
			ExitButton = Controller.Stop,
			ReportButton = openReport,
		}
	do
		Effects.bindButton(controls[name], callback)
		Effects.bindHover(controls[name], Config.Hover)
	end
	Effects.bindButton(revive.ReviveButton, function()
		toast("Revive", "Info")
	end)
	Effects.bindHover(revive.ReviveButton, Config.Hover)
	Effects.bindHover(main.CloseButton, Config.Hover)
	Effects.bindButton(report.SendButton, send)
	Effects.bindHover(report.SendButton, Config.Hover)
	local sendButton = report.SendButton
	local function shade(on)
		TweenService:Create(
			sendButton,
			TweenInfo.new(0.14),
			{ BackgroundColor3 = if on then Color3.fromRGB(195, 195, 195) else Color3.new(1, 1, 1) }
		):Play()
	end
	sendButton.MouseEnter:Connect(function()
		if Input.MouseEnabled then
			shade(true)
		end
	end)
	sendButton.MouseLeave:Connect(function()
		shade(false)
	end)
	for _, entryData in Config.Reasons do
		local row = main.Reasons:FindFirstChild(entryData.Id, true)
		if row then
			local scale = row:FindFirstChild("ReasonScale") or Instance.new("UIScale")
			scale.Name = "ReasonScale"
			scale.Parent = row
			local hovered = false
			local tween
			local sequence = 0
			local function animate(value, duration)
				if tween then
					tween:Cancel()
				end
				tween = TweenService:Create(
					scale,
					TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
					{ Scale = value }
				)
				tween:Play()
			end
			row.MouseEnter:Connect(function()
				if not Input.MouseEnabled then
					return
				end
				hovered = true
				Effects.playHoverSound()
				animate(1.01, 0.12)
			end)
			row.MouseLeave:Connect(function()
				hovered = false
				animate(1, 0.12)
			end)
			row.Activated:Connect(function()
				Effects.playClickSound()
				selected = entryData.Id
				styleSelection()
				sequence += 1
				local current = sequence
				animate(1.025, 0.1)
				task.delay(0.1, function()
					if sequence == current and row.Parent then
						animate(if hovered then 1.01 else 1, 0.14)
					end
				end)
			end)
		end
	end
	detailsBox:GetPropertyChangedSignal("Text"):Connect(function()
		local count = utf8.len(detailsBox.Text) or #detailsBox.Text
		sizeDetails()
		main.DetailsCard.CharacterCount.Text = ("%d / %d"):format(count, Config.MaxDetailsLength)
		main.DetailsCard.CharacterCount.TextColor3 = if count > Config.MaxDetailsLength
			then Color3.fromRGB(255, 80, 90)
			else Color3.new(1, 1, 1)
	end)
	local function updateRevives()
		local count = player:GetAttribute(Config.Revive.Attribute)
		revive.Count.Text = "Revives : "
			.. tostring(if type(count) == "number" then math.max(0, math.floor(count)) else 0)
	end
	player:GetAttributeChangedSignal(Config.Revive.Attribute):Connect(updateRevives)
	updateRevives()
	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)
	player.CharacterAdded:Connect(function()
		Controller.Stop()
	end)
	workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
		if active and target then
			showTarget(target)
		end
	end)
	Input.InputBegan:Connect(function(input, processed)
		if processed or not active then
			return
		end
		if input.KeyCode == Enum.KeyCode.Escape or input.KeyCode == Enum.KeyCode.ButtonB then
			if UIManager.IsOpen("SpectatorReport") then
				closeReport()
				fit()
			else
				Controller.Stop()
			end
		end
	end)
	fit()
	task.spawn(function()
		while gui.Parent do
			task.wait(0.35)
			if active then
				local list = targets()
				if #list == 0 then
					Controller.Stop()
					toast("Empty")
				elseif not table.find(list, target) then
					closeReport()
					showTarget(list[1])
					fit()
				else
					local h = target.Character and target.Character:FindFirstChildOfClass("Humanoid")
					local camera = workspace.CurrentCamera
					if camera and h and camera.CameraSubject ~= h then
						camera.CameraSubject = h
					end
				end
			end
		end
	end)
end
return Controller
