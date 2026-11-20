-- ReplicatedStorage/Shared/EggCatalog
-- THE odds table. The server rolls against these exact numbers and the egg shop
-- shows these exact numbers, so they can never disagree (Roblox paid random
-- items policy). Change odds only here.
--
-- A hatch makes two independent rolls:
--   1. rarity, from RarityWeights (out of 10,000, so 1 = 0.01%)
--   2. dragon, from the egg's element weights, split evenly across that
--      element's dragons
-- The chance of one exact outcome = rarity chance x dragon chance.
--
-- Robux eggs (RobuxEggs) are paid random items: same table, same roll, odds
-- shown before buying, hidden from players whose policy restricts them.
-- The Luck Boost (Robux) doubles Rare-and-better weights on coin eggs; the
-- shop shows the boosted odds while it's active, and the roll uses the same ones.

local DragonCatalog = require(script.Parent.DragonCatalog)
local Rarities = require(script.Parent.Rarities)

local EggCatalog = {}

export type Egg = {
	Id: string,
	Name: string,
	Order: number,
	Price: number, -- coins
	Power: number, -- "egg power": income multiplier for dragons from this egg
	RarityWeights: { [string]: number }, -- out of 10,000
	ElementWeights: { [string]: number }, -- relative weight per element
	Color: Color3,
	Description: string,
	Robux: boolean?, -- bought with Robux (paid random item)
}

local BASE_FOUR = { Fire = 1, Water = 1, Nature = 1, Earth = 1 }
local BASE_SIX = { Fire = 1, Water = 1, Nature = 1, Earth = 1, Storm = 1, Ice = 1 }

local eggs: { Egg } = {
	{
		Id = "Hatchling", Name = "Hatchling Egg", Order = 1, Price = 100, Power = 1,
		RarityWeights = { Common = 6000, Uncommon = 2500, Rare = 1000, Epic = 400, Legendary = 90, Mythic = 10 },
		ElementWeights = BASE_FOUR,
		Color = Color3.fromRGB(225, 205, 170),
		Description = "Fire, Water, Nature and Earth dragons.",
	},
	{
		Id = "Grove", Name = "Grove Egg", Order = 2, Price = 5_000, Power = 5,
		RarityWeights = { Common = 5500, Uncommon = 2700, Rare = 1200, Epic = 450, Legendary = 120, Mythic = 30 },
		ElementWeights = BASE_SIX,
		Color = Color3.fromRGB(120, 180, 100),
		Description = "Adds Storm and Ice dragons. 5x egg power.",
	},
	{
		Id = "Ember", Name = "Ember Egg", Order = 3, Price = 400_000, Power = 25,
		RarityWeights = { Common = 5000, Uncommon = 2800, Rare = 1400, Epic = 550, Legendary = 200, Mythic = 50 },
		ElementWeights = BASE_SIX,
		Color = Color3.fromRGB(230, 110, 50),
		Description = "Better rarity odds. 25x egg power.",
	},
	{
		Id = "Celestial", Name = "Celestial Egg", Order = 4, Price = 25_000_000, Power = 125,
		RarityWeights = { Common = 4500, Uncommon = 2900, Rare = 1600, Epic = 700, Legendary = 240, Mythic = 60 },
		-- Light 5%, Shadow 5%, the other six 15% each (total weight 40)
		ElementWeights = { Fire = 6, Water = 6, Nature = 6, Earth = 6, Storm = 6, Ice = 6, Light = 2, Shadow = 2 },
		Color = Color3.fromRGB(250, 230, 160),
		Description = "Adds rare Light and Shadow dragons. 125x egg power.",
	},
	{
		Id = "Ancient", Name = "Ancient Egg", Order = 5, Price = 1_500_000_000, Power = 625,
		RarityWeights = { Common = 4000, Uncommon = 3000, Rare = 1800, Epic = 850, Legendary = 280, Mythic = 70 },
		-- Light 10%, Shadow 10%, the other six 13.33% each (total weight 30)
		ElementWeights = { Fire = 4, Water = 4, Nature = 4, Earth = 4, Storm = 4, Ice = 4, Light = 3, Shadow = 3 },
		Color = Color3.fromRGB(110, 80, 140),
		Description = "The best odds in the sanctuary. 625x egg power.",
	},
}

-- Robux eggs. Their egg power matches the best egg power you already own, so
-- they stay useful at every stage of the game.
local robuxEggs: { Egg } = {
	{
		Id = "RoyalEgg", Name = "Royal Egg", Order = 101, Price = 0, Power = 0, Robux = true,
		RarityWeights = { Common = 0, Uncommon = 4000, Rare = 3500, Epic = 1800, Legendary = 600, Mythic = 100 },
		ElementWeights = { Fire = 5, Water = 5, Nature = 5, Earth = 5, Storm = 5, Ice = 5, Light = 3, Shadow = 3 },
		Color = Color3.fromRGB(230, 190, 90),
		Description = "Never Common. Any of the 16 dragons. Egg power matches your best dragon.",
	},
	{
		Id = "MythicEgg", Name = "Mythic Egg", Order = 102, Price = 0, Power = 0, Robux = true,
		RarityWeights = { Common = 0, Uncommon = 0, Rare = 0, Epic = 6000, Legendary = 3200, Mythic = 800 },
		ElementWeights = { Fire = 1, Water = 1, Nature = 1, Earth = 1, Storm = 1, Ice = 1, Light = 1, Shadow = 1 },
		Color = Color3.fromRGB(255, 90, 140),
		Description = "Epic or better, every time. Any element. Egg power matches your best dragon.",
	},
}

EggCatalog.List = eggs -- coin eggs (the egg shop)
EggCatalog.RobuxEggs = robuxEggs
EggCatalog.ById = {} :: { [string]: Egg }
for _, egg in eggs do
	EggCatalog.ById[egg.Id] = egg
end
for _, egg in robuxEggs do
	EggCatalog.ById[egg.Id] = egg
end

-- Luck Boost: these rarities' weights are multiplied, Common gives up the room.
EggCatalog.LuckMultiplier = 2
EggCatalog.LuckRarities = { Rare = true, Epic = true, Legendary = true, Mythic = true }

function EggCatalog.Get(id: any): Egg?
	return if type(id) == "string" then EggCatalog.ById[id] else nil
end

-- Tutorial rewards: fixed dragons, never random. -------------------------------
-- The player picks one starter (free, Common, egg power 1). After their first
-- Hatchling Egg, they get the matching bonus dragon (Uncommon, egg power 1).
EggCatalog.Starters = {
	{ Species = "Cindermaw", BonusSpecies = "Squallwing" }, -- Fire -> Forge, bonus Storm (Forge)
	{ Species = "Briarhorn", BonusSpecies = "Tidewhelp" }, -- Nature -> Farm, bonus Water (Farm)
	{ Species = "Quarrytusk", BonusSpecies = "Frostveil" }, -- Earth -> Mine, bonus Ice (Mine)
}
EggCatalog.StarterRarity = "Common"
EggCatalog.BonusRarity = "Uncommon"

function EggCatalog.GetStarter(speciesId: any)
	for _, starter in EggCatalog.Starters do
		if starter.Species == speciesId then
			return starter
		end
	end
	return nil
end

-- Odds ------------------------------------------------------------------------------

local RARITY_TOTAL = 10_000

-- The rarity weights actually used, with the luck boost applied (coin eggs only).
function EggCatalog.GetWeights(eggId: string, lucky: boolean?): { [string]: number }
	local egg = EggCatalog.ById[eggId]
	local weights = {}
	for rarity, weight in egg.RarityWeights do
		weights[rarity] = weight
	end
	if lucky and not egg.Robux then
		local added = 0
		for rarity in EggCatalog.LuckRarities do
			local weight = weights[rarity] or 0
			added += weight * (EggCatalog.LuckMultiplier - 1)
			weights[rarity] = weight * EggCatalog.LuckMultiplier
		end
		weights.Common = (weights.Common or 0) - added
	end
	return weights
end

-- { { Rarity, Weight, Chance } } in rarity order. Chance is 0..1.
function EggCatalog.GetRarityOdds(eggId: string, lucky: boolean?)
	local weights = EggCatalog.GetWeights(eggId, lucky)
	local result = {}
	for _, rarity in Rarities.Order do
		local weight = weights[rarity] or 0
		if weight > 0 then
			table.insert(result, { Rarity = rarity, Weight = weight, Chance = weight / RARITY_TOTAL })
		end
	end
	return result
end

-- { { Species, Element, Weight, Chance } } in catalog order. Chance is 0..1.
function EggCatalog.GetDragonOdds(eggId: string)
	local egg = EggCatalog.ById[eggId]
	local entries = {}
	local total = 0
	for _, species in DragonCatalog.List do
		local elementWeight = egg.ElementWeights[species.Element]
		if elementWeight and elementWeight > 0 then
			local sameElement = #DragonCatalog.OfElements({ species.Element })
			local weight = elementWeight / sameElement
			total += weight
			table.insert(entries, { Species = species.Id, Element = species.Element, Weight = weight })
		end
	end
	for _, entry in entries do
		entry.Chance = entry.Weight / total
	end
	return entries
end

-- Every possible outcome with its exact chance (0..1), for the full odds view.
function EggCatalog.GetOutcomeTable(eggId: string, lucky: boolean?)
	local outcomes = {}
	for _, r in EggCatalog.GetRarityOdds(eggId, lucky) do
		for _, d in EggCatalog.GetDragonOdds(eggId) do
			table.insert(outcomes, { Rarity = r.Rarity, Species = d.Species, Chance = r.Chance * d.Chance })
		end
	end
	return outcomes
end

-- The roll. `rng` is a Random object. Server only: the client never rolls.
function EggCatalog.Roll(eggId: string, rng: Random, lucky: boolean?): (string, string)
	local rarityPick = rng:NextInteger(1, RARITY_TOTAL)
	local rarity = Rarities.Order[1]
	local running = 0
	for _, r in EggCatalog.GetRarityOdds(eggId, lucky) do
		running += r.Weight
		if rarityPick <= running then
			rarity = r.Rarity
			break
		end
	end

	local dragons = EggCatalog.GetDragonOdds(eggId)
	local dragonPick = rng:NextNumber()
	local species = dragons[#dragons].Species
	local cumulative = 0
	for _, d in dragons do
		cumulative += d.Chance
		if dragonPick < cumulative then
			species = d.Species
			break
		end
	end
	return rarity, species
end

-- Exact when the chance is a short decimal ("12.5%", "0.0125%"). Repeating
-- decimals like 1/12 show 4 significant digits with "≈" ("≈8.333%"), so the
-- shown number is never a silently rounded version of the real one.
function EggCatalog.FormatChance(chance: number): string
	local percent = chance * 100
	local text = string.format("%.4g", percent)
	local shown = tonumber(text) or 0
	local exact = math.abs(shown - percent) < 1e-9 * math.max(1, percent)
	return (if exact then "" else "≈") .. text .. "%"
end

-- Consistency check for tests and startup. Returns a list of problems.
function EggCatalog.Validate(): { string }
	local problems = {}
	local all = table.clone(eggs)
	for _, egg in robuxEggs do
		table.insert(all, egg)
	end
	for _, egg in all do
		if not egg.Robux then
			local luckySum = 0
			for rarity, weight in EggCatalog.GetWeights(egg.Id, true) do
				if weight < 0 then
					table.insert(problems, egg.Id .. ": luck boost makes " .. rarity .. " negative")
				end
				luckySum += weight
			end
			if luckySum ~= RARITY_TOTAL then
				table.insert(problems, egg.Id .. ": boosted weights sum to " .. luckySum)
			end
		end
		local sum = 0
		for rarity, weight in egg.RarityWeights do
			if not Rarities.IsValid(rarity) then
				table.insert(problems, egg.Id .. ": unknown rarity " .. tostring(rarity))
			end
			if weight ~= math.floor(weight) or weight < 0 then
				table.insert(problems, egg.Id .. ": rarity weights must be whole numbers")
			end
			sum += weight
		end
		if sum ~= RARITY_TOTAL then
			table.insert(problems, egg.Id .. ": rarity weights sum to " .. sum .. ", not 10000")
		end
		local dragonTotal = 0
		for _, d in EggCatalog.GetDragonOdds(egg.Id) do
			dragonTotal += d.Chance
		end
		if math.abs(dragonTotal - 1) > 1e-9 then
			table.insert(problems, egg.Id .. ": dragon chances sum to " .. dragonTotal)
		end
		for element in egg.ElementWeights do
			if #DragonCatalog.OfElements({ element }) == 0 then
				table.insert(problems, egg.Id .. ": no dragons of element " .. element)
			end
		end
	end
	for _, starter in EggCatalog.Starters do
		if not DragonCatalog.Get(starter.Species) or not DragonCatalog.Get(starter.BonusSpecies) then
			table.insert(problems, "starter references an unknown dragon")
		end
	end
	return problems
end

return EggCatalog
