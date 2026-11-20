-- ReplicatedStorage/Shared/ProductCatalog
-- Everything sold for Robux, what it does, and who may see it.
-- IDs live in GameConfig (GamePasses / DevProducts). Prices here are what the
-- shop shows if Roblox can't tell us the real price; the real price is set in
-- Creator Hub and read live by the shop. [PLACEHOLDER] prices: tune after playtests.
--
-- Rules kept here (from the plan and Roblox's paid random items policy):
--   * Random = true items (Robux eggs, Luck Boost) are hidden from players whose
--     policy restricts paid random items, and the server refuses them too.
--   * Restricted players get the fixed-dragon shop and cosmetics instead.
--   * Fixed dragons are never above Epic. Robux never buys PvP wins (Ranked
--     ignores rarity and level).
--   * No currency is sold for Robux (no coin packs), so coin eggs stay free-earned.

local ProductCatalog = {}

ProductCatalog.Passes = {
	{ Key = "DoubleCoins", Name = "2x Coins", Price = 249, Text = "Double all coin income from your sanctuary, forever." },
	{ Key = "AutoHatch", Name = "Auto Hatch", Price = 149, Text = "Keeps hatching the egg you pick while you have coins and nest room." },
	{ Key = "FastHatch", Name = "Fast Hatch", Price = 99, Text = "Hatch eggs 4x faster." },
	{ Key = "ExtraNests", Name = "+10 Nest", Price = 99, Text = "Your nest holds 10 more resting dragons." },
}

ProductCatalog.Products = {
	RoyalEgg = { Name = "Royal Egg", Price = 49, Random = true, Egg = "RoyalEgg" },
	MythicEgg = { Name = "Mythic Egg", Price = 199, Random = true, Egg = "MythicEgg" },
	LuckBoost = { Name = "Luck Boost", Price = 39, Random = true, Minutes = 15,
		Text = "For 15 minutes, Rare, Epic, Legendary and Mythic chances are doubled on coin eggs. The egg shop shows the boosted odds." },
	FixedDragon = { Name = "Choose a dragon", Price = 249, Random = false, Rarity = "Epic",
		Text = "Pick any dragon. You get exactly that dragon at Epic rarity, with egg power matching your best dragon. No randomness." },
	Cosmetic = { Name = "Dragon style", Price = 79, Random = false,
		Text = "A wing trail or aura for every dragon you ride. Looks only: no stat changes." },
}

-- May this player see / buy this product? restricted = PaidRandomItemsRestricted.
function ProductCatalog.IsAllowed(key: string, restricted: boolean): boolean
	local product = ProductCatalog.Products[key]
	if not product then
		return false
	end
	return not (product.Random and restricted)
end

function ProductCatalog.GetPass(key: string)
	for _, pass in ProductCatalog.Passes do
		if pass.Key == key then
			return pass
		end
	end
	return nil
end

return ProductCatalog
