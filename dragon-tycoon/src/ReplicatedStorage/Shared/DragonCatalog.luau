-- ReplicatedStorage/Shared/DragonCatalog
-- The 16 launch dragons (2 per element). Rarity is NOT part of a species: it is
-- rolled per hatch. Rig = which of the 4 base body models it uses.

local DragonCatalog = {}

export type Species = {
	Id: string,
	Name: string,
	Element: string,
	Rig: "Drake" | "Wyvern" | "Serpent" | "Behemoth",
	Hook: string, -- visual description for art
	Role: string, -- one-line combat identity (skills come in Phase 3)
}

local list: { Species } = {
	{ Id = "Cindermaw", Name = "Cindermaw", Element = "Fire", Rig = "Drake", Hook = "Soot-black scales, glowing ember cracks along the jaw", Role = "Close-range burner that stacks burn" },
	{ Id = "Pyrelance", Name = "Pyrelance", Element = "Fire", Rig = "Wyvern", Hook = "Spear-tailed flier trailing molten wing edges", Role = "Dives from above for burst damage" },
	{ Id = "Briarhorn", Name = "Briarhorn", Element = "Nature", Rig = "Behemoth", Hook = "Bark-plated shoulders, flowering thorn horns", Role = "Tank that regenerates while holding ground" },
	{ Id = "Sylvenreach", Name = "Sylvenreach", Element = "Nature", Rig = "Serpent", Hook = "Vine-wrapped coils, glowing seedpod lanterns along the spine", Role = "Roots enemies and drains health" },
	{ Id = "Tidewhelp", Name = "Tidewhelp", Element = "Water", Rig = "Serpent", Hook = "Sleek finned body with a foam-white crest", Role = "Slippery skirmisher with knockback waves" },
	{ Id = "Deepkeel", Name = "Deepkeel", Element = "Water", Rig = "Drake", Hook = "Barnacled keel ridge, glowing deep-sea freckles", Role = "Shield-breaker with pressure blasts" },
	{ Id = "Quarrytusk", Name = "Quarrytusk", Element = "Earth", Rig = "Behemoth", Hook = "Boulder hump, crystal-veined tusks, folded stubby wings", Role = "Slow bruiser with stun slams" },
	{ Id = "Faultcrown", Name = "Faultcrown", Element = "Earth", Rig = "Drake", Hook = "Cracked-stone crown, magma seams, dust with each step", Role = "Area quaker that splits the battlefield" },
	{ Id = "Squallwing", Name = "Squallwing", Element = "Storm", Rig = "Wyvern", Hook = "Tattered storm-gray wings crackling with violet sparks", Role = "Fast hit-and-run with chained sparks" },
	{ Id = "Thunderquill", Name = "Thunderquill", Element = "Storm", Rig = "Serpent", Hook = "Lightning-rod quills ripple along a coiling body", Role = "Ranged chain-lightning caster" },
	{ Id = "Rimeclaw", Name = "Rimeclaw", Element = "Ice", Rig = "Drake", Hook = "Frost-rimed claws, breath hangs as pale mist", Role = "Slows enemies with stacking chill" },
	{ Id = "Frostveil", Name = "Frostveil", Element = "Ice", Rig = "Wyvern", Hook = "See-through icicle wing membranes, snow-drift mane", Role = "Evasive kiter that freezes when dodging" },
	{ Id = "Dawnwarden", Name = "Dawnwarden", Element = "Light", Rig = "Behemoth", Hook = "Gilded sun-plate armor, sunrise-gold halo crest", Role = "Guardian that shields and cleanses" },
	{ Id = "Solhallow", Name = "Solhallow", Element = "Light", Rig = "Serpent", Hook = "Radiant ribbon body circled by orbiting sun-glyphs", Role = "Support beams that grow with combo" },
	{ Id = "Duskrend", Name = "Duskrend", Element = "Shadow", Rig = "Wyvern", Hook = "Smoke-trailing wings, violet eyes, silent hooked talons", Role = "Assassin that blinks behind targets" },
	{ Id = "Gloamveil", Name = "Gloamveil", Element = "Shadow", Rig = "Behemoth", Hook = "Eclipse-ringed horns, dark body that dims nearby light", Role = "Drains enemies and steals their buffs" },
}

DragonCatalog.List = list
DragonCatalog.ById = {} :: { [string]: Species }
for _, species in list do
	DragonCatalog.ById[species.Id] = species
end

function DragonCatalog.Get(id: any): Species?
	return if type(id) == "string" then DragonCatalog.ById[id] else nil
end

-- All species of the given elements, in catalog order.
function DragonCatalog.OfElements(elements: { string }): { Species }
	local result = {}
	for _, species in list do
		if table.find(elements, species.Element) then
			table.insert(result, species)
		end
	end
	return result
end

return DragonCatalog
