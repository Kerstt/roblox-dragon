-- ServerStorage/Modules/QueueService
-- Battle queues for this server.
--   Casual   matches real players whose dragons have similar power (level and
--            rarity); the allowed gap widens the longer you wait.
--   Ranked   matches real players by trophies; every dragon fights at level 30
--            with no rarity bonus (CombatConfig.Stats).
--   Practice starts right away against the AI sparring dragon.
--   Raid     gathers 1-4 players; it starts when 4 have joined or the first has
--            waited RaidConfig.LobbyWait seconds.
-- PvP queues only ever match real players.
--
-- Every action returns { ok = true, ... } or { ok = false, error = "code" }.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Shared

local CombatConfig = require(Shared.CombatConfig)
local RaidConfig = require(Shared.RaidConfig)
local DragonCatalog = require(Shared.DragonCatalog)
local DataService = require(script.Parent.DataService)
local CombatService = require(script.Parent.CombatService)

local QueueService = {}

local SPECIES = { "Cindermaw", "Pyrelance", "Briarhorn", "Sylvenreach", "Tidewhelp", "Deepkeel", "Quarrytusk", "Faultcrown",
	"Squallwing", "Thunderquill", "Rimeclaw", "Frostveil", "Dawnwarden", "Solhallow", "Duskrend", "Gloamveil" }

type Entry = { Player: Player, DragonId: string, Power: number, Trophies: number, JoinedAt: number }
local queues: { [string]: { [Player]: Entry } } = { Casual = {}, Ranked = {}, Raid = {} }
local rng = Random.new()

local function fail(code: string)
	return { ok = false, error = code }
end

local function removeFromQueues(player: Player): boolean
	local was = false
	for _, queue in queues do
		if queue[player] then
			queue[player] = nil
			was = true
		end
	end
	return was
end

function QueueService.Join(player: Player, mode: string, dragonId: string)
	if mode ~= "Casual" and mode ~= "Ranked" and mode ~= "Practice" and mode ~= "Raid" then
		return fail("invalid")
	end
	local data = DataService.GetData(player)
	if not data then
		return fail("not_loaded")
	end
	local dragon = data.Dragons[dragonId]
	if not dragon then
		return fail("not_found")
	end
	if CombatService.IsInMatch(player) then
		return fail("in_battle")
	end
	removeFromQueues(player)

	if mode == "Practice" then
		-- A random sparring partner of another element, at your dragon's level.
		local ownElement = (DragonCatalog.Get(dragon.Species) :: any).Element
		local choices = {}
		for _, id in SPECIES do
			local species = DragonCatalog.Get(id)
			if species and species.Element ~= ownElement then
				table.insert(choices, id)
			end
		end
		local botSpecies = choices[rng:NextInteger(1, #choices)]
		if CombatService.FreeArenas() == 0 then
			return fail("arenas_busy")
		end
		local started = CombatService.StartMatch("Practice", { Player = player, DragonId = dragonId },
			{ Bot = true, Species = botSpecies, Level = dragon.Level or 1 })
		if not started then
			return fail("arenas_busy")
		end
		return { ok = true, started = true }
	end

	queues[mode][player] = {
		Player = player,
		DragonId = dragonId,
		Power = CombatConfig.Power(dragon.Level or 1, dragon.Rarity),
		Trophies = data.Combat.Trophies,
		JoinedAt = os.clock(),
	}
	CombatService.SendQueueStatus(player, { Status = "Searching", Mode = mode })
	return { ok = true, started = false }
end

function QueueService.Leave(player: Player)
	removeFromQueues(player)
	CombatService.SendQueueStatus(player, { Status = "Idle" })
	return { ok = true }
end

function QueueService.GetQueue(player: Player): string?
	for mode, queue in queues do
		if queue[player] then
			return mode
		end
	end
	return nil
end

local function compatible(mode: string, a: Entry, b: Entry, t: number): boolean
	local waited = math.max(t - a.JoinedAt, t - b.JoinedAt)
	local q = CombatConfig.Queue
	if mode == "Casual" then
		local gap = math.abs(a.Power - b.Power) / math.min(a.Power, b.Power)
		return gap <= q.CasualWindow + q.CasualWindowGrowth * waited
	end
	return math.abs(a.Trophies - b.Trophies) <= q.RankedWindow + q.RankedWindowGrowth * waited
end

-- Still able to fight? (dragon not released, player still here)
local function stillValid(entry: Entry): boolean
	if entry.Player.Parent ~= Players or CombatService.IsInMatch(entry.Player) then
		return false
	end
	local data = DataService.GetData(entry.Player)
	return data ~= nil and data.Dragons[entry.DragonId] ~= nil
end

-- Raid lobby: start with whoever is there once it's full or has waited long enough.
local function gatherRaid(t: number)
	local queue = queues.Raid
	local list = {}
	for player, entry in queue do
		if stillValid(entry) then
			table.insert(list, entry)
		else
			queue[player] = nil
			CombatService.SendQueueStatus(player, { Status = "Idle" })
		end
	end
	if #list == 0 then
		return
	end
	table.sort(list, function(x, y)
		return x.JoinedAt < y.JoinedAt
	end)
	local waited = t - list[1].JoinedAt
	local startsIn = math.max(0, math.ceil(RaidConfig.LobbyWait - waited))
	if (#list >= RaidConfig.MaxParty or startsIn <= 0) and CombatService.FreeArenas() > 0 then
		local party = {}
		for i = 1, math.min(#list, RaidConfig.MaxParty) do
			local e = list[i]
			queue[e.Player] = nil
			table.insert(party, { Player = e.Player, DragonId = e.DragonId })
		end
		if not CombatService.StartRaid(party) then
			-- Put everyone who can still fight back in the lobby.
			for i = 1, math.min(#list, RaidConfig.MaxParty) do
				if stillValid(list[i]) then
					queue[list[i].Player] = list[i]
				end
			end
		end
		return
	end
	for _, e in list do
		CombatService.SendQueueStatus(e.Player, { Status = "Searching", Mode = "Raid", Party = math.min(#list, RaidConfig.MaxParty), StartsIn = startsIn })
	end
end

local function matchmake()
	local t = os.clock()
	gatherRaid(t)
	for mode, queue in queues do
		if mode == "Raid" then
			continue
		end
		local list = {}
		for player, entry in queue do
			if stillValid(entry) then
				table.insert(list, entry)
			else
				queue[player] = nil
				CombatService.SendQueueStatus(player, { Status = "Idle" })
			end
		end
		table.sort(list, function(x, y)
			return x.JoinedAt < y.JoinedAt
		end)
		local used = {}
		for i, a in list do
			if used[a] or CombatService.FreeArenas() == 0 then
				continue
			end
			for j = i + 1, #list do
				local b = list[j]
				if not used[b] and compatible(mode, a, b, t) then
					used[a], used[b] = true, true
					queue[a.Player], queue[b.Player] = nil, nil
					local started = CombatService.StartMatch(mode, { Player = a.Player, DragonId = a.DragonId }, { Player = b.Player, DragonId = b.DragonId })
					if not started then
						-- Put them back if they can still fight.
						for _, e in { a, b } do
							if stillValid(e) then
								queue[e.Player] = e
							end
						end
					end
					break
				end
			end
		end
	end
end

function QueueService.init()
	Players.PlayerRemoving:Connect(removeFromQueues)
	task.spawn(function()
		while true do
			task.wait(1)
			local ok, err = pcall(matchmake)
			if not ok then
				warn("[QueueService] matchmaking failed:", err)
			end
		end
	end)
end

return QueueService
