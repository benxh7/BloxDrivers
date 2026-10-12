-- Ubicación en Studio: ServerScriptService > Services > Crate > CrateService (ModuleScript)
-- Autoridad de las cajas: compra, tirada y sorteo. Cajas y premios viven en profile.Data.Crates.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local RS = game:GetService("ReplicatedStorage")
local Config = require(RS:WaitForChild("CrateConfig"))
local Remotes = require(RS:WaitForChild("Remotes"))
local DebugConfig = require(RS:WaitForChild("DebugConfig"))
local DataService = require(ServerScriptService:WaitForChild("Services"):WaitForChild("Data"):WaitForChild("DataService"))

local Service = {}

-- Pedidos del mismo jugador más seguidos que esto se descartan (el remote devuelve nil).
local REQUEST_COOLDOWN = 0.15
-- Respuestas recordadas por jugador: un reintento con el mismo RequestId no cobra dos veces.
local MAX_RECEIPTS = 32
-- Tope de cajas que un script de confianza puede dar de una vez.
local MAX_GRANT = 1000

type Wallet = { Cash: number, Gems: number }
type Session = { Receipts: { [string]: any }, ReceiptOrder: { string }, Wallet: Wallet? }
type Response = { Ok: boolean, Message: string?, State: any?, Results: { string }?, CaseId: string?, Lucky: boolean? }

local sessions: { [Player]: Session } = {}
local random = Random.new()

local function demoEnabled(): boolean
	return Config.StudioDemo and RunService:IsStudio()
end

local function fail(message: string): Response
	return { Ok = false, Message = message }
end

local function session(player: Player): Session
	local current = sessions[player]
	if not current then
		current = {
			Receipts = {},
			ReceiptOrder = {},
			Wallet = if demoEnabled() then { Cash = Config.DemoCash, Gems = Config.DemoGems } else nil,
		}
		sessions[player] = current
	end
	return current
end

local function crateData(player: Player): any?
	local profile = DataService.GetProfile(player)
	return profile and profile.Data.Crates
end

local function snapshot(player: Player): any
	local data = crateData(player)
	local wallet = session(player).Wallet
	return {
		Owned = if data then table.clone(data.Owned) else {},
		Cash = wallet and wallet.Cash,
		Gems = wallet and wallet.Gems,
		Demo = wallet ~= nil,
	}
end

local function remember(current: Session, requestId: string, response: Response)
	current.Receipts[requestId] = response
	table.insert(current.ReceiptOrder, requestId)
	if #current.ReceiptOrder > MAX_RECEIPTS then
		current.Receipts[table.remove(current.ReceiptOrder, 1)] = nil
	end
end

local function charge(wallet: Wallet?, currency: string, price: number): string?
	if not wallet then
		return "Purchases are not available yet."
	end
	if wallet[currency] < price then
		return ("Not enough %s."):format(currency:lower())
	end
	wallet[currency] -= price
	return nil
end

local BUY_OPTIONS = {
	Gems1 = { Count = 1, Currency = "Gems", Price = function(case) return case.Gems end },
	Gems3 = { Count = 3, Currency = "Gems", Price = function(case) return case.Gems * 3 end },
	Cash1 = { Count = 1, Currency = "Cash", Price = function(case) return case.Cash end },
}

local function buy(player: Player, data: any, caseId: string, option: any): Response
	local choice = BUY_OPTIONS[option]
	if not choice then
		return fail("Unknown purchase option.")
	end
	local problem = charge(session(player).Wallet, choice.Currency, choice.Price(Config.Cases[caseId]))
	if problem then
		return fail(problem)
	end
	data.Owned[caseId] = (data.Owned[caseId] or 0) + choice.Count
	return { Ok = true, State = snapshot(player), CaseId = caseId }
end

-- El premio se guarda acá, antes de la animación: cerrar, morir o saltear no cambia nada.
local function open(player: Player, data: any, caseId: string, lucky: boolean, count: any): Response
	if lucky then
		if count ~= 1 and count ~= 3 then
			return fail("Invalid opening count.")
		end
		local problem = charge(session(player).Wallet, "Gems", Config.Cases[caseId].LuckyGems * count)
		if problem then
			return fail(problem)
		end
	else
		count = 1
		if (data.Owned[caseId] or 0) < 1 then
			return fail("You do not own this case. Buy one first.")
		end
		data.Owned[caseId] -= 1
	end
	local results = {}
	for _ = 1, count do
		local reward = Config.Pick(caseId, lucky, random)
		local key = caseId .. ":" .. reward.Id
		data.Rewards[key] = (data.Rewards[key] or 0) + 1
		table.insert(results, reward.Id)
	end
	return { Ok = true, State = snapshot(player), Results = results, CaseId = caseId, Lucky = lucky }
end

local function handle(player: Player, action: any, caseId: any, option: any, requestId: any): Response
	if type(action) ~= "string" or type(caseId) ~= "string" or not Config.Cases[caseId] then
		return fail("Unknown case.")
	end
	local data = crateData(player)
	if not data then
		return fail("Your data is still loading, try again.")
	end
	if action == "State" then
		return { Ok = true, State = snapshot(player) }
	end
	if type(requestId) ~= "string" or #requestId < 8 or #requestId > 80 then
		return fail("Invalid request.")
	end
	local current = session(player)
	local previous = current.Receipts[requestId]
	if previous then
		return previous
	end
	local response
	if action == "Buy" then
		response = buy(player, data, caseId, option)
	elseif action == "Spin" or action == "Lucky" then
		response = open(player, data, caseId, action == "Lucky", option)
	else
		return fail("Unknown action.")
	end
	if response.Ok then
		remember(current, requestId, response)
	end
	return response
end

-- Solo para scripts de confianza del servidor (códigos, tienda, premios).
function Service.GrantCase(player: Player, caseId: string, count: number): (boolean, string?)
	local data = crateData(player)
	if not data then
		return false, "Profile not loaded"
	end
	if not Config.Cases[caseId] or type(count) ~= "number" or count % 1 ~= 0 or count < 1 or count > MAX_GRANT then
		return false, "Invalid grant"
	end
	data.Owned[caseId] = (data.Owned[caseId] or 0) + count
	return true
end

function Service.Init()
	DataService.OnProfileLoaded(function(_player, profile)
		if not demoEnabled() then
			return
		end
		local owned = profile.Data.Crates.Owned
		for caseId in Config.Cases do
			owned[caseId] = math.max(owned[caseId] or 0, Config.DemoOwned)
		end
	end)
	Remotes.onServerInvoke("CrateRequest", function(player, ...)
		local ok, response = pcall(handle, player, ...)
		if not ok then
			DebugConfig.warn("[CrateService] Pedido falló: " .. tostring(response))
			return fail("The case could not be opened. Please try again.")
		end
		return response
	end, REQUEST_COOLDOWN)
	Players.PlayerRemoving:Connect(function(player)
		sessions[player] = nil
	end)
end

return Service
