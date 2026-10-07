-- Ubicación en Studio: StarterPlayer > StarterPlayerScripts > Controllers > AdminBroadcastController (ModuleScript)
-- Lo que ven TODOS desde el Admin Panel: anuncio arriba, poll con votos, warns y mensajes al chat.
-- Popup del servidor: no se registra en UIManager.
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local TextChatService = game:GetService("TextChatService")
local TweenService = game:GetService("TweenService")
local ContentProvider = game:GetService("ContentProvider")
local UIManager = require(script.Parent:WaitForChild("UIManager"))
local Utils = script.Parent.Parent:WaitForChild("Utils")
local UIEffects = require(Utils:WaitForChild("UIEffects"))
local UITemplates = require(Utils:WaitForChild("UITemplates"))
local Notifications = require(Utils:WaitForChild("Notifications"))
local GradientButton = require(Utils:WaitForChild("GradientButton"))
local Remotes = require(RS:WaitForChild("Remotes"))
local Config = require(RS:WaitForChild("AdminConfig"))

local Controller = {}

local GUI_NAME = "AdminBroadcastGui"
-- Color de cada opción del poll en orden; la votada se pinta con VOTED_PALETTE.
local OPTION_PALETTES = { "Green", "Red", "Blue", "Purple" }
local VOTED_PALETTE = "Orange"
-- Escala desde la que entran el anuncio y el poll.
local POP_FROM = 0.6
-- Separación (px) entre el anuncio y el poll cuando se ven los dos.
local STACK_GAP = 8
-- Cuánto tarda el avatar en volver a su tamaño después de cada "sílaba".
local TALK_DURATION = 0.1

local gui, announcement, pollFrame, talkScale
local queue = {}
local showingAnnouncement = false
local poll = nil
local myVote: number? = nil
local optionFrames = {}
local voices: { [string]: Sound } = {}

local function restack()
	local top = if announcement.Visible then announcement.AbsoluteSize.Y + STACK_GAP else 0
	TweenService:Create(pollFrame, TweenInfo.new(0.2, Enum.EasingStyle.Quad), {
		Position = UDim2.new(0.5, 0, 0, 6 + top),
	}):Play()
end

-- ByUserId acepta el nombre de un preset o un asset propio (con el volumen/tono de Default).
local function voiceFor(userId: number): Sound?
	local presets = Config.Voice.Presets
	local choice = Config.Voice.ByUserId[userId]
	local preset = presets[choice or "Default"]
		or table.clone(presets.Default)
	if choice and not presets[choice] then
		preset.Sound = choice
	end
	if preset.Sound == "" then
		preset = presets.Default
	end
	if voices[preset.Sound] == nil then
		local sound = UIEffects.makeSound("AdminVoice", preset.Sound, preset.Volume)
		if sound then
			sound:SetAttribute("BasePitch", preset.Pitch)
		end
		voices[preset.Sound] = sound
	end
	return voices[preset.Sound]
end

local function speak(voice: Sound?, pitch: number?)
	if voice then
		local base = (voice:GetAttribute("BasePitch") or 1) * (pitch or 1)
		voice.PlaybackSpeed = base * (1 + (math.random() * 2 - 1) * Config.Voice.PitchVariation)
		voice.TimePosition = 0
		voice:Play()
	end
	talkScale.Scale = Config.Typing.TalkScale
	TweenService:Create(talkScale, TweenInfo.new(TALK_DURATION, Enum.EasingStyle.Quad), { Scale = 1 }):Play()
end

-- Letra por letra con MaxVisibleGraphemes: el texto completo ya está puesto, así el banner
-- (AutomaticSize) toma su alto final antes de aparecer y no salta mientras escribe.
local function typeText(label: TextLabel, text: string, voice: Sound?)
	local typing = Config.Typing
	local chars = {}
	local letters = 0
	for first, last in utf8.graphemes(text) do
		local char = text:sub(first, last)
		table.insert(chars, char)
		if not char:match("^[%s%p]+$") then
			letters += 1
		end
	end
	-- Pocas letras = más lento, como un personaje que duda.
	local slowdown = math.clamp(typing.ShortLetters / math.max(letters, 1), 1, typing.MaxSlowdown)
	local spoken = 0
	for index, char in chars do
		label.MaxVisibleGraphemes = index
		local isEllipsis = char == "…"
			or char == "." and (chars[index - 1] == "." or chars[index + 1] == ".")
		if isEllipsis then
			speak(voice, typing.DotPitch)
			task.wait(typing.DotDelay)
			continue
		end
		local isPunctuation = char:match("^[%.,!%?;:]$") ~= nil
		if not char:match("^[%s%p]+$") then
			if spoken % Config.Voice.SoundEvery == 0 then
				speak(voice)
			end
			spoken += 1
		end
		task.wait(typing.LetterDelay * slowdown * (if isPunctuation then typing.PunctuationPause else 1))
	end
	label.MaxVisibleGraphemes = -1
end

local function showNextAnnouncement()
	if showingAnnouncement or #queue == 0 then
		return
	end
	showingAnnouncement = true
	local data = table.remove(queue, 1)
	announcement.UserLabel.Text = "@" .. data.Name
	announcement.MessageLabel.Text = data.Text
	announcement.MessageLabel.MaxVisibleGraphemes = 0
	announcement.Avatar.Image = ""
	task.spawn(function()
		local ok, content = pcall(
			Players.GetUserThumbnailAsync,
			Players,
			data.UserId,
			Enum.ThumbnailType.HeadShot,
			Enum.ThumbnailSize.Size150x150
		)
		if ok then
			announcement.Avatar.Image = content
		end
	end)
	UIEffects.playSound(Config.Sounds.Announcement, 0.5)
	UIEffects.popIn(announcement, POP_FROM)
	restack()
	task.spawn(function()
		typeText(announcement.MessageLabel, data.Text, voiceFor(data.UserId))
		task.wait(Config.AnnouncementDuration)
		UIEffects.popOut(announcement, function()
			showingAnnouncement = false
			restack()
			showNextAnnouncement()
		end, POP_FROM)
	end)
end

local function paintOptions(counts: { number }?, ended: boolean?)
	if not poll then
		return
	end
	local total = 0
	for _, amount in counts or {} do
		total += amount
	end
	local best = 0
	for _, amount in counts or {} do
		best = math.max(best, amount)
	end
	for index, frame in optionFrames do
		local amount = if counts then counts[index] or 0 else 0
		local percent = if total > 0 then math.floor(amount / total * 100 + 0.5) else 0
		frame.VotesLabel.Text = ("%d (%d%%)"):format(amount, percent)
		local palette = if index == myVote then VOTED_PALETTE else OPTION_PALETTES[index] or "Grey"
		if ended and (amount < best or best == 0) then
			palette = "Grey"
		end
		local colors = Config.Palettes[palette]
		GradientButton.paint(frame.VoteButton, colors)
		frame.Bar.Fill.BackgroundColor3 = colors[2]
		TweenService:Create(frame.Bar.Fill, TweenInfo.new(0.3, Enum.EasingStyle.Quad), {
			Size = UDim2.fromScale(percent / 100, 1),
		}):Play()
	end
end

local function clearPoll()
	for _, frame in optionFrames do
		frame:Destroy()
	end
	table.clear(optionFrames)
end

local function startPoll(data, vote: number?)
	clearPoll()
	poll = { Id = data.Id, EndsAt = os.clock() + data.Remaining, Ended = false }
	myVote = vote
	pollFrame.QuestionLabel.Text = data.Question
	for index, text in data.Options do
		local frame = UITemplates.clone("AdminPollOption")
		if not frame then
			return
		end
		frame.Name = "Option" .. index
		frame.LayoutOrder = index
		frame.VoteButton.Label.Text = text
		frame.Visible = true
		frame.Parent = pollFrame.Options
		optionFrames[index] = frame
		UIEffects.bindHover(frame.VoteButton, { Scale = 1.06, Rotation = 3, Duration = 0.14 })
		UIEffects.bindButton(frame.VoteButton, function()
			if not poll or poll.Ended or poll.Id ~= data.Id or myVote == index then
				return
			end
			myVote = index
			Remotes.event("VotePoll"):FireServer(data.Id, index)
			paintOptions(poll.Counts)
		end)
	end
	poll.Counts = data.Counts
	paintOptions(data.Counts)
	UIEffects.popIn(pollFrame, POP_FROM)
	restack()
	local id = data.Id
	task.spawn(function()
		while poll and poll.Id == id and not poll.Ended do
			pollFrame.Timer.TimeLabel.Text = math.max(0, math.ceil(poll.EndsAt - os.clock())) .. "s"
			task.wait(0.25)
		end
	end)
end

local function endPoll(data)
	if not poll or poll.Id ~= data.Id then
		return
	end
	poll.Ended = true
	poll.Counts = data.Counts
	pollFrame.Timer.TimeLabel.Text = "END"
	paintOptions(data.Counts, true)
	UIEffects.playSound(Config.Sounds.PollEnd, 0.5)
	local id = data.Id
	task.delay(Config.PollResultDuration, function()
		if poll and poll.Id == id then
			poll = nil
			UIEffects.popOut(pollFrame, clearPoll, POP_FROM)
		end
	end)
end

local function systemMessage(text: string)
	local channels = TextChatService:FindFirstChild("TextChannels")
	local general = channels and channels:FindFirstChild("RBXGeneral")
	if general and general:IsA("TextChannel") then
		pcall(general.DisplaySystemMessage, general, '<font color="#2DDCFF"><b>[SERVER]</b></font> ' .. text)
	end
end

function Controller.Init()
	gui = UIManager.WaitForGui(GUI_NAME)
	if not gui then
		return
	end
	announcement = gui:WaitForChild("Announcement")
	pollFrame = gui:WaitForChild("Poll")
	announcement.Visible = false
	-- UIScale propio del avatar: el del anuncio ya lo usa el pop de entrada.
	talkScale = Instance.new("UIScale")
	talkScale.Name = "TalkScale"
	talkScale.Parent = announcement.Avatar
	task.spawn(function()
		local sound = voiceFor(0)
		if sound then
			pcall(ContentProvider.PreloadAsync, ContentProvider, { sound })
		end
	end)
	pollFrame.Visible = false

	Remotes.onUpdate("adminAnnouncement", function(data)
		table.insert(queue, data)
		showNextAnnouncement()
	end)
	Remotes.onUpdate("adminServerMessage", function(data)
		systemMessage(data.Text)
		Notifications.Show(data.Text, { Theme = "Info", Duration = 5 })
	end)
	Remotes.onUpdate("adminWarned", function(data)
		Notifications.Show(("WARNING from %s: %s"):format(data.By, data.Reason), { Theme = "Error", Duration = 8 })
	end)
	Remotes.onUpdate("adminPollStarted", function(data)
		startPoll(data, nil)
	end)
	Remotes.onUpdate("adminPollCounts", function(data)
		if poll and poll.Id == data.Id and not poll.Ended then
			poll.Counts = data.Counts
			paintOptions(data.Counts)
		end
	end)
	Remotes.onUpdate("adminPollEnded", endPoll)

	announcement:GetPropertyChangedSignal("Visible"):Connect(restack)
	announcement:GetPropertyChangedSignal("AbsoluteSize"):Connect(restack)

	-- Entró con un poll en curso.
	local ok, data, vote = pcall(function()
		return Remotes.func("GetActivePoll"):InvokeServer()
	end)
	if ok and type(data) == "table" and not poll then
		startPoll(data, vote)
	end
end

return Controller
