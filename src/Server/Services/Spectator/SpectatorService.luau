-- Ubicación en Studio: ServerScriptService > Services > Spectator > SpectatorService (ModuleScript)
-- Autoridad del espectador (ReplicationFocus) y de los reportes a Discord (SubmitPlayerReport).
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local Http = game:GetService("HttpService")
local RunService = game:GetService("RunService")
local Config = require(RS:WaitForChild("SpectatorConfig"))
local Settings = require(script.Parent.ReportConfig)
local Policy = require(script.Parent.ReportPolicy)
local ReportEmbed = require(script.Parent.ReportEmbed)
local Remotes = require(RS:WaitForChild("Remotes"))
local Service = {}
-- Como mucho un cambio de objetivo cada tanto por jugador; el último pedido nunca se descarta.
local TARGET_INTERVAL = 0.1
local watching = {}
local lastTarget, pendingTarget = {}, {}
local focusBefore = {}
local function isDebugSelf(observer, target)
	return Config.DebugSelfSpectate == true and RunService:IsStudio() and observer == target and target ~= nil
end
local function clearObserver(player)
	watching[player] = nil
	if focusBefore[player] then
		local part = focusBefore[player].Part
		player.ReplicationFocus = if part and part.Parent then part else nil
		focusBefore[player] = nil
	end
end
local limiter = Policy.NewLimiter(Settings.CooldownSeconds, Settings.AttemptInterval)
function Service.SetRoundActive(active)
	RS:SetAttribute(Config.RoundAttribute, active == true)
	if not active then
		for player, id in watching do
			if id ~= player.UserId or not isDebugSelf(player, player) then
				clearObserver(player)
			end
		end
	end
end
function Service.SetParticipant(player, enabled, role)
	player:SetAttribute(Config.ParticipantAttribute, enabled == true)
	player:SetAttribute(Config.RoleAttribute, role or "PLAYER")
end
function Service.IsEligible(player)
	local h = player and player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	return RS:GetAttribute(Config.RoundAttribute) == true
		and player ~= nil
		and player.Parent == Players
		and player:GetAttribute(Config.ParticipantAttribute) == true
		and h ~= nil
		and h.Health > 0
end
local function canObserve(observer, target)
	if isDebugSelf(observer, target) then
		local h = target.Character and target.Character:FindFirstChildOfClass("Humanoid")
		return target.Parent == Players and h ~= nil and h.Health > 0
	end
	return observer ~= target and Service.IsEligible(target)
end
local function submit(player, targetId, reason, details)
	local clean, err = Policy.Validate(reason, details)
	if not clean then
		return { Ok = false, Code = err }
	end
	if type(targetId) ~= "number" or targetId % 1 ~= 0 then
		return { Ok = false, Code = "TargetGone" }
	end
	local target = Players:GetPlayerByUserId(targetId)
	if watching[player] ~= targetId or not canObserve(player, target) then
		return { Ok = false, Code = "TargetGone" }
	end
	local allowed, code, remaining = limiter.Reserve(player.UserId, targetId, os.clock())
	if not allowed then
		return { Ok = false, Code = code, Remaining = remaining }
	end
	local function finish(ok, result)
		limiter.Complete(player.UserId, targetId, os.clock(), ok)
		return { Ok = ok, Code = result, Cooldown = if ok then Settings.CooldownSeconds else nil }
	end
	local debugReport = isDebugSelf(player, target)
	if debugReport and Settings.SendDebugReports ~= true then
		return finish(true, "DebugPreview")
	end
	-- GetSecret falla si el secreto no está cargado o si HTTP está apagado.
	local found, webhook = pcall(Http.GetSecret, Http, Settings.WebhookSecret)
	if not found then
		if RunService:IsStudio() and Settings.StudioDryRun then
			return finish(true, "Preview")
		end
		return finish(false, "NotConfigured")
	end
	if not Http.HttpEnabled then
		return finish(false, "NotConfigured")
	end
	-- Nombres e IDs salen del servidor; el texto del jugador es contenido sin verificar.
	local payload = ReportEmbed.build(player, target, reason, clean, debugReport)
	local ok, response = pcall(function()
		return Http:RequestAsync({
			Url = webhook:AddSuffix("?wait=true"),
			Method = "POST",
			Headers = { ["Content-Type"] = "application/json" },
			Body = Http:JSONEncode(payload),
		})
	end)
	-- No loguear URL/token ni el texto; no reintentar un POST que quizá ya llegó.
	if not ok or not response.Success then
		return finish(false, "Failed")
	end
	return finish(true, "Sent")
end
local function applyTarget(player, id)
	if id == 0 then
		clearObserver(player)
		return
	end
	local target = Players:GetPlayerByUserId(id)
	if canObserve(player, target) then
		if not focusBefore[player] then
			focusBefore[player] = { Part = player.ReplicationFocus }
		end
		watching[player] = id
		player.ReplicationFocus = target.Character:FindFirstChild("HumanoidRootPart")
	else
		clearObserver(player)
	end
end
-- Throttle con "último gana": un clic rápido en Next no deja al servidor mirando otro objetivo.
local function requestTarget(player, id)
	if type(id) ~= "number" or id % 1 ~= 0 then
		return
	end
	local now = os.clock()
	local delay = (lastTarget[player] or 0) + TARGET_INTERVAL - now
	if delay <= 0 and pendingTarget[player] == nil then
		lastTarget[player] = now
		applyTarget(player, id)
		return
	end
	local scheduled = pendingTarget[player] ~= nil
	pendingTarget[player] = id
	if scheduled then
		return
	end
	task.delay(math.max(0, delay), function()
		local latest = pendingTarget[player]
		pendingTarget[player] = nil
		if latest ~= nil and player.Parent == Players then
			lastTarget[player] = os.clock()
			applyTarget(player, latest)
		end
	end)
end
function Service.Init()
	if RS:GetAttribute(Config.RoundAttribute) == nil then
		Service.SetRoundActive(false)
	end
	Remotes.onServerEvent("SetSpectatorTarget", requestTarget)
	Remotes.onServerInvoke("SubmitPlayerReport", submit, 0.25)
	Players.PlayerRemoving:Connect(function(player)
		lastTarget[player] = nil
		pendingTarget[player] = nil
		clearObserver(player)
		for observer, id in watching do
			if id == player.UserId then
				clearObserver(observer)
			end
		end
	end)
	task.spawn(function()
		local lastPrune = 0
		while true do
			task.wait(1)
			for observer, id in watching do
				local target = Players:GetPlayerByUserId(id)
				if not canObserve(observer, target) then
					clearObserver(observer)
				elseif target.Character then
					observer.ReplicationFocus = target.Character:FindFirstChild("HumanoidRootPart")
				end
			end
			if os.clock() - lastPrune >= 60 then
				lastPrune = os.clock()
				limiter.Prune(lastPrune)
			end
		end
	end)
end
return Service
