-- ReplicatedStorage/Shared/SanctuaryConfig
-- Sanctuary numbers and the income formula. Shared so the UI shows the same
-- numbers the server pays. All values are starting values for playtesting.

local Elements = require(script.Parent.Elements)
local Rarities = require(script.Parent.Rarities)
local DragonCatalog = require(script.Parent.DragonCatalog)

local SanctuaryConfig = {}

SanctuaryConfig.Stations = { "Mine", "Farm", "Forge", "Watchtower" }
SanctuaryConfig.SlotsPerStation = 3

-- Slots are bought in order; the Nth slot costs SlotCosts[N], at any station
-- the player chooses (max SlotsPerStation each). The first slot is free and
-- goes to the starter dragon's station.
SanctuaryConfig.SlotCosts = {
	0, 150, 600, 2_500, 10_000, 40_000, 150_000, 600_000, 2_500_000, 10_000_000, 40_000_000, 150_000_000,
}

SanctuaryConfig.NestCapacity = 20 -- dragons not working at a station

-- Station upgrades: +10% income per level for dragons at that station.
SanctuaryConfig.StationMaxLevel = 25
SanctuaryConfig.StationLevelBonus = 0.10
SanctuaryConfig.StationUpgradeBase = 250
SanctuaryConfig.StationUpgradeGrowth = 2.0 -- sim: first station maxed ~day 26 at 20 min/day

SanctuaryConfig.BaseIncome = 1 -- coins/sec of a Common, level 1, egg power 1 dragon
SanctuaryConfig.LevelBonus = 0.05 -- +5% per level above 1

SanctuaryConfig.OfflineRate = 0.15 -- share of live income earned while offline
SanctuaryConfig.OfflineCapSeconds = 8 * 60 * 60
SanctuaryConfig.OfflineMinSeconds = 60 -- shorter absences pay nothing (rejoins)

SanctuaryConfig.HatchCooldown = 2.0 -- min seconds between hatches (server enforced); main lever for day-1 pace

-- Nest size for one save, including the +10 Nest pass.
function SanctuaryConfig.NestCapacityFor(data: any): number
	return SanctuaryConfig.NestCapacity + ((data and data.Sanctuary and data.Sanctuary.ExtraNest) or 0)
end

function SanctuaryConfig.IsStation(name: any): boolean
	return type(name) == "string" and table.find(SanctuaryConfig.Stations, name) ~= nil
end

-- Cost to go from `level` to `level + 1`, or nil at max.
function SanctuaryConfig.UpgradeCost(level: number): number?
	if level >= SanctuaryConfig.StationMaxLevel then
		return nil
	end
	return math.floor(SanctuaryConfig.StationUpgradeBase * SanctuaryConfig.StationUpgradeGrowth ^ level)
end

-- Cost of the next slot when `slotsBought` slots are owned, or nil when all are bought.
function SanctuaryConfig.NextSlotCost(slotsBought: number): number?
	return SanctuaryConfig.SlotCosts[slotsBought + 1]
end

-- Coins per second for one dragon working at a station (before the 2x pass).
-- dragon = { Species, Rarity, Level, Power }
function SanctuaryConfig.DragonIncome(dragon: any, station: string, stationLevel: number): number
	local species = DragonCatalog.Get(dragon.Species)
	local rarity = Rarities.Info[dragon.Rarity]
	if not species or not rarity then
		return 0
	end
	local levelMultiplier = 1 + SanctuaryConfig.LevelBonus * ((dragon.Level or 1) - 1)
	local stationMultiplier = 1 + SanctuaryConfig.StationLevelBonus * (stationLevel or 0)
	return SanctuaryConfig.BaseIncome
		* (dragon.Power or 1)
		* rarity.IncomeMultiplier
		* levelMultiplier
		* Elements.GetStationMultiplier(station, species.Element)
		* stationMultiplier
end

-- Total coins/sec for a whole save (before the 2x pass).
function SanctuaryConfig.TotalIncome(data: any): number
	local total = 0
	for _, dragon in data.Dragons do
		if dragon.Station then
			local station = data.Sanctuary.Stations[dragon.Station]
			total += SanctuaryConfig.DragonIncome(dragon, dragon.Station, station and station.Level or 0)
		end
	end
	return total
end

return SanctuaryConfig
