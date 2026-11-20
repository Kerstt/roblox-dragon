-- ReplicatedStorage/Shared/Elements
-- The 8 dragon elements, their matchups, and their sanctuary station bonuses.
-- Shared so the UI can show the same matchups the server uses.
--
--   Triangle 1:  Fire > Nature > Water > Fire
--   Triangle 2:  Earth > Storm > Ice > Earth
--   Pair:        Light <> Shadow (each is strong against the other)
--   Across groups: neutral.
--
-- Light and Shadow are rarer: egg tables (Phase 2) only put them in higher tiers.

local Elements = {}

Elements.STRONG_MULTIPLIER = 1.25 -- attacker has the advantage
Elements.WEAK_MULTIPLIER = 0.8 -- defender has the advantage
Elements.STATION_BONUS = 1.25 -- dragon works at a station its element prefers

export type ElementId = "Fire" | "Nature" | "Water" | "Earth" | "Storm" | "Ice" | "Light" | "Shadow"

export type ElementInfo = {
	Id: ElementId,
	DisplayName: string,
	Color: Color3, -- signature color for UI, eggs and effects
	Group: string,
	IsRare: boolean,
	Flavor: string, -- one-line description for UI
}

-- Display order for menus.
Elements.Order = { "Fire", "Nature", "Water", "Earth", "Storm", "Ice", "Light", "Shadow" } :: { ElementId }

Elements.Info = {
	Fire = { Id = "Fire", DisplayName = "Fire", Color = Color3.fromRGB(255, 110, 40), Group = "Primal", IsRare = false,
		Flavor = "Burns through Nature. Doused by Water." },
	Nature = { Id = "Nature", DisplayName = "Nature", Color = Color3.fromRGB(90, 170, 70), Group = "Primal", IsRare = false,
		Flavor = "Drinks up Water. Burned by Fire." },
	Water = { Id = "Water", DisplayName = "Water", Color = Color3.fromRGB(40, 130, 200), Group = "Primal", IsRare = false,
		Flavor = "Douses Fire. Absorbed by Nature." },
	Earth = { Id = "Earth", DisplayName = "Earth", Color = Color3.fromRGB(165, 115, 60), Group = "Elemental", IsRare = false,
		Flavor = "Grounds Storm. Cracked by Ice." },
	Storm = { Id = "Storm", DisplayName = "Storm", Color = Color3.fromRGB(140, 90, 255), Group = "Elemental", IsRare = false,
		Flavor = "Shatters Ice. Grounded by Earth." },
	Ice = { Id = "Ice", DisplayName = "Ice", Color = Color3.fromRGB(170, 230, 255), Group = "Elemental", IsRare = false,
		Flavor = "Cracks Earth. Shattered by Storm." },
	Light = { Id = "Light", DisplayName = "Light", Color = Color3.fromRGB(255, 225, 130), Group = "Celestial", IsRare = true,
		Flavor = "Rare. Locked in an endless duel with Shadow." },
	Shadow = { Id = "Shadow", DisplayName = "Shadow", Color = Color3.fromRGB(80, 45, 115), Group = "Celestial", IsRare = true,
		Flavor = "Rare. Locked in an endless duel with Light." },
} :: { [ElementId]: ElementInfo }

-- Beats[a] = list of elements a is strong against.
Elements.Beats = {
	Fire = { "Nature" },
	Nature = { "Water" },
	Water = { "Fire" },
	Earth = { "Storm" },
	Storm = { "Ice" },
	Ice = { "Earth" },
	Light = { "Shadow" },
	Shadow = { "Light" },
} :: { [ElementId]: { ElementId } }

-- Sanctuary stations and the elements that earn the station bonus there.
-- Every element prefers exactly one station; any dragon can work anywhere.
Elements.StationAffinity = {
	Forge = { "Fire", "Storm" },
	Mine = { "Earth", "Ice" },
	Farm = { "Nature", "Water" },
	Watchtower = { "Light", "Shadow" },
} :: { [string]: { ElementId } }

local function contains(list: { string }?, value: string): boolean
	return list ~= nil and table.find(list, value) ~= nil
end

function Elements.IsValid(element: any): boolean
	return type(element) == "string" and Elements.Info[element] ~= nil
end

function Elements.IsStrongAgainst(attacker: string, defender: string): boolean
	return contains(Elements.Beats[attacker], defender)
end

-- Damage multiplier for an attack. Unknown elements are neutral.
-- Light vs Shadow (and back) is strong both ways.
function Elements.GetDamageMultiplier(attacker: string, defender: string): number
	if Elements.IsStrongAgainst(attacker, defender) then
		return Elements.STRONG_MULTIPLIER
	end
	if Elements.IsStrongAgainst(defender, attacker) then
		return Elements.WEAK_MULTIPLIER
	end
	return 1
end

-- Income multiplier for a dragon of this element working at this station.
function Elements.GetStationMultiplier(station: string, element: string): number
	return if contains(Elements.StationAffinity[station], element) then Elements.STATION_BONUS else 1
end

-- The station this element prefers, or nil.
function Elements.GetPreferredStation(element: string): string?
	for station, list in Elements.StationAffinity do
		if contains(list, element) then
			return station
		end
	end
	return nil
end

-- Checks the tables above are consistent. Returns a list of problems (empty = OK).
function Elements.Validate(): { string }
	local problems = {}
	for _, id in Elements.Order do
		if not Elements.Info[id] then
			table.insert(problems, id .. " has no Info")
		end
		local beats = Elements.Beats[id]
		if not beats or #beats ~= 1 then
			table.insert(problems, id .. " should beat exactly one element")
		end
		local beatenBy = 0
		for _, other in Elements.Order do
			if Elements.IsStrongAgainst(other, id) then
				beatenBy += 1
			end
		end
		if beatenBy ~= 1 then
			table.insert(problems, id .. " should be beaten by exactly one element (is " .. beatenBy .. ")")
		end
		local stations = 0
		for _, list in Elements.StationAffinity do
			if contains(list, id) then
				stations += 1
			end
		end
		if stations ~= 1 then
			table.insert(problems, id .. " should prefer exactly one station (prefers " .. stations .. ")")
		end
	end
	for id in Elements.Info do
		if not table.find(Elements.Order, id) then
			table.insert(problems, id .. " is missing from Order")
		end
	end
	return problems
end

return Elements
