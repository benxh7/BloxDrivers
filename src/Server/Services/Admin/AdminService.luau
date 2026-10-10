-- Ubicación en Studio: ServerScriptService > Services > Admin > AdminService (ModuleScript)
-- Autoridad del Admin Panel: AdminRequest(action, payload) valida rango y datos de cada acción.
local Players = game:GetService("Players")
local MessagingService = game:GetService("MessagingService")
local TeleportService = game:GetService("TeleportService")
local UserService = game:GetService("UserService")
local RS = game:GetService("ReplicatedStorage")
local Config = require(RS:WaitForChild("AdminConfig"))
local Remotes = require(RS:WaitForChild("Remotes"))
local DebugConfig = require(RS:WaitForChild("DebugConfig"))
local Ranks = require(script.Parent.AdminRanks)
local Broadcast = require(script.Parent.AdminBroadcast)
local LogService = require(script.Parent.Parent:WaitForChild("Logs"):WaitForChild("LogService"))
local StaffAudit = require(script.Parent.StaffAudit)

local Service = {}

local TOPIC = "AdminModeration"
-- Acciones que quedan en el log de Staff de quien las hace (auditoría del propio staff).
local STAFF_ACTIONS = {
	Announce = true,
	ServerMessage = true,
	StartPoll = true,
	EndPoll = true,
	Kick = true,
	Warn = true,
	Ban = true,
	Unban = true,
	Teleport = true,
	Bring = true,
	Grant = true,
	Revoke = true,
	RevertSanctions = true,
}
-- Distancia (studs) a la que queda el que se teletransporta respecto del otro.
local TELEPORT_OFFSET = CFrame.new(0, 0, 4)

-- TargetLog va al log de Moderation del afectado y StaffLog al de Staff de quien la hizo
-- (sin StaffLog se usa Message). Se sacan antes de responder al cliente.
type Result = {
	Ok: boolean,
	Message: string,
	Data: any?,
	TargetLog: { UserId: number, Text: string }?,
	StaffLog: string?,
	-- Ban/kick/warn hecho: queda en la auditoría del staff para poder revertirlo.
	Sanction: StaffAudit.Sanction?,
}
type Target = { UserId: number, Name: string, Player: Player? }

local function reply(ok: boolean, message: string, data: any?): Result
	return { Ok = ok, Message = message, Data = data }
end

local function cleanText(value: any, maxLength: number): string?
	if type(value) ~= "string" then
		return nil
	end
	local text = value:gsub("[%c]", " "):match("^%s*(.-)%s*$")
	if text == "" or utf8.len(text) == nil then
		return nil
	end
	if utf8.len(text) > maxLength then
		text = text:sub(1, utf8.offset(text, maxLength + 1) - 1)
	end
	return text
end

-- El panel ya corta al escribir: algo más largo solo llega salteándose el cliente, y se
-- rechaza en vez de recortarlo sin avisar.
local function tooLong(value: any, maxLength: number): boolean
	return type(value) == "string" and (utf8.len(value) or math.huge) > maxLength
end

local function tooLongReply(what: string, maxLength: number)
	return reply(false, ("%s is too long (max %d characters)"):format(what, maxLength))
end

local function findOnline(query: string): Player?
	local lower = query:lower()
	local partial
	for _, player in Players:GetPlayers() do
		if player.Name:lower() == lower or player.DisplayName:lower() == lower then
			return player
		end
		if not partial and (player.Name:lower():sub(1, #lower) == lower or player.DisplayName:lower():sub(1, #lower) == lower) then
			partial = player
		end
	end
	return partial
end

local function nameOf(userId: number): string
	local ok, name = pcall(Players.GetNameFromUserIdAsync, Players, userId)
	return if ok then name else tostring(userId)
end

-- Acepta UserId, nombre o display de alguien conectado (completo o el comienzo), o un nombre
-- de usuario de alguien que no está en este servidor.
local function resolve(value: any): Target?
	local query = cleanText(value, 40)
	if not query then
		return nil
	end
	local id = tonumber(query)
	if id and id % 1 == 0 and id > 0 then
		local online = Players:GetPlayerByUserId(id)
		return { UserId = id, Name = if online then online.Name else nameOf(id), Player = online }
	end
	local online = findOnline(query)
	if online then
		return { UserId = online.UserId, Name = online.Name, Player = online }
	end
	if not query:match("^[%w_]+$") then
		return nil
	end
	local ok, userId = pcall(Players.GetUserIdFromNameAsync, Players, query)
	if not ok or not userId then
		return nil
	end
	return { UserId = userId, Name = nameOf(userId), Player = Players:GetPlayerByUserId(userId) }
end

-- Nadie sanciona ni toca el rango de alguien de su mismo rango o superior.
local function outranks(admin: Player, userId: number): boolean
	return admin.UserId ~= userId and Ranks.Level(admin.UserId) > Ranks.Level(userId)
end

local function parseDuration(value: any): number?
	local text = if type(value) == "string" then value:lower():gsub("%s", "") else ""
	if text == "" or text == "perm" or text == "permanent" or text == "-1" then
		return -1
	end
	local amount, unit = text:match("^(%d+%.?%d*)(%a?)$")
	local seconds = tonumber(amount)
	if not seconds then
		return nil
	end
	seconds *= Config.BanUnits[if unit == "" then "d" else unit] or 0
	if seconds < 60 or seconds > Config.Limits.MaxBanDays * 86400 then
		return nil
	end
	return math.floor(seconds)
end

local function describe(seconds: number): string
	if seconds < 0 then
		return "permanently"
	end
	for _, unit in { { "w", 604800 }, { "d", 86400 }, { "h", 3600 }, { "m", 60 } } do
		if seconds >= unit[2] then
			return ("for %g%s"):format(math.floor(seconds / unit[2] * 10) / 10, unit[1])
		end
	end
	return ("for %ds"):format(seconds)
end

local function moderateLocally(data)
	local target = Players:GetPlayerByUserId(data.UserId)
	if not target then
		return
	end
	if data.Kind == "Kick" then
		target:Kick(("Kicked by an admin. Reason: %s"):format(data.Reason))
	elseif data.Kind == "Warn" then
		Remotes.fireTo(target, "adminWarned", { Reason = data.Reason, By = data.By })
	end
end

-- Si el objetivo no está acá, el aviso va a todos los servidores (el que lo tenga actúa).
local function moderate(kind: string, admin: Player, target: Target, reason: string): Result
	local data = { Kind = kind, UserId = target.UserId, Reason = reason, By = admin.Name }
	local verb = if kind == "Kick" then "Kicked" else "Warned"
	if target.Player then
		moderateLocally(data)
		return reply(true, ("%s %s"):format(verb, target.Name))
	end
	local ok = pcall(MessagingService.PublishAsync, MessagingService, TOPIC, data)
	if not ok then
		return reply(false, target.Name .. " is not in this server")
	end
	return reply(true, ("%s request sent to all servers for %s"):format(kind, target.Name))
end

local function profile(userId: number, entry: Ranks.Entry?)
	local online = Players:GetPlayerByUserId(userId)
	return {
		UserId = userId,
		Name = if online then online.Name elseif entry then entry.Name else nameOf(userId),
		DisplayName = if online then online.DisplayName else nil,
		Rank = Ranks.Get(userId),
		GrantedByName = if entry then entry.GrantedByName else nil,
		GrantedAt = if entry then entry.GrantedAt else nil,
		InServer = online ~= nil,
		AccountAge = if online then online.AccountAge else nil,
		Fixed = Ranks.IsOwner(userId),
	}
end

local Actions: { [string]: (admin: Player, payload: { [string]: any }) -> Result } = {}

function Actions.Announce(admin, payload)
	if tooLong(payload.Text, Config.Limits.Message) then
		return tooLongReply("Message", Config.Limits.Message)
	end
	local text = cleanText(payload.Text, Config.Limits.Message)
	if not text then
		return reply(false, "Write a message first")
	end
	local result = reply(Broadcast.Announce(admin, text, payload.Global == true))
	result.StaffLog = "Announced: " .. text
	return result
end

function Actions.ServerMessage(admin, payload)
	if tooLong(payload.Text, Config.Limits.Message) then
		return tooLongReply("Message", Config.Limits.Message)
	end
	local text = cleanText(payload.Text, Config.Limits.Message)
	if not text then
		return reply(false, "Write a message first")
	end
	local result = reply(Broadcast.ServerMessage(admin, text, payload.Global == true))
	result.StaffLog = "Server message: " .. text
	return result
end

function Actions.StartPoll(admin, payload)
	if tooLong(payload.Question, Config.Limits.PollQuestion) then
		return tooLongReply("Question", Config.Limits.PollQuestion)
	end
	local question = cleanText(payload.Question, Config.Limits.PollQuestion)
	if not question then
		return reply(false, "Write the poll question")
	end
	local seconds = tonumber(payload.Seconds)
	if not seconds or seconds % 1 ~= 0 or seconds < Config.Limits.PollMinSeconds or seconds > Config.Limits.PollMaxSeconds then
		return reply(false, ("Time must be %d-%d seconds"):format(Config.Limits.PollMinSeconds, Config.Limits.PollMaxSeconds))
	end
	local options = {}
	if type(payload.Options) == "table" then
		for index = 1, Config.Limits.PollMaxOptions do
			if tooLong(payload.Options[index], Config.Limits.PollOption) then
				return tooLongReply("Option " .. index, Config.Limits.PollOption)
			end
			local option = cleanText(payload.Options[index], Config.Limits.PollOption)
			if option then
				table.insert(options, option)
			end
		end
	end
	if #options < Config.Limits.PollMinOptions then
		return reply(false, ("A poll needs at least %d options"):format(Config.Limits.PollMinOptions))
	end
	local result = reply(Broadcast.StartPoll(admin, question, options, seconds, payload.Global == true))
	result.StaffLog = "Started poll: " .. question
	return result
end

function Actions.EndPoll()
	return reply(Broadcast.EndPoll())
end

local function sanction(kind: string)
	return function(admin: Player, payload): Result
		local target = resolve(payload.Target)
		if not target then
			return reply(false, "Player not found")
		end
		if not outranks(admin, target.UserId) then
			return reply(false, "You can't do that to " .. target.Name)
		end
		if tooLong(payload.Reason, Config.Limits.Reason) then
			return tooLongReply("Reason", Config.Limits.Reason)
		end
		local reason = cleanText(payload.Reason, Config.Limits.Reason) or "No reason given"
		local result = moderate(kind, admin, target, reason)
		local verb = if kind == "Kick" then "Kicked" else "Warned"
		result.TargetLog = { UserId = target.UserId, Text = ("%s by @%s · %s"):format(verb, admin.Name, reason) }
		result.StaffLog = ("%s @%s · %s"):format(verb, target.Name, reason)
		result.Sanction = {
			Kind = kind,
			TargetId = target.UserId,
			TargetName = target.Name,
			Reason = reason,
			Duration = 0,
			At = os.time(),
			Reverted = false,
		}
		return result
	end
end
Actions.Kick = sanction("Kick")
Actions.Warn = sanction("Warn")

function Actions.Ban(admin, payload)
	local target = resolve(payload.Target)
	if not target then
		return reply(false, "Player not found")
	end
	if not outranks(admin, target.UserId) then
		return reply(false, "You can't ban " .. target.Name)
	end
	local duration = parseDuration(payload.Duration)
	if not duration then
		return reply(false, ("Invalid time. Use 30m, 12h, 7d, 2w or perm (max %dd)"):format(Config.Limits.MaxBanDays))
	end
	if tooLong(payload.Reason, Config.Limits.Reason) then
		return tooLongReply("Reason", Config.Limits.Reason)
	end
	local reason = cleanText(payload.Reason, Config.Limits.Reason) or "No reason given"
	-- BanAsync también saca al jugador de todos los servidores donde esté.
	local ok, err = pcall(Players.BanAsync, Players, {
		UserIds = { target.UserId },
		ApplyToUniverse = true,
		Duration = duration,
		DisplayReason = reason,
		PrivateReason = ("Banned by %s (%d)"):format(admin.Name, admin.UserId),
		ExcludeAltAccounts = false,
	})
	if not ok then
		DebugConfig.warn("[AdminService] BanAsync falló: " .. tostring(err))
		return reply(false, "Ban failed: " .. tostring(err))
	end
	local result = reply(true, ("Banned %s %s"):format(target.Name, describe(duration)))
	result.TargetLog = {
		UserId = target.UserId,
		Text = ("Banned %s by @%s · %s"):format(describe(duration), admin.Name, reason),
	}
	result.StaffLog = ("Banned @%s %s · %s"):format(target.Name, describe(duration), reason)
	result.Sanction = {
		Kind = "Ban",
		TargetId = target.UserId,
		TargetName = target.Name,
		Reason = reason,
		Duration = duration,
		At = os.time(),
		Reverted = false,
	}
	return result
end

function Actions.Unban(admin, payload)
	local target = resolve(payload.Target)
	if not target then
		return reply(false, "Player not found")
	end
	local ok, err = pcall(Players.UnbanAsync, Players, { UserIds = { target.UserId }, ApplyToUniverse = true })
	if not ok then
		return reply(false, "Unban failed: " .. tostring(err))
	end
	local result = reply(true, "Unbanned " .. target.Name)
	result.TargetLog = { UserId = target.UserId, Text = "Unbanned by @" .. admin.Name }
	return result
end

local function pivotTo(mover: Player, anchor: Player): boolean
	local from, to = mover.Character, anchor.Character
	if not (from and to and to.PrimaryPart and from.PrimaryPart) then
		return false
	end
	from:PivotTo(to:GetPivot() * TELEPORT_OFFSET)
	return true
end

function Actions.Teleport(admin, payload)
	local target = resolve(payload.Target)
	if not target or target.UserId == admin.UserId then
		return reply(false, "Player not found")
	end
	if target.Player then
		return if pivotTo(admin, target.Player)
			then reply(true, "Teleported to " .. target.Name)
			else reply(false, "Character not loaded")
	end
	local ok, _, err, placeId, jobId = pcall(TeleportService.GetPlayerPlaceInstanceAsync, TeleportService, target.UserId)
	if not ok or not jobId or jobId == "" then
		return reply(false, target.Name .. " is not online" .. if err and err ~= "" then " (" .. err .. ")" else "")
	end
	local options = Instance.new("TeleportOptions")
	options.ServerInstanceId = jobId
	local sent, teleportErr = pcall(TeleportService.TeleportAsync, TeleportService, placeId, { admin }, options)
	if not sent then
		return reply(false, "Teleport failed: " .. tostring(teleportErr))
	end
	return reply(true, "Joining " .. target.Name .. "'s server...")
end

function Actions.Bring(admin, payload)
	local target = resolve(payload.Target)
	if not target or not target.Player or target.UserId == admin.UserId then
		return reply(false, "Player is not in this server")
	end
	if not outranks(admin, target.UserId) then
		return reply(false, "You can't bring " .. target.Name)
	end
	if not pivotTo(target.Player, admin) then
		return reply(false, "Character not loaded")
	end
	local result = reply(true, "Brought " .. target.Name)
	result.TargetLog = { UserId = target.UserId, Text = "Brought by @" .. admin.Name }
	return result
end

function Actions.Grant(admin, payload)
	local rank = payload.Rank
	if type(rank) ~= "string" or not table.find(Config.GrantableRanks, rank) then
		return reply(false, "Invalid rank")
	end
	if Config.Ranks[rank].Level >= Ranks.Level(admin.UserId) then
		return reply(false, "You can only grant ranks below yours")
	end
	local target = resolve(payload.Target)
	if not target then
		return reply(false, "Player not found")
	end
	if not outranks(admin, target.UserId) then
		return reply(false, target.Name .. " already has an equal or higher rank")
	end
	local ok, err = Ranks.Set(target.UserId, {
		Rank = rank,
		Name = target.Name,
		GrantedBy = admin.UserId,
		GrantedByName = admin.Name,
		GrantedAt = os.time(),
	})
	if not ok then
		return reply(false, err or "Could not save")
	end
	local result = reply(true, ("%s is now %s"):format(target.Name, Config.Ranks[rank].Label))
	result.TargetLog = {
		UserId = target.UserId,
		Text = ("Given rank %s by @%s"):format(Config.Ranks[rank].Label, admin.Name),
	}
	return result
end

function Actions.Revoke(admin, payload)
	local userId = tonumber(payload.UserId)
	if not userId or not Ranks.Entry(userId) then
		return reply(false, "That player has no rank")
	end
	if Ranks.IsOwner(userId) or not outranks(admin, userId) then
		return reply(false, "You can't revoke that rank")
	end
	local entry = Ranks.Entry(userId)
	local ok, err = Ranks.Remove(userId)
	if not ok then
		return reply(false, err or "Could not save")
	end
	local result = reply(true, "Revoked " .. entry.Name .. "'s rank")
	result.TargetLog = {
		UserId = userId,
		Text = ("Rank %s revoked by @%s"):format(Config.Ranks[entry.Rank].Label, admin.Name),
	}
	return result
end

-- Búsqueda del Player Panel. "Other" = conectado en otro servidor (solo en el juego publicado).
function Actions.Lookup(_admin, payload)
	local target = resolve(payload.Target)
	if not target then
		return reply(false, "Player not found")
	end
	local displayName = if target.Player then target.Player.DisplayName else nil
	if not displayName then
		local ok, infos = pcall(UserService.GetUserInfosByUserIdsAsync, UserService, { target.UserId })
		displayName = if ok and infos[1] then infos[1].DisplayName else target.Name
	end
	local status = "Here"
	if not target.Player then
		local ok, _, _, _, jobId = pcall(TeleportService.GetPlayerPlaceInstanceAsync, TeleportService, target.UserId)
		status = if ok and jobId and jobId ~= "" then "Other" else "Offline"
	end
	return reply(true, "", {
		UserId = target.UserId,
		Name = target.Name,
		DisplayName = displayName,
		Status = status,
		Rank = Ranks.Get(target.UserId),
	})
end

function Actions.ViewLogs(_admin, payload)
	local userId = tonumber(payload.UserId)
	if not userId or userId % 1 ~= 0 or userId == 0 then
		return reply(false, "Player not found")
	end
	local logs, counts = LogService.Get(userId)
	if not logs then
		return reply(false, "Could not load logs, try again")
	end
	return reply(true, "", { Entries = logs, Counts = counts or {} })
end

function Actions.ListAdmins()
	local list = {}
	local seen = {}
	for key, entry in Ranks.All() do
		local userId = tonumber(key)
		if userId then
			seen[userId] = true
			table.insert(list, profile(userId, entry))
		end
	end
	for _, player in Players:GetPlayers() do
		if not seen[player.UserId] and Ranks.IsOwner(player.UserId) then
			table.insert(list, profile(player.UserId, nil))
		end
	end
	table.sort(list, function(a, b)
		local la, lb = Ranks.Level(a.UserId), Ranks.Level(b.UserId)
		if la ~= lb then
			return la > lb
		end
		return a.Name:lower() < b.Name:lower()
	end)
	return reply(true, "", list)
end

function Actions.Inspect(_admin, payload)
	local userId = tonumber(payload.UserId)
	if not userId or not Ranks.Get(userId) then
		return reply(false, "That player has no rank")
	end
	local data = profile(userId, Ranks.Entry(userId))
	data.Audit = StaffAudit.Summary(userId)
	return reply(true, "", data)
end

function Actions.RevertSanctions(admin, payload)
	local userId = tonumber(payload.UserId)
	if not userId or userId % 1 ~= 0 or userId == admin.UserId or Ranks.IsOwner(userId) then
		return reply(false, "You can't revert that player's sanctions")
	end
	local name = (Ranks.Entry(userId) and Ranks.Entry(userId).Name) or nameOf(userId)
	local reverted, failed = StaffAudit.RevertBans(userId, name, admin)
	local result = reply(
		failed == 0,
		if failed == 0
			then ("Reverted %d active bans by %s"):format(reverted, name)
			else ("Reverted %d bans by %s, %d failed"):format(reverted, name, failed)
	)
	result.StaffLog = ("Reverted all bans by @%s (%d)"):format(name, reverted)
	return result
end

function Service.Init()
	Ranks.Init()
	StaffAudit.Init()
	Broadcast.Init()
	Ranks.OnChanged(function()
		for _, player in Players:GetPlayers() do
			if Ranks.Level(player.UserId) > 0 then
				Remotes.fireTo(player, "adminRanksChanged")
			end
		end
	end)

	pcall(MessagingService.SubscribeAsync, MessagingService, TOPIC, function(message)
		local data = message.Data
		if type(data) == "table" and type(data.UserId) == "number" then
			moderateLocally(data)
		end
	end)

	Remotes.onServerInvoke("AdminRequest", function(admin: Player, action: any, payload: any): Result
		local handler = type(action) == "string" and Actions[action]
		local required = handler and Config.Permissions[action]
		if not handler or not required then
			return reply(false, "Unknown action")
		end
		if Ranks.Level(admin.UserId) < required then
			return reply(false, "You don't have permission for that")
		end
		local ok, result = pcall(handler, admin, if type(payload) == "table" then payload else {})
		if not ok then
			DebugConfig.warn(("[AdminService] %s falló: %s"):format(action, tostring(result)))
			return reply(false, "Something went wrong")
		end
		DebugConfig.print(("[AdminService] %s -> %s: %s"):format(admin.Name, action, result.Message))
		if result.Ok then
			if result.TargetLog then
				LogService.Add(result.TargetLog.UserId, "Moderation", result.TargetLog.Text, nil, action)
			end
			if STAFF_ACTIONS[action] then
				LogService.Add(admin.UserId, "Staff", result.StaffLog or result.Message, nil, action)
				StaffAudit.Record(admin, action, result.Sanction)
			end
		end
		result.TargetLog = nil
		result.StaffLog = nil
		result.Sanction = nil
		return result
	end, 0.3)
end

return Service
