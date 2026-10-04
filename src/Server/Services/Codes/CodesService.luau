-- Ubicación en Studio: ServerScriptService > Services > Codes > CodesService (ModuleScript)
-- Canje de códigos: saldo y canje se guardan en UNA transacción (UpdateAsync). Wallet es
-- el saldo propio de este sistema, no toca otra economía.
local RS = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local DSS = game:GetService("DataStoreService")
local Http = game:GetService("HttpService")
local Remotes = require(RS:WaitForChild("Remotes"))
local Config = require(script.Parent.CodesConfig)
local Service = {}
local busy, last = {}, {}
local database = DSS:GetDataStore(Config.DataStoreName)
local function result(ok, message)
	return { Ok = ok, Message = message }
end
function Service.Normalize(raw)
	if type(raw) ~= "string" or #raw > 64 then
		return nil
	end
	local code = raw:match("^%s*(.-)%s*$"):upper()
	if #code == 0 or not code:match("^[A-Z0-9_%-]+$") then
		return nil
	end
	return code
end
function Service.Validate(code, now)
	local entry = Config.Codes[code]
	if not entry or entry.Enabled == false then
		return nil, "Invalid code."
	end
	if entry.ExpiresAt and now >= entry.ExpiresAt then
		return nil, "This code has expired."
	end
	if entry.StartsAt and now < entry.StartsAt then
		return nil, "This code is not active yet."
	end
	if not entry.Demo then
		if type(entry.Rewards) ~= "table" or #entry.Rewards == 0 then
			return nil, "Rewards are not configured yet."
		end
		for _, r in entry.Rewards do
			if
				not ({ Cash = true, Gems = true, Revive = true, Item = true })[r.Type]
				or type(r.Amount) ~= "number"
				or r.Amount ~= r.Amount
				or r.Amount % 1 ~= 0
				or r.Amount <= 0
				or r.Amount > 1e9
				or (r.Type == "Item" and (type(r.Id) ~= "string" or #r.Id == 0 or #r.Id > 64))
			then
				return nil, "Rewards are not configured correctly."
			end
		end
	end
	return entry
end
-- Función pura: la usan UpdateAsync y las pruebas.
function Service.Apply(data, code, entry, token, now)
	data = data or { Redeemed = {}, Wallet = { Cash = 0, Gems = 0, Revive = 0, Items = {} } }
	data.Redeemed = data.Redeemed or {}
	data.Wallet = data.Wallet or { Cash = 0, Gems = 0, Revive = 0, Items = {} }
	data.Wallet.Items = data.Wallet.Items or {}
	if data.Redeemed[code] then
		return data
	end
	for _, r in entry.Rewards do
		if r.Type == "Item" then
			data.Wallet.Items[r.Id] = (data.Wallet.Items[r.Id] or 0) + r.Amount
		else
			data.Wallet[r.Type] = (data.Wallet[r.Type] or 0) + r.Amount
		end
	end
	data.Redeemed[code] = { Token = token, At = now }
	return data
end
function Service.Redeem(player, raw)
	local nowClock = os.clock()
	if busy[player] or (last[player] and nowClock - last[player] < Config.Cooldown) then
		return result(false, "Please wait a moment.")
	end
	last[player] = nowClock
	local code = Service.Normalize(raw)
	if not code then
		return result(false, "Enter a valid code.")
	end
	local entry, reason = Service.Validate(code, os.time())
	if not entry then
		return result(false, reason)
	end
	if entry.Demo then
		return result(true, entry.Message or "Test code redeemed!")
	end
	busy[player] = true
	local token = Http:GenerateGUID(false)
	local ok, data = pcall(function()
		return database:UpdateAsync("Player_" .. player.UserId, function(previous)
			-- Se revalida: UpdateAsync puede reintentar después de que expiró.
			if not Service.Validate(code, os.time()) then
				return nil
			end
			return Service.Apply(previous, code, entry, token, os.time())
		end)
	end)
	busy[player] = nil
	if not ok then
		warn("[CodesService] Save failed: " .. tostring(data))
		return result(false, "Could not save. Please try again.")
	end
	if not data then
		return result(false, "This code is no longer active.")
	end
	if data.Redeemed[code].Token ~= token then
		return result(false, "Code already redeemed.")
	end
	return result(true, entry.Message or "Rewards claimed!")
end
-- Para que otros servicios lean el saldo cuando se conecte la economía.
function Service.GetWallet(userId)
	local ok, data = pcall(database.GetAsync, database, "Player_" .. userId)
	if not ok then
		return nil
	end
	return data and data.Wallet or { Cash = 0, Gems = 0, Revive = 0, Items = {} }
end
function Service.Init()
	Remotes.onServerInvoke("RedeemCode", Service.Redeem)
	Players.PlayerRemoving:Connect(function(p)
		busy[p] = nil
		last[p] = nil
	end)
end
return Service
