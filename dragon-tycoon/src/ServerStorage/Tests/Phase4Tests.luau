-- ServerStorage/Tests/Phase4Tests
-- Monetization, policy and tutorial tests (no real purchases).
-- Run: print(require(game.ServerStorage.Tests.Phase4Tests).run())

local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Shared
local Modules = ServerStorage.Modules

local EggCatalog = require(Shared.EggCatalog)
local ProductCatalog = require(Shared.ProductCatalog)
local CosmeticCatalog = require(Shared.CosmeticCatalog)
local GameConfig = require(Shared.GameConfig)
local SanctuaryConfig = require(Shared.SanctuaryConfig)
local TutorialConfig = require(Shared.TutorialConfig)
local SoundConfig = require(Shared.SoundConfig)
local Rarities = require(Shared.Rarities)
local DataService = require(Modules.DataService)
local SanctuaryLogic = require(Modules.SanctuaryLogic)
local PurchaseService = require(Modules.PurchaseService)
local ShopService = require(Modules.ShopService)

local Phase4Tests = {}

local MENU = { Eggs = true, Dragons = true, Stations = true, Ride = true, Battle = true, Shop = true }

local function rarityChances(eggId: string, lucky: boolean?)
	local map = {}
	for _, r in EggCatalog.GetRarityOdds(eggId, lucky) do
		map[r.Rarity] = r.Chance
	end
	return map
end

function Phase4Tests.run(): string
	local passed, failed = 0, 0
	local lines = {}
	local function check(name: string, ok: boolean, detail: any?)
		if ok then
			passed += 1
		else
			failed += 1
			table.insert(lines, "FAIL " .. name .. (if detail ~= nil then ": " .. tostring(detail) else ""))
		end
	end

	-- Odds table ---------------------------------------------------------------
	local problems = EggCatalog.Validate()
	check("egg catalog valid (incl. luck + Robux eggs)", #problems == 0, table.concat(problems, "; "))
	check("coin egg list unchanged", #EggCatalog.List == 5, #EggCatalog.List)
	check("2 Robux eggs", #EggCatalog.RobuxEggs == 2)
	for _, egg in EggCatalog.List do
		local normal, lucky = rarityChances(egg.Id), rarityChances(egg.Id, true)
		local sum = 0
		for _, c in lucky do
			sum += c
		end
		check("luck odds sum to 1 " .. egg.Id, math.abs(sum - 1) < 1e-9, sum)
		for rarity in EggCatalog.LuckRarities do
			check("luck doubles " .. rarity .. " " .. egg.Id, math.abs((lucky[rarity] or 0) - 2 * (normal[rarity] or 0)) < 1e-9)
		end
		check("luck lowers Common " .. egg.Id, (lucky.Common or 0) < (normal.Common or 0))
	end
	for _, egg in EggCatalog.RobuxEggs do
		local normal, lucky = rarityChances(egg.Id), rarityChances(egg.Id, true)
		check("luck ignores Robux egg " .. egg.Id, normal.Epic == lucky.Epic)
		check("Robux egg never Common " .. egg.Id, (normal.Common or 0) == 0)
		check("Robux egg has a product " .. egg.Id, ProductCatalog.Products[egg.Id] ~= nil and ProductCatalog.Products[egg.Id].Random == true)
	end
	local rng = Random.new(7)
	local commons = 0
	for _ = 1, 400 do
		local rarity = EggCatalog.Roll("MythicEgg", rng)
		if Rarities.Info[rarity].Rank < 4 then
			commons += 1
		end
	end
	check("Mythic Egg rolls Epic or better", commons == 0, commons)

	-- Policy -------------------------------------------------------------------
	for key, product in ProductCatalog.Products do
		check("restricted rule " .. key, ProductCatalog.IsAllowed(key, true) == not product.Random)
		check("allowed rule " .. key, ProductCatalog.IsAllowed(key, false) == true)
		check("product id slot " .. key, GameConfig.DevProducts[key] ~= nil)
		check("grant exists " .. key, ShopService._grants[key] ~= nil)
	end
	for key in GameConfig.DevProducts do
		check("config key has product " .. key, ProductCatalog.Products[key] ~= nil)
	end
	check("fixed dragon capped at Epic", Rarities.Info[ProductCatalog.Products.FixedDragon.Rarity].Rank <= Rarities.Info.Epic.Rank)
	check("no coin packs", ProductCatalog.Products.CoinPack == nil)
	for _, pass in ProductCatalog.Passes do
		check("pass id slot " .. pass.Key, GameConfig.GamePasses[pass.Key] ~= nil)
	end
	check("unknown product refused", ProductCatalog.IsAllowed("Nope", false) == false)

	-- Hatching rules -------------------------------------------------------------
	local data = DataService.defaultData()
	data.Tutorial.Starter = "Cindermaw"
	data.Coins = 1e12
	local ok, err = SanctuaryLogic.CanHatch(data, "RoyalEgg")
	check("Robux egg can't be bought with coins", ok == false and err == "invalid", err)
	check("nest base size", SanctuaryConfig.NestCapacityFor(data) == SanctuaryConfig.NestCapacity)
	data.Sanctuary.ExtraNest = 10
	check("nest pass adds 10", SanctuaryConfig.NestCapacityFor(data) == SanctuaryConfig.NestCapacity + 10)
	local luckyResult = SanctuaryLogic.ApplyHatch(data, "Hatchling", Random.new(1), true)
	check("hatch records luck", luckyResult.Lucky == true)

	-- Grants (fake player, fake receipts) ---------------------------------------
	local fakePlayer: any = { UserId = -1, Name = "Test", Parent = nil }
	local d = DataService.defaultData()
	d.Tutorial.Starter = "Briarhorn"
	d.Dragons.D1 = { Species = "Briarhorn", Rarity = "Common", Level = 1, XP = 0, Power = 25 }
	d.NextDragonId = 2
	local okEgg = ShopService._grants.RoyalEgg(fakePlayer, d, {})
	local newest = d.Dragons.D2
	check("Royal Egg grants a dragon", okEgg == true and newest ~= nil)
	check("Royal Egg never Common", newest ~= nil and newest.Rarity ~= "Common")
	check("Royal Egg matches best egg power", newest ~= nil and newest.Power == 25, newest and newest.Power)
	local before = os.time()
	ShopService._grants.LuckBoost(fakePlayer, d, {})
	local firstUntil = d.Boosts.LuckUntil
	ShopService._grants.LuckBoost(fakePlayer, d, {})
	check("Luck Boost 15 min", firstUntil >= before + 15 * 60 and firstUntil <= os.time() + 15 * 60)
	check("Luck Boost stacks", d.Boosts.LuckUntil == firstUntil + 15 * 60)
	d.Purchases.Pending.FixedDragon = "Duskrend"
	ShopService._grants.FixedDragon(fakePlayer, d, {})
	local fixed = d.Dragons.D3
	check("fixed dragon is exactly the pick", fixed ~= nil and fixed.Species == "Duskrend" and fixed.Rarity == "Epic", fixed and fixed.Species)
	check("fixed dragon clears the pick", d.Purchases.Pending.FixedDragon == "")
	d.Purchases.Pending.Cosmetic = "FrostTrail"
	ShopService._grants.Cosmetic(fakePlayer, d, {})
	check("cosmetic owned", d.Cosmetics.Owned.FrostTrail == true)
	check("cosmetic worn", d.Cosmetics.Trail == "FrostTrail")
	d.Purchases.Pending.Cosmetic = "FrostTrail" -- already owned: they still get a style
	ShopService._grants.Cosmetic(fakePlayer, d, {})
	local ownedCount = 0
	for _ in d.Cosmetics.Owned do
		ownedCount += 1
	end
	check("duplicate cosmetic gives another style", ownedCount == 2, ownedCount)

	-- Receipts are granted once
	local receipt = { PurchaseId = "test-receipt-1", ProductId = 0, PlayerId = -1, CurrencySpent = 49 }
	local product = { Name = "RoyalEgg", Grant = ShopService._grants.RoyalEgg }
	local dragonsBefore = d.NextDragonId
	local first = PurchaseService.applyReceipt(fakePlayer, d, receipt, product)
	local second = PurchaseService.applyReceipt(fakePlayer, d, receipt, product)
	check("receipt granted", first == "granted", first)
	check("same receipt not granted twice", second == "already" and d.NextDragonId == dragonsBefore + 1, second)

	-- Cosmetics, tutorial, sound data -------------------------------------------
	for _, c in CosmeticCatalog.List do
		check("cosmetic kind " .. c.Id, c.Kind == "Trail" or c.Kind == "Aura")
		check("cosmetic colors " .. c.Id, #c.Colors == 2)
	end
	check("tutorial has steps", #TutorialConfig.Steps >= 5)
	for i, step in TutorialConfig.Steps do
		check("tutorial text " .. i, type(step.Title) == "string" and type(step.Text) == "string")
		if step.Highlight then
			check("tutorial highlight is a menu button " .. step.Highlight, MENU[step.Highlight] == true)
		end
	end
	check("tutorial done marker", TutorialConfig.Get(TutorialConfig.Done) == nil)
	for name, spec in SoundConfig.Effects do
		check("sound id " .. name, type(spec.Id) == "string" and spec.Id:sub(1, 8) == "rbxasset")
	end
	for mood, list in SoundConfig.Music do
		check("music " .. mood, #list > 0)
	end

	table.insert(lines, 1, string.format("Phase 4 tests: %d passed, %d failed", passed, failed))
	return table.concat(lines, "\n")
end

return Phase4Tests
