-- Ubicación en Studio: ServerScriptService > Services > Admin > StaffAudit (ModuleScript)
-- Auditoría del staff: cuántas acciones hizo cada uno y qué bans puso, en profile.Data.Staff.
-- Permite al Owner levantar de una vez todos los bans activos de un staff que abusó.
local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local RS = game:GetService("ReplicatedStorage")
local Config = require(RS:WaitForChild("AdminConfig"))
local DebugConfig = require(RS:WaitForChild("DebugConfig"))
local EasyProfileStore = require(ServerStorage:WaitForChild("EasyProfileStore"))
local Services = ServerScriptService:WaitForChild("Services")
local DataService = require(Services:WaitForChild("Data"):WaitForChild("DataService"))
local LogService = require(Services:WaitForChild("Logs"):WaitForChild("LogService"))

export type Sanction = {
	Kind: string,
	TargetId: number,
	TargetName: string,
	Reason: string,
	-- Segundos del ban; -1 = permanente. 0 en kicks y warns.
	Duration: number,
	At: number,
	Reverted: boolean,
}

export type Summary = {
	Total: number,
	Counts: { [string]: number },
	Bans: number,
	ActiveBans: number,
}

local StaffAudit = {}

local MESSAGE_TYPE = "StaffRevert"
local MAX_HISTORY_PAGES = 5

-- Staff con una reversión en curso: el doble click del Owner no la corre dos veces.
local reverting: { [number]: boolean } = {}

local function staffData(userId: number): any?
	local player = Players:GetPlayerByUserId(userId)
	local profile = player and DataService.GetProfile(player)
	return profile and profile.Data.Staff
end

local function readStaff(userId: number): any?
	local data = DataService.ReadData(userId)
	return data and data.Staff
end

local function isActiveBan(sanction: Sanction, now: number): boolean
	if sanction.Kind ~= "Ban" or sanction.Reverted then
		return false
	end
	return sanction.Duration < 0 or sanction.At + sanction.Duration > now
end

-- Quien hace la acción siempre está conectado: se escribe directo en su perfil.
function StaffAudit.Record(admin: Player, action: string, sanction: Sanction?)
	local data = staffData(admin.UserId)
	if not data then
		return
	end
	data.Counts[action] = (data.Counts[action] or 0) + 1
	if sanction then
		table.insert(data.Sanctions, 1, sanction)
		while #data.Sanctions > Config.Audit.MaxSanctions do
			table.remove(data.Sanctions)
		end
	end
end

function StaffAudit.Summary(userId: number): Summary?
	local data = readStaff(userId)
	if not data then
		return nil
	end
	local now = os.time()
	local total, bans, active = 0, 0, 0
	for _, amount in data.Counts do
		total += amount
	end
	for _, sanction in data.Sanctions do
		if sanction.Kind == "Ban" then
			bans += 1
			if isActiveBan(sanction, now) then
				active += 1
			end
		end
	end
	-- Counts.Ban es de por vida; la lista de bans guarda solo los últimos MaxSanctions.
	return { Total = total, Counts = data.Counts, Bans = data.Counts.Ban or bans, ActiveBans = active }
end

local function markReverted(data: any, untilTime: number)
	for _, sanction in data.Sanctions do
		if sanction.Kind == "Ban" and sanction.At <= untilTime then
			sanction.Reverted = true
		end
	end
end

-- true si el ban vigente de `targetId` lo puso `staffId` (BanAsync guarda "(<UserId>)" en
-- PrivateReason); nil si no se pudo consultar (en Studio la API responde 403).
local function bannedBy(targetId: number, staffId: number): boolean?
	local ok, pages = pcall(Players.GetBanHistoryAsync, Players, targetId)
	if not ok then
		return nil
	end
	local latest, latestAt = nil, -math.huge
	for _ = 1, MAX_HISTORY_PAGES do
		for _, entry in pages:GetCurrentPage() do
			local start = DateTime.fromIsoDate(entry.StartTime)
			local at = if start then start.UnixTimestamp else 0
			if at >= latestAt then
				latest, latestAt = entry, at
			end
		end
		if pages.IsFinished or not pcall(pages.AdvanceToNextPageAsync, pages) then
			break
		end
	end
	return latest ~= nil and latest.Ban and (latest.PrivateReason or ""):find(("(%d)"):format(staffId), 1, true) ~= nil
end

-- Levanta todos los bans activos que puso `staffId`. Devuelve cuántos levantó y cuántos fallaron.
-- Un jugador que después baneó OTRO staff (o que ya fue desbaneado) no se toca.
function StaffAudit.RevertBans(staffId: number, staffName: string, owner: Player): (number, number)
	if reverting[staffId] then
		return 0, 0
	end
	local data = readStaff(staffId)
	if not data then
		return 0, 0
	end
	reverting[staffId] = true
	local now = os.time()
	local reverted, failed = 0, 0
	local seen = {}
	for _, sanction in data.Sanctions do
		if isActiveBan(sanction, now) and not seen[sanction.TargetId] then
			seen[sanction.TargetId] = true
			local checked, stillTheirs = pcall(bannedBy, sanction.TargetId, staffId)
			stillTheirs = if checked then stillTheirs else nil
			if stillTheirs == false then
				continue
			elseif stillTheirs == nil then
				DebugConfig.warn(("[StaffAudit] Sin historial de bans de %d; se desbanea igual"):format(sanction.TargetId))
			end
			local ok, err = pcall(Players.UnbanAsync, Players, { UserIds = { sanction.TargetId }, ApplyToUniverse = true })
			if ok then
				reverted += 1
				LogService.Add(
					sanction.TargetId,
					"Moderation",
					("Ban by @%s reverted by @%s (staff review)"):format(staffName, owner.Name),
					nil,
					"Unban"
				)
			else
				failed += 1
				DebugConfig.warn(("[StaffAudit] UnbanAsync(%d) falló: %s"):format(sanction.TargetId, tostring(err)))
			end
		end
	end
	-- Staff desconectado: el perfil guardado no se puede editar; la marca llega como mensaje.
	local live = staffData(staffId)
	if live then
		markReverted(live, now)
	else
		pcall(function()
			EasyProfileStore:PublishMessage(staffId, { Type = MESSAGE_TYPE, Until = now })
		end)
	end
	LogService.Add(
		staffId,
		"Staff",
		("All active bans (%d) reverted by @%s"):format(reverted, owner.Name),
		nil,
		"RevertSanctions"
	)
	reverting[staffId] = nil
	return reverted, failed
end

function StaffAudit.Init()
	DataService.OnMessage(MESSAGE_TYPE, function(player, message, processed)
		local data = staffData(player.UserId)
		if data and type(message.Until) == "number" then
			markReverted(data, message.Until)
		end
		processed()
	end)
end

return StaffAudit
