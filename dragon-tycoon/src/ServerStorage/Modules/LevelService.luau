-- ServerStorage/Modules/LevelService
-- Dragon XP and levels on the server: station-work XP each second, Feed (coins),
-- Infuse (Dragon Essence) and battle XP. Numbers live in Shared/Leveling.
--
-- Every action returns { ok = true, ... } or { ok = false, error = "code" }.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Leveling = require(ReplicatedStorage.Shared.Leveling)
local DragonCatalog = require(ReplicatedStorage.Shared.DragonCatalog)
local DataService = require(script.Parent.DataService)
local EconomyService = require(script.Parent.EconomyService)

local LevelService = {}

local changed = Instance.new("BindableEvent")
-- Fires (player) when any dragon's XP or level changes.
LevelService.Changed = changed.Event
local notice = Instance.new("BindableEvent")
-- Fires (player, kind, payload) for messages like "level up".
LevelService.Notice = notice.Event

local function fail(code: string)
	return { ok = false, error = code }
end

-- Adds XP to one dragon and reports level-ups. Returns levels gained.
function LevelService.AddXP(player: Player, dragonId: string, amount: number, quiet: boolean?): number
	local data = DataService.GetData(player)
	local dragon = data and data.Dragons[dragonId]
	if not dragon then
		return 0
	end
	local before = dragon.Level or 1
	local gained = Leveling.AddXP(dragon, amount)
	if gained > 0 and not quiet then
		local species = DragonCatalog.Get(dragon.Species)
		local unlocked = Leveling.SkillsUnlocked(dragon.Level) - Leveling.SkillsUnlocked(before)
		notice:Fire(player, "LevelUp", {
			Name = species and species.Name or dragon.Species,
			Level = dragon.Level,
			SkillUnlocked = unlocked > 0,
		})
	end
	changed:Fire(player)
	return gained
end

-- Spend coins for XP.
function LevelService.Feed(player: Player, dragonId: string)
	local data = DataService.GetData(player)
	if not data then
		return fail("not_loaded")
	end
	local dragon = data.Dragons[dragonId]
	if not dragon then
		return fail("not_found")
	end
	local cost = Leveling.FeedCost(dragon.Level or 1)
	if not cost then
		return fail("max_dragon_level")
	end
	if not EconomyService.TrySpendCoins(player, cost, "Feed") then
		return fail("not_enough_coins")
	end
	local xp = Leveling.FeedXP(dragon.Level or 1)
	local gained = LevelService.AddXP(player, dragonId, xp)
	return { ok = true, xp = xp, levels = gained, level = dragon.Level }
end

-- Spend Dragon Essence to finish the current level.
function LevelService.Infuse(player: Player, dragonId: string)
	local data = DataService.GetData(player)
	if not data then
		return fail("not_loaded")
	end
	local dragon = data.Dragons[dragonId]
	if not dragon then
		return fail("not_found")
	end
	local cost = Leveling.InfuseCost(dragon)
	if not cost then
		return fail("max_dragon_level")
	end
	if (data.Essence or 0) < cost then
		return fail("not_enough_essence")
	end
	data.Essence -= cost
	local xp = cost * Leveling.EssenceXP
	local gained = LevelService.AddXP(player, dragonId, xp)
	return { ok = true, essence = cost, levels = gained, level = dragon.Level }
end

-- Working dragons earn XP every second the owner is online.
local function stationTick()
	for _, player in Players:GetPlayers() do
		local data = DataService.GetData(player)
		if data then
			local any = false
			for dragonId, dragon in data.Dragons do
				if dragon.Station and (dragon.Level or 1) < Leveling.MaxLevel then
					local before = dragon.Level or 1
					if Leveling.AddXP(dragon, Leveling.StationXPPerSecond) > 0 then
						local species = DragonCatalog.Get(dragon.Species)
						notice:Fire(player, "LevelUp", {
							Name = species and species.Name or dragon.Species,
							Level = dragon.Level,
							SkillUnlocked = Leveling.SkillsUnlocked(dragon.Level) > Leveling.SkillsUnlocked(before),
						})
						any = true
					end
				end
			end
			if any then
				changed:Fire(player)
			end
		end
	end
end

function LevelService.init()
	task.spawn(function()
		while true do
			task.wait(1)
			local ok, err = pcall(stationTick)
			if not ok then
				warn("[LevelService] Station XP tick failed:", err)
			end
		end
	end)
end

return LevelService
