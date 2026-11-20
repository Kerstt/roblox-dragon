-- ServerStorage/Modules/DragonService
-- Creating, counting and releasing dragons. Pure functions on a save's data
-- table (no yields, no networking), so they are easy to test.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Shared

local DragonCatalog = require(Shared.DragonCatalog)
local Rarities = require(Shared.Rarities)
local SanctuaryConfig = require(Shared.SanctuaryConfig)

local DragonService = {}

-- Adds a dragon to the save. Returns its id and the dragon.
function DragonService.Create(data: any, speciesId: string, rarity: string, power: number, source: string): (string, any)
	assert(DragonCatalog.Get(speciesId), "unknown species " .. tostring(speciesId))
	assert(Rarities.IsValid(rarity), "unknown rarity " .. tostring(rarity))
	local id = "D" .. tostring(data.NextDragonId)
	data.NextDragonId += 1
	local dragon = {
		Species = speciesId,
		Rarity = rarity,
		Level = 1,
		XP = 0,
		Power = power,
		Egg = source,
		Station = nil,
		Hatched = os.time(),
	}
	data.Dragons[id] = dragon
	return id, dragon
end

-- Dragons not working at a station (they live in the nest).
function DragonService.IdleCount(data: any): number
	local count = 0
	for _, dragon in data.Dragons do
		if not dragon.Station then
			count += 1
		end
	end
	return count
end

function DragonService.NestHasRoom(data: any): boolean
	return DragonService.IdleCount(data) < SanctuaryConfig.NestCapacityFor(data)
end

-- Releases one dragon for Essence. Returns the Essence gained, or nil and a reason.
function DragonService.Release(data: any, dragonId: any): (number?, string?)
	if type(dragonId) ~= "string" then
		return nil, "invalid"
	end
	local dragon = data.Dragons[dragonId]
	if not dragon then
		return nil, "not_found"
	end
	if dragon.Station then
		return nil, "working" -- take it off its station first
	end
	local essence = Rarities.Info[dragon.Rarity].Essence
	data.Dragons[dragonId] = nil
	data.Essence += essence
	return essence
end

return DragonService
