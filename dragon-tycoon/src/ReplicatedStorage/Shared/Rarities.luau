-- ReplicatedStorage/Shared/Rarities
-- The 6 rarities. Rarity is rolled on every hatch (any dragon can be any rarity)
-- and changes the dragon's look, income and a small PvP bonus.

local Rarities = {}

export type RarityId = "Common" | "Uncommon" | "Rare" | "Epic" | "Legendary" | "Mythic"

export type RarityInfo = {
	Id: RarityId,
	Rank: number, -- 1 = Common ... 6 = Mythic
	Color: Color3,
	IncomeMultiplier: number,
	PvpMultiplier: number, -- small on purpose: rarity must not decide fights
	Essence: number, -- Dragon Essence received when released
}

Rarities.Order = { "Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic" } :: { RarityId }

Rarities.Info = {
	Common = { Id = "Common", Rank = 1, Color = Color3.fromRGB(190, 190, 190), IncomeMultiplier = 1, PvpMultiplier = 1.00, Essence = 1 },
	Uncommon = { Id = "Uncommon", Rank = 2, Color = Color3.fromRGB(90, 200, 110), IncomeMultiplier = 2, PvpMultiplier = 1.05, Essence = 3 },
	Rare = { Id = "Rare", Rank = 3, Color = Color3.fromRGB(70, 150, 255), IncomeMultiplier = 5, PvpMultiplier = 1.10, Essence = 10 },
	Epic = { Id = "Epic", Rank = 4, Color = Color3.fromRGB(170, 90, 255), IncomeMultiplier = 15, PvpMultiplier = 1.15, Essence = 40 },
	Legendary = { Id = "Legendary", Rank = 5, Color = Color3.fromRGB(255, 170, 40), IncomeMultiplier = 50, PvpMultiplier = 1.20, Essence = 150 },
	Mythic = { Id = "Mythic", Rank = 6, Color = Color3.fromRGB(255, 70, 120), IncomeMultiplier = 200, PvpMultiplier = 1.25, Essence = 600 },
} :: { [RarityId]: RarityInfo }

function Rarities.IsValid(rarity: any): boolean
	return type(rarity) == "string" and Rarities.Info[rarity] ~= nil
end

return Rarities
