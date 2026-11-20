-- ServerStorage/Modules/SanctuaryService
-- Player actions for the sanctuary (hatch, assign, buy slots, upgrade, release),
-- the per-second income loop, and offline income. Rules live in
-- SanctuaryLogic; this module adds coins, cooldowns and change events.
--
-- Every action returns { ok = true, ... } or { ok = false, error = "code" }.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Shared

local Rarities = require(Shared.Rarities)
local SanctuaryConfig = require(Shared.SanctuaryConfig)
local DataService = require(script.Parent.DataService)
local EconomyService = require(script.Parent.EconomyService)
local DragonService = require(script.Parent.DragonService)
local SanctuaryLogic = require(script.Parent.SanctuaryLogic)
local EggRollLog = require(script.Parent.EggRollLog)
local PurchaseService = require(script.Parent.PurchaseService)

local FAST_HATCH_SPEEDUP = 4 -- Fast Hatch pass

local SanctuaryService = {}

local changed = Instance.new("BindableEvent")
-- Fires (player, reason) after anything in the player's sanctuary changes.
SanctuaryService.Changed = changed.Event
local notice = Instance.new("BindableEvent")
-- Fires (player, kind, payload) for one-off messages to show the player.
SanctuaryService.Notice = notice.Event

local rng = Random.new()
local lastHatch: { [Player]: number } = {}
local incomeCarry: { [Player]: number } = {}

local MAX_RELEASE_PER_CALL = 100

local function fail(code: string)
	return { ok = false, error = code }
end

local function getData(player: Player): any
	return DataService.GetData(player)
end

-- Coins per second right now, including the 2x Coins pass.
function SanctuaryService.GetIncomeRate(player: Player): number
	local data = getData(player)
	if not data then
		return 0
	end
	return SanctuaryConfig.TotalIncome(data) * EconomyService.GetIncomeMultiplier(player)
end

-- Actions ------------------------------------------------------------------------

function SanctuaryService.ChooseStarter(player: Player, speciesId: string)
	local data = getData(player)
	if not data then
		return fail("not_loaded")
	end
	local ok, result = SanctuaryLogic.ChooseStarter(data, speciesId)
	if not ok then
		return fail(result :: string)
	end
	changed:Fire(player, "starter")
	return { ok = true, dragonId = result }
end

function SanctuaryService.HatchMulti(player: Player, eggId: string, count: number)
	local data = getData(player)
	if not data then
		return fail("not_loaded")
	end
	local now = os.clock()
	local cooldown = SanctuaryConfig.HatchCooldown
	if PurchaseService.OwnsPassCached(player, "FastHatch") then
		cooldown /= FAST_HATCH_SPEEDUP
	end
	if lastHatch[player] and now - lastHatch[player] < cooldown - 0.05 then
		return fail("too_fast")
	end
	local ok, totalCost = SanctuaryLogic.CanHatchMulti(data, eggId, count)
	if not ok then
		return fail(totalCost)
	end
	if not EconomyService.TrySpendCoins(player, totalCost, "Egg_" .. eggId .. "x" .. tostring(count)) then
		return fail("not_enough_coins")
	end
	lastHatch[player] = now
	local lucky = (data.Boosts.LuckUntil or 0) > os.time()
	local results = table.create(count)
	for i = 1, count do
		local r = SanctuaryLogic.ApplyHatch(data, eggId, rng, lucky)
		EggRollLog.Record(player, eggId, r, "Coins")
		results[i] = r
	end
	changed:Fire(player, "hatch")
	return { ok = true, results = results, result = results[1] }
end

function SanctuaryService.Hatch(player: Player, eggId: string)
	local res = SanctuaryService.HatchMulti(player, eggId, 1)
	if not res.ok then
		return res
	end
	return { ok = true, result = res.result }
end

function SanctuaryService.Assign(player: Player, dragonId: string, station: string?)
	local data = getData(player)
	if not data then
		return fail("not_loaded")
	end
	local ok, err = SanctuaryLogic.Assign(data, dragonId, station)
	if not ok then
		return fail(err :: string)
	end
	changed:Fire(player, "assign")
	return { ok = true }
end

function SanctuaryService.BuySlot(player: Player, station: string)
	local data = getData(player)
	if not data then
		return fail("not_loaded")
	end
	if data.Tutorial.Starter == "" then
		return fail("choose_starter_first")
	end
	local ok, cost = SanctuaryLogic.CanBuySlot(data, station)
	if not ok then
		return fail(cost)
	end
	if cost > 0 and not EconomyService.TrySpendCoins(player, cost, "Slot") then
		return fail("not_enough_coins")
	end
	SanctuaryLogic.ApplyBuySlot(data, station)
	changed:Fire(player, "slot")
	return { ok = true }
end

function SanctuaryService.Upgrade(player: Player, station: string)
	local data = getData(player)
	if not data then
		return fail("not_loaded")
	end
	local ok, cost = SanctuaryLogic.CanUpgrade(data, station)
	if not ok then
		return fail(cost)
	end
	if not EconomyService.TrySpendCoins(player, cost, "Upgrade_" .. station) then
		return fail("not_enough_coins")
	end
	SanctuaryLogic.ApplyUpgrade(data, station)
	changed:Fire(player, "upgrade")
	return { ok = true }
end

-- Releases up to MAX_RELEASE_PER_CALL idle dragons for Essence.
function SanctuaryService.Release(player: Player, dragonIds: { string })
	local data = getData(player)
	if not data then
		return fail("not_loaded")
	end
	if #dragonIds > MAX_RELEASE_PER_CALL then
		return fail("too_many")
	end
	local total, released = 0, 0
	for _, id in dragonIds do
		local essence = DragonService.Release(data, id)
		if essence then
			total += essence
			released += 1
		end
	end
	if released > 0 then
		changed:Fire(player, "release")
	end
	return { ok = true, released = released, essence = total }
end

function SanctuaryService.SetAutoRelease(player: Player, rarity: string, enabled: boolean)
	local data = getData(player)
	if not data then
		return fail("not_loaded")
	end
	if not Rarities.IsValid(rarity) then
		return fail("invalid")
	end
	data.Settings.AutoRelease[rarity] = if enabled then true else nil
	changed:Fire(player, "settings")
	return { ok = true }
end

function SanctuaryService.SetQuickHatch(player: Player, enabled: boolean)
	local data = getData(player)
	if not data then
		return fail("not_loaded")
	end
	data.Settings.QuickHatch = enabled == true
	changed:Fire(player, "settings")
	return { ok = true }
end

-- Income ---------------------------------------------------------------------------

local function incomeTick()
	for _, player in Players:GetPlayers() do
		local data = getData(player)
		if data then
			local rate = SanctuaryService.GetIncomeRate(player)
			data.Stats.LastIncomeRate = rate
			-- "Last seen": autosaves carry it, so a crash or a failed final save
			-- can't make offline income count time the player was online.
			data.Stats.LastLogout = os.time()
			if player:GetAttribute("Income") ~= rate then
				player:SetAttribute("Income", rate)
			end
			local carry = (incomeCarry[player] or 0) + rate
			local whole = math.floor(carry)
			if whole >= 1 then
				EconomyService.AddIncome(player, whole)
				carry -= whole
			end
			incomeCarry[player] = carry
		end
	end
end

local function onProfileLoaded(player: Player, data: any)
	local coins, seconds = SanctuaryLogic.OfflineEarnings(data, os.time())
	if coins >= 1 then
		EconomyService.AddCoins(player, coins, "OfflineIncome")
		notice:Fire(player, "WelcomeBack", { Coins = coins, Seconds = seconds })
	end
	player:SetAttribute("Income", SanctuaryService.GetIncomeRate(player))
end

function SanctuaryService.init()
	DataService.ProfileLoaded:Connect(onProfileLoaded)
	DataService.ProfileReleasing:Connect(function(player: Player)
		-- BindableEvents copy tables, so write to the live save.
		local data = getData(player)
		if data then
			data.Stats.LastIncomeRate = SanctuaryService.GetIncomeRate(player)
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		lastHatch[player] = nil
		incomeCarry[player] = nil
	end)
	task.spawn(function()
		while true do
			task.wait(1)
			local ok, err = pcall(incomeTick)
			if not ok then
				warn("[SanctuaryService] Income tick failed:", err)
			end
		end
	end)
end

return SanctuaryService
