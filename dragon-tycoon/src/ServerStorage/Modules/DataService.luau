-- ServerStorage/Modules/DataService
-- Saves and loads each player's data safely.
--
-- How it stays safe:
--  * Session locking: when a server loads a player, it writes its session id into
--    the save. Other servers wait instead of loading the same save, and a server
--    that has lost the lock can never write over newer data.
--  * Every write uses UpdateAsync, retries with backoff, and respects the
--    6-second-per-key write limit.
--  * Saves on leave, on server shutdown (BindToClose) and on an autosave timer.
--  * If a save can't be loaded, the player is kicked instead of playing on empty
--    data that would overwrite their real save.
--
-- Other systems read and change data through DataService.GetData(player) and
-- should only change it synchronously (no yields between reading and writing).

local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local MockDataStore = require(script.Parent.MockDataStore)

local DataService = {}

local CURRENT_VERSION: number = GameConfig.DataVersion

-- Helpers -----------------------------------------------------------------

local function deepCopy(value: any): any
	if type(value) ~= "table" then
		return value
	end
	local copy = {}
	for k, v in value do
		copy[k] = deepCopy(v)
	end
	return copy
end
DataService.deepCopy = deepCopy

-- The shape of a brand-new save. Add new fields here; reconcile() fills them in
-- for existing players automatically.
local function defaultData()
	return {
		Coins = GameConfig.StartingCoins,
		Essence = 0, -- from releasing dragons; spent on Infuse (dragon XP)
		-- [dragonId: string] = { Species, Rarity, Level, XP, Power, Egg, Station?, Hatched }
		Dragons = {},
		NextDragonId = 1,
		Sanctuary = {
			SlotsBought = 0,
			ExtraNest = 0, -- from the +10 Nest pass (set on every join from ownership)
			Stations = {
				Mine = { Level = 0, Slots = 0 },
				Farm = { Level = 0, Slots = 0 },
				Forge = { Level = 0, Slots = 0 },
				Watchtower = { Level = 0, Slots = 0 },
			},
		},
		Tutorial = {
			Starter = "", -- species id once chosen
			BonusGiven = false,
			Step = 0, -- guided tutorial progress (TutorialService); 99 = finished
		},
		Boosts = {
			LuckUntil = 0, -- os.time() when the Luck Boost ends
		},
		Cosmetics = {
			Owned = {}, -- [cosmeticId] = true
			Trail = "", -- equipped trail id
			Aura = "", -- equipped aura id
		},
		Settings = {
			AutoRelease = {}, -- [rarity] = true to release new hatches of that rarity
			QuickHatch = false,
			AutoHatchEgg = "", -- Auto Hatch pass: egg id to keep hatching ("" = off)
		},
		Purchases = {
			Receipts = {}, -- [purchaseId] = os.time() it was granted
			ReceiptOrder = {}, -- purchaseIds oldest first, used to trim Receipts
			History = {}, -- { ProductId, PurchaseId, Robux, Time }
			Pending = { FixedDragon = "", Cosmetic = "" }, -- what the player picked before buying
		},
		Combat = {
			Trophies = 0, -- ranked rating
			BestTrophies = 0,
			Wins = 0,
			Losses = 0,
			RankedWins = 0,
			RankedLosses = 0,
			Scales = 0, -- crafting material from PvP
			PracticeDay = 0, -- day number of the practice reward counter
			PracticeRewards = 0, -- practice matches that gave XP today
			RankedPairs = {}, -- [opponentUserId] = { Day, Count }, limits trophy farming
			Relics = 0, -- rare crafting material from raids
			RaidClears = 0,
			RaidDay = 0, -- day number of the raid reward counter
			RaidRewards = 0, -- raids that gave rewards today
		},
		Stats = {
			FirstJoin = 0,
			LastLogin = 0,
			LastLogout = 0,
			TotalPlayTime = 0,
			Hatches = 0,
			LastIncomeRate = 0, -- coins/sec at logout, used for offline income
		},
	}
end
DataService.defaultData = defaultData

-- Fill in fields the template has but the save is missing.
local function reconcile(data: { [any]: any }, template: { [any]: any })
	for k, v in template do
		if data[k] == nil then
			data[k] = deepCopy(v)
		elseif type(v) == "table" and type(data[k]) == "table" then
			reconcile(data[k], v)
		end
	end
end

-- MIGRATIONS[n] upgrades data from version n-1 to version n.
local MIGRATIONS: { [number]: (any) -> any } = {
	-- [2] = function(data) ... return data end,
}

local function migrate(record: any): any
	local data = if type(record.Data) == "table" then record.Data else defaultData()
	local version = record.Version or 0
	while version < CURRENT_VERSION do
		version += 1
		local step = MIGRATIONS[version]
		if step then
			data = step(data)
		end
	end
	reconcile(data, defaultData())
	return data
end
DataService._migrate = migrate

local function keyFor(userId: number): string
	return "Player_" .. tostring(userId)
end

-- Manager: the session-locking core. One per server; tests create several to
-- act like several servers sharing one store. -------------------------------

export type Profile = {
	UserId: number,
	Data: any,
	Active: boolean,
	LastSave: number,
	Saving: boolean,
	Releasing: boolean,
}

local Manager = {}
Manager.__index = Manager

export type ManagerOptions = {
	sessionId: string?,
	lockRetries: number?, -- extra load attempts while another server holds the lock
	lockRetryDelay: number?, -- seconds between those attempts
	staleLockSeconds: number?, -- a lock older than this is treated as abandoned
	requestRetries: number?, -- attempts per DataStore request
	backoffBase: number?, -- first retry wait; doubles each time
	minSaveGap: number?, -- min seconds between writes to one key
	now: (() -> number)?,
}

function DataService.newManager(store: any, options: ManagerOptions?)
	local o: ManagerOptions = options or {}
	return setmetatable({
		store = store,
		sessionId = o.sessionId or HttpService:GenerateGUID(false),
		profiles = {} :: { [number]: Profile },
		lockRetries = o.lockRetries or 6,
		lockRetryDelay = o.lockRetryDelay or 5,
		-- Live sessions refresh their lock on every autosave, so a lock this old
		-- belongs to a server that crashed.
		staleLockSeconds = o.staleLockSeconds or GameConfig.AutosaveInterval * 3,
		requestRetries = o.requestRetries or 4,
		backoffBase = o.backoffBase or 1,
		minSaveGap = o.minSaveGap or 6,
		now = o.now or os.time,
	}, Manager)
end

-- Runs a DataStore request with retries and exponential backoff.
function Manager:_request(fn: () -> any): (boolean, any)
	local lastError
	for attempt = 1, self.requestRetries do
		local ok, result = pcall(fn)
		if ok then
			return true, result
		end
		lastError = result
		if attempt < self.requestRetries then
			task.wait(self.backoffBase * 2 ^ (attempt - 1))
		end
	end
	return false, lastError
end

-- Loads a player's save and takes the session lock.
-- Returns the profile, or nil and a reason ("error: ...").
function Manager:Load(userId: number): (Profile?, string?)
	local existing = self.profiles[userId]
	if existing and not existing.Releasing then
		return existing
	end
	-- Fast rejoin while the last session's final save is still running: wait
	-- for it to finish, then load the fresh save.
	while self.profiles[userId] do
		task.wait(0.1)
	end

	local key = keyFor(userId)
	for attempt = 1, self.lockRetries + 1 do
		local blocked = false
		local tooNew = false

		local ok, result = self:_request(function()
			return self.store:UpdateAsync(key, function(record)
				blocked = false -- UpdateAsync may run this more than once
				tooNew = false
				local now = self.now()
				record = record or { Version = CURRENT_VERSION, Data = defaultData() }
				if (record.Version or 0) > CURRENT_VERSION then
					tooNew = true
					return nil -- saved by newer server code: old code must not touch it
				end
				local session = record.Session
				local heldByOther = session ~= nil and session.Id ~= self.sessionId
				local stale = heldByOther and (now - (session.Time or 0)) > self.staleLockSeconds
				if heldByOther and not stale then
					blocked = true
					return nil -- cancel the write and wait
				end
				record.Session = { Id = self.sessionId, Time = now }
				return record, { userId }
			end)
		end)

		if not ok then
			return nil, "error: " .. tostring(result)
		end
		if tooNew then
			return nil, "newer version"
		end
		if not blocked and type(result) == "table" then
			local profile: Profile = {
				UserId = userId,
				Data = migrate(result),
				Active = true,
				LastSave = os.clock(),
				Saving = false,
				Releasing = false,
			}
			self.profiles[userId] = profile
			return profile
		end
		if attempt <= self.lockRetries then
			task.wait(self.lockRetryDelay)
		end
	end
	-- Still open on another server (its final save may be slow). Never take it
	-- by force: that could throw away that server's newer data.
	return nil, "locked"
end

-- Writes the profile to the store. With release = true it also drops the lock
-- and forgets the profile. Returns true, or false and a reason
-- ("inactive", "lost lock", "error: ...").
function Manager:Save(userId: number, release: boolean?): (boolean, string?)
	local profile = self.profiles[userId]
	if not profile or not profile.Active then
		return false, "inactive"
	end

	-- One write at a time per profile.
	while profile.Saving do
		task.wait(0.1)
	end
	if not profile.Active then
		return false, "inactive"
	end
	profile.Saving = true

	-- Respect Roblox's limit of one write per key every 6 seconds.
	local wait = self.minSaveGap - (os.clock() - profile.LastSave)
	if wait > 0 then
		task.wait(wait)
	end

	-- Copying can fail on bad data (e.g. a table that contains itself); that must
	-- never leave Saving stuck, or every later save would wait forever.
	local copied, snapshot = pcall(deepCopy, profile.Data)
	local lostLock = false
	local ok, result = false, "could not copy data: " .. tostring(snapshot)
	if copied then ok, result = self:_request(function()
		return self.store:UpdateAsync(keyFor(userId), function(record)
			lostLock = false
			if type(record) ~= "table" or record.Session == nil or record.Session.Id ~= self.sessionId then
				lostLock = true
				return nil -- another server owns this save now: never overwrite it
			end
			local now = self.now()
			record.Data = snapshot
			record.Version = math.max(record.Version or 0, CURRENT_VERSION)
			record.LastSaved = now
			record.Session = if release then nil else { Id = self.sessionId, Time = now }
			return record, { userId }
		end)
	end) end

	profile.LastSave = os.clock()
	profile.Saving = false

	if ok and lostLock then
		profile.Active = false
		self.profiles[userId] = nil
		return false, "lost lock"
	end
	if release then
		-- Forget the profile even if the write failed: the player is gone, and a
		-- stale lock expires on its own (staleLockSeconds).
		profile.Active = false
		self.profiles[userId] = nil
	end
	if not ok then
		return false, "error: " .. tostring(result)
	end
	return true
end

function Manager:Get(userId: number): Profile?
	local profile = self.profiles[userId]
	return if profile and profile.Active then profile else nil
end

-- Player-facing layer (one manager for this server) ---------------------------

local manager: any = nil
local started = false

local profileLoaded = Instance.new("BindableEvent")
local profileReleasing = Instance.new("BindableEvent")
-- Fires (player, data) once a player's save is loaded and ready.
DataService.ProfileLoaded = profileLoaded.Event
-- Fires (player, data) just before the final save when a player leaves.
DataService.ProfileReleasing = profileReleasing.Event

local joinTimes: { [Player]: number } = {}
local loadingCount = 0 -- loads in progress (BindToClose waits for them)

function DataService.GetData(player: Player): any
	local profile = manager and manager:Get(player.UserId)
	return profile and profile.Data
end

function DataService.IsLoaded(player: Player): boolean
	return DataService.GetData(player) ~= nil
end

-- Waits up to `timeout` seconds for the player's data. Returns nil if it never loads.
function DataService.WaitForData(player: Player, timeout: number?): any
	local deadline = os.clock() + (timeout or 15)
	while os.clock() < deadline and player.Parent do
		local data = DataService.GetData(player)
		if data then
			return data
		end
		task.wait(0.25)
	end
	return DataService.GetData(player)
end

local function kickForLostLock(player: Player)
	if player.Parent then
		player:Kick("Your Dragon Tycoon save was opened on another server. Please rejoin.")
	end
end

-- Saves right away (used after Robux purchases). Returns true when it's stored.
function DataService.SaveNow(player: Player): boolean
	if not manager then
		return false
	end
	local ok, reason = manager:Save(player.UserId, false)
	if not ok then
		warn("[DataService] SaveNow failed for", player.Name, reason)
		if reason == "lost lock" then
			kickForLostLock(player)
		end
	end
	return ok
end

local function onPlayerAdded(player: Player)
	joinTimes[player] = os.time()
	loadingCount += 1
	local loadOk, profile, reason = pcall(manager.Load, manager, player.UserId)
	loadingCount -= 1
	if not loadOk then
		reason = profile
		profile = nil
	end
	if not profile then
		warn("[DataService] Could not load", player.Name, reason)
		if player.Parent then
			local message = if reason == "newer version"
				then "This server is out of date. Please rejoin to get the latest version."
				else "We couldn't load your Dragon Tycoon save. Your progress is safe, please rejoin in a minute."
			player:Kick(message)
		end
		return
	end
	if player.Parent ~= Players then
		-- Left while loading: give the lock back straight away.
		manager:Save(player.UserId, true)
		return
	end

	local stats = profile.Data.Stats
	if stats.FirstJoin == 0 then
		stats.FirstJoin = os.time()
	end
	stats.LastLogin = os.time()

	player:SetAttribute("DataLoaded", true)
	profileLoaded:Fire(player, profile.Data)
end

local function onPlayerRemoving(player: Player)
	local profile = manager:Get(player.UserId)
	if not profile or profile.Releasing then
		joinTimes[player] = nil
		return
	end
	profile.Releasing = true

	profileReleasing:Fire(player, profile.Data)
	local stats = profile.Data.Stats
	stats.LastLogout = os.time()
	stats.TotalPlayTime += os.time() - (joinTimes[player] or os.time())
	joinTimes[player] = nil

	local ok, reason = manager:Save(player.UserId, true)
	if not ok then
		warn("[DataService] Final save failed for", player.Name, reason)
	end
end

local function autosaveLoop()
	while true do
		task.wait(GameConfig.AutosaveInterval)
		for _, player in Players:GetPlayers() do
			local profile = manager:Get(player.UserId)
			if profile and not profile.Releasing then
				task.spawn(function()
					local ok, reason = manager:Save(player.UserId, false)
					if not ok and reason == "lost lock" then
						kickForLostLock(player)
					elseif not ok and reason ~= "inactive" then
						warn("[DataService] Autosave failed for", player.Name, reason)
					end
				end)
			end
		end
	end
end

-- Picks the real DataStore, or an in-memory one in Studio when API access is off.
local function openStore(): any
	-- Studio play-tests use their own store, so testing never touches live saves.
	local storeName = if RunService:IsStudio() then GameConfig.DataStoreName .. "_Studio" else GameConfig.DataStoreName
	local ok, store = pcall(function()
		return DataStoreService:GetDataStore(storeName)
	end)
	if ok and RunService:IsStudio() then
		local probeOk, probeError = pcall(function()
			return store:GetAsync("__studio_probe")
		end)
		if not probeOk then
			ok = false
			store = probeError
		end
	end
	if ok then
		return store
	end
	if RunService:IsStudio() then
		warn("[DataService] DataStores unavailable in Studio (" .. tostring(store) .. "). "
			.. "Using a temporary in-memory store: NOTHING WILL BE SAVED. "
			.. "Turn on Game Settings > Security > Enable Studio Access to API Services to test real saving.")
		return MockDataStore.new()
	end
	error("[DataService] DataStore unavailable: " .. tostring(store))
end

-- Call once at server start, before anything that listens to ProfileLoaded.
function DataService.init()
	if manager then
		return
	end
	manager = DataService.newManager(openStore(), {
		sessionId = if game.JobId ~= "" then game.JobId else HttpService:GenerateGUID(false),
	})
end

-- Call after every other service has connected to ProfileLoaded.
function DataService.start()
	assert(manager, "DataService.init() must run before start()")
	if started then
		return
	end
	started = true

	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end

	game:BindToClose(function()
		local pending = 0
		for _, player in Players:GetPlayers() do
			pending += 1
			task.spawn(function()
				onPlayerRemoving(player)
				pending -= 1
			end)
		end
		-- Wait for every final save, including ones PlayerRemoving already
		-- started, and for loads still running (they release on their own).
		local deadline = os.clock() + 25
		while (pending > 0 or loadingCount > 0 or next(manager.profiles) ~= nil) and os.clock() < deadline do
			task.wait(0.2)
		end
	end)

	task.spawn(autosaveLoop)
end

return DataService
