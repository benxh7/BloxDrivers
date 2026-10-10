-- Ubicación en Studio: StarterPlayer > StarterPlayerScripts > Controllers > AdminPanelController (ModuleScript)
-- Ventana "AdminPanel" (pestañas Server / Player / Admin List). Solo pide: AdminService decide.
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local UIManager = require(script.Parent:WaitForChild("UIManager"))
local Utils = script.Parent.Parent:WaitForChild("Utils")
local UIEffects = require(Utils:WaitForChild("UIEffects"))
local UITemplates = require(Utils:WaitForChild("UITemplates"))
local WindowLayout = require(Utils:WaitForChild("WindowLayout"))
local Notifications = require(Utils:WaitForChild("Notifications"))
local GradientButton = require(Utils:WaitForChild("GradientButton"))
local Remotes = require(RS:WaitForChild("Remotes"))
local Config = require(RS:WaitForChild("AdminConfig"))

local ChatNameColor = require(Utils:WaitForChild("ChatNameColor"))

local Controller = {}

local WINDOW_NAME = "AdminPanel"
local GUI_NAME = "AdminPanelGui"
-- Segundos que un botón peligroso (BAN, REVOKE) espera el segundo click de confirmación.
local CONFIRM_WINDOW = 3

local player = Players.LocalPlayer
local gui, main, pages, tabs
local serverPage, playerPage, adminsPage
local currentTab = "Server"
local globalScope: { [Instance]: boolean } = {}
local grantIndex = 1
local busy: { [string]: boolean } = {}
local profileUserId: number? = nil
local profileName: string? = nil
local searched = nil
-- Logs del jugador buscado (todas las categorías) y la pestaña elegida.
local playerLogs = nil
local logCounts = {}
local logsStatus = "Search a player to see their logs"
local logCategory = "All"
local logPeriod = 1
local setBlur
local shellTransparency
local inspectVersion = 0

local function myLevel(): number
	local rank = Config.Ranks[player:GetAttribute("AdminRank") or ""]
	return if rank then rank.Level else 0
end

local function paint(button: GuiObject, palette: string)
	GradientButton.paint(button, Config.Palettes[palette])
end

local function bind(button: GuiButton, callback: () -> ())
	UIEffects.bindButton(button, callback)
	UIEffects.bindHover(button, { Scale = 1.06, Rotation = 5, Duration = 0.14 })
end

-- Primer click cambia el texto a "SURE?"; solo el segundo dentro de CONFIRM_WINDOW ejecuta.
local function bindConfirm(button: GuiButton, callback: () -> ())
	local armedAt = 0
	local label = button:FindFirstChild("Label") :: TextLabel
	local original = label.Text
	bind(button, function()
		if os.clock() - armedAt <= CONFIRM_WINDOW then
			armedAt = 0
			label.Text = original
			callback()
			return
		end
		armedAt = os.clock()
		label.Text = "SURE?"
		task.delay(CONFIRM_WINDOW, function()
			if os.clock() - armedAt >= CONFIRM_WINDOW then
				label.Text = original
			end
		end)
	end)
end

local REQUEST_SPACING = 0.35
local lastRequestAt = 0

local function request(action: string, payload: { [string]: any }?, quiet: boolean?): any
	if busy[action] then
		return nil
	end
	busy[action] = true
	-- AdminRequest descarta pedidos a menos de REQUEST_SPACING del anterior (cooldown del
	-- servidor): búsqueda + logs salen juntos, así que se esperan en vez de perderse.
	local wait = lastRequestAt + REQUEST_SPACING - os.clock()
	if wait > 0 then
		lastRequestAt += REQUEST_SPACING
		task.wait(wait)
	else
		lastRequestAt = os.clock()
	end
	local ok, result = pcall(function()
		return Remotes.func("AdminRequest"):InvokeServer(action, payload or {})
	end)
	busy[action] = nil
	if not ok or type(result) ~= "table" then
		Notifications.Show("Request failed, try again", { Theme = "Error" })
		return nil
	end
	if result.Message ~= "" and not (quiet and result.Ok) then
		Notifications.Show(result.Message, {
			Theme = if result.Ok then "Success" else "Error",
			SoundId = if result.Ok then Config.Sounds.Success else Config.Sounds.Error,
		})
	end
	return result
end

local function setThumbnail(image: ImageLabel, userId: number, size: Enum.ThumbnailSize?)
	image.Image = ""
	image:SetAttribute("ThumbnailUserId", userId)
	task.spawn(function()
		local ok, content = pcall(
			Players.GetUserThumbnailAsync,
			Players,
			userId,
			Enum.ThumbnailType.HeadShot,
			size or Enum.ThumbnailSize.Size150x150
		)
		if ok and image.Parent and image:GetAttribute("ThumbnailUserId") == userId then
			image.Image = content
		end
	end)
end

local function clearList(container: Instance)
	for _, child in container:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
end

-- Solo tamaño de ventana y header (igual que Settings/Shop). Tarjetas, pestañas y filas se
-- acomodan solas con sus constraints y layouts de Studio.
local function fitWindow()
	local screen = gui.AbsoluteSize
	if screen.X <= 0 or screen.Y <= 0 then
		return
	end
	if adminsPage.Profile.Visible and adminsPage.Visible then
        local width = math.min(800, screen.X * .88, screen.Y * .86 * 1.30)
        main.Size = UDim2.fromOffset(width, width / 1.30)
        main.Position = UDim2.fromScale(.5, .52)
        pages.Position = UDim2.fromScale(0,0)
        pages.Size = UDim2.fromScale(1,1)
        return
    end
    local width, height = WindowLayout.fitMain(screen, main)
	local tabWidth = tabs.AbsoluteSize.X
	local reserved = (tabWidth + 16) * 2 + 16
	if screen.X - width < reserved then
		width = screen.X - reserved
		main.Size = UDim2.fromOffset(math.floor(width), math.floor(height))
	end
	-- Corrida a la izquierda para que ventana + pestañas queden centradas juntas.
	main.Position = UDim2.new(0.5, -math.floor((tabWidth + 16) / 2), 0.53, 0)
	local headerHeight = WindowLayout.fitHeader(main.Header, height, 88, 52)
	pages.Position = UDim2.fromOffset(0, headerHeight + 6)
	pages.Size = UDim2.new(1, 0, 1, -headerHeight - 14)
	tabs.Position = UDim2.new(1, 16, 0, headerHeight + 10)
end

-- AutomaticCanvasSize no ve el alto que les da el UIAspectRatioConstraint a las tarjetas:
-- el canvas sale del contenido real del layout.
local function bindCanvas(page: ScrollingFrame)
	local layout = page:FindFirstChildOfClass("UIListLayout") :: UIListLayout
	local pad = page:FindFirstChildOfClass("UIPadding")
	page.AutomaticCanvasSize = Enum.AutomaticSize.None
	local function update()
		local extra = if pad then pad.PaddingTop.Offset + pad.PaddingBottom.Offset else 0
		page.CanvasSize = UDim2.fromOffset(0, layout.AbsoluteContentSize.Y + extra)
	end
	layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(update)
	update()
end

local function rankText(rankId: string?): (string, Color3)
	local rank = Config.Ranks[rankId or ""]
	if not rank then
		return "NONE", Color3.fromRGB(190, 190, 190)
	end
	return rank.Label, rank.Color
end

local function canRevoke(entry): boolean
	local rank = Config.Ranks[entry.Rank or ""]
	return not entry.Fixed
		and entry.UserId ~= player.UserId
		and myLevel() >= Config.Permissions.Revoke
		and myLevel() > (if rank then rank.Level else 0)
end

local refreshAdmins

local function revoke(userId: number)
	local result = request("Revoke", { UserId = userId })
	if result and result.Ok then
		adminsPage.Profile.Visible = false
		adminsPage.List.Visible = true
		refreshAdmins()
	end
end

local function showProfile(userId: number)
	inspectVersion += 1
	local version = inspectVersion
	local result = request("Inspect", { UserId = userId }, true)
	if version ~= inspectVersion then return end
	if not result or not result.Ok then
		return
	end
	local data = result.Data
	profileUserId = userId
	profileName = data.Name
	local profile = adminsPage.Profile
	local card = profile.AvatarCard
	local label, color = rankText(data.Rank)
	card.NameBar.NameLabel.Text = data.DisplayName or data.Name
	card.UserLabel.Text = "@" .. data.Name
	card.RankLabel.Text = label
	card.RankLabel.TextColor3 = color
	-- Username, not display name or rank: the classic Roblox chat name color.
    local tint = ChatNameColor.FromUsername(data.Name)
    card.AvatarBox.BackgroundColor3 = Color3.new(1, 1, 1)
    card.AvatarBox.UIGradient.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, tint:Lerp(Color3.new(1, 1, 1), .38)),
        ColorSequenceKeypoint.new(.48, tint),
        ColorSequenceKeypoint.new(1, tint:Lerp(Color3.new(0, 0, 0), .20)),
    })
    card.Description.Text = "No profile\ndescription\nyet."
	setThumbnail(card.AvatarBox.Avatar, userId, Enum.ThumbnailSize.Size420x420)
	local lines = {
		('<font color="#%s">Rank : %s</font>'):format(color:ToHex(), label),
		('<font color="#FFE55A">UserId : %d</font>'):format(userId),
		if data.InServer
			then '<font color="#5BFF3C">Status : In this server</font>'
			else '<font color="#B4BCD2">Status : Not in this server</font>',
		('<font color="#2DDCFF">Granted by : %s</font>'):format(
			if data.Fixed then "Game owner" else (data.GrantedByName or "-")
		),
		('<font color="#E66BFF">Granted on : %s</font>'):format(
			if data.GrantedAt then os.date("%d/%m/%Y", data.GrantedAt) else "-"
		),
	}
	if data.AccountAge then
		table.insert(lines, ('<font color="#FFAA28">Account age : %dd</font>'):format(data.AccountAge))
	end
	-- Auditoría del staff: total de acciones y sanciones (los bans activos se pueden revertir).
	local audit = data.Audit
	if audit then
		local counts = audit.Counts
		table.insert(lines, ('<font color="#FFFFFF">Staff actions : %d</font>'):format(audit.Total))
		table.insert(lines, ('<font color="#FF5A64">Bans : %d (%d active)</font>'):format(audit.Bans, audit.ActiveBans))
		table.insert(
			lines,
			('<font color="#FFAA28">Kicks : %d · Warns : %d</font>'):format(counts.Kick or 0, counts.Warn or 0)
		)
	end
	profile.InfoCard.Stats.Text = table.concat(lines, "\n")
	local staffActions = profile.InfoCard.StaffActions
	staffActions.Visible = audit ~= nil
	-- UNDO BANS: solo el Owner, nunca sobre sí mismo ni otro Owner, y solo si hay algo que levantar.
	staffActions.UndoSlot.Visible = audit ~= nil
		and myLevel() >= Config.Permissions.RevertSanctions
		and not data.Fixed
		and userId ~= player.UserId
		and audit.ActiveBans > 0
	-- Actions centra los botones: sin REVOKE, BACK queda solo en el medio.
	profile.InfoCard.Actions.RevokeSlot.Visible = canRevoke(data)
	adminsPage.List.Visible = false
	adminsPage.EmptyLabel.Visible = false
	profile.Visible = true
end

function refreshAdmins()
	local result = request("ListAdmins", nil, true)
	if not result or not result.Ok then
		return
	end
	local list = adminsPage.List
	clearList(list)
	for index, entry in result.Data do
		local row = UITemplates.clone("AdminRow")
		if not row then
			return
		end
		local label, color = rankText(entry.Rank)
		row.Name = tostring(entry.UserId)
		row.LayoutOrder = index
		row.DisplayLabel.Text = entry.DisplayName or entry.Name
		row.UserLabel.Text = "@" .. entry.Name
		row.RankLabel.Text = label
		row.RankLabel.TextColor3 = color
		row.Avatar.OnlineDot.Visible = entry.InServer
		-- Actions es un UIListLayout alineado a la derecha: sin REVOKE, INSPECT se corre solo.
		row.Actions.RevokeSlot.Visible = canRevoke(entry)
		row.Visible = true
		setThumbnail(row.Avatar, entry.UserId)
		bind(row.Actions.InspectSlot.InspectButton, function()
			showProfile(entry.UserId)
		end)
		bindConfirm(row.Actions.RevokeSlot.RevokeButton, function()
			revoke(entry.UserId)
		end)
		row.Parent = list
	end
	adminsPage.EmptyLabel.Visible = #result.Data == 0 and not adminsPage.Profile.Visible
end

local STATUS = {
	Here = { "In this server", Color3.fromRGB(91, 255, 60) },
	Other = { "In another server", Color3.fromRGB(45, 220, 255) },
	Offline = { "Offline", Color3.fromRGB(180, 188, 210) },
}

local function periodStart(): number
	local period = Config.Logs.Periods[logPeriod]
	if period.Days == 0 then
		local now = os.date("*t")
		return os.time({ year = now.year, month = now.month, day = now.day, hour = 0 })
	end
	return if period.Days then os.time() - period.Days * 86400 else 0
end

-- Logs de antes de que existiera `Kind`: se deduce por el verbo con que empieza el texto.
local KIND_PREFIXES = { Ban = "Banned", Kick = "Kicked", Warn = "Warned", Unban = "Unbanned" }

local function kindOf(entry): string?
	if entry.Kind then
		return entry.Kind
	end
	for kind, prefix in KIND_PREFIXES do
		if entry.Text:sub(1, #prefix + 1) == prefix .. " " then
			return kind
		end
	end
	return nil
end

-- Cantidad de logs de una categoría (y de un tipo, si se pasa) en el período elegido.
-- En "ALL TIME" usa el total de por vida: el perfil guarda solo las últimas entradas.
local function countLogs(category: string, kind: string?): number
	local since = periodStart()
	local amount = 0
	for _, entry in playerLogs and playerLogs[category] or {} do
		if entry.At >= since and (not kind or kindOf(entry) == kind) then
			amount += 1
		end
	end
	if since == 0 then
		local key = if kind then category .. ":" .. kind else category
		amount = math.max(amount, logCounts[key] or 0)
	end
	return amount
end

local SANCTION_KINDS = { { "Ban", "Bans" }, { "Kick", "Kicks" }, { "Warn", "Warns" }, { "Unban", "Unbans" } }

-- Moderation: sanciones que recibió. Staff: las que puso. All: las recibidas.
local function breakdownText(): string
	if not playerLogs then
		return ""
	end
	local category = if logCategory == "Staff" then "Staff" elseif logCategory == "All" then "Moderation" else logCategory
	if category ~= "Moderation" and category ~= "Staff" then
		return ("Total: %d"):format(countLogs(category))
	end
	local parts = {}
	for _, kind in SANCTION_KINDS do
		table.insert(parts, ("%s: %d"):format(kind[2], countLogs(category, kind[1])))
	end
	local prefix = if category == "Staff" then "Issued: " else "Received: "
	return prefix .. table.concat(parts, " · ")
end

-- Entradas de la pestaña elegida ("All" = todas las categorías), dentro del período y
-- ordenadas de la más nueva a la más vieja. Cada una lleva el ícono de su categoría.
local function visibleLogs(): { { At: number, Text: string, Icon: string } }
	local since = periodStart()
	local list = {}
	for _, category in Config.Logs.Categories do
		if logCategory == "All" or logCategory == category.Id then
			for _, entry in playerLogs and playerLogs[category.Id] or {} do
				if entry.At >= since then
					table.insert(list, { At = entry.At, Text = entry.Text, Icon = entry.Icon or category.Icon })
				end
			end
		end
	end
	table.sort(list, function(a, b)
		return a.At > b.At
	end)
	return list
end

local function renderLogs()
	local card = playerPage.LogsCard
	local total = 0
	for _, category in Config.Logs.Categories do
		local button = card[category.Button]
		local amount = countLogs(category.Id)
		total += amount
		paint(button, if category.Id == logCategory then category.Palette else "Grey")
		button.Count.Label.Text = tostring(amount)
		button.Count.Visible = playerLogs ~= nil
	end
	local all = Config.Logs.All
	paint(card[all.Button], if logCategory == "All" then all.Palette else "Grey")
	card[all.Button].Count.Label.Text = tostring(total)
	card[all.Button].Count.Visible = playerLogs ~= nil
	card.BreakdownLabel.Text = breakdownText()
	card.PeriodButton.Label.Text = Config.Logs.Periods[logPeriod].Label
	clearList(card.List)
	local entries = visibleLogs()
	local order, lastDay = 0, nil
	for _, entry in entries do
		-- Un separador cada vez que cambia el día, para leer el detalle fecha por fecha.
		local day = os.date("%A %d/%m/%Y", entry.At)
		if day ~= lastDay then
			lastDay = day
			local header = UITemplates.clone("AdminLogDay")
			if header then
				order += 1
				header.LayoutOrder = order
				header.Text = day
				header.Visible = true
				header.Parent = card.List
			end
		end
		local row = UITemplates.clone("AdminLogRow")
		if not row then
			return
		end
		order += 1
		row.LayoutOrder = order
		row.Details.DateLabel.Text = os.date("%H:%M", entry.At)
		row.Details.TextLabel.Text = entry.Text
		row.IconBox.Icon.Image = entry.Icon
		row.Visible = true
		row.Parent = card.List
	end
	card.EmptyLabel.Text = if playerLogs then "No logs in this period" else logsStatus
	card.EmptyLabel.Visible = #entries == 0
	card.List.CanvasPosition = Vector2.zero
end

local function loadLogs(data)
	local card = playerPage.LogsCard
	playerLogs = nil
	logCounts = {}
	if not data then
		card.TargetLabel.Text = "Search a player to see their logs"
		logsStatus = "Search a player to see their logs"
		renderLogs()
		return
	end
	card.TargetLabel.Text = ("Logs of %s (@%s)"):format(data.DisplayName, data.Name)
	logsStatus = "Loading..."
	renderLogs()
	local result = request("ViewLogs", { UserId = data.UserId }, true)
	-- Otro jugador buscado mientras cargaba: se descarta esta respuesta.
	if searched ~= data then
		return
	end
	playerLogs = if result and result.Ok then result.Data.Entries else nil
	logCounts = if result and result.Ok then result.Data.Counts else {}
	logsStatus = "Could not load logs"
	renderLogs()
end

local function showSearchResult(data)
	searched = data
	task.spawn(loadLogs, data)
	local result = playerPage.CommandsCard.Result
	result.EmptyLabel.Visible = data == nil
	for _, name in { "AvatarBox", "NameLabel", "UserLabel", "StatusLabel" } do
		result[name].Visible = data ~= nil
	end
	if not data then
		return
	end
	result.NameLabel.Text = data.DisplayName
	result.UserLabel.Text = "@" .. data.Name
	local status = STATUS[data.Status] or STATUS.Offline
	result.StatusLabel.Text = status[1]
	result.StatusLabel.TextColor3 = status[2]
	setThumbnail(result.AvatarBox.Avatar, data.UserId, Enum.ThumbnailSize.Size420x420)
end

local function search()
	local input = playerPage.CommandsCard.SearchInput
	if not input.Text:match("%S") then
		return
	end
	local result = request("Lookup", { Target = input.Text }, true)
	showSearchResult(if result and result.Ok then result.Data else nil)
end

local function selectTab(id: string)
	currentTab = id
	for _, tab in Config.Tabs do
		local button = tabs:FindFirstChild(tab.Id .. "Tab", true)
		if button then
			paint(button, if tab.Id == id then "Green" else "Grey")
		end
		pages[tab.Page].Visible = tab.Id == id
	end
	if id == "Admins" then
		adminsPage.Profile.Visible = false
		adminsPage.List.Visible = true
		refreshAdmins()
	end
end

-- Color del contador al llegar al máximo.
local COUNT_FULL_COLOR = Color3.fromRGB(255, 90, 100)

-- TextBox no tiene tope propio: lo que pase de `max` se corta al escribir (no al enviar) y el
-- contador "n/max" muestra cuánto queda.
local function bindLimit(input: TextBox, max: number, counter: TextLabel?)
	local baseColor = counter and counter.TextColor3
	local function update()
		local length = utf8.len(input.Text) or #input.Text
		if length > max then
			input.Text = input.Text:sub(1, (utf8.offset(input.Text, max + 1) or #input.Text + 1) - 1)
			return
		end
		if counter then
			counter.Text = ("%d/%d"):format(length, max)
			counter.TextColor3 = if length >= max then COUNT_FULL_COLOR else baseColor
		end
	end
	input:GetPropertyChangedSignal("Text"):Connect(update)
	update()
end

local function bindScope(card: Instance)
	local button = card.ScopeButton
	globalScope[card] = false
	bind(button, function()
		globalScope[card] = not globalScope[card]
		button.Label.Text = if globalScope[card] then "GLOBAL" else "SERVER"
		paint(button, if globalScope[card] then "Purple" else "Blue")
	end)
end

local function bindServerPage()
	for _, entry in { { serverPage.AnnounceCard, "Announce" }, { serverPage.MessageCard, "ServerMessage" } } do
		local card, action = entry[1], entry[2]
		bindScope(card)
		bindLimit(card.TextInput, Config.Limits.Message, card:FindFirstChild("CharCount"))
		bind(card.SendButton, function()
			local result = request(action, { Text = card.TextInput.Text, Global = globalScope[card] })
			if result and result.Ok then
				card.TextInput.Text = ""
			end
		end)
	end
	local poll = serverPage.PollCard
	bindScope(poll)
	bindLimit(poll.QuestionInput, Config.Limits.PollQuestion, poll:FindFirstChild("CharCount"))
	for index = 1, Config.Limits.PollMaxOptions do
		bindLimit(poll["Option" .. index], Config.Limits.PollOption)
	end
	bind(poll.SubmitButton, function()
		local options = {}
		for index = 1, Config.Limits.PollMaxOptions do
			local input = poll:FindFirstChild("Option" .. index)
			if input and input.Text:match("%S") then
				table.insert(options, input.Text)
			end
		end
		local result = request("StartPoll", {
			Question = poll.QuestionInput.Text,
			Options = options,
			Seconds = tonumber(poll.TimeInput.Text),
			Global = globalScope[poll],
		})
		if result and result.Ok then
			poll.QuestionInput.Text = ""
			for index = 1, Config.Limits.PollMaxOptions do
				poll["Option" .. index].Text = ""
			end
		end
	end)
	bind(poll.EndButton, function()
		request("EndPoll")
	end)
end

local function grantRank(): string
	return Config.GrantableRanks[grantIndex]
end

local function paintGrantRank()
	local button = playerPage.GrantCard.RankButton
	local rank = Config.Ranks[grantRank()]
	button.Label.Text = rank.Label
	paint(button, rank.Palette)
end

local function bindPlayerPage()
	local logsCard = playerPage.LogsCard
	for _, category in Config.Logs.Categories do
		bind(logsCard[category.Button], function()
			logCategory = category.Id
			renderLogs()
		end)
	end
	bind(logsCard[Config.Logs.All.Button], function()
		logCategory = "All"
		renderLogs()
	end)
	paint(logsCard.PeriodButton, "Orange")
	bind(logsCard.PeriodButton, function()
		logPeriod = logPeriod % #Config.Logs.Periods + 1
		renderLogs()
	end)
	local card = playerPage.CommandsCard
	bindLimit(card.ReasonInput, Config.Limits.Reason)
	bind(card.SearchButton, search)
	card.SearchInput.FocusLost:Connect(function(enterPressed)
		if enterPressed then
			search()
		end
	end)
	showSearchResult(nil)
	-- Las acciones van al jugador buscado (por UserId), no a lo que quedó escrito en el input.
	local function act(action: string, extra: { [string]: any }?)
		if not searched then
			Notifications.Show("Search a player first", { Theme = "Error" })
			return nil
		end
		local payload = { Target = tostring(searched.UserId), Reason = card.ReasonInput.Text }
		for key, value in extra or {} do
			payload[key] = value
		end
		local target = searched
		local result = request(action, payload)
		if result and result.Ok then
			task.spawn(loadLogs, target)
		end
		return result
	end
	bind(card.KickButton, function()
		act("Kick")
	end)
	bindConfirm(card.BanButton, function()
		act("Ban", { Duration = card.DurationInput.Text })
	end)
	bind(card.UnbanButton, function()
		act("Unban")
	end)
	bind(card.WarnButton, function()
		act("Warn")
	end)
	bind(card.TeleportButton, function()
		act("Teleport")
	end)
	bind(card.BringButton, function()
		act("Bring")
	end)

	local grant = playerPage.GrantCard
	bind(grant.RankButton, function()
		grantIndex = grantIndex % #Config.GrantableRanks + 1
		paintGrantRank()
	end)
	bind(grant.GrantButton, function()
		local result = request("Grant", { Target = grant.TargetInput.Text, Rank = grantRank() })
		if result and result.Ok then
			grant.TargetInput.Text = ""
		end
	end)
	bind(grant.ListButton, function()
		selectTab("Admins")
	end)
	paintGrantRank()
end

local function bindAdminsPage()
    local profile = adminsPage.Profile
    local function updateProfileChrome()
        local focused = profile.Visible and adminsPage.Visible
        main.BackgroundTransparency = if focused then 1 else shellTransparency
        main.Outline.Enabled = not focused
        main.InnerBorder.Visible = not focused
        main.Header.Visible = not focused
        tabs.Visible = not focused
        if setBlur then setBlur(not focused and UIManager.IsOpen(WINDOW_NAME)) end
        fitWindow()
    end
    profile:GetPropertyChangedSignal("Visible"):Connect(updateProfileChrome)
    adminsPage:GetPropertyChangedSignal("Visible"):Connect(updateProfileChrome)
    bind(profile.ProfileClose, function()
        profile.Visible = false
        adminsPage.List.Visible = true
        refreshAdmins()
    end)
	bind(profile.InfoCard.Actions.BackSlot.BackButton, function()
		profile.Visible = false
		adminsPage.List.Visible = true
		refreshAdmins()
	end)
	bindConfirm(profile.InfoCard.Actions.RevokeSlot.RevokeButton, function()
		if profileUserId then
			revoke(profileUserId)
		end
	end)
	-- LOGS: abre el Player Panel con ese staff buscado y la pestaña Staff de sus logs.
	bind(profile.InfoCard.StaffActions.LogsSlot.LogsButton, function()
		if not profileName then
			return
		end
		logCategory = "Staff"
		selectTab("Player")
		playerPage.CommandsCard.SearchInput.Text = profileName
		search()
	end)
	bindConfirm(profile.InfoCard.StaffActions.UndoSlot.UndoButton, function()
		local userId = profileUserId
		if not userId then
			return
		end
		local result = request("RevertSanctions", { UserId = userId })
		if result and result.Ok then
			showProfile(userId)
		end
	end)
end

local function bindHUDButton()
	local hud = UIManager.WaitForGui("HUD")
	local button = hud and hud:FindFirstChild("AdminButton", true)
	local function update()
		local allowed = myLevel() > 0
		if button then
			button.Visible = allowed
		end
		if not allowed then
			UIManager.Close(WINDOW_NAME)
		end
	end
	player:GetAttributeChangedSignal("AdminRank"):Connect(update)
	update()
end

function Controller.Init()
	gui = UIManager.WaitForGui(GUI_NAME)
	if not gui then
		return
	end
	main = gui:WaitForChild("Main")
	shellTransparency = main.BackgroundTransparency
	pages = main:WaitForChild("Pages")
	tabs = main:WaitForChild("Tabs")
	serverPage = pages:WaitForChild("ServerPage")
	playerPage = pages:WaitForChild("PlayerPage")
	adminsPage = pages:WaitForChild("AdminsPage")

	for _, tab in Config.Tabs do
		local button = tabs:FindFirstChild(tab.Id .. "Tab", true)
		if button then
			bind(button, function()
				selectTab(tab.Id)
			end)
		end
	end
	bindServerPage()
	bindPlayerPage()
	bindAdminsPage()

	setBlur = UIEffects.makeBlur("AdminPanelBlur", Config.Blur.Size, Config.Blur.Duration)
	UIManager.Register(WINDOW_NAME, main, {
		HiddenScale = Config.Open.FromScale,
		OpenDuration = Config.Open.Duration,
		CloseOnButtonB = true,
	})
	UIEffects.bindHover(main.Header.CloseButton, { Scale = 1.08, Rotation = 5 })
	UIManager.OnOpened(WINDOW_NAME, function()
		if myLevel() <= 0 then
			UIManager.Close(WINDOW_NAME)
			return
		end
		setBlur(true)
		selectTab(currentTab)
		task.defer(fitWindow)
	end)
	UIManager.OnClosed(WINDOW_NAME, function()
		setBlur(false)
	end)

	Remotes.onUpdate("adminRanksChanged", function()
		if UIManager.IsOpen(WINDOW_NAME) and currentTab == "Admins" and not adminsPage.Profile.Visible then
			refreshAdmins()
		end
	end)
	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(fitWindow)
	tabs:GetPropertyChangedSignal("AbsoluteSize"):Connect(fitWindow)
	for _, page in { serverPage, playerPage, adminsPage.List, playerPage.LogsCard.List } do
		bindCanvas(page)
	end
	task.defer(fitWindow)
	task.spawn(bindHUDButton)
end

return Controller
