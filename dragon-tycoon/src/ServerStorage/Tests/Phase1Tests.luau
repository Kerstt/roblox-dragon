-- ServerStorage/Tests/Phase1Tests
-- Tests for Phase 1 that run without real players or real DataStores.
-- Simulates 3 players and 2 servers sharing one in-memory store.
-- Run from the command bar:  print(require(game.ServerStorage.Tests.Phase1Tests).run())

local ServerStorage = game:GetService("ServerStorage")
local Modules = ServerStorage.Modules

local DataService = require(Modules.DataService)
local MockDataStore = require(Modules.MockDataStore)
local PurchaseService = require(Modules.PurchaseService)
local EconomyService = require(Modules.EconomyService)
local PlayerPolicyService = require(Modules.PlayerPolicyService)

local Phase1Tests = {}

local FAST = {
	lockRetries = 2,
	lockRetryDelay = 0,
	requestRetries = 3,
	backoffBase = 0,
	minSaveGap = 0,
}

local function options(sessionId: string, extra: { [string]: any }?)
	local o = table.clone(FAST)
	o.sessionId = sessionId
	for k, v in extra or {} do
		o[k] = v
	end
	return o
end

function Phase1Tests.run(): string
	local passed, failed = 0, 0
	local lines = {}
	local function check(name: string, condition: boolean, detail: any?)
		if condition then
			passed += 1
		else
			failed += 1
			table.insert(lines, "FAIL: " .. name .. (if detail ~= nil then " (" .. tostring(detail) .. ")" else ""))
		end
	end

	local PLAYERS = { 1001, 1002, 1003 }

	-- 1. Three new players load defaults, play, and save. -----------------------
	do
		local store = MockDataStore.new()
		local serverA = DataService.newManager(store, options("A"))
		for i, userId in PLAYERS do
			local profile = serverA:Load(userId)
			check("new player " .. userId .. " loads", profile ~= nil)
			check("new player starts with 0 coins", profile and profile.Data.Coins == 0)
			check("new save has a Sanctuary", profile and profile.Data.Sanctuary ~= nil)
			profile.Data.Coins = i * 100
			profile.Data.Dragons["d1"] = { Species = "Emberwing", Rarity = "Rare", Element = "Fire", Level = i, XP = 0 }
		end
		for _, userId in PLAYERS do
			local ok, reason = serverA:Save(userId, true)
			check("player " .. userId .. " final save", ok, reason)
			check("released profile is forgotten", serverA:Get(userId) == nil)
		end

		-- 2. They rejoin on another server and get exactly what they saved. ------
		local serverB = DataService.newManager(store, options("B"))
		for i, userId in PLAYERS do
			local callsBefore = store.calls
			local profile = serverB:Load(userId)
			check("rejoin loads on first try", store.calls - callsBefore == 1, store.calls - callsBefore)
			check("coins kept for " .. userId, profile and profile.Data.Coins == i * 100, profile and profile.Data.Coins)
			check("dragon kept for " .. userId, profile and profile.Data.Dragons.d1 and profile.Data.Dragons.d1.Level == i)
		end
	end

	-- 3. Session lock: a second server can't load or overwrite an open save. ------
	do
		local store = MockDataStore.new()
		local serverA = DataService.newManager(store, options("A"))
		local serverB = DataService.newManager(store, options("B"))
		local userId = PLAYERS[1]

		local a = serverA:Load(userId)
		a.Data.Coins = 500
		serverA:Save(userId, false)

		local callsBefore = store.calls
		local blocked, blockedReason = serverB:Load(userId)
		check("second server retried while locked", store.calls - callsBefore == FAST.lockRetries + 1, store.calls - callsBefore)
		check("second server never takes a live lock", blocked == nil and blockedReason == "locked", blockedReason)
		check("first server still owns the save", serverA:Get(userId) ~= nil and serverA:Save(userId, false) == true)

		serverA:Save(userId, true)
		local b = serverB:Load(userId)
		check("second server loads after release", b and b.Data.Coins == 500, b and b.Data.Coins)
	end

	-- 3b. A server that lost its lock (it froze past the stale time) can't overwrite. ---
	do
		local store = MockDataStore.new()
		local serverA = DataService.newManager(store, options("A"))
		local later = function()
			return os.time() + 10000
		end
		local serverB = DataService.newManager(store, options("B", { now = later }))
		local userId = PLAYERS[1]
		local a = serverA:Load(userId)
		local b = serverB:Load(userId)
		check("stale lock taken over", b ~= nil)
		b.Data.Coins = 700
		serverB:Save(userId, false)
		a.Data.Coins = 999999
		local ok, reason = serverA:Save(userId, false)
		check("old server's save is refused", ok == false and reason == "lost lock", reason)
		check("old server drops the profile", serverA:Get(userId) == nil)
		check("newer data is not overwritten", store.data["Player_" .. userId].Data.Coins == 700, store.data["Player_" .. userId].Data.Coins)
	end

	-- 4. A released save loads immediately elsewhere. ---------------------------------
	do
		local store = MockDataStore.new()
		local serverA = DataService.newManager(store, options("A"))
		local serverB = DataService.newManager(store, options("B"))
		serverA:Load(PLAYERS[2])
		serverA:Save(PLAYERS[2], true)
		local callsBefore = store.calls
		check("released save loads elsewhere", serverB:Load(PLAYERS[2]) ~= nil)
		check("no waiting after release", store.calls - callsBefore == 1, store.calls - callsBefore)
	end

	-- 5. Abandoned lock (crashed server) is taken over right away. -----------------
	do
		local store = MockDataStore.new()
		store.data.Player_1003 = {
			Version = 1,
			Data = { Coins = 42 },
			Session = { Id = "crashed-server", Time = os.time() - 10000 },
		}
		local serverB = DataService.newManager(store, options("B"))
		local callsBefore = store.calls
		local profile = serverB:Load(1003)
		check("stale lock taken on first try", profile ~= nil and store.calls - callsBefore == 1, store.calls - callsBefore)
		check("stale-lock data kept", profile and profile.Data.Coins == 42)
		check("missing fields filled in", profile and profile.Data.Purchases and profile.Data.Purchases.Receipts ~= nil)
	end

	-- 6. DataStore outages. ----------------------------------------------------------
	do
		local store = MockDataStore.new()
		store.failNext = 2 -- two hiccups, then it works
		local server = DataService.newManager(store, options("A"))
		check("load survives brief outage", server:Load(PLAYERS[1]) ~= nil)

		local down = MockDataStore.new()
		down.data.Player_1002 = { Version = 1, Data = { Coins = 123 } }
		down.failAll = true
		local server2 = DataService.newManager(down, options("A"))
		local profile, reason = server2:Load(PLAYERS[2])
		check("load fails cleanly in a full outage", profile == nil and reason ~= nil)
		down.failAll = false
		check("failed load didn't touch the save", down.data.Player_1002.Data.Coins == 123)

		local server3 = DataService.newManager(store, options("C"))
		local p = server3:Load(PLAYERS[3])
		p.Data.Coins = 77
		store.failAll = true
		local ok = server3:Save(PLAYERS[3], false)
		check("save reports failure in outage", ok == false)
		check("profile stays open after failed autosave", server3:Get(PLAYERS[3]) ~= nil)
		store.failAll = false
		check("save succeeds after outage", server3:Save(PLAYERS[3], false) == true)
		check("saved value correct", store.data.Player_1003.Data.Coins == 77)
	end

	-- 7. Robux receipts are granted exactly once. ---------------------------------------
	do
		local data = DataService.defaultData()
		local fakePlayer = {} :: any
		local product = { Name = "CoinPack", Grant = function(_, d)
			d.Coins += 1000
			return true
		end }
		local receipt = { PurchaseId = "p-1", ProductId = 55, PlayerId = 1001, CurrencySpent = 25 }
		check("first receipt granted", PurchaseService.applyReceipt(fakePlayer, data, receipt, product) == "granted")
		check("retried receipt not granted twice", PurchaseService.applyReceipt(fakePlayer, data, receipt, product) == "already")
		check("coins added once", data.Coins == 1000, data.Coins)
		check("purchase logged", #data.Purchases.History == 1)
		check("unknown product not granted", PurchaseService.applyReceipt(fakePlayer, data, { PurchaseId = "p-2", ProductId = 9 }, nil) == "failed")
		local broken = { Name = "Broken", Grant = function() error("boom") end }
		check("erroring grant not recorded", PurchaseService.applyReceipt(fakePlayer, data, { PurchaseId = "p-3", ProductId = 7 }, broken) == "failed" and data.Purchases.Receipts["p-3"] == nil)
		local halfway = { Name = "Halfway", Grant = function(_, d)
			d.Coins += 5000
			d.NextDragonId += 1
			error("failed after changing data")
		end }
		PurchaseService.applyReceipt(fakePlayer, data, { PurchaseId = "p-4", ProductId = 8 }, halfway)
		check("half-done grant is undone", data.Coins == 1000 and data.NextDragonId == 1, data.Coins)
		local saysNo = { Name = "SaysNo", Grant = function(_, d)
			d.Coins += 1
			return false
		end }
		PurchaseService.applyReceipt(fakePlayer, data, { PurchaseId = "p-5", ProductId = 9 }, saysNo)
		check("grant returning false is undone", data.Coins == 1000, data.Coins)
	end

	-- 10. A save written by newer server code is refused, not overwritten. ----------------
	do
		local store = MockDataStore.new()
		store.data.Player_1001 = { Version = 999, Data = { Coins = 5, FutureField = true } }
		local server = DataService.newManager(store, options("A"))
		local profile, reason = server:Load(1001)
		check("newer save refused", profile == nil and reason == "newer version", reason)
		check("newer save untouched", store.data.Player_1001.Version == 999 and store.data.Player_1001.Session == nil)
	end

	-- 11. Bad data can't jam the save queue. --------------------------------------------
	do
		local store = MockDataStore.new()
		local server = DataService.newManager(store, options("A"))
		local profile = server:Load(1002)
		local cyclic = {}
		cyclic.Self = cyclic
		profile.Data.Loop = cyclic
		local ok = server:Save(1002, false)
		check("cyclic data save fails cleanly", ok == false)
		check("save queue not stuck", profile.Saving == false)
		profile.Data.Loop = nil
		check("next save works", server:Save(1002, false) == true)
	end

	-- 12. Fast rejoin while the final save is still running. --------------------------
	do
		local store = MockDataStore.new()
		local server = DataService.newManager(store, options("A", { minSaveGap = 0.3 }))
		local old = server:Load(1003)
		old.Data.Coins = 321
		old.Releasing = true
		task.spawn(function()
			server:Save(1003, true) -- waits ~0.3s for the write gap
		end)
		local fresh = server:Load(1003) -- player rejoined the same server
		check("rejoin gets a new, live profile", fresh ~= nil and fresh ~= old and fresh.Active, fresh and fresh.Active)
		check("rejoin sees the final save", fresh and fresh.Data.Coins == 321, fresh and fresh.Data.Coins)
		check("rejoined profile is the one in use", server:Get(1003) == fresh)
	end

	-- 8. Coin amounts from anywhere are sanitized. -------------------------------------
	do
		local s = EconomyService.sanitizeAmount
		check("rejects negative", s(-5) == nil)
		check("rejects zero", s(0) == nil)
		check("rejects NaN", s(0 / 0) == nil)
		check("rejects infinity", s(math.huge) == nil)
		check("rejects strings", s("100" :: any) == nil)
		check("floors decimals", s(10.9) == 10)
		check("rejects over the cap", s(1e16) == nil)
	end

	-- 9. Policy flags fail closed. ---------------------------------------------------------
	do
		local f = PlayerPolicyService.fromPolicyInfo
		check("unknown policy is restricted", f(nil, false).ArePaidRandomItemsRestricted == true)
		check("unknown policy has no trading", f(nil, false).IsPaidItemTradingAllowed == false)
		check("missing field is restricted", f({}, true).ArePaidRandomItemsRestricted == true)
		check("explicit false unlocks", f({ ArePaidRandomItemsRestricted = false }, true).ArePaidRandomItemsRestricted == false)
		check("restricted player stays restricted", f({ ArePaidRandomItemsRestricted = true }, true).ArePaidRandomItemsRestricted == true)
		check("trading needs explicit true", f({ IsPaidItemTradingAllowed = "yes" }, true).IsPaidItemTradingAllowed == false)
	end

	table.insert(lines, 1, string.format("Phase 1 tests: %d passed, %d failed", passed, failed))
	return table.concat(lines, "\n")
end

return Phase1Tests
