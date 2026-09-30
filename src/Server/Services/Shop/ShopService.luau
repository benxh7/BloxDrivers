-- Ubicación en Studio: ServerScriptService > Services > Shop > ShopService (ModuleScript)
--
-- Autoridad de la tienda. Pareja de ShopController (cliente) y ShopConfig (catálogo).
--   · "RequestShopPurchase"(itemId): valida el item y abre el prompt de Roblox. El
--     cliente nunca manda IDs de producto ni precios.
--   · Developer Products: se otorgan en ProcessReceipt. ES ÚNICO POR JUEGO: ningún otro
--     script puede asignar MarketplaceService.ProcessReceipt.
--   · Game Passes: se chequean al entrar (UserOwnsGamePassAsync) y al comprarse; otros
--     servicios preguntan con ShopService.OwnsPass(player, itemId).
--
-- Qué otorga cada Product lo decide un "grant" por Reward.Type, que registra quien
-- maneje esos datos (ej. el futuro DataService):
--   ShopService.RegisterGrant("Cash", function(player, amount) ... return true end)
-- Sin grant registrado la compra queda NotProcessedYet (Roblox la reintenta) en vez de
-- cobrar sin entregar.
local Players = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage:WaitForChild("Remotes"))
local ShopConfig = require(ReplicatedStorage:WaitForChild("ShopConfig"))
local DebugConfig = require(ReplicatedStorage:WaitForChild("DebugConfig"))

local ShopService = {}

local PURCHASE_COOLDOWN = 1
local OWNED_COOLDOWN = 2

type Grant = (player: Player, amount: number, receipt: { [string]: any }) -> boolean

local grants: { [string]: Grant } = {}
-- ProductId / GamePassId -> itemId de ShopConfig.
local productToItem: { [number]: string } = {}
local passToItem: { [number]: string } = {}
-- UserId -> { itemId = true } de Game Passes.
local ownedPasses: { [number]: { [string]: boolean } } = {}
-- Recibos ya otorgados en ESTE servidor. OJO: no sobrevive a un reinicio; cuando exista
-- DataService, guardar el PurchaseId en el perfil del jugador para que sea idempotente.
local granted: { [string]: boolean } = {}

for itemId, item in ShopConfig.Items do
	local id = item.ProductId
	if id and id > 0 then
		if item.Kind == "Product" then
			productToItem[id] = itemId
		elseif item.Kind == "GamePass" then
			passToItem[id] = itemId
		end
	end
end

function ShopService.RegisterGrant(rewardType: string, grant: Grant)
	grants[rewardType] = grant
end

function ShopService.OwnsPass(player: Player, itemId: string): boolean
	local passes = ownedPasses[player.UserId]
	return passes ~= nil and passes[itemId] == true
end

local function markPass(player: Player, itemId: string)
	local passes = ownedPasses[player.UserId]
	if not passes then
		passes = {}
		ownedPasses[player.UserId] = passes
	end
	passes[itemId] = true
end

local function loadPasses(player: Player)
	for passId, itemId in passToItem do
		local ok, owns = pcall(MarketplaceService.UserOwnsGamePassAsync, MarketplaceService, player.UserId, passId)
		if ok and owns then
			markPass(player, itemId)
			-- Por si el cliente ya preguntó con GetShopOwned antes de que esto terminara.
			Remotes.fireTo(player, "shopOwned", itemId)
		elseif not ok then
			DebugConfig.warn(("[ShopService] UserOwnsGamePassAsync(%d) falló: %s"):format(passId, tostring(owns)))
		end
	end
end

local function onPurchaseRequest(player: Player, itemId: any)
	if typeof(itemId) ~= "string" then
		return
	end
	local item = ShopConfig.get(itemId)
	if not item or not item.ProductId or item.ProductId <= 0 then
		return
	end

	local ok, err
	if item.Kind == "Product" then
		ok, err = pcall(MarketplaceService.PromptProductPurchase, MarketplaceService, player, item.ProductId)
	elseif item.Kind == "GamePass" then
		if ShopService.OwnsPass(player, itemId) then
			return
		end
		ok, err = pcall(MarketplaceService.PromptGamePassPurchase, MarketplaceService, player, item.ProductId)
	else
		return
	end
	if not ok then
		DebugConfig.warn(("[ShopService] No se pudo abrir el prompt de '%s': %s"):format(itemId, tostring(err)))
	end
end

local function processReceipt(receipt: { [string]: any }): Enum.ProductPurchaseDecision
	if granted[receipt.PurchaseId] then
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end

	local player = Players:GetPlayerByUserId(receipt.PlayerId)
	if not player then
		-- Se fue antes de otorgar: Roblox reintenta cuando vuelva a entrar.
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local itemId = productToItem[receipt.ProductId]
	local item = itemId and ShopConfig.get(itemId)
	local reward = item and item.Reward
	if not reward then
		DebugConfig.warn(("[ShopService] Producto %d sin item/Reward en ShopConfig"):format(receipt.ProductId))
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local grant = grants[reward.Type]
	if not grant then
		DebugConfig.warn(("[ShopService] No hay grant registrado para '%s' (item '%s')"):format(reward.Type, itemId))
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	-- Otorgar PRIMERO; recién si salió bien se confirma la compra.
	local ok, result = pcall(grant, player, reward.Amount, receipt)
	if not ok or result ~= true then
		DebugConfig.warn(("[ShopService] Falló el grant de '%s' para %s: %s"):format(itemId, player.Name, tostring(result)))
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	granted[receipt.PurchaseId] = true
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

function ShopService.Init()
	MarketplaceService.ProcessReceipt = processReceipt

	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player: Player, passId: number, purchased: boolean)
		local itemId = passToItem[passId]
		if purchased and itemId then
			markPass(player, itemId)
			Remotes.fireTo(player, "shopOwned", itemId)
		end
	end)

	Remotes.onServerEvent("RequestShopPurchase", onPurchaseRequest, PURCHASE_COOLDOWN)
	Remotes.onServerInvoke("GetShopOwned", function(player: Player)
		local list = {}
		for itemId in ownedPasses[player.UserId] or {} do
			table.insert(list, itemId)
		end
		return list
	end, OWNED_COOLDOWN)

	Players.PlayerAdded:Connect(loadPasses)
	for _, player in Players:GetPlayers() do
		task.spawn(loadPasses, player)
	end
	Players.PlayerRemoving:Connect(function(player: Player)
		ownedPasses[player.UserId] = nil
	end)
end

return ShopService
