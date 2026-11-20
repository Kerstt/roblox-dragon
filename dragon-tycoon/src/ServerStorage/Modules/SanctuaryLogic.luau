-- ServerStorage/Modules/SanctuaryLogic
-- The rules of the sanctuary as pure functions on a save's data table: starter
-- choice, slots, assigning dragons, upgrades, hatching and offline income.
-- No yields and no networking, so they are fully testable. Coin spending is
-- done by the caller (SanctuaryService) between the Can* check and the Apply*.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Shared

local DragonCatalog = require(Shared.DragonCatalog)
local EggCatalog = require(Shared.EggCatalog)
local Elements = require(Shared.Elements)
local Rarities = require(Shared.Rarities)
local SanctuaryConfig = require(Shared.SanctuaryConfig)
local DragonService = require(script.Parent.DragonService)

local SanctuaryLogic = {}

-- Dragons currently working at a station, sorted by id (gives stable slot order).
function SanctuaryLogic.DragonsAt(data: any, station: string): { string }
	local ids = {}
	for id, dragon in data.Dragons do
		if dragon.Station == station then
			table.insert(ids, id)
		end
	end
	table.sort(ids, function(a, b)
		return (tonumber(a:sub(2)) or 0) < (tonumber(b:sub(2)) or 0)
	end)
	return ids
end

-- Starter --------------------------------------------------------------------

function SanctuaryLogic.ChooseStarter(data: any, speciesId: any): (boolean, string?)
	if data.Tutorial.Starter ~= "" then
		return false, "already_chosen"
	end
	local starter = EggCatalog.GetStarter(speciesId)
	if not starter then
		return false, "invalid"
	end
	local species = DragonCatalog.Get(speciesId)
	local station = Elements.GetPreferredStation(species.Element) :: string
	local id, dragon = DragonService.Create(data, speciesId, EggCatalog.StarterRarity, 1, "Starter")
	-- The first slot is free and goes to the starter's preferred station.
	if data.Sanctuary.SlotsBought == 0 then
		data.Sanctuary.SlotsBought = 1
		data.Sanctuary.Stations[station].Slots += 1
	end
	dragon.Station = station
	data.Tutorial.Starter = speciesId
	return true, id
end

-- Slots ------------------------------------------------------------------------

-- Returns true and the cost, or false and a reason.
function SanctuaryLogic.CanBuySlot(data: any, station: any): (boolean, any)
	if not SanctuaryConfig.IsStation(station) then
		return false, "invalid"
	end
	if data.Sanctuary.Stations[station].Slots >= SanctuaryConfig.SlotsPerStation then
		return false, "station_full"
	end
	local cost = SanctuaryConfig.NextSlotCost(data.Sanctuary.SlotsBought)
	if not cost then
		return false, "all_slots_bought"
	end
	if data.Coins < cost then
		return false, "not_enough_coins"
	end
	return true, cost
end

function SanctuaryLogic.ApplyBuySlot(data: any, station: string)
	data.Sanctuary.SlotsBought += 1
	data.Sanctuary.Stations[station].Slots += 1
end

-- Assigning ----------------------------------------------------------------------

-- station = a station name to put the dragon to work, or nil to send it to the nest.
function SanctuaryLogic.Assign(data: any, dragonId: any, station: any): (boolean, string?)
	if type(dragonId) ~= "string" then
		return false, "invalid"
	end
	local dragon = data.Dragons[dragonId]
	if not dragon then
		return false, "not_found"
	end
	if station == nil then
		if not dragon.Station then
			return true
		end
		if not DragonService.NestHasRoom(data) then
			return false, "nest_full"
		end
		dragon.Station = nil
		return true
	end
	if not SanctuaryConfig.IsStation(station) then
		return false, "invalid"
	end
	if dragon.Station == station then
		return true
	end
	local used = #SanctuaryLogic.DragonsAt(data, station)
	if used >= data.Sanctuary.Stations[station].Slots then
		return false, "no_free_slot"
	end
	dragon.Station = station
	return true
end

-- Upgrades -------------------------------------------------------------------------

function SanctuaryLogic.CanUpgrade(data: any, station: any): (boolean, any)
	if not SanctuaryConfig.IsStation(station) then
		return false, "invalid"
	end
	local info = data.Sanctuary.Stations[station]
	if info.Slots == 0 then
		return false, "station_closed"
	end
	local cost = SanctuaryConfig.UpgradeCost(info.Level)
	if not cost then
		return false, "max_level"
	end
	if data.Coins < cost then
		return false, "not_enough_coins"
	end
	return true, cost
end

function SanctuaryLogic.ApplyUpgrade(data: any, station: string)
	data.Sanctuary.Stations[station].Level += 1
end

-- Hatching ---------------------------------------------------------------------------

function SanctuaryLogic.CanHatch(data: any, eggId: any): (boolean, any)
	local egg = EggCatalog.Get(eggId)
	if not egg or egg.Robux then
		return false, "invalid" -- Robux eggs are only granted by a purchase receipt
	end
	if data.Tutorial.Starter == "" then
		return false, "choose_starter_first"
	end
	-- Room needed in the nest: the rolled dragon (unless every rarity this egg
	-- can roll is set to auto-release), plus the tutorial bonus if it's due.
	local need = 0
	for rarity, weight in egg.RarityWeights do
		if weight > 0 and data.Settings.AutoRelease[rarity] ~= true then
			need = 1
			break
		end
	end
	if eggId == "Hatchling" and not data.Tutorial.BonusGiven then
		need += 1
	end
	if DragonService.IdleCount(data) + need > SanctuaryConfig.NestCapacityFor(data) then
		return false, "nest_full"
	end
	if data.Coins < egg.Price then
		return false, "not_enough_coins"
	end
	return true, egg.Price
end

-- Rolls and stores the result (coins already spent by the caller).
-- Returns { Id?, Species, Rarity, Released, Essence, Bonus? }.
function SanctuaryLogic.ApplyHatch(data: any, eggId: string, rng: Random, lucky: boolean?)
	local egg = EggCatalog.Get(eggId) :: any
	local rarity, species = EggCatalog.Roll(eggId, rng, lucky)
	local result: any = { Egg = eggId, Species = species, Rarity = rarity, Released = false, Essence = 0, Lucky = lucky == true }

	if data.Settings.AutoRelease[rarity] == true then
		local essence = Rarities.Info[rarity].Essence
		data.Essence += essence
		result.Released = true
		result.Essence = essence
	else
		result.Id = DragonService.Create(data, species, rarity, egg.Power, eggId)
	end
	data.Stats.Hatches += 1

	-- Tutorial reward after the first Hatchling Egg: a fixed dragon, not a roll.
	if eggId == "Hatchling" and not data.Tutorial.BonusGiven then
		local starter = EggCatalog.GetStarter(data.Tutorial.Starter)
		if starter then
			local bonusId = DragonService.Create(data, starter.BonusSpecies, EggCatalog.BonusRarity, 1, "TutorialBonus")
			result.Bonus = { Id = bonusId, Species = starter.BonusSpecies, Rarity = EggCatalog.BonusRarity }
		end
		data.Tutorial.BonusGiven = true
	end
	return result
end

-- Offline income ----------------------------------------------------------------------

-- Coins earned while away, based on the income rate saved at logout.
-- Returns (coins, secondsCounted).
function SanctuaryLogic.OfflineEarnings(data: any, now: number): (number, number)
	local lastLogout = data.Stats.LastLogout or 0
	local rate = data.Stats.LastIncomeRate or 0
	if lastLogout <= 0 or rate <= 0 then
		return 0, 0
	end
	local away = now - lastLogout
	if away < SanctuaryConfig.OfflineMinSeconds then
		return 0, 0
	end
	local seconds = math.min(away, SanctuaryConfig.OfflineCapSeconds)
	return math.floor(rate * SanctuaryConfig.OfflineRate * seconds), seconds
end

return SanctuaryLogic
