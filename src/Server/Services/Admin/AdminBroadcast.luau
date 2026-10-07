-- Ubicación en Studio: ServerScriptService > Services > Admin > AdminBroadcast (ModuleScript)
-- Anuncios, mensajes de servidor y polls del Admin Panel, en este servidor o en todos (Global).
local Players = game:GetService("Players")
local MessagingService = game:GetService("MessagingService")
local TextService = game:GetService("TextService")
local HttpService = game:GetService("HttpService")
local RS = game:GetService("ReplicatedStorage")
local Config = require(RS:WaitForChild("AdminConfig"))
local Remotes = require(RS:WaitForChild("Remotes"))
local DebugConfig = require(RS:WaitForChild("DebugConfig"))

local Broadcast = {}

local TOPIC = "AdminBroadcast"
-- Cada cuánto se reparten los votos entre servidores en un poll Global (MessagingService tiene cupo).
local COUNTS_INTERVAL = 2
-- Tope de avisos de votos a los clientes, para no mandar uno por cada voto.
local CLIENT_UPDATE_INTERVAL = 0.4

type Poll = {
	Id: string,
	Question: string,
	Options: { string },
	EndsAt: number,
	Global: boolean,
	Author: string,
	votes: { [number]: number },
	remote: { [string]: { number } },
	dirty: boolean,
	-- Votos de este servidor que los demás todavía no recibieron.
	unpublished: boolean,
	ended: boolean,
}

local poll: Poll? = nil

-- Roblox exige filtrar todo texto de un jugador que vean otros.
local function filter(text: string, fromUserId: number): string?
	local ok, result = pcall(function()
		return TextService:FilterStringAsync(text, fromUserId):GetNonChatStringForBroadcastAsync()
	end)
	if not ok then
		DebugConfig.warn("[AdminBroadcast] Falló el filtro de texto: " .. tostring(result))
		return nil
	end
	return result
end

local function publish(data: { [string]: any }): boolean
	local ok, err = pcall(MessagingService.PublishAsync, MessagingService, TOPIC, data)
	if not ok then
		DebugConfig.warn("[AdminBroadcast] No se pudo publicar a otros servidores: " .. tostring(err))
	end
	return ok
end

local function counts(current: Poll): { number }
	local total = table.create(#current.Options, 0)
	for _, index in current.votes do
		total[index] += 1
	end
	for _, other in current.remote do
		for index, amount in other do
			if total[index] then
				total[index] += math.max(0, tonumber(amount) or 0)
			end
		end
	end
	return total
end

local function pollPayload(current: Poll)
	return {
		Id = current.Id,
		Question = current.Question,
		Options = current.Options,
		Remaining = math.max(0, current.EndsAt - os.time()),
		Global = current.Global,
		Author = current.Author,
		Counts = counts(current),
	}
end

local function endPoll(id: string)
	local current = poll
	if not current or current.Id ~= id or current.ended then
		return
	end
	current.ended = true
	poll = nil
	Remotes.fireAll("adminPollEnded", { Id = current.Id, Counts = counts(current) })
end

local function startPoll(data)
	if poll and not poll.ended then
		endPoll(poll.Id)
	end
	local current: Poll = {
		Id = data.Id,
		Question = data.Question,
		Options = data.Options,
		EndsAt = data.EndsAt,
		Global = data.Global,
		Author = data.Author,
		votes = {},
		remote = {},
		dirty = false,
		unpublished = false,
		ended = false,
	}
	poll = current
	Remotes.fireAll("adminPollStarted", pollPayload(current))
	task.delay(math.max(0, current.EndsAt - os.time()), endPoll, current.Id)
end

local function show(data)
	if data.Kind == "Announce" then
		Remotes.fireAll("adminAnnouncement", data)
	elseif data.Kind == "Message" then
		Remotes.fireAll("adminServerMessage", data)
	elseif data.Kind == "PollStart" then
		startPoll(data)
	elseif data.Kind == "PollEnd" then
		endPoll(data.Id)
	elseif data.Kind == "PollCounts" then
		local current = poll
		if current and current.Id == data.Id and data.JobId ~= game.JobId and type(data.Counts) == "table" then
			current.remote[data.JobId] = data.Counts
			current.dirty = true
		end
	end
end

-- Global: MessagingService también le entrega el mensaje a este servidor, así que no se
-- muestra acá dos veces; si falla la publicación, al menos sale en este servidor.
local function send(data, global: boolean)
	if not (global and publish(data)) then
		show(data)
	end
end

function Broadcast.Announce(sender: Player, text: string, global: boolean): (boolean, string)
	local clean = filter(text, sender.UserId)
	if not clean then
		return false, "Text filter failed, try again"
	end
	send({
		Kind = "Announce",
		Text = clean,
		UserId = sender.UserId,
		Name = sender.Name,
		DisplayName = sender.DisplayName,
	}, global)
	return true, if global then "Announcement sent to all servers" else "Announcement sent"
end

function Broadcast.ServerMessage(sender: Player, text: string, global: boolean): (boolean, string)
	local clean = filter(text, sender.UserId)
	if not clean then
		return false, "Text filter failed, try again"
	end
	send({ Kind = "Message", Text = clean, Name = sender.Name }, global)
	return true, if global then "Message sent to all servers" else "Message sent"
end

function Broadcast.StartPoll(sender: Player, question: string, options: { string }, seconds: number, global: boolean)
	if poll and not poll.ended then
		return false, "A poll is already running, end it first"
	end
	local cleanQuestion = filter(question, sender.UserId)
	if not cleanQuestion then
		return false, "Text filter failed, try again"
	end
	local cleanOptions = {}
	for _, option in options do
		local clean = filter(option, sender.UserId)
		if not clean then
			return false, "Text filter failed, try again"
		end
		table.insert(cleanOptions, clean)
	end
	send({
		Kind = "PollStart",
		Id = HttpService:GenerateGUID(false),
		Question = cleanQuestion,
		Options = cleanOptions,
		EndsAt = os.time() + seconds,
		Global = global,
		Author = sender.Name,
	}, global)
	return true, "Poll started"
end

function Broadcast.EndPoll(): (boolean, string)
	local current = poll
	if not current or current.ended then
		return false, "There is no active poll"
	end
	send({ Kind = "PollEnd", Id = current.Id }, current.Global)
	return true, "Poll ended"
end

function Broadcast.Init()
	pcall(MessagingService.SubscribeAsync, MessagingService, TOPIC, function(message)
		if type(message.Data) == "table" then
			show(message.Data)
		end
	end)

	Remotes.onServerEvent("VotePoll", function(player: Player, id: any, index: any)
		local current = poll
		if not current or current.ended or id ~= current.Id then
			return
		end
		if type(index) ~= "number" or index % 1 ~= 0 or not current.Options[index] then
			return
		end
		current.votes[player.UserId] = index
		current.dirty = true
		current.unpublished = true
	end, 0.25)

	Remotes.onServerInvoke("GetActivePoll", function(player: Player)
		local current = poll
		if not current or current.ended then
			return nil
		end
		return pollPayload(current), current.votes[player.UserId]
	end, 1)

	task.spawn(function()
		local lastPublish = 0
		while true do
			task.wait(CLIENT_UPDATE_INTERVAL)
			local current = poll
			if not current then
				continue
			end
			if current.dirty then
				current.dirty = false
				Remotes.fireAll("adminPollCounts", { Id = current.Id, Counts = counts(current) })
			end
			if current.Global and current.unpublished and os.clock() - lastPublish >= COUNTS_INTERVAL then
				current.unpublished = false
				lastPublish = os.clock()
				local own = table.create(#current.Options, 0)
				for _, index in current.votes do
					own[index] += 1
				end
				task.spawn(publish, { Kind = "PollCounts", Id = current.Id, JobId = game.JobId, Counts = own })
			end
		end
	end)
end

return Broadcast
