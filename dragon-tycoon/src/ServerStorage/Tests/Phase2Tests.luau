-- ServerStorage/Tests/Phase2Tests
-- Tests for the Phase 2 rules (no players or DataStores needed).
-- Run from the command bar:  print(require(game.ServerStorage.Tests.Phase2Tests).run())

local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Phase2Tests = {}

function Phase2Tests.run(modules: Instance?, shared: Instance?): string
	local M = modules or ServerStorage.Modules
	local S = shared or ReplicatedStorage.Shared
	local DataService = require(M.DataService)
	local Logic = require(M.SanctuaryLogic)
	local Dragons = require(M.DragonService)
	local EggCatalog = require(S.EggCatalog)
	local Config = require(S.SanctuaryConfig)

	local passed, failed = 0, 0
	local lines = {}
	local function check(name: string, condition: any, detail: any?)
		if condition then
			passed += 1
		else
			failed += 1
			table.insert(lines, "FAIL: " .. name .. (if detail ~= nil then " (" .. tostring(detail) .. ")" else ""))
		end
	end
	local function fresh()
		return DataService.defaultData()
	end
	local function count(t)
		local n = 0
		for _ in t do
			n += 1
		end
		return n
	end

	-- Catalog -------------------------------------------------------------------
	local problems = EggCatalog.Validate()
	check("egg tables consistent", #problems == 0, table.concat(problems, "; "))
	for _, egg in EggCatalog.List do
		local total = 0
		for _, o in EggCatalog.GetOutcomeTable(egg.Id) do
			total += o.Chance
		end
		check(egg.Id .. " outcomes sum to 100%", math.abs(total - 1) < 1e-9, total)
	end
	check("no Light/Shadow before Celestial", (function()
		for _, id in { "Hatchling", "Grove", "Ember" } do
			for _, d in EggCatalog.GetDragonOdds(id) do
				if d.Element == "Light" or d.Element == "Shadow" then
					return false
				end
			end
		end
		return true
	end)())
	local celestialLight = 0
	for _, d in EggCatalog.GetDragonOdds("Celestial") do
		if d.Element == "Light" then
			celestialLight += d.Chance
		end
	end
	check("Celestial Light = 5%", math.abs(celestialLight - 0.05) < 1e-9, celestialLight)

	-- Rolls match the table (small sample, generous tolerance)
	do
		local rng = Random.new(7)
		local N = 20000
		local counts = {}
		for _ = 1, N do
			local rarity = EggCatalog.Roll("Hatchling", rng)
			counts[rarity] = (counts[rarity] or 0) + 1
		end
		local common = (counts.Common or 0) / N
		check("Hatchling Common ~60% over 20k rolls", math.abs(common - 0.6) < 0.015, common)
		check("Hatchling Uncommon ~25%", math.abs((counts.Uncommon or 0) / N - 0.25) < 0.015)
		check("Hatchling never rolls unknown rarity", count(counts) <= 6)
	end

	-- Starter ------------------------------------------------------------------
	do
		local data = fresh()
		check("can't hatch before starter", select(2, Logic.CanHatch(data, "Hatchling")) == "choose_starter_first")
		check("invalid starter refused", select(2, Logic.ChooseStarter(data, "Solhallow")) == "invalid")
		local ok, id = Logic.ChooseStarter(data, "Cindermaw")
		check("starter chosen", ok and data.Dragons[id] ~= nil)
		check("starter is Common", data.Dragons[id].Rarity == "Common")
		check("starter works at the Forge", data.Dragons[id].Station == "Forge")
		check("first slot free at Forge", data.Sanctuary.Stations.Forge.Slots == 1 and data.Sanctuary.SlotsBought == 1)
		check("starter only once", select(2, Logic.ChooseStarter(data, "Briarhorn")) == "already_chosen")
		check("starter income 1.25/s", math.abs(Config.TotalIncome(data) - 1.25) < 1e-9, Config.TotalIncome(data))
	end

	-- Hatching ----------------------------------------------------------------------
	do
		local data = fresh()
		Logic.ChooseStarter(data, "Quarrytusk")
		check("not enough coins", select(2, Logic.CanHatch(data, "Hatchling")) == "not_enough_coins")
		check("unknown egg", select(2, Logic.CanHatch(data, "Golden")) == "invalid")
		data.Coins = 100
		local ok, cost = Logic.CanHatch(data, "Hatchling")
		check("can hatch with 100", ok and cost == 100)
		local result = Logic.ApplyHatch(data, "Hatchling", Random.new(1))
		check("hatch creates a dragon", result.Id and data.Dragons[result.Id] ~= nil)
		check("hatched dragon has egg power 1", data.Dragons[result.Id].Power == 1)
		check("tutorial bonus given", result.Bonus and result.Bonus.Species == "Frostveil" and result.Bonus.Rarity == "Uncommon")
		check("bonus stored", data.Dragons[result.Bonus.Id] and data.Dragons[result.Bonus.Id].Egg == "TutorialBonus")
		local second = Logic.ApplyHatch(data, "Hatchling", Random.new(2))
		check("bonus only once", second.Bonus == nil)
		check("hatch count", data.Stats.Hatches == 2)

		local grove = Logic.ApplyHatch(data, "Grove", Random.new(3))
		check("Grove dragons have egg power 5", data.Dragons[grove.Id].Power == 5)

		data.Settings.AutoRelease = { Common = true, Uncommon = true, Rare = true, Epic = true, Legendary = true, Mythic = true }
		local before = count(data.Dragons)
		local released = Logic.ApplyHatch(data, "Hatchling", Random.new(4))
		check("auto-release keeps no dragon", released.Released and count(data.Dragons) == before)
		check("auto-release gives essence", released.Essence > 0 and data.Essence == released.Essence)
	end

	-- Shown odds are exact (or marked approximate) -----------------------------------
	check("12.5% shown exactly", EggCatalog.FormatChance(0.125) == "12.5%", EggCatalog.FormatChance(0.125))
	check("0.0125% shown exactly", EggCatalog.FormatChance(0.001 * 0.125) == "0.0125%", EggCatalog.FormatChance(0.001 * 0.125))
	check("0.1% shown exactly", EggCatalog.FormatChance(0.001) == "0.1%", EggCatalog.FormatChance(0.001))
	check("1/12 marked approximate", EggCatalog.FormatChance(1 / 12):sub(1, 3) == "≈", EggCatalog.FormatChance(1 / 12))

	-- Nest cap counts the tutorial bonus; auto-release frees the nest check --------------
	do
		local data = fresh()
		Logic.ChooseStarter(data, "Cindermaw")
		for _ = 1, Config.NestCapacity - 1 do
			Dragons.Create(data, "Tidewhelp", "Common", 1, "Hatchling")
		end
		data.Coins = 1_000_000
		check("19/20 nest + pending bonus blocks first Hatchling", select(2, Logic.CanHatch(data, "Hatchling")) == "nest_full")
		check("19/20 nest allows a Grove egg (no bonus)", Logic.CanHatch(data, "Grove") == true)
		Dragons.Create(data, "Tidewhelp", "Common", 1, "Hatchling")
		data.Tutorial.BonusGiven = true
		check("full nest blocks Grove", select(2, Logic.CanHatch(data, "Grove")) == "nest_full")
		for _, r in { "Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic" } do
			data.Settings.AutoRelease[r] = true
		end
		check("full nest + auto-release everything still hatches", Logic.CanHatch(data, "Grove") == true)
	end

	-- Nest cap ------------------------------------------------------------------------
	do
		local data = fresh()
		Logic.ChooseStarter(data, "Briarhorn")
		for _ = 1, Config.NestCapacity do
			Dragons.Create(data, "Tidewhelp", "Common", 1, "Hatchling")
		end
		data.Coins = 1000
		check("full nest blocks hatching", select(2, Logic.CanHatch(data, "Hatchling")) == "nest_full")
		local working
		for id, d in data.Dragons do
			if d.Station then
				working = id
			end
		end
		check("can't rest into a full nest", select(2, Logic.Assign(data, working, nil)) == "nest_full")
	end

	-- Slots and assigning ---------------------------------------------------------------
	do
		local data = fresh()
		Logic.ChooseStarter(data, "Cindermaw")
		local idle = Dragons.Create(data, "Rimeclaw", "Rare", 1, "Hatchling")
		check("no free slot at Forge", select(2, Logic.Assign(data, idle, "Forge")) == "no_free_slot")
		check("closed station has no slot", select(2, Logic.Assign(data, idle, "Mine")) == "no_free_slot")
		check("bad station refused", select(2, Logic.Assign(data, idle, "Moon")) == "invalid")
		check("bad dragon refused", select(2, Logic.Assign(data, "D999", "Forge")) == "not_found")
		check("non-string dragon refused", select(2, Logic.Assign(data, 5, "Forge")) == "invalid")

		check("slot needs coins", select(2, Logic.CanBuySlot(data, "Mine")) == "not_enough_coins")
		data.Coins = 150
		local ok, cost = Logic.CanBuySlot(data, "Mine")
		check("2nd slot costs 150", ok and cost == 150, cost)
		Logic.ApplyBuySlot(data, "Mine")
		check("slot added", data.Sanctuary.Stations.Mine.Slots == 1 and data.Sanctuary.SlotsBought == 2)
		check("next slot costs 600", Config.NextSlotCost(data.Sanctuary.SlotsBought) == 600)
		check("assign to Mine", Logic.Assign(data, idle, "Mine") == true)
		check("Ice at Mine gets the bonus", math.abs(Config.DragonIncome(data.Dragons[idle], "Mine", 0) - 6.25) < 1e-9)
		check("rest works", Logic.Assign(data, idle, nil) == true and data.Dragons[idle].Station == nil)
		check("release refuses working dragon", select(2, Dragons.Release(data, (next(Logic.DragonsAt(data, "Forge")) and Logic.DragonsAt(data, "Forge")[1]))) == "working")
		local essence = Dragons.Release(data, idle)
		check("release Rare gives 10 essence", essence == 10 and data.Essence == 10)
		check("released dragon gone", data.Dragons[idle] == nil)
		check("double release refused", select(2, Dragons.Release(data, idle)) == "not_found")

		data.Sanctuary.Stations.Mine.Slots = 3
		data.Coins = 1e9
		check("4th slot at a station refused", select(2, Logic.CanBuySlot(data, "Mine")) == "station_full")
		data.Sanctuary.SlotsBought = 12
		check("13th slot refused", select(2, Logic.CanBuySlot(data, "Farm")) == "all_slots_bought")
	end

	-- Upgrades --------------------------------------------------------------------------
	do
		local data = fresh()
		Logic.ChooseStarter(data, "Cindermaw")
		check("can't upgrade closed station", select(2, Logic.CanUpgrade(data, "Mine")) == "station_closed")
		data.Coins = 249
		check("upgrade needs 250", select(2, Logic.CanUpgrade(data, "Forge")) == "not_enough_coins")
		data.Coins = 250
		local ok, cost = Logic.CanUpgrade(data, "Forge")
		check("first upgrade costs 250", ok and cost == 250)
		Logic.ApplyUpgrade(data, "Forge")
		check("level 1 gives +10%", math.abs(Config.TotalIncome(data) - 1.375) < 1e-9, Config.TotalIncome(data))
		data.Sanctuary.Stations.Forge.Level = Config.StationMaxLevel
		check("max level refused", select(2, Logic.CanUpgrade(data, "Forge")) == "max_level")
	end

	-- Offline income ----------------------------------------------------------------------
	do
		local data = fresh()
		local now = 1_000_000
		check("first join earns nothing offline", Logic.OfflineEarnings(data, now) == 0)
		data.Stats.LastLogout = now - 3600
		data.Stats.LastIncomeRate = 10
		local coins, seconds = Logic.OfflineEarnings(data, now)
		check("1h offline at 10/s = 5400 (15%)", coins == 5400 and seconds == 3600, coins)
		data.Stats.LastLogout = now - 100_000
		coins, seconds = Logic.OfflineEarnings(data, now)
		check("offline capped at 8h", seconds == 8 * 3600 and coins == math.floor(10 * 0.15 * 8 * 3600), coins)
		data.Stats.LastLogout = now - 30
		check("quick rejoin earns nothing", Logic.OfflineEarnings(data, now) == 0)
	end

	-- 4-Egg Multi-Hatch & Discovery ("NEW!") tracking -----------------------------------
	do
		local data = fresh()
		Logic.ChooseStarter(data, "Cindermaw")
		check("starter marked discovered", data.Discovered.Cindermaw == true)
		check("invalid multi count 0 refused", select(2, Logic.CanHatchMulti(data, "Hatchling", 0)) == "invalid")
		check("invalid multi count 5 refused", select(2, Logic.CanHatchMulti(data, "Hatchling", 5)) == "invalid")
		data.Coins = 399
		check("4x Hatchling needs 400 coins", select(2, Logic.CanHatchMulti(data, "Hatchling", 4)) == "not_enough_coins")
		data.Coins = 400
		local ok, totalCost = Logic.CanHatchMulti(data, "Hatchling", 4)
		check("4x Hatchling costs 400", ok and totalCost == 400, totalCost)
		local rng = Random.new(42)
		local seen = { Cindermaw = true }
		for i = 1, 4 do
			local r = Logic.ApplyHatch(data, "Hatchling", rng)
			local expectedNew = not seen[r.Species]
			seen[r.Species] = true
			check("multi roll " .. i .. " IsNew accurate", r.IsNew == expectedNew)
		end
		check("4x multi hatch count = 4", data.Stats.Hatches == 4)
	end

	table.insert(lines, 1, string.format("Phase 2 tests: %d passed, %d failed", passed, failed))
	return table.concat(lines, "\n")
end

return Phase2Tests
