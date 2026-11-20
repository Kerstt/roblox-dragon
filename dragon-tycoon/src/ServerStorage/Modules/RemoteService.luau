-- ServerStorage/Modules/RemoteService
-- The only door between clients and the server.
--
-- ReplicatedStorage/Remotes (created at server start):
--   Request (RemoteFunction)  client -> server: Request:InvokeServer(action, ...)
--   State   (RemoteEvent)     server -> client: a snapshot of the player's sanctuary
--   Notice  (RemoteEvent)     server -> client: one-off messages (welcome back, ...)
--
-- Every request is rate-limited, every argument is type-checked here, and the
-- action itself is validated again by SanctuaryService/SanctuaryLogic.
-- The server never invokes the client.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Shared

local SanctuaryConfig = require(Shared.SanctuaryConfig)
local DataService = require(script.Parent.DataService)
local SanctuaryService = require(script.Parent.SanctuaryService)
local DragonService = require(script.Parent.DragonService)
local RateLimiter = require(script.Parent.RateLimiter)
local MountService = require(script.Parent.MountService)
local LevelService = require(script.Parent.LevelService)
local CombatService = require(script.Parent.CombatService)
local QueueService = require(script.Parent.QueueService)
local Leveling = require(Shared.Leveling)
local ShopService = require(script.Parent.ShopService)
local TutorialService = require(script.Parent.TutorialService)
local PurchaseService = require(script.Parent.PurchaseService)
local ProductCatalog = require(Shared.ProductCatalog)

local RemoteService = {}

local MAX_STRING = 40
local PUSH_INTERVAL = 0.2

local limiter = RateLimiter.new(8, 16) -- 8 requests/sec sustained, bursts of 16
local remotes: Folder
local requestRemote: RemoteFunction
local stateRemote: RemoteEvent
local noticeRemote: RemoteEvent
local dirty: { [Player]: boolean } = {}

local function fail(code: string)
	return { ok = false, error = code }
end

local function isShortString(value: any): boolean
	return type(value) == "string" and #value > 0 and #value <= MAX_STRING
end

-- What the client is allowed to know about its own sanctuary.
function RemoteService.BuildSnapshot(player: Player, data: any)
	local dragons = {}
	for id, d in data.Dragons do
		dragons[id] = { Species = d.Species, Rarity = d.Rarity, Level = d.Level, XP = d.XP, Power = d.Power, Station = d.Station, Egg = d.Egg }
	end
	local stations = {}
	for name, s in data.Sanctuary.Stations do
		stations[name] = { Level = s.Level, Slots = s.Slots }
	end
	local autoRelease = {}
	for rarity, on in data.Settings.AutoRelease do
		autoRelease[rarity] = on == true
	end
	return {
		Coins = data.Coins,
		Essence = data.Essence,
		Income = SanctuaryService.GetIncomeRate(player),
		Dragons = dragons,
		SlotsBought = data.Sanctuary.SlotsBought,
		NextSlotCost = SanctuaryConfig.NextSlotCost(data.Sanctuary.SlotsBought),
		Stations = stations,
		IdleCount = DragonService.IdleCount(data),
		NestCapacity = SanctuaryConfig.NestCapacityFor(data),
		Starter = data.Tutorial.Starter,
		BonusGiven = data.Tutorial.BonusGiven,
		AutoRelease = autoRelease,
		QuickHatch = data.Settings.QuickHatch,
		Hatches = data.Stats.Hatches,
		Combat = {
			Trophies = data.Combat.Trophies,
			BestTrophies = data.Combat.BestTrophies,
			Wins = data.Combat.Wins,
			Losses = data.Combat.Losses,
			RankedWins = data.Combat.RankedWins,
			RankedLosses = data.Combat.RankedLosses,
			Scales = data.Combat.Scales,
			Relics = data.Combat.Relics,
			RaidClears = data.Combat.RaidClears,
			RaidLeft = if data.Combat.RaidDay == math.floor(os.time() / 86400)
				then math.max(0, Leveling.RaidRewardsPerDay - data.Combat.RaidRewards)
				else Leveling.RaidRewardsPerDay,
			PracticeLeft = if data.Combat.PracticeDay == math.floor(os.time() / 86400)
				then math.max(0, Leveling.PracticeRewardsPerDay - data.Combat.PracticeRewards)
				else Leveling.PracticeRewardsPerDay,
		},
		Queue = QueueService.GetQueue(player),
		InBattle = CombatService.IsInMatch(player),
		TutorialStep = data.Tutorial.Step,
		Shop = (function()
			local passes = {}
			for _, pass in ProductCatalog.Passes do
				passes[pass.Key] = PurchaseService.OwnsPassCached(player, pass.Key)
			end
			local owned = {}
			for id, yes in data.Cosmetics.Owned do
				if yes then
					table.insert(owned, id)
				end
			end
			return {
				Passes = passes,
				LuckSeconds = ShopService.LuckSecondsLeft(data),
				Cosmetics = owned,
				Trail = data.Cosmetics.Trail,
				Aura = data.Cosmetics.Aura,
				AutoHatchEgg = data.Settings.AutoHatchEgg,
			}
		end)(),
	}
end

local function pushState(player: Player)
	local data = DataService.GetData(player)
	if data and player.Parent == Players then
		stateRemote:FireClient(player, RemoteService.BuildSnapshot(player, data))
	end
end

function RemoteService.MarkDirty(player: Player)
	dirty[player] = true
end

-- Action handlers: check argument types, then call the service. -----------------

local ACTIONS: { [string]: (Player, ...any) -> any } = {
	GetState = function(player)
		local data = DataService.GetData(player)
		if not data then
			return fail("not_loaded")
		end
		return { ok = true, state = RemoteService.BuildSnapshot(player, data) }
	end,
	ChooseStarter = function(player, speciesId)
		if not isShortString(speciesId) then
			return fail("invalid")
		end
		return SanctuaryService.ChooseStarter(player, speciesId)
	end,
	Hatch = function(player, eggId)
		if not isShortString(eggId) then
			return fail("invalid")
		end
		return SanctuaryService.Hatch(player, eggId)
	end,
	Assign = function(player, dragonId, station)
		if not isShortString(dragonId) then
			return fail("invalid")
		end
		if station ~= false and not isShortString(station) then
			return fail("invalid")
		end
		return SanctuaryService.Assign(player, dragonId, if station == false then nil else station)
	end,
	BuySlot = function(player, station)
		if not isShortString(station) then
			return fail("invalid")
		end
		return SanctuaryService.BuySlot(player, station)
	end,
	Upgrade = function(player, station)
		if not isShortString(station) then
			return fail("invalid")
		end
		return SanctuaryService.Upgrade(player, station)
	end,
	Release = function(player, ids)
		if type(ids) ~= "table" or #ids == 0 or #ids > 100 then
			return fail("invalid")
		end
		if CombatService.IsInMatch(player) then
			return fail("in_battle")
		end
		local clean = {}
		for i = 1, #ids do
			if not isShortString(ids[i]) then
				return fail("invalid")
			end
			clean[i] = ids[i]
		end
		return SanctuaryService.Release(player, clean)
	end,
	SetAutoRelease = function(player, rarity, enabled)
		if not isShortString(rarity) or type(enabled) ~= "boolean" then
			return fail("invalid")
		end
		return SanctuaryService.SetAutoRelease(player, rarity, enabled)
	end,
	SetQuickHatch = function(player, enabled)
		if type(enabled) ~= "boolean" then
			return fail("invalid")
		end
		return SanctuaryService.SetQuickHatch(player, enabled)
	end,
	Summon = function(player, dragonId)
		if not isShortString(dragonId) then
			return fail("invalid")
		end
		return MountService.Summon(player, dragonId)
	end,
	Dismiss = function(player)
		return MountService.Dismiss(player)
	end,
	-- Leveling
	Feed = function(player, dragonId)
		if not isShortString(dragonId) then
			return fail("invalid")
		end
		return LevelService.Feed(player, dragonId)
	end,
	Infuse = function(player, dragonId)
		if not isShortString(dragonId) then
			return fail("invalid")
		end
		return LevelService.Infuse(player, dragonId)
	end,
	-- Battles
	QueueJoin = function(player, mode, dragonId)
		if not isShortString(mode) or not isShortString(dragonId) then
			return fail("invalid")
		end
		local result = QueueService.Join(player, mode, dragonId)
		RemoteService.MarkDirty(player)
		return result
	end,
	QueueLeave = function(player)
		local result = QueueService.Leave(player)
		RemoteService.MarkDirty(player)
		return result
	end,
	-- Shop
	Buy = function(player, key, choice)
		if not isShortString(key) or (choice ~= nil and not isShortString(choice)) then
			return fail("invalid")
		end
		local result = ShopService.Buy(player, key, choice)
		RemoteService.MarkDirty(player)
		return result
	end,
	BuyPass = function(player, key)
		if not isShortString(key) then
			return fail("invalid")
		end
		return ShopService.BuyPass(player, key)
	end,
	Equip = function(player, kind, id)
		if not isShortString(kind) or type(id) ~= "string" or #id > MAX_STRING then
			return fail("invalid")
		end
		return ShopService.Equip(player, kind, id)
	end,
	SetAutoHatch = function(player, eggId)
		if type(eggId) ~= "string" or #eggId > MAX_STRING then
			return fail("invalid")
		end
		return ShopService.SetAutoHatch(player, eggId)
	end,
}

local function onRequest(player: Player, action: any, ...: any)
	if type(action) ~= "string" or ACTIONS[action] == nil then
		return fail("invalid")
	end
	if not limiter:Allow(player) then
		return fail("rate_limited")
	end
	local ok, result = pcall(ACTIONS[action], player, ...)
	if not ok then
		warn("[RemoteService]", action, "failed for", player.Name, result)
		return fail("server_error")
	end
	if type(result) == "table" and result.ok then
		local first = ...
		local tutorialOk, err = pcall(TutorialService.OnAction, player, action, first)
		if not tutorialOk then
			warn("[RemoteService] tutorial step failed:", err)
		end
	end
	return result
end

function RemoteService.init()
	remotes = Instance.new("Folder")
	remotes.Name = "Remotes"
	requestRemote = Instance.new("RemoteFunction")
	requestRemote.Name = "Request"
	requestRemote.Parent = remotes
	stateRemote = Instance.new("RemoteEvent")
	stateRemote.Name = "State"
	stateRemote.Parent = remotes
	noticeRemote = Instance.new("RemoteEvent")
	noticeRemote.Name = "Notice"
	noticeRemote.Parent = remotes
	remotes.Parent = ReplicatedStorage

	requestRemote.OnServerInvoke = onRequest

	SanctuaryService.Changed:Connect(RemoteService.MarkDirty)
	LevelService.Changed:Connect(RemoteService.MarkDirty)
	ShopService.Changed:Connect(RemoteService.MarkDirty)
	TutorialService.Changed:Connect(RemoteService.MarkDirty)
	for _, source in { ShopService.Notice, TutorialService.Notice } do
		source:Connect(function(player, kind, payload)
			if player.Parent == Players then
				noticeRemote:FireClient(player, kind, payload)
			end
		end)
	end
	CombatService.Changed:Connect(RemoteService.MarkDirty)
	LevelService.Notice:Connect(function(player, kind, payload)
		if player.Parent == Players then
			noticeRemote:FireClient(player, kind, payload)
		end
	end)
	SanctuaryService.Notice:Connect(function(player, kind, payload)
		if player.Parent == Players then
			noticeRemote:FireClient(player, kind, payload)
		end
	end)
	DataService.ProfileLoaded:Connect(function(player)
		-- Deferred so offline income and other load-time changes are included.
		task.defer(pushState, player)
	end)
	Players.PlayerRemoving:Connect(function(player)
		dirty[player] = nil
	end)

	task.spawn(function()
		while true do
			task.wait(PUSH_INTERVAL)
			for player in dirty do
				dirty[player] = nil
				pushState(player)
			end
		end
	end)
end

return RemoteService
