-- ServerStorage/Modules/ShopService
-- The Robux shop on the server: prompts purchases (after checking the player's
-- policy), grants Developer Products through PurchaseService's receipt handler,
-- and runs the Game Pass perks (Auto Hatch, +10 Nest; 2x Coins and Fast Hatch
-- are checked where they apply).
--
-- Paid random items (Robux eggs, Luck Boost) are refused for players whose
-- policy restricts them, before any prompt. Fixed dragons and cosmetics are for
-- everyone. Choices (which dragon / which style) are saved before the prompt,
-- so the receipt always grants exactly what the player picked.
--
-- In Studio, products whose ID is still 0 are "test bought" through the same
-- receipt code, so the whole flow can be tried without real Robux.
--
-- Every action returns { ok = true, ... } or { ok = false, error = "code" }.

local Players = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Shared

local GameConfig = require(Shared.GameConfig)
local ProductCatalog = require(Shared.ProductCatalog)
local CosmeticCatalog = require(Shared.CosmeticCatalog)
local EggCatalog = require(Shared.EggCatalog)
local DragonCatalog = require(Shared.DragonCatalog)
local DataService = require(script.Parent.DataService)
local PurchaseService = require(script.Parent.PurchaseService)
local PlayerPolicyService = require(script.Parent.PlayerPolicyService)
local DragonService = require(script.Parent.DragonService)
local EggRollLog = require(script.Parent.EggRollLog)
local SanctuaryService = require(script.Parent.SanctuaryService)

local ShopService = {}

local changed = Instance.new("BindableEvent")
-- Fires (player) after a purchase or shop setting changes the save.
ShopService.Changed = changed.Event
local notice = Instance.new("BindableEvent")
-- Fires (player, kind, payload): RobuxHatch, LuckBoost, Cosmetic, AutoHatched, AutoHatchStopped.
ShopService.Notice = notice.Event

local EXTRA_NEST = 10
local rng = Random.new()

local function fail(code: string)
	return { ok = false, error = code }
end

local function later(player: Player, kind: string?, payload: any?)
	-- Grants must not yield or fire events mid-grant; tell everyone afterwards.
	task.defer(function()
		if kind then
			notice:Fire(player, kind, payload)
		end
		changed:Fire(player)
	end)
end

-- Robux-egg and shop dragons match the best egg power the player already has.
local function bestPower(data: any): number
	local best = 1
	for _, dragon in data.Dragons do
		best = math.max(best, dragon.Power or 1)
	end
	return best
end

-- Grants (called by PurchaseService.applyReceipt; must not yield) ----------------

local function eggGrant(eggId: string)
	return function(player: Player, data: any, _receipt: any): boolean
		if not PlayerPolicyService.CanBuyPaidRandomItems(player) then
			warn("[ShopService] Restricted player bought a Robux egg (prompt bypassed?)", player.UserId, eggId)
		end
		local rarity, species = EggCatalog.Roll(eggId, rng)
		data.Discovered = data.Discovered or {}
		local isNew = data.Discovered[species] ~= true
		data.Discovered[species] = true
		local id = DragonService.Create(data, species, rarity, bestPower(data), eggId)
		data.Stats.Hatches += 1
		local result = { Egg = eggId, Id = id, Species = species, Rarity = rarity, Released = false, Essence = 0, IsNew = isNew }
		EggRollLog.Record(player, eggId, result, "Robux")
		later(player, "RobuxHatch", result)
		return true
	end
end

local GRANTS: { [string]: (Player, any, any) -> boolean } = {
	RoyalEgg = eggGrant("RoyalEgg"),
	MythicEgg = eggGrant("MythicEgg"),
	LuckBoost = function(player, data, _receipt)
		local minutes = ProductCatalog.Products.LuckBoost.Minutes
		data.Boosts.LuckUntil = math.max(os.time(), data.Boosts.LuckUntil or 0) + minutes * 60
		later(player, "LuckBoost", { Until = data.Boosts.LuckUntil })
		return true
	end,
	FixedDragon = function(player, data, _receipt)
		local species = data.Purchases.Pending.FixedDragon
		if not DragonCatalog.Get(species) then
			species = if DragonCatalog.Get(data.Tutorial.Starter) then data.Tutorial.Starter else "Cindermaw"
		end
		data.Discovered = data.Discovered or {}
		local isNew = data.Discovered[species] ~= true
		data.Discovered[species] = true
		local rarity = ProductCatalog.Products.FixedDragon.Rarity
		local id = DragonService.Create(data, species, rarity, bestPower(data), "Shop")
		data.Purchases.Pending.FixedDragon = ""
		later(player, "RobuxHatch", { Egg = "Shop", Id = id, Species = species, Rarity = rarity, Released = false, Essence = 0, IsNew = isNew })
		return true
	end,
	Cosmetic = function(player, data, _receipt)
		local owned = data.Cosmetics.Owned
		local id = data.Purchases.Pending.Cosmetic
		if not CosmeticCatalog.Get(id) or owned[id] then
			id = nil
			for _, c in CosmeticCatalog.List do -- they paid: give the first style they don't have
				if not owned[c.Id] then
					id = c.Id
					break
				end
			end
		end
		data.Purchases.Pending.Cosmetic = ""
		if not id then
			warn("[ShopService] Cosmetic bought but every style is owned", player.UserId)
			return true
		end
		owned[id] = true
		local cosmetic = CosmeticCatalog.Get(id) :: any
		data.Cosmetics[cosmetic.Kind] = id -- wear it right away
		later(player, "Cosmetic", { Id = id })
		return true
	end,
}
ShopService._grants = GRANTS -- for tests

-- Actions ----------------------------------------------------------------------------

-- Asks Roblox to show the purchase prompt for a Developer Product.
-- choice: species id (FixedDragon) or cosmetic id (Cosmetic).
function ShopService.Buy(player: Player, key: string, choice: string?)
	local data = DataService.GetData(player)
	if not data then
		return fail("not_loaded")
	end
	local product = ProductCatalog.Products[key]
	local grant = GRANTS[key]
	if not product or not grant then
		return fail("invalid")
	end
	if not ProductCatalog.IsAllowed(key, not PlayerPolicyService.CanBuyPaidRandomItems(player)) then
		return fail("not_available")
	end
	if key == "FixedDragon" then
		if not DragonCatalog.Get(choice) then
			return fail("invalid")
		end
		data.Purchases.Pending.FixedDragon = choice
	elseif key == "Cosmetic" then
		if not CosmeticCatalog.Get(choice) then
			return fail("invalid")
		end
		if data.Cosmetics.Owned[choice :: string] then
			return fail("already_owned")
		end
		data.Purchases.Pending.Cosmetic = choice
	end

	local productId = GameConfig.DevProducts[key]
	if type(productId) == "number" and productId > 0 then
		MarketplaceService:PromptProductPurchase(player, productId)
		return { ok = true, prompted = true }
	end
	if RunService:IsStudio() then
		-- No real product yet: run the real receipt code with a test receipt.
		local receipt = { PurchaseId = "studio-" .. HttpService:GenerateGUID(false), ProductId = 0, PlayerId = player.UserId, CurrencySpent = 0 }
		local decision = PurchaseService.applyReceipt(player, data, receipt, { Name = key, Grant = grant })
		return { ok = decision == "granted", test = true, error = if decision == "granted" then nil else "server_error" }
	end
	return fail("coming_soon")
end

function ShopService.BuyPass(player: Player, key: string)
	if not ProductCatalog.GetPass(key) then
		return fail("invalid")
	end
	if PurchaseService.OwnsPassCached(player, key) then
		return fail("already_owned")
	end
	local passId = GameConfig.GamePasses[key]
	if type(passId) ~= "number" or passId <= 0 then
		return fail("coming_soon")
	end
	MarketplaceService:PromptGamePassPurchase(player, passId)
	return { ok = true, prompted = true }
end

-- Wear (or take off, id = "") a style you own.
function ShopService.Equip(player: Player, kind: string, id: string)
	local data = DataService.GetData(player)
	if not data then
		return fail("not_loaded")
	end
	if kind ~= "Trail" and kind ~= "Aura" then
		return fail("invalid")
	end
	if id ~= "" then
		local cosmetic = CosmeticCatalog.Get(id)
		if not cosmetic or cosmetic.Kind ~= kind or not data.Cosmetics.Owned[id] then
			return fail("invalid")
		end
	end
	data.Cosmetics[kind] = id
	changed:Fire(player)
	return { ok = true }
end

-- Auto Hatch pass: pick the egg to keep hatching ("" to stop).
function ShopService.SetAutoHatch(player: Player, eggId: string)
	local data = DataService.GetData(player)
	if not data then
		return fail("not_loaded")
	end
	if eggId ~= "" then
		local egg = EggCatalog.Get(eggId)
		if not egg or egg.Robux then
			return fail("invalid")
		end
		if not PurchaseService.OwnsPassCached(player, "AutoHatch") then
			return fail("needs_pass")
		end
	end
	data.Settings.AutoHatchEgg = eggId
	changed:Fire(player)
	return { ok = true }
end

-- Seconds left on the Luck Boost (0 = off).
function ShopService.LuckSecondsLeft(data: any): number
	return math.max(0, (data.Boosts.LuckUntil or 0) - os.time())
end

-- Perks --------------------------------------------------------------------------------

local function refreshNest(player: Player)
	local data = DataService.GetData(player)
	if not data then
		return
	end
	local extra = if PurchaseService.OwnsPass(player, "ExtraNests") then EXTRA_NEST else 0
	if data.Sanctuary.ExtraNest ~= extra then
		data.Sanctuary.ExtraNest = extra
		changed:Fire(player)
	end
end

local STOP_REASONS = { not_enough_coins = true, nest_full = true, invalid = true, choose_starter_first = true }

local function autoHatchTick()
	for _, player in Players:GetPlayers() do
		local data = DataService.GetData(player)
		local eggId = data and data.Settings.AutoHatchEgg
		if eggId and eggId ~= "" then
			if not PurchaseService.OwnsPassCached(player, "AutoHatch") then
				data.Settings.AutoHatchEgg = ""
				changed:Fire(player)
			else
				local result = SanctuaryService.Hatch(player, eggId)
				if result.ok then
					notice:Fire(player, "AutoHatched", result.result)
				elseif STOP_REASONS[result.error] then
					data.Settings.AutoHatchEgg = ""
					notice:Fire(player, "AutoHatchStopped", { Reason = result.error })
					changed:Fire(player)
				end
			end
		end
	end
end

function ShopService.init()
	for key, productId in GameConfig.DevProducts do
		if type(productId) == "number" and productId > 0 and GRANTS[key] then
			PurchaseService.RegisterProduct(productId, key, GRANTS[key])
		end
	end
	DataService.ProfileLoaded:Connect(function(player)
		task.spawn(refreshNest, player)
	end)
	PurchaseService.PassPurchased:Connect(function(player, passName)
		if passName == "ExtraNests" then
			task.spawn(refreshNest, player)
		end
		changed:Fire(player)
	end)
	task.spawn(function()
		while true do
			task.wait(0.5)
			local ok, err = pcall(autoHatchTick)
			if not ok then
				warn("[ShopService] auto hatch failed:", err)
			end
		end
	end)
end

return ShopService
