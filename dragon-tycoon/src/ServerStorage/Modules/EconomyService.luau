-- ServerStorage/Modules/EconomyService
-- The only place coins change. Every change is validated, capped, mirrored to
-- the leaderboard, and logged to Roblox's economy analytics.

local AnalyticsService = game:GetService("AnalyticsService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local DataService = require(script.Parent.DataService)
local PurchaseService = require(script.Parent.PurchaseService)

local EconomyService = {}

local CURRENCY = "Coins"

-- Turns any input into a safe whole positive amount, or nil if it isn't one.
function EconomyService.sanitizeAmount(amount: any): number?
	if type(amount) ~= "number" or amount ~= amount then -- not a number, or NaN
		return nil
	end
	if amount <= 0 or amount == math.huge then
		return nil
	end
	local whole = math.floor(amount)
	if whole <= 0 or whole > GameConfig.MaxCoins then
		return nil
	end
	return whole
end

local function updateLeaderstats(player: Player, coins: number)
	local leaderstats = player:FindFirstChild("leaderstats")
	local value = leaderstats and leaderstats:FindFirstChild(CURRENCY)
	if value then
		(value :: IntValue).Value = coins
	end
	player:SetAttribute(CURRENCY, coins)
end

-- transactionType: a Roblox AnalyticsEconomyTransactionType name, e.g.
-- "Gameplay", "Shop" or "IAP" (Robux purchases).
local function logEconomy(player: Player, flow: Enum.AnalyticsEconomyFlowType, amount: number, balance: number, reason: string, transactionType: string)
	pcall(function()
		AnalyticsService:LogEconomyEvent(player, flow, CURRENCY, amount, balance, transactionType, reason)
	end)
end

function EconomyService.GetCoins(player: Player): number
	local data = DataService.GetData(player)
	return if data then data.Coins else 0
end

-- Adds coins. Returns false if the data isn't loaded or the amount is invalid.
-- reason: short label like "StationIncome" or "RobuxCoinPack" (for analytics).
-- transactionType: "Gameplay" by default; pass "IAP" for coins bought with Robux.
function EconomyService.AddCoins(player: Player, amount: number, reason: string, transactionType: string?): boolean
	local data = DataService.GetData(player)
	local safe = EconomyService.sanitizeAmount(amount)
	if not data or not safe then
		return false
	end
	local before = data.Coins
	data.Coins = math.min(before + safe, GameConfig.MaxCoins)
	updateLeaderstats(player, data.Coins)
	logEconomy(player, Enum.AnalyticsEconomyFlowType.Source, data.Coins - before, data.Coins, reason, transactionType or "Gameplay")
	return true
end

-- Income ticks happen every second, so analytics for them are batched into one
-- event per player per minute instead of one per tick.
local pendingIncome: { [Player]: number } = {}

function EconomyService.AddIncome(player: Player, amount: number): boolean
	local data = DataService.GetData(player)
	local safe = EconomyService.sanitizeAmount(amount)
	if not data or not safe then
		return false
	end
	local before = data.Coins
	data.Coins = math.min(before + safe, GameConfig.MaxCoins)
	updateLeaderstats(player, data.Coins)
	pendingIncome[player] = (pendingIncome[player] or 0) + (data.Coins - before)
	return true
end

local function flushIncome(player: Player)
	local amount = pendingIncome[player]
	pendingIncome[player] = nil
	if amount and amount > 0 then
		logEconomy(player, Enum.AnalyticsEconomyFlowType.Source, amount, EconomyService.GetCoins(player), "SanctuaryIncome", "Gameplay")
	end
end

-- Spends coins if the player has enough. Returns true only if they were spent.
function EconomyService.TrySpendCoins(player: Player, amount: number, reason: string): boolean
	local data = DataService.GetData(player)
	local safe = EconomyService.sanitizeAmount(amount)
	if not data or not safe or data.Coins < safe then
		return false
	end
	data.Coins -= safe
	updateLeaderstats(player, data.Coins)
	logEconomy(player, Enum.AnalyticsEconomyFlowType.Sink, safe, data.Coins, reason, "Shop")
	return true
end

-- Multiplier for sanctuary income (Phase 2 uses this). Only affects income,
-- never PvP. Never yields: pass ownership is fetched when the player joins.
function EconomyService.GetIncomeMultiplier(player: Player): number
	return if PurchaseService.OwnsPassCached(player, "DoubleCoins") then 2 else 1
end

function EconomyService.init()
	task.spawn(function()
		while true do
			task.wait(60)
			for player in pendingIncome do
				flushIncome(player)
			end
		end
	end)
	DataService.ProfileReleasing:Connect(function(player: Player)
		flushIncome(player)
	end)

	DataService.ProfileLoaded:Connect(function(player: Player, data: any)
		local leaderstats = Instance.new("Folder")
		leaderstats.Name = "leaderstats"
		local coins = Instance.new("IntValue")
		coins.Name = CURRENCY
		coins.Value = data.Coins
		coins.Parent = leaderstats
		leaderstats.Parent = player
		player:SetAttribute(CURRENCY, data.Coins)

		-- Studio only (separate test save): one-time test coins
		-- (BindableEvents copy tables: write to the live save from GetData.)
		local live = DataService.GetData(player)
		if RunService:IsStudio() and (GameConfig.StudioTestCoins or 0) > 0 and live and not live.Stats.StudioTestCoins then
			live.Stats.StudioTestCoins = true
			EconomyService.AddCoins(player, GameConfig.StudioTestCoins, "StudioTest")
		end
	end)
end

return EconomyService
