-- ServerStorage/Tests/ElementsTests
-- Run from the command bar:  print(require(game.ServerStorage.Tests.ElementsTests).run())

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Elements = require(ReplicatedStorage.Shared.Elements)

local ElementsTests = {}

function ElementsTests.run(elementsModule: any?): string
	local E = elementsModule or Elements
	local passed, failed = 0, 0
	local lines = {}
	local function check(name: string, condition: boolean, detail: any?)
		if condition then
			passed += 1
		else
			failed += 1
			table.insert(lines, "FAIL: " .. name .. (if detail ~= nil then " (" .. tostring(detail) .. ")" else ""))
		end
	end

	local problems = E.Validate()
	check("tables are consistent", #problems == 0, table.concat(problems, "; "))
	check("8 elements", #E.Order == 8, #E.Order)

	-- The two triangles
	local strong = { { "Fire", "Nature" }, { "Nature", "Water" }, { "Water", "Fire" }, { "Earth", "Storm" }, { "Storm", "Ice" }, { "Ice", "Earth" } }
	for _, pair in strong do
		check(pair[1] .. " strong vs " .. pair[2], E.GetDamageMultiplier(pair[1], pair[2]) == E.STRONG_MULTIPLIER)
		check(pair[2] .. " weak vs " .. pair[1], E.GetDamageMultiplier(pair[2], pair[1]) == E.WEAK_MULTIPLIER)
	end

	-- Light and Shadow
	check("Light strong vs Shadow", E.GetDamageMultiplier("Light", "Shadow") == E.STRONG_MULTIPLIER)
	check("Shadow strong vs Light", E.GetDamageMultiplier("Shadow", "Light") == E.STRONG_MULTIPLIER)
	check("Light vs Fire neutral", E.GetDamageMultiplier("Light", "Fire") == 1)
	check("Light and Shadow are rare", E.Info.Light.IsRare and E.Info.Shadow.IsRare)

	-- Neutral matchups
	check("same element neutral", E.GetDamageMultiplier("Fire", "Fire") == 1)
	check("across triangles neutral", E.GetDamageMultiplier("Fire", "Ice") == 1 and E.GetDamageMultiplier("Storm", "Water") == 1)
	check("unknown element neutral", E.GetDamageMultiplier("Banana", "Fire") == 1)

	-- Every element has exactly one strong and one weak matchup in total
	for _, a in E.Order do
		local strongCount, weakCount = 0, 0
		for _, d in E.Order do
			local m = E.GetDamageMultiplier(a, d)
			if m > 1 then strongCount += 1 elseif m < 1 then weakCount += 1 end
		end
		local expectedWeak = if E.Info[a].IsRare then 0 else 1
		check(a .. " has 1 strong matchup", strongCount == 1, strongCount)
		check(a .. " has " .. expectedWeak .. " weak matchups", weakCount == expectedWeak, weakCount)
	end

	-- Stations
	check("Fire bonus at Forge", E.GetStationMultiplier("Forge", "Fire") == E.STATION_BONUS)
	check("Fire no bonus at Farm", E.GetStationMultiplier("Farm", "Fire") == 1)
	check("Storm prefers only the Forge", E.GetPreferredStation("Storm") == "Forge" and E.GetStationMultiplier("Watchtower", "Storm") == 1)
	check("Shadow prefers Watchtower", E.GetPreferredStation("Shadow") == "Watchtower")
	check("unknown station neutral", E.GetStationMultiplier("Moon", "Fire") == 1)
	check("IsValid", E.IsValid("Ice") and not E.IsValid("ice") and not E.IsValid(5))

	table.insert(lines, 1, string.format("Elements tests: %d passed, %d failed", passed, failed))
	return table.concat(lines, "\n")
end

return ElementsTests
