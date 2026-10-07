-- Ubicación en Studio: StarterPlayer > StarterPlayerScripts > Controllers > DailyController (ModuleScript)
-- Demo local: estado por sesión, sin premios reales ni persistencia.
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Config = require(RS:WaitForChild("DailyConfig"))
local UIManager = require(script.Parent.UIManager)
local UIEffects = require(script.Parent.Parent.Utils.UIEffects)
local WindowLayout = require(script.Parent.Parent.Utils.WindowLayout)
local Notifications = require(script.Parent.Parent.Utils.Notifications)
local Controller = {}
local claimedCount = if RunService:IsStudio()
	then math.clamp(math.floor(Config.StudioClaimedDays), 0, #Config.Rewards)
	else 0
local nextClaimAt = 0
local cards = {}
local chromaTweens = {}
local gui, main, content
local initialized = false
function Controller.GetState(day)
	if type(day) ~= "number" or day % 1 ~= 0 or not Config.Rewards[day] then
		return nil
	end
	if day <= claimedCount then
		return "Claimed"
	end
	if day == claimedCount + 1 and os.time() >= nextClaimAt then
		return "Ready"
	end
	return "Locked"
end
local function refresh()
	for day, card in cards do
		local state = Controller.GetState(day)
		card.Status.Text = Config.States[state].Text
		card.Status.TextColor3 = Config.States[state].Color
		card.Selectable = state == "Ready"
		card:SetAttribute("RewardState", state)
	end
end
function Controller.Claim(day)
	if Controller.GetState(day) ~= "Ready" then
		return false
	end
	claimedCount = day
	nextClaimAt = os.time() + math.max(1, Config.DaySeconds)
	refresh()
	Notifications.Show(
		"Claimed " .. Config.Rewards[day].Title .. "!",
		{ Theme = "Success", SoundId = "rbxassetid://109742263473623" }
	)
	return true
end
local function fit()
	if not gui or gui.AbsoluteSize.X <= 0 then
		return
	end
	local screen = gui.AbsoluteSize
	local width = math.min(1240, screen.X * 0.94)
	local height = math.min(width * 460 / 1195, screen.Y * 0.90)
	main.Size = UDim2.fromOffset(width, height)
	main.Position = UDim2.fromScale(0.5, 0.53)
	local hh = WindowLayout.fitHeader(main.Header, height, 78, 48)
	local margin = math.max(12, width * 0.022)
	local w = width - margin * 2
	local h = height - hh - 24
	content.Position = UDim2.fromOffset(margin, hh + 10)
	content.Size = UDim2.new(1, -margin * 2, 1, -hh - 24)
	local columns = if w >= 900 then 7 elseif w >= 520 then 4 elseif w >= 380 then 3 else 2
	local rowCount = math.ceil(#Config.Rewards / columns)
	local gapX = if columns == 7 then width * 40 / 1195 else math.clamp(w * 0.027, 14, 28)
	local gapY = 40
	local pad = 10
	local top = 24
	local cw = (w - pad * 2 - (columns - 1) * gapX) / columns
	local ch = (
		if columns == 7 then cw * 140 / 130 else math.clamp((h - top - 20 - (rowCount - 1) * gapY) / rowCount, 130, 190)
	) * 0.92
	for day, card in cards do
		local row = math.floor((day - 1) / columns)
		local col = (day - 1) % columns
		card.Parent.Position = UDim2.fromOffset(pad + col * (cw + gapX), top + row * (ch + gapY))
		card.Parent.Size = UDim2.fromOffset(cw, ch)
	end
	local canvas = top + rowCount * ch + (rowCount - 1) * gapY + 20
	content.CanvasSize = UDim2.fromOffset(0, canvas)
	content.ScrollBarThickness = if canvas > h + 1 then 4 else 0
end
function Controller.Init()
	if initialized then
		return
	end
	initialized = true
	gui = UIManager.WaitForGui("DailyRewardsGui")
	main = gui:WaitForChild("Main")
	content = main:WaitForChild("Content")
	for day, item in Config.Rewards do
		local slot = Instance.new("Frame")
		slot.Name = "Day" .. day .. "Slot"
		slot.BackgroundTransparency = 1
		slot.Parent = content
		local card = RS.UITemplates.DailyCard:Clone()
		card.Name = "Day" .. day
		card.DayLabel.Text = "Day " .. day
		card.RewardLabel.Text = item.Title
		card.Icon.Image = item.Icon
		card.Parent = slot
		cards[day] = card
		if item.Special then
			card.UIGradient.Rotation = 25
			card.UIGradient.Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 62, 156)),
				ColorSequenceKeypoint.new(0.25, Color3.fromRGB(180, 55, 255)),
				ColorSequenceKeypoint.new(0.5, Color3.fromRGB(54, 203, 255)),
				ColorSequenceKeypoint.new(0.75, Color3.fromRGB(114, 255, 59)),
				ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 211, 59)),
			})
			if day == 7 or day == 14 then
				table.insert(
					chromaTweens,
					TweenService:Create(
						card.UIGradient,
						TweenInfo.new(8, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, -1),
						{ Rotation = 385 }
					)
				)
			end
		end
		if item.SpinDecal then
			card.SpinDecal.Visible = true
			table.insert(
				chromaTweens,
				TweenService:Create(
					card.SpinDecal,
					TweenInfo.new(Config.SpinSecondsPerTurn, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, -1),
					{ Rotation = 360 }
				)
			)
		end
		if item.IconCount == 2 then
			card.Icon.Size = UDim2.fromScale(0.60, 0.58)
			card.Icon.Position = UDim2.fromScale(0.34, 0.34)
			local second = card.Icon:Clone()
			second.Name = "SecondIcon"
			second.Position = UDim2.fromScale(0.66, 0.43)
			second.Parent = card
		end
		UIEffects.bindButton(card, function()
			Controller.Claim(day)
		end)
		UIEffects.bindHover(card, { Scale = 1.05, Rotation = 5, Duration = 0.15 })
	end
	local setBlur = UIEffects.makeBlur("DailyBlur", 16, 0.2)
	UIManager.Register("DailyRewards", main, { HiddenScale = 0.1, OpenDuration = 0.35, CloseOnButtonB = true })
	UIManager.OnOpened("DailyRewards", function()
		refresh()
		for _, tween in chromaTweens do
			tween:Play()
		end
		setBlur(true)
	end)
	UIManager.OnClosed("DailyRewards", function()
		for _, tween in chromaTweens do
			tween:Pause()
		end
		setBlur(false)
	end)
	gui.Destroying:Connect(function()
		for _, tween in chromaTweens do
			tween:Cancel()
		end
		table.clear(chromaTweens)
	end)
	UIEffects.bindHover(main.Header.CloseButton, { Scale = 1.08, Rotation = 5, Duration = 0.14 })
	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)
	fit()
	refresh()
	gui:SetAttribute("ControllerReady", true)
	task.spawn(function()
		while gui.Parent do
			refresh()
			task.wait(1)
		end
	end)
end
return Controller
