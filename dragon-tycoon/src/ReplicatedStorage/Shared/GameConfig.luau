-- ReplicatedStorage/Shared/GameConfig
-- Shared settings for Dragon Tycoon. Both the server and the client can read this,
-- so never put secrets here.

local GameConfig = {}

-- Saving ------------------------------------------------------------------
-- Changing the store name starts everyone with fresh data, so only bump it on purpose.
GameConfig.DataStoreName = "DragonTycoon_PlayerData_v1"
-- Schema version of the saved data. Bump it and add a migration in DataService
-- whenever the shape of the saved data changes.
GameConfig.DataVersion = 1
GameConfig.AutosaveInterval = 60 -- seconds between autosaves

-- Economy -----------------------------------------------------------------
GameConfig.StartingCoins = 0
GameConfig.MaxCoins = 1e15 -- keeps coin math exact (doubles are exact up to ~9e15)

-- Robux products ------------------------------------------------------------
-- 0 means "not created yet". Create them in the Creator Hub and paste the IDs here.
GameConfig.GamePasses = {
	DoubleCoins = 0,
	AutoHatch = 0,
	FastHatch = 0,
	ExtraNests = 0,
}
-- Developer Products (Creator Hub > your experience > Monetization > Developer Products).
GameConfig.DevProducts = {
	RoyalEgg = 0,
	MythicEgg = 0,
	LuckBoost = 0,
	FixedDragon = 0,
	Cosmetic = 0,
}

-- Purchase records kept per player (oldest are dropped past these limits).
GameConfig.MaxStoredReceipts = 100
GameConfig.MaxPurchaseHistory = 200

-- Policy testing (Studio only) ---------------------------------------------------
-- Set to { ArePaidRandomItemsRestricted = true } to test the restricted-player
-- experience in Studio. Ignored in live servers.
GameConfig.StudioPolicyOverride = nil

-- Studio testing ---------------------------------------------------------------
-- In Studio, saves go to a separate "_Studio" store so tests never touch live
-- saves, and a fresh test save gets these coins once to try things quickly.
GameConfig.StudioTestCoins = 50_000

return GameConfig
