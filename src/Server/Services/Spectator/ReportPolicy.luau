-- Ubicación en Studio: ServerScriptService > Services > Spectator > ReportPolicy (ModuleScript)
-- Validación del texto de un reporte y rate limit por reportero/objetivo.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage:WaitForChild("SpectatorConfig"))
local Policy = {}
function Policy.Validate(reason, details)
	if type(details) ~= "string" then
		return nil, "Details"
	end
	local length = utf8.len(details)
	if not length then
		return nil, "Details"
	end
	if length > Config.MaxDetailsLength then
		return nil, "TooLong"
	end
	local clean = details
		:gsub("%c", " ")
		:gsub(utf8.char(0x200B), "")
		:gsub(utf8.char(0xFEFF), "")
		:gsub(utf8.char(0xA0), " ")
		:match("^%s*(.-)%s*$")
	if clean == "" then
		return nil, "Details"
	end
	for _, entry in Config.Reasons do
		if reason == entry.Id then
			return clean
		end
	end
	return nil, "Reason"
end
function Policy.NewLimiter(cooldown, interval)
	local pairsByReporter, attempts, busy = {}, {}, {}
	local limiter = {}
	function limiter.Reserve(reporter, target, now)
		local per = pairsByReporter[reporter]
		local expiry = per and per[target]
		if expiry and expiry > now then
			return false, "Cooldown", math.ceil(expiry - now)
		end
		if busy[reporter] or (attempts[reporter] and now - attempts[reporter] < interval) then
			return false, "Busy"
		end
		attempts[reporter] = now
		busy[reporter] = true
		return true
	end
	function limiter.Complete(reporter, target, now, success)
		busy[reporter] = nil
		if success then
			pairsByReporter[reporter] = pairsByReporter[reporter] or {}
			pairsByReporter[reporter][target] = now + cooldown
		end
	end
	function limiter.Prune(now)
		for id, per in pairsByReporter do
			for target, expiry in per do
				if expiry <= now then
					per[target] = nil
				end
			end
			if next(per) == nil then
				pairsByReporter[id] = nil
			end
		end
		for id, time in attempts do
			if now - time > cooldown and not busy[id] then
				attempts[id] = nil
			end
		end
	end
	return limiter
end
return Policy
