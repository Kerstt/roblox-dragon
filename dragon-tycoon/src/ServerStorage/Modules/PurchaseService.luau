-- ServerStorage/Modules/PurchaseService
-- Robux purchases: Game Pass ownership and the ProcessReceipt handler for
-- Developer Products.
--
-- ProcessReceipt rules:
--  * Each PurchaseId is granted once. It's recorded in the player's save, so a
--    retried receipt is never granted twice.
--  * We only tell Roblox "PurchaseGranted" once the grant is saved, including
--    for retries of a receipt we granted but couldn't save yet.
--  * Only one call per PurchaseId runs at a time.
--  * If a grant fails part-way, the player's data is put back as it was.
--  * Grant functions must NOT yield.
--
-- Products are registered by the systems that own them (Phase 4), e.g.:
--   PurchaseService.RegisterProduct(123456, "CoinPackSmall", function(player, data, receipt)
--       return EconomyService.AddCoins(player, 1000, "RobuxCoinPack", "IAP")
--   end)

local Players = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local DataService = require(script.Parent.DataService)

local PurchaseService = {}

type GrantFn = (player: Player, data: any, receipt: any) -> boolean
type Product = { Name: string, Grant: GrantFn }

local PASS_RETRY_SECONDS = 60 -- after a failed ownership check, wait this long before asking again

local products: { [number]: Product } = {}
local inFlight: { [string]: boolean } = {} -- PurchaseIds being processed right now
local unsaved: { [string]: boolean } = {} -- granted in memory, not yet confirmed saved
local passOwnership: { [Player]: { [string]: boolean } } = {}
local passFailedAt: { [Player]: { [string]: number } } = {}

local passPurchased = Instance.new("BindableEvent")
-- Fires (player, passName) when a player buys a Game Pass in this session.
PurchaseService.PassPurchased = passPurchased.Event

function PurchaseService.RegisterProduct(productId: number, name: string, grant: GrantFn)
	assert(type(productId) == "number" and productId > 0, "Product ID must be a positive number")
	assert(products[productId] == nil, "Product already registered: " .. tostring(productId))
	products[productId] = { Name = name, Grant = grant }
end

-- Game Passes -----------------------------------------------------------------

local function passIdFor(passName: string): number?
	local passId = GameConfig.GamePasses[passName]
	return if type(passId) == "number" and passId > 0 then passId else nil
end

-- Checks ownership with Roblox. May yield. Use OwnsPassCached in hot paths.
function PurchaseService.OwnsPass(player: Player, passName: string): boolean
	local passId = passIdFor(passName)
	if not passId then
		return false -- pass not created yet
	end
	local cache = passOwnership[player]
	if cache and cache[passName] ~= nil then
		return cache[passName]
	end
	local failed = passFailedAt[player]
	if failed and failed[passName] and os.clock() - failed[passName] < PASS_RETRY_SECONDS then
		return false
	end

	local ok, owns = pcall(MarketplaceService.UserOwnsGamePassAsync, MarketplaceService, player.UserId, passId)
	if player.Parent ~= Players then
		return false -- left while we waited; don't recreate their cache entries
	end
	if not ok then
		warn("[PurchaseService] Pass check failed for", player.Name, passName, owns)
		passFailedAt[player] = passFailedAt[player] or {}
		passFailedAt[player][passName] = os.clock()
		return false
	end
	passOwnership[player] = passOwnership[player] or {}
	passOwnership[player][passName] = owns == true
	return owns == true
end

-- Never yields: answers from what we already know (false until checked).
function PurchaseService.OwnsPassCached(player: Player, passName: string): boolean
	local cache = passOwnership[player]
	return cache ~= nil and cache[passName] == true
end

local function prefetchPasses(player: Player)
	for passName in GameConfig.GamePasses do
		if passIdFor(passName) then
			task.spawn(PurchaseService.OwnsPass, player, passName)
		end
	end
end

local function passNameForId(passId: number): string?
	for name in GameConfig.GamePasses do
		if passIdFor(name) == passId then
			return name
		end
	end
	return nil
end

-- Developer Products --------------------------------------------------------------

-- Puts every top-level field of target back to snapshot's values.
local function restoreInPlace(target: { [any]: any }, snapshot: { [any]: any })
	for key in target do
		if snapshot[key] == nil then
			target[key] = nil
		end
	end
	for key, value in snapshot do
		target[key] = value
	end
end

-- Applies one receipt to a player's data. Pure logic, no saving.
-- Returns "already", "granted" or "failed".
function PurchaseService.applyReceipt(player: Player, data: any, receipt: any, product: Product?): string
	local purchases = data.Purchases
	if purchases.Receipts[receipt.PurchaseId] then
		return "already"
	end
	if not product then
		return "failed"
	end

	local before = DataService.deepCopy(data)
	local ok, granted = pcall(product.Grant, player, data, receipt)
	if not ok or granted ~= true then
		restoreInPlace(data, before) -- undo anything the grant changed before failing
		warn("[PurchaseService] Grant failed for product", receipt.ProductId, if ok then "(returned false)" else granted)
		return "failed"
	end

	purchases.Receipts[receipt.PurchaseId] = os.time()
	table.insert(purchases.ReceiptOrder, receipt.PurchaseId)
	while #purchases.ReceiptOrder > GameConfig.MaxStoredReceipts do
		local oldest = table.remove(purchases.ReceiptOrder, 1)
		purchases.Receipts[oldest] = nil
	end

	table.insert(purchases.History, {
		ProductId = receipt.ProductId,
		PurchaseId = receipt.PurchaseId,
		Robux = receipt.CurrencySpent,
		Time = os.time(),
	})
	while #purchases.History > GameConfig.MaxPurchaseHistory do
		table.remove(purchases.History, 1)
	end
	return "granted"
end

local function handleReceipt(receipt: any): Enum.ProductPurchaseDecision
	local player = Players:GetPlayerByUserId(receipt.PlayerId)
	if not player then
		return Enum.ProductPurchaseDecision.NotProcessedYet -- granted next time they join
	end
	local data = DataService.WaitForData(player, 15)
	if not data then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local product = products[receipt.ProductId]
	if not product then
		warn("[PurchaseService] No handler for product", receipt.ProductId)
	end

	local id = receipt.PurchaseId
	local result = PurchaseService.applyReceipt(player, data, receipt, product)
	if result == "failed" then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	if result == "already" and not unsaved[id] then
		return Enum.ProductPurchaseDecision.PurchaseGranted -- already in a successful save
	end

	-- Newly granted, or granted earlier but never confirmed saved: save first.
	unsaved[id] = true
	if DataService.SaveNow(player) then
		unsaved[id] = nil
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end
	return Enum.ProductPurchaseDecision.NotProcessedYet
end

local function processReceipt(receipt: any): Enum.ProductPurchaseDecision
	local id = receipt.PurchaseId
	if inFlight[id] then
		return Enum.ProductPurchaseDecision.NotProcessedYet -- Roblox will retry
	end
	inFlight[id] = true
	local ok, decision = pcall(handleReceipt, receipt)
	inFlight[id] = nil
	if ok then
		return decision
	end
	warn("[PurchaseService] ProcessReceipt error:", decision)
	return Enum.ProductPurchaseDecision.NotProcessedYet
end

function PurchaseService.init()
	MarketplaceService.ProcessReceipt = processReceipt

	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, wasPurchased)
		if not wasPurchased or player.Parent ~= Players then
			return
		end
		local name = passNameForId(passId)
		if not name then
			return
		end
		passOwnership[player] = passOwnership[player] or {}
		passOwnership[player][name] = true
		passPurchased:Fire(player, name)
	end)

	Players.PlayerAdded:Connect(prefetchPasses)
	for _, player in Players:GetPlayers() do
		prefetchPasses(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		passOwnership[player] = nil
		passFailedAt[player] = nil
	end)
end

return PurchaseService
