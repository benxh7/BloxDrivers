-- Ubicación en Studio: StarterPlayer > StarterPlayerScripts > Controllers > PlaytimeController (ModuleScript)
-- Demo de sesión, exclusivamente visual. No remotes, currency grants ni DataStores.
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Config = require(RS:WaitForChild("PlaytimeConfig"))
local UIManager = require(script.Parent.UIManager)
local UIEffects = require(script.Parent.Parent.Utils.UIEffects)
local WindowLayout = require(script.Parent.Parent.Utils.WindowLayout)
local Notifications = require(script.Parent.Parent.Utils.Notifications)
local Controller = {}
local startTime = os.clock()
local claimed = {}
local cards = {}
local definitions = {}
local gui, main, content
local initialized = false
for _, reward in Config.Rewards do
	assert(not definitions[reward.Id], "Duplicate playtime reward: " .. reward.Id)
	definitions[reward.Id] = reward
end
local function elapsed()
	return os.clock() - startTime + (if RunService:IsStudio() then math.max(0, Config.StudioTimeOffsetSeconds) else 0)
end
function Controller.GetState(id)
	local item = definitions[id]
	if not item then
		return nil
	end
	if claimed[id] then
		return "Claimed", 0
	end
	local remaining = math.max(0, math.ceil(item.Seconds - elapsed()))
	return if remaining == 0 then "Ready" else "Waiting", remaining
end
local function clockText(seconds)
	return string.format("%02d:%02d:%02d", math.floor(seconds / 3600), math.floor(seconds / 60) % 60, seconds % 60)
end
local function updateCard(id)
	local card = cards[id]
	if not card then
		return
	end
	local state, remaining = Controller.GetState(id)
	local style = Config.States[state]
	card.Status.Text = style.Text or clockText(remaining)
	card.Status.TextColor3 = style.Color
	card:SetAttribute("RewardState", state)
	card:SetAttribute("RemainingSeconds", remaining)
	card.Selectable = state == "Ready"
end
function Controller.Claim(id)
	if Controller.GetState(id) ~= "Ready" then
		return false
	end
	claimed[id] = true
	updateCard(id)
	Notifications.Show(
		"Claimed " .. definitions[id].Title .. "!",
		{ Theme = "Success", SoundId = "rbxassetid://109742263473623" }
	)
	return true
end
local function fit()
	if not gui or gui.AbsoluteSize.X <= 0 then
		return
	end
	local screen = gui.AbsoluteSize
	local width = math.min(920, screen.X * 0.86, screen.Y * 0.84 * 674 / 534)
	local height = width * 534 / 674
	main.Size = UDim2.fromOffset(math.floor(width), math.floor(height))
	main.Position = UDim2.fromScale(0.5, 0.53)
	local hh = WindowLayout.fitHeader(main.Header, height, 88, 52)
	local margin = math.max(10, width * 0.025)
	content.Position = UDim2.fromOffset(margin, hh + 12)
	content.Size = UDim2.new(1, -margin * 2, 1, -hh - 26)
	local availableW = width - margin * 2
	local availableH = height - hh - 26
	local narrow = availableW < 430
	local rows = Config.Rows
	if narrow then
		rows = {}
		for index, item in Config.Rewards do
			local row = math.ceil(index / 2)
			rows[row] = rows[row] or {}
			table.insert(rows[row], item.Id)
		end
	end
	local gap = width * 10 / 674
	local pad = 5
	local cardH = if narrow
		then math.max(124, availableW * 0.44)
		else math.max(116, (availableH - pad * 2 - gap * 2) / 3)
	for rowIndex, row in rows do
		local count = #row
		local rowGap = if narrow then gap elseif count == 4 then width * 26 / 674 else width * 8 / 674
		local cardW = (availableW - pad * 2 - rowGap * (count - 1)) / count
		local rowH = if narrow then cardH elseif count == 4 then cardW else cardW * 115 / 210
		local rowY = if narrow
			then pad + (rowIndex - 1) * (cardH + gap)
			else pad + (rowIndex - 1) * ((availableW - pad * 2 - width * 78 / 674) / 4 + gap)
		for column, id in row do
			local card = cards[id]
			local slot = card.Parent
			slot.Position = UDim2.fromOffset(pad + (column - 1) * (cardW + rowGap), rowY)
			slot.Size = UDim2.fromOffset(cardW, rowH)
		end
	end
	local canvas = pad * 2 + #rows * cardH + (#rows - 1) * gap
	if not narrow then
		canvas = 0
		for _, card in cards do
			canvas = math.max(canvas, card.Parent.Position.Y.Offset + card.Parent.Size.Y.Offset + pad)
		end
	end
	content.CanvasSize = UDim2.fromOffset(0, canvas)
	content.ScrollBarThickness = if canvas > availableH + 1 then 4 else 0
end
function Controller.Init()
	if initialized then
		return
	end
	initialized = true
	gui = UIManager.WaitForGui("PlaytimeRewardsGui")
	main = gui:WaitForChild("Main")
	content = main:WaitForChild("Content")
	local template = RS.UITemplates:WaitForChild("PlaytimeCard")
	for _, item in Config.Rewards do
		local slot = Instance.new("Frame")
		slot.Name = item.Id .. "Slot"
		slot.BackgroundTransparency = 1
		slot.BorderSizePixel = 0
		slot.Parent = content
		local card = template:Clone()
		card.Name = item.Id
		card.Title.Text = item.CardTitle or item.Title
		card.Icon.Image = item.Icon
		card.Size = UDim2.fromScale(Config.CardScale, Config.CardScale)
		card.Parent = slot
		if item.IconCount == 2 then
			card.Icon.Size = UDim2.fromScale(0.52, 0.63)
			card.Icon.Position = UDim2.fromScale(0.37, 0.50)
			local second = card.Icon:Clone()
			second.Name = "SecondIcon"
			second.Position = UDim2.fromScale(0.65, 0.58)
			second.Parent = card
		end
		cards[item.Id] = card
		UIEffects.bindButton(card, function()
			Controller.Claim(item.Id)
		end)
		UIEffects.bindHover(card, { Scale = 1.05, Rotation = 5, Duration = 0.15 })
		updateCard(item.Id)
	end
	local setBlur = UIEffects.makeBlur("PlaytimeBlur", 16, 0.2)
	UIManager.Register("PlaytimeRewards", main, { HiddenScale = 0.1, OpenDuration = 0.35, CloseOnButtonB = true })
	UIManager.OnOpened("PlaytimeRewards", function()
		setBlur(true)
	end)
	UIManager.OnClosed("PlaytimeRewards", function()
		setBlur(false)
	end)
	UIEffects.bindHover(main.Header.CloseButton, { Scale = 1.08, Rotation = 5, Duration = 0.14 })
	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)
	fit()
	gui:SetAttribute("ControllerReady", true)
	task.spawn(function()
		while gui.Parent do
			for id in cards do
				updateCard(id)
			end
			task.wait(0.25)
		end
	end)
end
return Controller
