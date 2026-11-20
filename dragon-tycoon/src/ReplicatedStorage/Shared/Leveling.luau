-- ReplicatedStorage/Shared/Leveling
-- Dragon levels and XP. Shared so the UI shows the same numbers the server uses.
--
-- XP comes from three places:
--   * Station work: every working dragon earns XP each second you're online.
--   * Battles: a win or loss gives a share of the XP needed for the next level.
--   * Feeding: spend coins (Feed) or Dragon Essence (Infuse) for XP.
-- Levels raise income (+5% per level, see SanctuaryConfig) and combat stats,
-- and unlock skills at levels 1 / 10 / 20 / 30 (the 4th is the ultimate).
-- Every number marked [PLACEHOLDER] is a first guess to tune after playtests.

local Leveling = {}

Leveling.MaxLevel = 50
-- Level each skill slot unlocks at. Ranked fights use level 30, so all 4 are open there.
Leveling.SkillUnlockLevels = { 1, 10, 20, 30 }

Leveling.StationXPPerSecond = 1 -- [PLACEHOLDER] per working dragon, while online
Leveling.FeedXPFraction = 0.3 -- [PLACEHOLDER] one Feed = 30% of the current level
Leveling.EssenceXP = 40 -- [PLACEHOLDER] XP per Dragon Essence
-- Share of the current level's XP given by a battle. [PLACEHOLDER]
Leveling.BattleXPFraction = {
	Win = 0.35,
	Loss = 0.15,
	PracticeWin = 0.12,
	PracticeLoss = 0.04,
	RaidWin = 0.5,
	RaidLoss = 0.1,
}
Leveling.PracticeRewardsPerDay = 15 -- practice matches per day that give XP
Leveling.RaidRewardsPerDay = 5 -- raids per day that give rewards

-- XP needed to go from `level` to `level + 1`. nil at max level.
function Leveling.XPToNext(level: number): number?
	if level >= Leveling.MaxLevel then
		return nil
	end
	return math.floor(60 * level ^ 1.6) -- [PLACEHOLDER] L1: 60, L10: 2388, L30: 13853, L49: 30371
end

-- Coins for one Feed at this level. nil at max level. [PLACEHOLDER]
function Leveling.FeedCost(level: number): number?
	if level >= Leveling.MaxLevel then
		return nil
	end
	return math.floor(25 * 1.33 ^ level + 0.5) -- L1: 33, L10: 433, L20: 7.5k, L30: 130k, L40: 2.3M
end

function Leveling.FeedXP(level: number): number
	local need = Leveling.XPToNext(level)
	return if need then math.ceil(need * Leveling.FeedXPFraction) else 0
end

-- Essence needed to finish the current level (Infuse). nil at max level.
function Leveling.InfuseCost(dragon: any): number?
	local need = Leveling.XPToNext(dragon.Level or 1)
	if not need then
		return nil
	end
	return math.max(1, math.ceil((need - (dragon.XP or 0)) / Leveling.EssenceXP))
end

-- kind: "Win" | "Loss" | "PracticeWin" | "PracticeLoss"
function Leveling.BattleXP(level: number, kind: string): number
	local need = Leveling.XPToNext(level)
	local fraction = Leveling.BattleXPFraction[kind] or 0
	return if need then math.ceil(need * fraction) else 0
end

-- Adds XP to a dragon table and levels it up. Returns how many levels it gained.
function Leveling.AddXP(dragon: any, amount: number): number
	if type(amount) ~= "number" or amount ~= amount or amount <= 0 then
		return 0
	end
	dragon.Level = dragon.Level or 1
	dragon.XP = (dragon.XP or 0) + math.floor(amount)
	local gained = 0
	while true do
		local need = Leveling.XPToNext(dragon.Level)
		if not need then
			dragon.XP = 0 -- max level
			break
		end
		if dragon.XP < need then
			break
		end
		dragon.XP -= need
		dragon.Level += 1
		gained += 1
	end
	return gained
end

-- How many of the 4 skills a dragon of this level has.
function Leveling.SkillsUnlocked(level: number): number
	local count = 0
	for _, unlockAt in Leveling.SkillUnlockLevels do
		if level >= unlockAt then
			count += 1
		end
	end
	return count
end

return Leveling
